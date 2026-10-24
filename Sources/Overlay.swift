import AppKit
import WebKit

/// Chuleta flotante: el pad con lo que hace cada posición del perfil activo. No roba el foco, no recibe clics
/// y se cierra sola. Se precarga al arrancar para que aparezca al instante.
final class Overlay {
    static let shared = Overlay()
    private var panel: NSPanel?
    private var web: WKWebView?
    private var hideItem: DispatchWorkItem?
    private let size = NSSize(width: 560, height: 860)

    func prepare() {
        guard panel == nil, let dir = Bundle.main.resourceURL?.appendingPathComponent("ui") else { return }
        let w = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: WKWebViewConfiguration())
        w.setValue(false, forKey: "drawsBackground")
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.level = .screenSaver
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isReleasedWhenClosed = false
        p.contentView = w
        w.loadFileURL(dir.appendingPathComponent("overlay.html"), allowingReadAccessTo: dir)
        panel = p; web = w
    }

    func show(seconds: Double) {
        DispatchQueue.main.async { [self] in
            prepare()
            guard let p = panel, let w = web else { return }
            let e = Engine.shared
            let secs = min(max(seconds, 1), 10)
            guard let cfgData = try? JSONEncoder().encode(e.config), let cfg = try? JSONSerialization.jsonObject(with: cfgData),
                  let d = try? JSONSerialization.data(withJSONObject: ["config": cfg, "profile": e.effectiveProfile.id, "seconds": secs]),
                  let json = String(data: d, encoding: .utf8) else { return }
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
            let vis = screen.visibleFrame
            let h = min(size.height, vis.height - 20)
            p.setFrame(NSRect(x: vis.midX - size.width / 2, y: vis.midY - h / 2, width: size.width, height: h), display: true)
            w.evaluateJavaScript("window.show(\(json))", completionHandler: nil)
            p.orderFrontRegardless()
            hideItem?.cancel()
            let item = DispatchWorkItem { [weak p] in p?.orderOut(nil) }
            hideItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + secs + 0.1, execute: item)
        }
    }
}
