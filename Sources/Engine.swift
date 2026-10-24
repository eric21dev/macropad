import Foundation
import AppKit
import IOKit
import IOKit.hid
import ApplicationServices
import CoreGraphics

let PAD_VID = 0x1189, PAD_PID = 0x8840
let MAGIC: Int64 = 0x4D50  // eventSourceUserData de los eventos que genera la propia app

// MARK: - Teclado / medios

enum Keys {
    static let mac: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50, "delete": 51, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126, "home": 115, "end": 119, "pageup": 116, "pagedown": 121, "fdelete": 117,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]
    static let alias = ["enter": "return", "backspace": "delete", "escape": "esc", "espacio": "space", "supr": "fdelete"]

    static func hidName(_ u: UInt8) -> String? {
        switch u {
        case 0x04...0x1D: return String(UnicodeScalar(UInt8(97) + u - 4))
        case 0x1E...0x26: return String(u - 0x1E + 1)
        case 0x27: return "0"
        case 0x28: return "return"
        case 0x29: return "esc"
        case 0x2A: return "delete"
        case 0x2B: return "tab"
        case 0x2C: return "space"
        case 0x3A...0x45: return "f\(u - 0x3A + 1)"
        case 0x4F: return "right"
        case 0x50: return "left"
        case 0x51: return "down"
        case 0x52: return "up"
        default: return nil
        }
    }
    static let hidForKeycode: [Int64: UInt8] = {
        var d = [Int64: UInt8]()
        for u in 0...255 { if let n = hidName(UInt8(u)), let c = mac[n] { d[Int64(c)] = UInt8(u) } }
        return d
    }()

    static func post(_ code: CGKeyCode, _ flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.setIntegerValueField(.eventSourceUserData, value: MAGIC)
            e?.post(tap: .cghidEventTap)
        }
    }

    /// "cmd+shift+4", "ctrl+alt+left"…
    @discardableResult static func combo(_ s: String) -> Bool {
        var flags = CGEventFlags(); var key: CGKeyCode?
        for raw in s.lowercased().split(separator: "+") {
            let part = raw.trimmingCharacters(in: .whitespaces)
            switch part {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "alt", "opt", "option": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: key = mac[alias[part] ?? part]
            }
        }
        guard let k = key else { return false }
        post(k, flags); return true
    }

    static func type(_ s: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        for ch in s {
            if ch == "\n" { post(36, []); usleep(8000); continue }
            let u = Array(String(ch).utf16)
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                e?.keyboardSetUnicodeString(stringLength: u.count, unicodeString: u)
                e?.setIntegerValueField(.eventSourceUserData, value: MAGIC)
                e?.post(tap: .cghidEventTap)
            }
            usleep(6000)
        }
    }

    // Teclas multimedia: nombre → código NX; usos de la página Consumer que envía el pad → código NX.
    static let media: [String: Int] = ["volup": 0, "voldown": 1, "brightup": 2, "brightdown": 3, "mute": 7, "playpause": 16, "next": 17, "prev": 18]
    static let nxForUsage: [UInt16: Int] = [0xE9: 0, 0xEA: 1, 0x6F: 2, 0x70: 3, 0xE2: 7, 0xCD: 16, 0xB5: 17, 0xB6: 18]
    static let usageForNX: [Int: UInt16] = Dictionary(uniqueKeysWithValues: nxForUsage.map { ($0.value, $0.key) })

    static func postMedia(_ key: Int) {
        for down in [true, false] {
            let st = down ? 0xA : 0xB
            let e = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(st << 8)),
                                       timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: (key << 16) | (st << 8), data2: -1)
            let ce = e?.cgEvent
            ce?.setIntegerValueField(.eventSourceUserData, value: MAGIC)
            ce?.post(tap: .cghidEventTap)
        }
    }
}

func sh(_ args: [String]) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: args[0]); p.arguments = Array(args.dropFirst())
    try? p.run()
}

// MARK: - Motor

final class Engine {
    static let shared = Engine()

    var config: Config = Store.load() { didSet { rebuildIndex() } }
    var autoProfile: String?
    /// Se llama en el hilo principal: ("status" | "pad" | "state", payload JSON-serializable)
    var onEvent: ((String, Any) -> Void)?

    private var slotForTrigger: [String: String] = [:]
    private var mgr: IOHIDManager?
    private var buffers: [UnsafeMutablePointer<UInt8>] = []
    private var vendorDev: IOHIDDevice?
    private var hidOpen = false
    private var prevKeys = Set<UInt8>()
    private var prevCC: UInt16 = 0
    private var counter = 0
    private var tapRef: CFMachPort?
    private var lastStatus: [String: Any] = [:]
    private var lastLED: LED?
    private let macroQueue = DispatchQueue(label: "macropad.macro")

    init() { rebuildIndex() }

    private func rebuildIndex() {
        slotForTrigger = Dictionary(config.slots.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
    }

    var effectiveProfile: Profile {
        let id = autoProfile ?? config.activeProfile
        return config.profiles.first { $0.id == id } ?? config.profiles.first ?? Defaults.config().profiles[0]
    }

    // MARK: arranque
    func start() {
        openHID()
        tryCreateTap()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    // MARK: HID
    func openHID() {
        if let m = mgr { IOHIDManagerClose(m, 0); mgr = nil }
        buffers.forEach { $0.deallocate() }; buffers = []; vendorDev = nil
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey: PAD_VID, kIOHIDProductIDKey: PAD_PID] as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(m, { _, _, _, dev in Engine.shared.attached(dev) }, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { _, _, _, dev in Engine.shared.detached(dev) }, nil)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        hidOpen = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
        mgr = m
    }

    private func attached(_ dev: IOHIDDevice) {
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 256); buffers.append(buf)
        IOHIDDeviceRegisterInputReportCallback(dev, buf, 256, { _, _, _, _, _, bytes, len in
            Engine.shared.handle(Array(UnsafeBufferPointer(start: bytes, count: len)))
        }, nil)
        if (IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsagePageKey as CFString) as? Int) == 0xFF00 {
            vendorDev = dev
            lastLED = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.applyProfileLED() }
        }
    }
    private func detached(_ dev: IOHIDDevice) { if dev == vendorDev { vendorDev = nil } }

    // MARK: informes → disparadores
    private func handle(_ b: [UInt8]) {
        guard !b.isEmpty else { return }
        if b[0] == 1, b.count >= 9 {
            let keys = Set(b[3..<9].filter { $0 != 0 })
            for k in keys.subtracting(prevKeys) { fire(String(format: "kb:%02x:%02x", b[1], k)) }
            prevKeys = keys
        } else if b[0] == 5, b.count >= 3 {
            let u = UInt16(b[1]) | UInt16(b[2]) << 8
            if u != 0 && u != prevCC { fire(String(format: "cc:%02x", u)) }
            prevCC = u
        }
    }

    private func fire(_ trigger: String) {
        counter += 1
        let slot = slotForTrigger[trigger]
        onEvent?("pad", ["trigger": trigger, "slot": slot as Any, "n": counter])
        guard let slot = slot, let a = effectiveProfile.bindings[slot], a.type != "default" else { return }
        run(a)
    }

    // MARK: acciones
    func run(_ a: Action) {
        let v = a.value ?? ""
        switch a.type {
        case "keys": Keys.combo(v)
        case "text": macroQueue.async { Keys.type(v) }
        case "shell": sh(["/bin/sh", "-c", v])
        case "app": sh(["/usr/bin/open", "-a", v])
        case "url": sh(["/usr/bin/open", v])
        case "media": if let k = Keys.media[v] { Keys.postMedia(k) }
        case "macro": if let m = config.macros.first(where: { $0.id == v }) { runMacro(m) }
        case "profile": switchProfile(v)
        case "overlay": Overlay.shared.show(seconds: Double(v) ?? 2)
        default: break
        }
    }

    func runMacro(_ m: Macro) {
        macroQueue.async {
            for s in m.steps {
                let v = s.v ?? ""
                switch s.t {
                case "keys": Keys.combo(v)
                case "text": Keys.type(v)
                case "delay": usleep(UInt32(max(0, min(s.ms ?? 100, 10000)) * 1000))
                case "shell": sh(["/bin/sh", "-c", v])
                case "app": sh(["/usr/bin/open", "-a", v])
                case "url": sh(["/usr/bin/open", v])
                case "media": if let k = Keys.media[v] { Keys.postMedia(k) }
                default: break
                }
                usleep(30_000)
            }
        }
    }

    // MARK: perfiles
    func switchProfile(_ idOrDir: String) {
        DispatchQueue.main.async {
            let ps = self.config.profiles
            guard !ps.isEmpty else { return }
            let i = ps.firstIndex { $0.id == self.config.activeProfile } ?? 0
            var target = idOrDir
            if idOrDir == "next" { target = ps[(i + 1) % ps.count].id }
            if idOrDir == "prev" { target = ps[(i + ps.count - 1) % ps.count].id }
            guard ps.contains(where: { $0.id == target }) else { return }
            self.config.activeProfile = target
            self.autoProfile = nil
            Store.save(self.config)
            self.applyProfileLED()
            self.onEvent?("state", ["activeProfile": target])
            self.onProfileChanged?()
        }
    }
    var onProfileChanged: (() -> Void)?

    @objc private func appActivated(_ n: Notification) {
        guard config.autoSwitch, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bid = app.bundleIdentifier, bid != Bundle.main.bundleIdentifier else { return }
        let match = config.profiles.first { $0.apps.contains(bid) }?.id
        if match != autoProfile {
            autoProfile = match
            applyProfileLED()
            onEvent?("state", ["effectiveProfile": effectiveProfile.id])
            onProfileChanged?()
        }
    }

    // MARK: LED (informe de salida al interfaz del fabricante, sin root)
    static func ledCode(_ l: LED) -> UInt8? {
        let colors = ["white": 0, "red": 1, "orange": 2, "yellow": 3, "green": 4, "cyan": 5, "blue": 6, "purple": 7]
        guard (0...2).contains(l.layer) else { return nil }
        let modes = ["backlight": 1, "shock": 2, "shock2": 3, "press": 4]
        if l.mode == "off" { return 0 }
        guard let m = modes[l.mode], let c = colors[l.color] else { return nil }
        if l.mode == "backlight" && c == 0 { return 0x05 }
        guard c > 0 else { return nil }
        return UInt8(c << 4 | m)
    }

    @discardableResult func setLED(_ l: LED) -> Bool {
        guard let dev = vendorDev, let code = Engine.ledCode(l) else { return false }
        var a = [UInt8](repeating: 0, count: 64); a.replaceSubrange(0..<13, with: [0x03, 0xfe, 0xb0, UInt8(l.layer + 1), 0x08, 0, 0, 0, 0, 0, 0x01, 0, code])
        var b = [UInt8](repeating: 0, count: 64); b.replaceSubrange(0..<4, with: [0x03, 0xfd, 0xfe, 0xff])
        var ok = true
        for p in [a, b] {
            ok = ok && IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 3, p, p.count) == kIOReturnSuccess
            usleep(50_000)
        }
        if ok { lastLED = l }
        return ok
    }

    func applyProfileLED() {
        guard let l = effectiveProfile.led, l != lastLED else { return }
        setLED(l)
    }

    // MARK: permisos y estado
    var inputGranted: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
    var axGranted: Bool { AXIsProcessTrusted() }

    func requestInput() { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
    func requestAX() { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }

    func deviceConnected() -> Bool {
        let d = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        d["idVendor"] = PAD_VID; d["idProduct"] = PAD_PID
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, d, &it) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(it) }
        let s = IOIteratorNext(it)
        if s != 0 { IOObjectRelease(s); return true }
        return false
    }

    func status() -> [String: Any] {
        ["device": deviceConnected(), "input": inputGranted, "accessibility": axGranted, "filter": tapRef != nil,
         "hidOpen": hidOpen && vendorDev != nil, "ledReady": vendorDev != nil]
    }

    private var lastInput = false
    private func poll() {
        let inp = inputGranted
        if inp && !lastInput && !(hidOpen && vendorDev != nil) { openHID() }   // se concedió el permiso: reabrir
        lastInput = inp
        if tapRef == nil && axGranted { tryCreateTap() }
        let s = status()
        if NSDictionary(dictionary: s) != NSDictionary(dictionary: lastStatus) {
            lastStatus = s; onEvent?("status", s)
            // El instalador lee este archivo para mostrar el estado en vivo.
            var out = s; out["pid"] = Int(getpid())
            if let d = try? JSONSerialization.data(withJSONObject: out) { try? d.write(to: Store.dir.appendingPathComponent("status.json")) }
        }
    }

    // MARK: filtro de eventos (traga el original cuando la posición tiene acción)
    private func isBound(_ trigger: String) -> Bool {
        guard let slot = slotForTrigger[trigger], let a = effectiveProfile.bindings[slot] else { return false }
        return a.type != "default"
    }

    private func tryCreateTap() {
        guard tapRef == nil, axGranted else { return }
        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << 14))
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                                        callback: { _, type, event, _ in Engine.shared.tap(type, event) }, userInfo: nil) else { return }
        tapRef = t
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0), .commonModes)
    }

    private func tap(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tapRef { CGEvent.tapEnable(tap: t, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == MAGIC { return pass }
        var id: String?
        if type == .keyDown || type == .keyUp {
            let f = event.flags; var mod: UInt8 = 0
            if f.contains(.maskControl) { mod |= 0x01 }
            if f.contains(.maskShift) { mod |= 0x02 }
            if f.contains(.maskAlternate) { mod |= 0x04 }
            if f.contains(.maskCommand) { mod |= 0x08 }
            if let u = Keys.hidForKeycode[event.getIntegerValueField(.keyboardEventKeycode)] { id = String(format: "kb:%02x:%02x", mod, u) }
        } else if type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 {
            if let u = Keys.usageForNX[(ns.data1 & 0xFFFF0000) >> 16] { id = String(format: "cc:%02x", u) }
        }
        if let id = id, isBound(id) { return nil }
        return pass
    }
}
