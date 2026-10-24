"use strict";
// Textos legibles de cada acción; los usan la ventana principal y la chuleta flotante.
const Lbl = (() => {
  const MEDIA = [["playpause", "Play / Pausa"], ["next", "Siguiente"], ["prev", "Anterior"], ["volup", "Volumen +"], ["voldown", "Volumen −"], ["mute", "Silencio"], ["brightup", "Brillo +"], ["brightdown", "Brillo −"]];
  const CC = { "cc:e9": "Volumen +", "cc:ea": "Volumen −", "cc:e2": "Silencio", "cc:6f": "Brillo +", "cc:70": "Brillo −", "cc:cd": "Play/Pausa", "cc:b5": "Siguiente", "cc:b6": "Anterior" };
  function hidName(u) {
    if (u >= 4 && u <= 29) return String.fromCharCode(65 + u - 4);
    if (u >= 30 && u <= 38) return String(u - 29);
    if (u === 39) return "0"; if (u === 44) return "␣"; if (u === 40) return "↩"; if (u === 41) return "⎋";
    return "0x" + u.toString(16);
  }
  function trigName(t) {
    if (!t) return "sin aprender"; if (CC[t]) return CC[t];
    const [k, m, u] = t.split(":"); if (k !== "kb") return t;
    const mm = parseInt(m, 16); return (mm & 1 ? "⌃" : "") + (mm & 2 ? "⇧" : "") + (mm & 4 ? "⌥" : "") + (mm & 8 ? "⌘" : "") + hidName(parseInt(u, 16));
  }
  const PRETTY = { cmd: "⌘", command: "⌘", shift: "⇧", alt: "⌥", opt: "⌥", option: "⌥", ctrl: "⌃", control: "⌃", return: "↩", enter: "↩", delete: "⌫", esc: "⎋", space: "␣", tab: "⇥", left: "←", right: "→", up: "↑", down: "↓" };
  const prettyCombo = c => (c || "").split("+").map(p => PRETTY[p.trim().toLowerCase()] || p.trim().toUpperCase()).join("");
  function actLabel(cfg, a, slot) {
    if (!a || a.type === "default") return trigName(cfg.slots[slot]);
    if (a.label) return a.label;
    const v = a.value || "";
    switch (a.type) {
      case "keys": return prettyCombo(v) || "Atajo";
      case "text": return "“" + v.replace(/\n/g, "↩") + "”";
      case "shell": return v || "Comando";
      case "app": return v || "App";
      case "url": return v.replace(/^https?:\/\//, "") || "Enlace";
      case "media": return (MEDIA.find(m => m[0] === v) || [0, "Multimedia"])[1];
      case "macro": return (cfg.macros.find(m => m.id === v) || { name: "Macro" }).name;
      case "profile": return v === "next" ? "Perfil ›" : v === "prev" ? "‹ Perfil" : ((cfg.profiles.find(p => p.id === v) || {}).name || "Perfil");
      case "none": return "Bloqueada";
      case "overlay": return "Chuleta";
    } return "";
  }
  return { MEDIA, trigName, prettyCombo, actLabel };
})();
