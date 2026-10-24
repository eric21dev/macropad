import Foundation

struct Action: Codable, Equatable { var type: String; var value: String?; var label: String? }
struct Step: Codable, Equatable { var t: String; var v: String?; var ms: Int? }
struct Macro: Codable, Equatable { var id: String; var name: String; var steps: [Step] }
struct LED: Codable, Equatable { var layer: Int; var mode: String; var color: String }
struct Profile: Codable, Equatable {
    var id: String
    var name: String
    var bindings: [String: Action]   // id de posición (k1…k15, A_l…C_p) → acción
    var led: LED?
    var apps: [String]               // bundle ids que activan este perfil solos
}
struct Config: Codable, Equatable {
    var version: Int
    var slots: [String: String]      // posición física → id del disparador que envía el pad
    var activeProfile: String
    var profiles: [Profile]
    var macros: [Macro]
    var autoSwitch: Bool
    var firstRunDone: Bool
}

enum Defaults {
    /// Mapa de fábrica del 15key_3knob (VID 0x1189, PID 0x8840): lo que envía cada tecla y mando.
    static let slots: [String: String] = [
        "k1": "kb:05:22", "k2": "kb:05:27", "k3": "kb:05:08", "k4": "kb:05:21", "k5": "kb:05:26",
        "k6": "kb:05:07", "k7": "kb:05:20", "k8": "kb:05:25", "k9": "kb:05:06", "k10": "kb:05:1f",
        "k11": "kb:05:24", "k12": "kb:05:05", "k13": "kb:05:1e", "k14": "kb:05:23", "k15": "kb:05:04",
        "A_l": "cc:70", "A_r": "cc:6f", "A_p": "cc:cd",
        "B_l": "cc:ea", "B_r": "cc:e9", "B_p": "cc:e2",
        "C_l": "cc:b6", "C_r": "cc:b5", "C_p": "kb:08:2c",
    ]
    static func config() -> Config {
        let p = Profile(id: "principal", name: "Principal", bindings: [:], led: nil, apps: [])
        return Config(version: 2, slots: slots, activeProfile: p.id, profiles: [p], macros: [], autoSwitch: true, firstRunDone: false)
    }
}

enum Store {
    static let dir: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Macropad")
    static var url: URL { dir.appendingPathComponent("config.json") }
    static let oldURL = URL(fileURLWithPath: NSString(string: "~/.config/macropad/config.json").expandingTildeInPath)

    static func load() -> Config {
        if let d = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(Config.self, from: d), !c.profiles.isEmpty { return c }
        return migrateOld() ?? Defaults.config()
    }

    static func save(_ c: Config) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? enc.encode(c) else { return }
        let tmp = url.appendingPathExtension("tmp")
        try? d.write(to: tmp)
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    /// Importa la configuración de la versión anterior (demonio + web): posiciones aprendidas y acciones por disparador.
    static func migrateOld() -> Config? {
        guard let d = try? Data(contentsOf: oldURL), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        var c = Defaults.config()
        if let s = j["slots"] as? [String: String], !s.isEmpty { c.slots = s }
        var bindings: [String: Action] = [:]
        if let b = j["bindings"] as? [String: [String: Any]] {
            for (slot, trig) in c.slots {
                guard let o = b[trig], let t = o["type"] as? String, t != "default" else { continue }
                bindings[slot] = Action(type: t, value: o["value"] as? String, label: (o["label"] as? String).flatMap { $0.isEmpty ? nil : $0 })
            }
        }
        c.profiles[0].bindings = bindings
        return c
    }
}
