import AppKit
import WebKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var web: WKWebView!
    let bridge = Bridge()
    var statusItem: NSStatusItem!
    let engine = Engine.shared

    func applicationDidFinishLaunching(_ n: Notification) {
        // Una sola instancia
        let me = NSRunningApplication.current
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "").first(where: { $0 != me }) {
            other.activate(options: [.activateAllWindows]); NSApp.terminate(nil); return
        }
        buildMenu()
        buildWindow()
        buildStatusItem()
        engine.onEvent = { [weak self] name, payload in self?.bridge.emit(name, payload) }
        engine.onProfileChanged = { [weak self] in self?.rebuildStatusMenu() }
        engine.start()

        // Primer arranque: registrar el inicio automático al iniciar sesión.
        if !engine.config.firstRunDone {
            try? SMAppService.mainApp.register()
            engine.config.firstRunDone = true; Store.save(engine.config)
        }
        let startedAtLogin = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        let needsSetup = !(engine.inputGranted && engine.axGranted && engine.deviceConnected())
        if !startedAtLogin || needsSetup { showWindow() }
        // Pide los permisos que falten (macOS muestra su aviso y deja abrir Ajustes).
        if !engine.inputGranted { engine.requestInput() }
        if !engine.axGranted { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.engine.requestAX() } }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }

    // MARK: ventana
    func buildWindow() {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(bridge, name: "mp")
        web = WKWebView(frame: .zero, configuration: cfg)
        web.setValue(false, forKey: "drawsBackground")
        bridge.web = web
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Macropad"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.078, green: 0.066, blue: 0.055, alpha: 1)
        window.minSize = NSSize(width: 980, height: 660)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = web
        window.center()
        window.setFrameAutosaveName("MacropadMain")
        if let dir = Bundle.main.resourceURL?.appendingPathComponent("ui") {
            web.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)
        }
    }

    func showWindow() {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)   // se queda en la barra de menú, sin icono en el Dock
        return false
    }

    // MARK: barra de menú
    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            for r in 0..<3 { for c in 0..<3 {
                NSBezierPath(roundedRect: NSRect(x: 2 + CGFloat(c) * 5, y: 2 + CGFloat(r) * 5, width: 4, height: 4), xRadius: 1, yRadius: 1).fill()
            } }
            return true
        }
        img.isTemplate = true
        statusItem.button?.image = img
        rebuildStatusMenu()
    }

    func rebuildStatusMenu() {
        let m = NSMenu()
        m.addItem(withTitle: "Abrir Macropad", action: #selector(openFromMenu), keyEquivalent: "").target = self
        m.addItem(.separator())
        let head = NSMenuItem(title: "Perfil", action: nil, keyEquivalent: ""); head.isEnabled = false; m.addItem(head)
        for p in engine.config.profiles {
            let it = NSMenuItem(title: p.name, action: #selector(pickProfile(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = p.id
            it.state = p.id == engine.effectiveProfile.id ? .on : .off
            m.addItem(it)
        }
        m.addItem(.separator())
        m.addItem(withTitle: "Salir de Macropad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = m
    }
    @objc func openFromMenu() { showWindow() }
    @objc func pickProfile(_ s: NSMenuItem) { if let id = s.representedObject as? String { engine.switchProfile(id) } }

    // MARK: menú principal (para que funcionen ⌘C/⌘V en la interfaz)
    func buildMenu() {
        let main = NSMenu()
        func sub(_ title: String, _ items: [(String, Selector, String)]) -> NSMenuItem {
            let it = NSMenuItem(); let m = NSMenu(title: title)
            for (t, a, k) in items { m.addItem(withTitle: t, action: a, keyEquivalent: k) }
            it.submenu = m; return it
        }
        main.addItem(sub("Macropad", [("Ocultar Macropad", #selector(NSApplication.hide(_:)), "h"), ("Salir de Macropad", #selector(NSApplication.terminate(_:)), "q")]))
        main.addItem(sub("Edición", [("Deshacer", Selector(("undo:")), "z"), ("Rehacer", Selector(("redo:")), "Z"), ("Cortar", #selector(NSText.cut(_:)), "x"),
                                      ("Copiar", #selector(NSText.copy(_:)), "c"), ("Pegar", #selector(NSText.paste(_:)), "v"), ("Seleccionar todo", #selector(NSText.selectAll(_:)), "a")]))
        main.addItem(sub("Ventana", [("Minimizar", #selector(NSWindow.performMiniaturize(_:)), "m"), ("Cerrar", #selector(NSWindow.performClose(_:)), "w")]))
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
