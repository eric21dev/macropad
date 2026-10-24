"use strict";
// ───────── puente con la app (o simulación si se abre en un navegador) ─────────
let _id = 0; const _pend = {};
window.__reply = (id, v) => { _pend[id]?.(v); delete _pend[id]; };
window.__event = (n, p) => onEvent(n, p);
const native = !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mp);
const bridge = (cmd, data) => new Promise(res => {
  if (!native) return res(mock(cmd, data));
  const id = ++_id; _pend[id] = res; window.webkit.messageHandlers.mp.postMessage({ id, cmd, data });
});
function mock(cmd) { return cmd === "init" ? mockInit() : true; }

// ───────── estado ─────────
const $ = (s, r = document) => r.querySelector(s);
const esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
let S = { config: null, status: {}, version: {}, apps: [], loginItem: false, tab: "pad", sel: null, learning: null, wizard: [], macroSel: null,
          setupDismissed: false, ledMsg: "", confirm: "", ledDraft: null };
const cur = () => S.config.profiles.find(p => p.id === S.config.activeProfile) || S.config.profiles[0];
let saveT; const save = () => { clearTimeout(saveT); saveT = setTimeout(() => bridge("save", S.config), 220); };

const KEYS = Array.from({ length: 15 }, (_, i) => "k" + (i + 1));
const ALLSLOTS = [...KEYS, ...["A", "B", "C"].flatMap(k => ["l", "p", "r"].map(d => k + "_" + d))];
const KNOBNAME = { A: "Mando A (pequeño de arriba)", B: "Mando B (pequeño de abajo)", C: "Mando C (grande)" };
const DIRNAME = { l: "giro a la izquierda", r: "giro a la derecha", p: "pulsar" };
const slotTitle = s => s[0] === "k" ? `Tecla ${s.slice(1)}` : `${KNOBNAME[s[0]]} · ${DIRNAME[s.slice(2)]}`;
const LEDC = { white: "#fff1d6", red: "#ff4b3a", orange: "#ff9a3c", yellow: "#ffd23c", green: "#4be07a", cyan: "#38e0e8", blue: "#4c8dff", purple: "#b46cff" };
const LEDN = { white: "Blanco", red: "Rojo", orange: "Naranja", yellow: "Amarillo", green: "Verde", cyan: "Cian", blue: "Azul", purple: "Púrpura" };
const TYPES = [["default", "Original (sin cambios)"], ["none", "Bloquear"], ["keys", "Atajo de teclado"], ["text", "Escribir texto"], ["macro", "Macro"],
  ["app", "Abrir app"], ["url", "Abrir enlace"], ["shell", "Comando de shell"], ["media", "Multimedia"], ["profile", "Cambiar de perfil"], ["overlay", "Mostrar chuleta del pad"]];
const MEDIA = Lbl.MEDIA;

// ───────── nombres legibles (compartidos con la chuleta) ─────────
const trigName = Lbl.trigName, prettyCombo = Lbl.prettyCombo;
const actLabel = (a, slot) => Lbl.actLabel(S.config, a, slot);
const act = s => cur().bindings[s] || { type: "default" };
function setAct(slot, patch, rerender) {
  const a = { ...act(slot), ...patch };
  if (a.type === "default" && !a.label) delete cur().bindings[slot]; else cur().bindings[slot] = a;
  save(); refreshPad(); if (rerender) renderInspector();
}

// ───────── pad ─────────
function ledColorOf(l) { return l && l.mode !== "off" ? (LEDC[l.color] || LEDC.blue) : null; }
function padHTML(readonly) {
  const p = cur(), col = ledColorOf(S.tab === "led" && S.ledDraft ? S.ledDraft : p.led) || "#4c8dff";
  const off = (S.tab === "led" && S.ledDraft ? S.ledDraft : p.led)?.mode === "off";
  const cls = s => [S.sel === s && !readonly ? "sel" : "", act(s).type !== "default" ? "bound" : ""].join(" ");
  const knob = (k, big) => `<div class="knobwrap ${big ? "big" : ""}"><div class="knob" id="knob${k}"><b>${k}</b></div><div class="kbtns">` +
    ["l", "p", "r"].map(d => { const s = k + "_" + d; return `<button class="kbtn ${cls(s)}" data-slot="${s}" title="${esc(slotTitle(s))}"><i>${{ l: "↺", p: "●", r: "↻" }[d]}</i><span>${esc(actLabel(act(s), s))}</span></button>`; }).join("") + `</div></div>`;
  return `<div class="pad" data-off="${off ? 1 : 0}" style="--led:${col}"><div class="plate"><div class="top"><div class="lcol">${knob("A")}${knob("B")}</div>${knob("C", true)}</div><div class="keys">` +
    KEYS.map((s, i) => `<button class="key ${cls(s)}" data-slot="${s}"><i>${i + 1}</i><span>${esc(actLabel(act(s), s))}</span></button>`).join("") + `</div></div></div>`;
}
function fitPad() {
  const st = $(".stage"), pd = $(".pad"); if (!st || !pd) return;
  const s = Math.min(1, (st.clientHeight - 14) / (pd.offsetHeight || 700), (st.clientWidth) / 380);
  pd.style.setProperty("--s", s.toFixed(3));
}
function refreshPad() {
  const st = $(".stage"); if (!st) return;
  const b = $(".banner", st); st.innerHTML = (b ? b.outerHTML : "") + padHTML(S.tab === "led"); bindPad(); fitPad();
}
function bindPad() {
  document.querySelectorAll("[data-slot]").forEach(el => el.onclick = () => {
    if (S.tab === "led") return;
    S.sel = el.dataset.slot; S.learning = null; S.wizard = []; refreshPad(); renderInspector(); renderBanner();
  });
}

// ───────── pestañas ─────────
const TABS = [["pad", "Asignar"], ["macros", "Macros"], ["led", "Iluminación"], ["settings", "Ajustes"]];
function renderTabs() { $("#tabs").innerHTML = TABS.map(([id, t]) => `<button class="${S.tab === id ? "on" : ""}" onclick="setTab('${id}')">${t}</button>`).join(""); }
function setTab(t) { S.tab = t; S.confirm = ""; render(); }

function renderProfiles() {
  $("#profiles").innerHTML = S.config.profiles.map(p => `<button class="prof ${p.id === S.config.activeProfile ? "on" : ""}" onclick="pickProfile('${p.id}')"><span class="dot"></span><span>${esc(p.name)}</span>${p.apps.length ? `<small>${p.apps.length} app${p.apps.length > 1 ? "s" : ""}</small>` : ""}</button>`).join("");
}
function pickProfile(id) { S.config.activeProfile = id; S.sel = null; S.ledDraft = null; save(); render(); }
function addProfile() {
  const n = S.config.profiles.length + 1, id = "p" + Date.now().toString(36);
  S.config.profiles.push({ id, name: "Perfil " + n, bindings: {}, led: null, apps: [] });
  S.config.activeProfile = id; S.sel = null; S.tab = "pad"; save(); render();
}
function renderChips() {
  const s = S.status, perms = s.input && s.accessibility;
  $("#chips").innerHTML = `<div class="chip ${s.device ? "ok" : ""}"><i></i>${s.device ? "Pad conectado" : "Pad no detectado"}</div><div class="chip ${perms ? "ok" : ""}"><i></i>${perms ? "Permisos concedidos" : "Faltan permisos"}</div>`;
}

function render() {
  renderTabs(); renderProfiles(); renderChips();
  const v = $("#view");
  if (S.tab === "pad") { v.innerHTML = `<div class="stage">${padHTML()}</div><div class="insp" id="insp"></div>`; bindPad(); renderInspector(); renderBanner(); setTimeout(fitPad, 0); }
  else if (S.tab === "macros") renderMacros(v);
  else if (S.tab === "led") renderLED(v);
  else renderSettings(v);
  renderOverlay();
}

// ───────── inspector ─────────
function renderInspector() {
  const el = $("#insp"); if (!el) return;
  if (!S.sel) return (el.innerHTML = profileCard());
  const s = S.sel, a = act(s), t = S.config.slots[s];
  const opts = TYPES.map(([v, n]) => `<option value="${v}" ${a.type === v ? "selected" : ""}>${n}</option>`).join("");
  el.innerHTML = `<h2>${esc(slotTitle(s))}</h2>
    <div class="sub">Envía: <code>${esc(trigName(t))}</code> · <button class="btn ghost sm" onclick="learn('${s}')">${S.learning === s ? "Pulsa en el pad…" : "Aprender"}</button></div>
    <label>Acción</label><select onchange="setType(this.value)">${opts}</select>
    ${fieldHTML(s, a)}
    ${a.type !== "default" ? `<label>Etiqueta (opcional)</label><input value="${esc(a.label || "")}" placeholder="Nombre corto" oninput="setAct('${s}',{label:this.value})">` : ""}
    <div class="row mt">${a.type !== "default" && a.type !== "none" ? `<button class="btn ghost sm" onclick="testAct()">Probar</button>` : ""}<button class="btn ghost sm" onclick="S.sel=null;refreshPad();renderInspector()">Cerrar</button></div>`;
}
function fieldHTML(s, a) {
  const v = esc(a.value || "");
  switch (a.type) {
    case "keys": return `<label>Atajo</label><div class="row"><input class="f" id="keysIn" value="${v}" placeholder="cmd+shift+4" oninput="setAct('${s}',{value:this.value})"><button class="btn ghost sm" onclick="recordKeys()" id="recBtn">Grabar</button></div><div class="hint">Modificadores: cmd, shift, alt, ctrl, fn. Ej.: <code>cmd+shift+4</code>, <code>fn+f11</code>. «Grabar» no detecta fn: añádela a mano.</div>`;
    case "text": return `<label>Texto a escribir</label><textarea oninput="setAct('${s}',{value:this.value})">${v}</textarea>`;
    case "shell": return `<label>Comando</label><textarea placeholder="open -a Calculator" oninput="setAct('${s}',{value:this.value})">${v}</textarea>`;
    case "app": return `<label>Aplicación</label><div class="row"><input class="f" value="${v}" placeholder="Safari" oninput="setAct('${s}',{value:this.value})"><button class="btn ghost sm" onclick="pickApp('${s}')">Elegir…</button></div>`;
    case "url": return `<label>Enlace</label><input value="${v}" placeholder="https://…" oninput="setAct('${s}',{value:this.value})">`;
    case "media": return `<label>Tecla multimedia</label><select onchange="setAct('${s}',{value:this.value},true)">${MEDIA.map(([k, n]) => `<option value="${k}" ${a.value === k ? "selected" : ""}>${n}</option>`).join("")}</select>`;
    case "macro": return `<label>Macro</label>${S.config.macros.length ? `<select onchange="setAct('${s}',{value:this.value})">${S.config.macros.map(m => `<option value="${m.id}" ${a.value === m.id ? "selected" : ""}>${esc(m.name)}</option>`).join("")}</select>` : `<div class="hint">Aún no hay macros.</div>`}<button class="btn ghost sm mt" onclick="setTab('macros')">Ir a Macros</button>`;
    case "profile": return `<label>Perfil</label><select onchange="setAct('${s}',{value:this.value})"><option value="next" ${a.value === "next" ? "selected" : ""}>Siguiente perfil</option><option value="prev" ${a.value === "prev" ? "selected" : ""}>Anterior perfil</option>${S.config.profiles.map(p => `<option value="${p.id}" ${a.value === p.id ? "selected" : ""}>${esc(p.name)}</option>`).join("")}</select>`;
    case "overlay": return `<label>Segundos visible</label><input type="number" min="1" max="10" step="1" value="${v || 2}" oninput="setAct('${s}',{value:this.value})"><div class="hint">Muestra sobre la pantalla el pad con lo que hace cada tecla y mando del perfil activo, y se cierra solo. Ideal como chuleta.</div>`;
    case "default": return `<div class="hint">La posición hace lo que el pad envía de fábrica.</div>`;
    case "none": return `<div class="hint">La pulsación se descarta y no hace nada.</div>`;
  } return "";
}
function setType(t) {
  const s = S.sel, d = { media: "playpause", profile: "next", overlay: "2", macro: S.config.macros[0]?.id || "" }[t];
  const a = { type: t, value: d ?? "", label: act(s).label };
  if (t === "default") { delete cur().bindings[s]; } else cur().bindings[s] = a;
  save(); refreshPad(); renderInspector();
}
function testAct() { bridge("test", act(S.sel)); }
async function pickApp(s) { const r = await bridge("pickApp"); if (r && r.name) { setAct(s, { value: r.name }, true); } }

let recHandler = null;
function recordKeys() {
  const btn = $("#recBtn"); if (!btn) return;
  if (recHandler) { document.removeEventListener("keydown", recHandler, true); recHandler = null; btn.textContent = "Grabar"; return; }
  btn.textContent = "Pulsa el atajo…";
  const codes = { Space: "space", Enter: "return", Escape: "esc", Backspace: "delete", Tab: "tab", ArrowLeft: "left", ArrowRight: "right", ArrowUp: "up", ArrowDown: "down", Minus: "-", Equal: "=", BracketLeft: "[", BracketRight: "]", Semicolon: ";", Quote: "'", Comma: ",", Period: ".", Slash: "/", Backslash: "\\", Backquote: "`", Home: "home", End: "end", PageUp: "pageup", PageDown: "pagedown" };
  recHandler = e => {
    e.preventDefault(); e.stopPropagation();
    let k = e.code.startsWith("Key") ? e.code.slice(3).toLowerCase() : e.code.startsWith("Digit") ? e.code.slice(5) : /^F\d+$/.test(e.code) ? e.code.toLowerCase() : codes[e.code];
    if (!k) return;
    const c = [e.metaKey && "cmd", e.shiftKey && "shift", e.altKey && "alt", e.ctrlKey && "ctrl", k].filter(Boolean).join("+");
    document.removeEventListener("keydown", recHandler, true); recHandler = null;
    setAct(S.sel, { value: c }, true);
  };
  document.addEventListener("keydown", recHandler, true);
}

function profileCard() {
  const p = cur(), apps = p.apps.map(id => `<span class="tag">${esc((S.apps.find(a => a.id === id) || { name: id }).name)}<button onclick="rmApp('${esc(id)}')">×</button></span>`).join("");
  const free = S.apps.filter(a => !p.apps.includes(a.id));
  return `<h2>Perfil</h2><div class="sub">Elige una tecla o un mando del pad para asignarle una acción.</div>
    <label>Nombre</label><input value="${esc(p.name)}" oninput="cur().name=this.value;save();renderProfiles()">
    <label>Se activa solo con estas apps</label><div class="tags">${apps || `<span class="hint">Ninguna: solo manualmente.</span>`}</div>
    <div class="row mt"><select class="f" id="appSel"><option value="">Añadir app abierta…</option>${free.map(a => `<option value="${esc(a.id)}">${esc(a.name)}</option>`).join("")}</select><button class="btn ghost sm" onclick="addApp()">Añadir</button></div>
    <div class="hint">${S.config.autoSwitch ? "El cambio automático está activado." : "El cambio automático está desactivado en Ajustes."}</div>
    <div class="row mt"><button class="btn ghost sm" onclick="dupProfile()">Duplicar</button>${S.config.profiles.length > 1 ? `<button class="btn danger sm" onclick="delProfile()">${S.confirm === "prof" ? "¿Seguro? Pulsa otra vez" : "Eliminar"}</button>` : ""}</div>`;
}
function addApp() { const v = $("#appSel").value; if (v) { cur().apps.push(v); save(); renderProfiles(); renderInspector(); } }
function rmApp(id) { cur().apps = cur().apps.filter(a => a !== id); save(); renderProfiles(); renderInspector(); }
function dupProfile() { const p = JSON.parse(JSON.stringify(cur())); p.id = "p" + Date.now().toString(36); p.name += " (copia)"; p.apps = []; S.config.profiles.push(p); S.config.activeProfile = p.id; save(); render(); }
function delProfile() {
  if (S.confirm !== "prof") { S.confirm = "prof"; return renderInspector(); }
  S.config.profiles = S.config.profiles.filter(p => p.id !== S.config.activeProfile); S.config.activeProfile = S.config.profiles[0].id; S.confirm = ""; save(); render();
}

// ───────── aprender posiciones ─────────
function learn(slot) { S.learning = slot; S.wizard = []; renderInspector(); renderBanner(); }
function startWizard() { S.wizard = ALLSLOTS.slice(1); S.learning = ALLSLOTS[0]; S.sel = null; S.tab = "pad"; render(); }
function cancelLearn() { S.learning = null; S.wizard = []; renderBanner(); renderInspector(); }
function renderBanner() {
  const st = $(".stage"); if (!st) return; $(".banner", st)?.remove();
  if (!S.learning) return;
  const total = ALLSLOTS.length, n = S.wizard.length ? total - S.wizard.length : 1;
  st.insertAdjacentHTML("afterbegin", `<div class="banner"><span>Pulsa en el pad: <b>${esc(slotTitle(S.learning))}</b>${S.wizard.length ? ` (${n}/${total})` : ""}</span><button class="btn ghost sm" onclick="cancelLearn()">Cancelar</button></div>`);
}

// ───────── macros ─────────
const STEPT = [["keys", "Atajo"], ["text", "Texto"], ["delay", "Espera"], ["shell", "Comando"], ["app", "Abrir app"], ["url", "Enlace"], ["media", "Multimedia"]];
function renderMacros(v) {
  const ms = S.config.macros; if (!ms.find(m => m.id === S.macroSel)) S.macroSel = ms[0]?.id || null;
  const m = ms.find(x => x.id === S.macroSel);
  v.innerHTML = `<div class="list"><div class="sec" style="margin-left:2px">Macros</div>${ms.map(x => `<button class="prof ${x.id === S.macroSel ? "on" : ""}" onclick="S.macroSel='${x.id}';S.confirm='';render()"><span class="dot"></span>${esc(x.name)}<small>${x.steps.length}</small></button>`).join("")}<button class="add" onclick="addMacro()">+ Nueva macro</button></div>
  <div class="scroll"><div class="card">${m ? macroEditor(m) : `<h2>Macros</h2><div class="sub">Una macro es una secuencia de pasos (atajos, texto, esperas, comandos…) que se lanza con una sola tecla del pad. Crea la primera.</div><button class="btn" onclick="addMacro()">Nueva macro</button>`}</div></div>`;
}
function macroEditor(m) {
  const rows = m.steps.map((s, i) => `<div class="step"><select onchange="stepType(${i},this.value)">${STEPT.map(([k, n]) => `<option value="${k}" ${s.t === k ? "selected" : ""}>${n}</option>`).join("")}</select>${stepValue(s, i)}
    <button class="ic" onclick="moveStep(${i},-1)">↑</button><button class="ic" onclick="moveStep(${i},1)">↓</button><button class="ic" onclick="delStep(${i})">×</button></div>`).join("");
  return `<h2>Editar macro</h2><label>Nombre</label><input value="${esc(m.name)}" oninput="curMacro().name=this.value;save()" onblur="render()">
    <label>Pasos</label>${rows || `<div class="hint">Sin pasos todavía.</div>`}
    <div class="row mt" style="flex-wrap:wrap">${STEPT.map(([k, n]) => `<button class="btn ghost sm" onclick="addStep('${k}')">+ ${n}</button>`).join("")}</div>
    <div class="row mt"><button class="btn sm" onclick="bridge('testMacro',curMacro())">Probar</button><button class="btn danger sm" onclick="delMacro()">${S.confirm === "macro" ? "¿Seguro? Pulsa otra vez" : "Eliminar"}</button></div>
    <div class="hint">Asígnala a una tecla en «Asignar» → Acción «Macro». Las teclas se escriben donde tengas el cursor.</div>`;
}
function stepValue(s, i) {
  if (s.t === "delay") return `<input class="f" type="number" min="0" max="10000" step="50" value="${s.ms ?? 200}" oninput="curMacro().steps[${i}].ms=+this.value;save()"><span class="hint" style="margin:0">ms</span>`;
  if (s.t === "media") return `<select class="f" onchange="curMacro().steps[${i}].v=this.value;save()" style="width:auto">${MEDIA.map(([k, n]) => `<option value="${k}" ${s.v === k ? "selected" : ""}>${n}</option>`).join("")}</select>`;
  const ph = { keys: "cmd+c", text: "Texto…", shell: "comando", app: "Safari", url: "https://" }[s.t];
  return `<input class="f" value="${esc(s.v || "")}" placeholder="${ph}" oninput="curMacro().steps[${i}].v=this.value;save()">`;
}
const curMacro = () => S.config.macros.find(m => m.id === S.macroSel);
function addMacro() { const id = "m" + Date.now().toString(36); S.config.macros.push({ id, name: "Macro " + (S.config.macros.length + 1), steps: [] }); S.macroSel = id; save(); render(); }
function delMacro() { if (S.confirm !== "macro") { S.confirm = "macro"; return render(); } const id = S.macroSel; S.config.macros = S.config.macros.filter(m => m.id !== id);
  S.config.profiles.forEach(p => Object.keys(p.bindings).forEach(k => { if (p.bindings[k].type === "macro" && p.bindings[k].value === id) delete p.bindings[k]; })); S.confirm = ""; save(); render(); }
function addStep(t) { curMacro().steps.push(t === "delay" ? { t, ms: 300 } : t === "media" ? { t, v: "playpause" } : { t, v: "" }); save(); render(); }
function stepType(i, t) { const s = curMacro().steps[i]; s.t = t; if (t === "delay") s.ms = s.ms ?? 300; if (t === "media") s.v = "playpause"; save(); render(); }
function moveStep(i, d) { const a = curMacro().steps, j = i + d; if (j < 0 || j >= a.length) return; [a[i], a[j]] = [a[j], a[i]]; save(); render(); }
function delStep(i) { curMacro().steps.splice(i, 1); save(); render(); }

// ───────── iluminación ─────────
const LEDMODES = [["backlight", "Fijo", "Siempre encendido"], ["press", "Al pulsar", "Se ilumina la tecla"], ["shock", "Efecto", "Destello al pulsar"], ["shock2", "Efecto 2", "Otro destello"], ["off", "Apagado", "Sin luz"]];
function renderLED(v) {
  const p = cur(); if (!S.ledDraft) S.ledDraft = p.led ? { ...p.led, layer: 0 } : { layer: 0, mode: "backlight", color: "blue" };
  const d = S.ledDraft, colors = Object.keys(LEDC).filter(c => c !== "white" || d.mode === "backlight");
  if (!colors.includes(d.color) && d.mode !== "off") d.color = "blue";
  v.innerHTML = `<div class="stage">${padHTML(true)}</div><div class="insp" style="width:380px"><h2>Iluminación</h2><div class="sub">Se guarda en el propio pad y se conserva al enchufarlo en otro ordenador.</div>
    <label>Modo</label><div class="modes">${LEDMODES.map(([k, n, s]) => `<button class="mode ${d.mode === k ? "on" : ""}" onclick="ledSet('mode','${k}')">${n}<small>${s}</small></button>`).join("")}</div>
    ${d.mode !== "off" ? `<label>Color</label><div class="sw">${colors.map(c => `<button title="${LEDN[c]}" class="${d.color === c ? "on" : ""}" style="--c:${LEDC[c]}" onclick="ledSet('color','${c}')"></button>`).join("")}</div>` : ""}
    <div class="tog"><div class="f"><b>Usar en el perfil «${esc(p.name)}»</b><div class="hint" style="margin:0">Se aplica al activar el perfil.</div></div><button class="sw2 ${p.led ? "on" : ""}" onclick="ledProfile()"></button></div>
    <div class="row"><button class="btn sm" onclick="ledApply()">Aplicar al pad</button><span class="hint" id="ledMsg" style="margin:0">${esc(S.ledMsg)}</span></div></div>`;
  bindPad(); setTimeout(fitPad, 0);
}
function ledSet(k, v) { S.ledDraft[k] = v; if (cur().led) { cur().led = { ...S.ledDraft }; save(); } renderLED($("#view")); ledApply(); }
function ledProfile() { cur().led = cur().led ? null : { ...S.ledDraft }; save(); renderLED($("#view")); }
let ledT; function ledApply() {
  clearTimeout(ledT); ledT = setTimeout(async () => { const ok = await bridge("led", S.ledDraft); S.ledMsg = ok ? "Enviado al pad ✓" : "No se pudo enviar (¿pad desconectado o sin permisos?)"; const m = $("#ledMsg"); if (m) m.textContent = S.ledMsg; }, 150);
}

// ───────── ajustes y permisos ─────────
function permRows() {
  const s = S.status, row = (ok, t, d, btn) => `<div class="perm ${ok ? "ok" : ""}"><span class="s">${ok ? "✓" : "!"}</span><div><b>${t}</b><small>${d}</small></div>${!ok && btn ? btn : ""}</div>`;
  return row(s.device, "Pad conectado", s.device ? "Detectado por USB (1189:8840)" : "Conéctalo por USB y comprueba que el interruptor no está apagado") +
    row(s.input, "Monitorización de entrada", "Para leer las teclas del pad", `<button class="btn sm" onclick="bridge('perm','input')">Dar acceso</button>`) +
    row(s.accessibility, "Accesibilidad", "Para lanzar atajos y bloquear la tecla original", `<button class="btn sm" onclick="bridge('perm','ax')">Dar acceso</button>`);
}
function renderSettings(v) {
  v.innerHTML = `<div class="scroll"><div class="card"><h2>Permisos y estado</h2><div class="sub">Se comprueban en vivo. Tras conceder uno, macOS a veces pide reiniciar la app.</div>${permRows()}
      <div class="row mt"><button class="btn ghost sm" onclick="bridge('relaunch')">Reiniciar Macropad</button><button class="btn ghost sm" onclick="bridge('settings','input')">Abrir Ajustes del Sistema</button></div></div>
    <div class="card"><h2>General</h2>
      <div class="tog"><div class="f"><b>Abrir al iniciar sesión</b><div class="hint" style="margin:0">Se queda en la barra de menú, sin ventana.</div></div><button class="sw2 ${S.loginItem ? "on" : ""}" onclick="toggleLogin()"></button></div>
      <div class="tog"><div class="f"><b>Cambiar de perfil según la app activa</b><div class="hint" style="margin:0">Usa las apps asignadas a cada perfil.</div></div><button class="sw2 ${S.config.autoSwitch ? "on" : ""}" onclick="S.config.autoSwitch=!S.config.autoSwitch;save();render()"></button></div></div>
    <div class="card"><h2>Mapa del pad</h2><div class="sub">Cada tecla y mando envía un código. Si cambias de pad o algo no cuadra, vuelve a enseñárselos uno a uno (24 posiciones).</div><button class="btn ghost sm" onclick="startWizard()">Aprender todo</button></div>
    <div class="card"><h2>Acerca de</h2><div class="sub" style="margin:0">Macropad · ${esc(S.version.version || "")} · ${esc(S.version.branch || "")} ${esc(S.version.commit || "")}. Configuración en <code>~/Library/Application Support/Macropad</code>.</div></div></div>`;
}
async function toggleLogin() { S.loginItem = await bridge("login", !S.loginItem); render(); }

// ───────── primera ejecución ─────────
function renderOverlay() {
  const o = $("#overlay"), s = S.status, ok = s.device && s.input && s.accessibility;
  if (S.setupDismissed || (ok && !S._showedSetup)) { o.hidden = true; return; }
  S._showedSetup = true;
  o.hidden = false;
  o.innerHTML = `<div class="card"><h2>${ok ? "Todo listo" : "Vamos a dejarlo listo"}</h2><div class="sub">${ok ? "Macropad ya puede leer el pad y lanzar acciones." : "Macropad necesita dos permisos de macOS y el pad conectado."}</div>${permRows()}
    <div class="hint">Si tras dar un permiso no se marca, pulsa «Reiniciar Macropad».</div>
    <div class="row mt"><button class="btn ghost sm" onclick="bridge('relaunch')">Reiniciar Macropad</button><div class="f"></div><button class="btn sm" onclick="S.setupDismissed=true;renderOverlay()">${ok ? "Empezar" : "Más tarde"}</button></div></div>`;
}

// ───────── eventos de la app ─────────
function onEvent(n, p) {
  if (n === "status") { S.status = p; renderChips(); renderOverlay(); if (S.tab === "settings") render(); }
  else if (n === "state") { if (p.activeProfile) S.config.activeProfile = p.activeProfile; S.ledDraft = null; S.sel = null; render(); }
  else if (n === "pad") {
    if (S.learning) {
      for (const k in S.config.slots) if (S.config.slots[k] === p.trigger && k !== S.learning) delete S.config.slots[k];
      S.config.slots[S.learning] = p.trigger; save();
      if (S.wizard.length) { S.learning = S.wizard.shift(); S.sel = S.learning; } else S.learning = null;
      refreshPad(); renderInspector(); renderBanner(); return;
    }
    if (!p.slot) return;
    const el = document.querySelector(`[data-slot="${p.slot}"]`); if (el) { el.classList.add("flash"); setTimeout(() => el.classList.remove("flash"), 220); }
    const kn = p.slot.match(/^([ABC])_([lr])$/); const kb = kn && $("#knob" + kn[1]); if (kb) kb.style.setProperty("--rot", (kn[2] === "l" ? -75 : 5) + "deg");
  }
}
function badge() {
  const v = S.version, d = v.date ? new Date(v.date) : null, pad = n => String(n).padStart(2, "0");
  const when = d && !isNaN(d) ? `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}` : "";
  $("#badge").textContent = `${v.branch} · ${v.commit}${v.dirty ? "*" : ""}${when ? " · " + when : ""}`;
}

(async () => {
  const r = await bridge("init");
  S.config = r.config; S.status = r.status; S.version = r.version; S.apps = r.apps; S.loginItem = r.loginItem;
  if (!native) { const q = new URLSearchParams(location.search); S.tab = q.get("tab") || "pad"; S.sel = q.get("sel") || null; S.setupDismissed = q.get("setup") !== "1"; if (q.get("off")) { S.status.input = false; S.status.accessibility = false; } }  // solo pruebas en navegador
  badge(); render();
  addEventListener("resize", fitPad);
  setInterval(async () => { S.apps = await bridge("apps"); }, 15000);
})();
