"use strict";
// Chuleta flotante: el pad con lo que hace cada posición del perfil activo. La app nativa llama a window.show(...).
const LEDC = { white: "#fff1d6", red: "#ff4b3a", orange: "#ff9a3c", yellow: "#ffd23c", green: "#4be07a", cyan: "#38e0e8", blue: "#4c8dff", purple: "#b46cff" };
const esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

window.show = ({ config, profile, seconds }) => {
  const p = config.profiles.find(x => x.id === profile) || config.profiles[0];
  const act = s => p.bindings[s] || { type: "default" };
  const label = s => Lbl.actLabel(config, act(s), s), dim = s => act(s).type === "default" ? "dim" : "";
  const col = p.led && p.led.mode !== "off" ? LEDC[p.led.color] || LEDC.blue : "#ffb347";
  const knob = (k, big) => `<div class="knobwrap ${big ? "big" : ""}"><div class="knob"><b>${k}</b></div><div class="kbtns">` +
    ["l", "p", "r"].map(d => { const s = k + "_" + d; return `<div class="kbtn ${dim(s)}"><i>${{ l: "↺", p: "●", r: "↻" }[d]}</i><span>${esc(label(s))}</span></div>`; }).join("") + `</div></div>`;
  const keys = Array.from({ length: 15 }, (_, i) => "k" + (i + 1)).map((s, i) => `<div class="key ${dim(s)}"><i>${i + 1}</i><span>${esc(label(s))}</span></div>`).join("");
  const hud = document.getElementById("hud");
  hud.innerHTML = `<div class="hd"><b>${esc(p.name)}</b><span>Chuleta del pad</span></div><div class="pad" style="--led:${col}"><div class="plate"><div class="top"><div class="lcol">${knob("A")}${knob("B")}</div>${knob("C", true)}</div><div class="keys">${keys}</div></div></div>`;
  const k = Math.min(1, (innerHeight - 4) / hud.offsetHeight, innerWidth / hud.offsetWidth);
  hud.style.setProperty("--k", k.toFixed(3));
  hud.classList.remove("run"); void hud.offsetWidth;
  hud.style.setProperty("--dur", Math.max(1, seconds) + "s");
  hud.classList.add("run");
};

if (!(window.webkit && window.webkit.messageHandlers)) {   // solo pruebas en navegador
  const c = mockInit().config; c.profiles[0].bindings.k4 = { type: "overlay", value: "2" };
  window.show({ config: c, profile: c.activeProfile, seconds: 600 });
}
