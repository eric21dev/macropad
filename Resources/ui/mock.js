"use strict";
// Datos de ejemplo para ver la interfaz en un navegador (la app nativa no los usa).
function mockInit() {
  const slots = {}; ["kb:05:22","kb:05:27","kb:05:08","kb:05:21","kb:05:26","kb:05:07","kb:05:20","kb:05:25","kb:05:06","kb:05:1f","kb:05:24","kb:05:05","kb:05:1e","kb:05:23","kb:05:04"].forEach((t, i) => slots["k" + (i + 1)] = t);
  Object.assign(slots, { A_l:"cc:70", A_r:"cc:6f", A_p:"cc:cd", B_l:"cc:ea", B_r:"cc:e9", B_p:"cc:e2", C_l:"cc:b6", C_r:"cc:b5", C_p:"kb:08:2c" });
  return { config: { version: 2, slots, activeProfile: "principal", autoSwitch: true, firstRunDone: true,
    macros: [{ id: "m1", name: "Firma de correo", steps: [{ t: "text", v: "Un saludo,\nEric" }, { t: "delay", ms: 200 }, { t: "keys", v: "cmd+return" }] }],
    profiles: [
      { id: "principal", name: "Principal", apps: [], led: { layer: 0, mode: "backlight", color: "amber" === "x" ? "" : "orange" },
        bindings: { k1: { type: "keys", value: "cmd+shift+4", label: "" }, k2: { type: "app", value: "Calculator" }, k3: { type: "macro", value: "m1" }, k5: { type: "url", value: "https://github.com" }, k8: { type: "text", value: "hola mundo" },
          k15: { type: "shell", value: "say hola" }, B_p: { type: "media", value: "mute" }, C_p: { type: "profile", value: "next" } } },
      { id: "p2", name: "Edición de vídeo", apps: ["com.apple.FinalCut"], led: { layer: 0, mode: "press", color: "cyan" }, bindings: {} } ] },
    status: { device: true, input: true, accessibility: true, filter: true, ledReady: true }, loginItem: true,
    version: { version: "1.0", branch: "main", commit: "demo", date: new Date().toISOString(), dirty: false },
    apps: [{ name: "Safari", id: "com.apple.Safari" }, { name: "Final Cut Pro", id: "com.apple.FinalCut" }] };
}

