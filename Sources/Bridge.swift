import AppKit
import WebKit
import ServiceManagement

/// Puente JS ↔ Swift: la interfaz llama a `window.webkit.messageHandlers.mp.postMessage({id, cmd, data})`
/// y la app responde con `window.__reply(id, valor)`; los avisos van por `window.__event(nombre, valor)`.
final class Bridge: NSObject, WKScriptMessageHandler {
    weak var web: WKWebView?
    private let engine = Engine.shared

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let b = m.body as? [String: Any], let id = b["id"] as? Int, let cmd = b["cmd"] as? String else { return }
        let r = handle(cmd, b["data"])
        eval("window.__reply(\(id), \(json(r)))")
    }

    func emit(_ name: String, _ payload: Any) { eval("window.__event(\(json(name)), \(json(payload)))") }

    private func eval(_ js: String) { DispatchQueue.main.async { self.web?.evaluateJavaScript(js, completionHandler: nil) } }

    private func json(_ o: Any) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.fragmentsAllowed]), let s = String(data: d, encoding: .utf8) else { return "null" }
        return s
    }

    private func toObject<T: Encodable>(_ v: T) -> Any {
        guard let d = try? JSONEncoder().encode(v), let o = try? JSONSerialization.jsonObject(with: d) else { return NSNull() }
        return o
    }

    private func decode<T: Decodable>(_ type: T.Type, _ o: Any?) -> T? {
        guard let o = o, JSONSerialization.isValidJSONObject(o), let d = try? JSONSerialization.data(withJSONObject: o) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    static let panes = ["input": "Privacy_ListenEvent", "ax": "Privacy_Accessibility"]
    static func openPane(_ kind: String) {
        if let p = panes[kind], let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(p)") { NSWorkspace.shared.open(u) }
    }

    static func buildInfo() -> [String: Any] {
        let i = Bundle.main.infoDictionary ?? [:]
        return ["version": i["CFBundleShortVersionString"] ?? "0", "branch": i["MPBranch"] ?? "?", "commit": i["MPCommit"] ?? "?",
                "date": i["MPDate"] ?? "", "dirty": (i["MPDirty"] as? String) == "1"]
    }

    private func handle(_ cmd: String, _ data: Any?) -> Any {
        switch cmd {
        case "init":
            return ["config": toObject(engine.config), "status": engine.status(), "version": Bridge.buildInfo(),
                    "loginItem": SMAppService.mainApp.status == .enabled, "apps": runningApps()]
        case "save":
            guard let c = decode(Config.self, data) else { return false }
            engine.config = c; Store.save(c); engine.applyProfileLED(); engine.onProfileChanged?()
            return true
        case "led":
            guard let l = decode(LED.self, data) else { return false }
            return engine.setLED(l)
        case "perm":
            let kind = data as? String ?? ""
            if kind == "input" { engine.requestInput() } else if kind == "ax" { engine.requestAX() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { Bridge.openPane(kind) }
            return true
        case "settings": Bridge.openPane(data as? String ?? ""); return true
        case "test":
            guard let a = decode(Action.self, data) else { return false }
            engine.run(a); return true
        case "testMacro":
            guard let m = decode(Macro.self, data) else { return false }
            engine.runMacro(m); return true
        case "login":
            let on = data as? Bool ?? false
            do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { return false }
            return SMAppService.mainApp.status == .enabled
        case "pickApp":
            let p = NSOpenPanel()
            p.directoryURL = URL(fileURLWithPath: "/Applications"); p.allowedContentTypes = [.applicationBundle]; p.allowsMultipleSelection = false
            guard p.runModal() == .OK, let u = p.url else { return NSNull() }
            return ["name": u.deletingPathExtension().lastPathComponent, "id": Bundle(url: u)?.bundleIdentifier ?? ""]
        case "apps": return runningApps()
        case "relaunch":
            let path = Bundle.main.bundlePath
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", "sleep 1; /usr/bin/open -n '\(path)'"]
            try? p.run()
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return true
        default: return NSNull()
        }
    }

    private func runningApps() -> [[String: String]] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .map { ["name": $0.localizedName ?? "", "id": $0.bundleIdentifier ?? ""] }
            .sorted { $0["name"]! < $1["name"]! }
    }
}
