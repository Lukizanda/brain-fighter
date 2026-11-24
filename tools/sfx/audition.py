#!/usr/bin/env python3
"""Build a single self-contained HTML page for auditioning rendered SFX.

Usage: python tools/sfx/audition.py [--dir build/sfx] [--out build/sfx/audition.html]
"""
import argparse
import base64
import json
import sys
from pathlib import Path

PLACEHOLDER = "__AUDITION_DATA__"

TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>SFX audition</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root{--bg:#f6f6f4;--fg:#1d1d1b;--mut:#6b6b66;--card:#fff;--line:#d9d9d3;--acc:#1f6feb;--accbg:#e4eeff;--hot:#fff1c9;--wave:#3a3a36}
@media (prefers-color-scheme:dark){:root{--bg:#161616;--fg:#e8e8e4;--mut:#9a9a94;--card:#202020;--line:#3a3a36;--acc:#6aa5ff;--accbg:#1c2b44;--hot:#4a3f12;--wave:#c9c9c2}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.4 system-ui,Segoe UI,sans-serif}
header.bar{position:sticky;top:0;z-index:5;background:var(--card);border-bottom:1px solid var(--line);padding:8px 16px;display:flex;gap:16px;align-items:center;flex-wrap:wrap}
header.bar h1{font-size:16px;margin:0}
button{font:inherit;color:inherit;background:var(--card);border:1px solid var(--line);border-radius:6px;padding:4px 10px;cursor:pointer}
button:hover{border-color:var(--acc)}
button.primary{background:var(--acc);border-color:var(--acc);color:#fff}
button:focus-visible,input:focus-visible,textarea:focus-visible{outline:2px solid var(--acc);outline-offset:1px}
label.vol{display:flex;gap:6px;align-items:center;color:var(--mut)}
.hint{color:var(--mut);font-size:12px}
main{padding:12px 16px}
table{border-collapse:collapse;width:100%;table-layout:fixed}
th,td{border-bottom:1px solid var(--line);padding:6px 8px;vertical-align:top;text-align:left}
thead th{position:sticky;top:var(--barh,48px);background:var(--bg);z-index:4;border-bottom:2px solid var(--line)}
col.c-cue{width:23%}col.c-fb{width:19%}
tr.group th{background:var(--accbg);font-size:12px;text-transform:uppercase;letter-spacing:.05em;padding:4px 8px;position:static}
.cue .lbl{font-weight:600}
.cue .note{color:var(--mut);font-size:12px}
.cue code,.tag{font:11px ui-monospace,Consolas,monospace;color:var(--mut)}
.tag{border:1px solid var(--line);border-radius:4px;padding:0 4px;margin-left:4px}
.cue .ab{margin-top:4px;font-size:12px;padding:2px 8px}
td.cell{position:relative}
td.cell.hot{background:var(--hot)}
.wavebox{position:relative;height:48px;margin-top:4px;cursor:pointer;border:1px solid var(--line);border-radius:4px;background:var(--card)}
.wavebox canvas{width:100%;height:100%;display:block}
.ph{position:absolute;top:0;bottom:0;width:2px;background:var(--acc);left:0;display:none;pointer-events:none}
.row1{display:flex;justify-content:space-between;align-items:center;gap:6px}
.dur{color:var(--mut);font-size:12px;font-variant-numeric:tabular-nums}
.none{color:var(--mut);font-style:italic}
.fb label{margin-right:8px;white-space:nowrap;font-size:13px}
.fb textarea{width:100%;height:36px;margin-top:4px;font:12px system-ui,sans-serif;color:inherit;background:var(--card);border:1px solid var(--line);border-radius:4px;resize:vertical}
#summary{width:100%;height:140px;margin-top:8px;font:12px ui-monospace,Consolas,monospace;color:inherit;background:var(--card);border:1px solid var(--line);border-radius:4px}
#status{color:var(--mut);font-size:12px}
</style>
</head>
<body>
<header class="bar" id="bar">
  <h1>SFX audition</h1>
  <button id="stop">Stop (Space)</button>
  <label class="vol">Volume <input type="range" id="vol" min="0" max="1" step="0.01" value="0.8"></label>
  <button id="copy" class="primary">Copy feedback</button>
  <span id="status"></span>
</header>
<main>
  <table id="tbl"></table>
  <h2 style="font-size:14px;margin:16px 0 0">Feedback summary</h2>
  <div class="hint">Copied text appears here too. If Copy fails, select it here and copy by hand.</div>
  <textarea id="summary" readonly></textarea>
</main>
<script type="application/json" id="data">__AUDITION_DATA__</script>
<script>
"use strict";
const DATA = JSON.parse(document.getElementById("data").textContent);
const GAP_SEQ_MS = 350, GAP_AB_MS = 250, KEY = "sfxAudition:";
const $ = (s, r) => (r || document).querySelector(s);
function el(tag, props, kids) {
  const e = document.createElement(tag);
  Object.assign(e, props || {});
  (kids || []).forEach(k => e.append(k));
  return e;
}
const sleep = ms => new Promise(r => setTimeout(r, ms));

let ctx = null, master = null, cur = null, runId = 0;
const cells = {};   // "kit|cue" -> {buf, canvas, td, ph, dur}
const decoded = [];

function audio() {
  if (!ctx) {
    ctx = new (window.AudioContext || window.webkitAudioContext)();
    master = ctx.createGain();
    master.gain.value = +$("#vol").value;
    master.connect(ctx.destination);
  }
  if (ctx.state === "suspended") ctx.resume();
  return ctx;
}

function b64ToBuf(b64) {
  const bin = atob(b64), u = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
  return u.buffer;
}

function drawWave(c) {
  const cv = c.canvas, dpr = window.devicePixelRatio || 1;
  const w = Math.max(40, cv.clientWidth), h = cv.clientHeight || 48;
  cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr);
  const g = cv.getContext("2d");
  g.scale(dpr, dpr);
  g.clearRect(0, 0, w, h);
  const css = getComputedStyle(document.body);
  g.strokeStyle = css.getPropertyValue("--line"); g.beginPath(); g.moveTo(0, h / 2); g.lineTo(w, h / 2); g.stroke();
  if (!c.buf) return;
  const d = c.buf.getChannelData(0), step = d.length / w;
  g.fillStyle = getComputedStyle(document.documentElement).getPropertyValue("--wave") || "#444";
  for (let x = 0; x < w; x++) {
    let mn = 1, mx = -1;
    const a = Math.floor(x * step), b = Math.min(d.length, Math.floor((x + 1) * step) + 1);
    for (let i = a; i < b; i++) { const v = d[i]; if (v < mn) mn = v; if (v > mx) mx = v; }
    if (mn > mx) continue;
    const y1 = (1 - mx) * h / 2, y2 = (1 - mn) * h / 2;
    g.fillRect(x, y1, 1, Math.max(1, y2 - y1));
  }
}

function clearHot() {
  document.querySelectorAll("td.hot").forEach(t => t.classList.remove("hot"));
  document.querySelectorAll(".ph").forEach(p => p.style.display = "none");
}
function stopSource() {
  if (cur) {
    const c = cur; cur = null;
    c.src.onended = null;
    try { c.src.stop(); } catch (e) {}
    c.finish();
  }
}
function stopAll() { runId++; stopSource(); clearHot(); }
function beginRun() { stopAll(); return runId; }

function playOne(c) {
  stopSource(); clearHot();
  return new Promise(resolve => {
    const a = audio(), src = a.createBufferSource();
    src.buffer = c.buf; src.connect(master);
    const t0 = a.currentTime;
    c.td.classList.add("hot"); c.ph.style.display = "block";
    let done = false;
    const finish = () => {
      if (done) return; done = true;
      c.td.classList.remove("hot"); c.ph.style.display = "none"; resolve();
    };
    cur = { src, finish };
    src.onended = () => { if (cur && cur.src === src) cur = null; finish(); };
    src.start();
    (function tick() {
      if (done) return;
      const f = Math.min(1, (a.currentTime - t0) / c.buf.duration);
      c.ph.style.left = (f * 100) + "%";
      requestAnimationFrame(tick);
    })();
  });
}

function playCell(kit, cue) {
  const c = cells[kit + "|" + cue];
  if (!c || !c.buf) return;
  beginRun();
  playOne(c);
}
async function runSeq(list, gap) {
  const id = beginRun();
  for (let i = 0; i < list.length; i++) {
    if (id !== runId) return;
    await playOne(list[i]);
    if (id !== runId) return;
    if (i < list.length - 1) await sleep(gap);
  }
}
function playAB(cue) {
  runSeq(DATA.kits.map(k => cells[k.id + "|" + cue]).filter(c => c && c.buf), GAP_AB_MS);
}
function playKit(kit) {
  runSeq(DATA.cues.map(q => cells[kit + "|" + q.id]).filter(c => c && c.buf), GAP_SEQ_MS);
}

/* ---- feedback ---- */
function load(cue) { try { return JSON.parse(localStorage.getItem(KEY + cue)) || {}; } catch (e) { return {}; } }
function save(cue, o) { try { localStorage.setItem(KEY + cue, JSON.stringify(o)); } catch (e) {} }
function summary() {
  const kitLabel = {}; DATA.kits.forEach(k => kitLabel[k.id] = k.label || k.id);
  const lines = ["SFX audition feedback", "Kits: " + DATA.kits.map(k => k.id + " = " + (k.label || k.id)).join("; "), ""];
  let n = 0;
  DATA.cues.forEach(q => {
    const s = load(q.id);
    if (!s.pick && !(s.note || "").trim()) return;
    n++;
    const pick = !s.pick ? "(no choice)" : s.pick === "either" ? "either" : (kitLabel[s.pick] || s.pick);
    lines.push(q.label + " [" + q.id + "]: " + pick + ((s.note || "").trim() ? " - " + s.note.trim() : ""));
  });
  if (!n) lines.push("(no choices or notes recorded yet)");
  return lines.join("\n");
}
function refreshSummary() { $("#summary").value = summary(); }

/* ---- build table ---- */
function build() {
  const tbl = $("#tbl");
  const colgroup = el("colgroup", {}, [el("col", { className: "c-cue" })]);
  DATA.kits.forEach(() => colgroup.append(el("col")));
  colgroup.append(el("col", { className: "c-fb" }));
  tbl.append(colgroup);
  const hr = el("tr", {}, [el("th", { textContent: "Cue" })]);
  DATA.kits.forEach(k => {
    const b = el("button", { textContent: "Play all", title: "Play every cue of this kit, top to bottom" });
    b.onclick = () => playKit(k.id);
    hr.append(el("th", {}, [el("div", { style: "font-weight:600", textContent: k.label || k.id }),
      el("code", { className: "tag", textContent: k.id, style: "margin:0 6px 0 0" }), b]));
  });
  hr.append(el("th", { textContent: "Your pick" }));
  tbl.append(el("thead", {}, [hr]));
  const tb = el("tbody");
  tbl.append(tb);
  const ncol = DATA.kits.length + 2;
  let lastGroup = null;
  DATA.cues.forEach(q => {
    if (q.group !== lastGroup) {
      lastGroup = q.group;
      tb.append(el("tr", { className: "group" }, [el("th", { colSpan: ncol, textContent: q.group || "" })]));
    }
    const ab = el("button", { className: "ab", textContent: "A/B", title: "Play each kit's version in turn" });
    ab.onclick = () => playAB(q.id);
    const head = el("td", { className: "cue" }, [
      el("div", { className: "lbl", textContent: q.label || q.id }),
      el("div", { className: "note", textContent: q.note || "" }),
      el("div", {}, [el("code", { textContent: q.id }), el("span", { className: "tag", textContent: q.band || "" })]),
      ab]);
    const tr = el("tr", {}, [head]);
    DATA.kits.forEach(k => {
      const td = el("td", { className: "cell" });
      const c = cells[k.id + "|" + q.id] = { td, buf: null };
      if (!(DATA.files[k.id] || {})[q.id]) {
        td.append(el("span", { className: "none", textContent: "no file" }));
      } else {
        const play = el("button", { textContent: "▶ Play" });
        play.onclick = () => playCell(k.id, q.id);
        c.dur = el("span", { className: "dur", textContent: "..." });
        c.canvas = el("canvas");
        c.ph = el("div", { className: "ph" });
        const box = el("div", { className: "wavebox", title: "Click to play" }, [c.canvas, c.ph]);
        box.onclick = () => playCell(k.id, q.id);
        td.append(el("div", { className: "row1" }, [play, c.dur]), box);
      }
      tr.append(td);
    });
    const s = load(q.id), fb = el("td", { className: "fb" });
    const name = "pick-" + q.id;
    const opts = DATA.kits.map(k => [k.id, k.label || k.id]).concat([["either", "either"]]);
    opts.forEach(([v, lab]) => {
      const r = el("input", { type: "radio", name, value: v, checked: s.pick === v });
      r.onchange = () => { const o = load(q.id); o.pick = v; save(q.id, o); refreshSummary(); };
      fb.append(el("label", {}, [r, " " + lab]));
    });
    const ta = el("textarea", { placeholder: "Notes", value: s.note || "" });
    ta.oninput = () => { const o = load(q.id); o.note = ta.value; save(q.id, o); refreshSummary(); };
    fb.append(ta);
    tr.append(fb);
    tb.append(tr);
  });
}

async function decodeAll() {
  const a = audio();
  let n = 0;
  for (const k of DATA.kits) for (const q of DATA.cues) {
    const b64 = (DATA.files[k.id] || {})[q.id];
    if (!b64) continue;
    const c = cells[k.id + "|" + q.id];
    try {
      c.buf = await a.decodeAudioData(b64ToBuf(b64));
      c.dur.textContent = Math.round(c.buf.duration * 1000) + " ms";
      drawWave(c); n++;
    } catch (e) {
      c.dur.textContent = "decode failed";
      console.error("decode failed", k.id, q.id, e);
    }
  }
  $("#status").textContent = n + " sounds ready";
}

$("#vol").oninput = e => { if (master) master.gain.value = +e.target.value; };
$("#stop").onclick = stopAll;
$("#copy").onclick = async () => {
  refreshSummary();
  const t = $("#summary").value;
  try { await navigator.clipboard.writeText(t); $("#status").textContent = "Copied to clipboard"; }
  catch (e) {
    $("#summary").select();
    let ok = false; try { ok = document.execCommand("copy"); } catch (e2) {}
    $("#status").textContent = ok ? "Copied to clipboard" : "Clipboard blocked - copy from the box below";
  }
};
document.addEventListener("keydown", e => {
  if (e.code !== "Space") return;
  const t = e.target;
  if (t && (t.tagName === "TEXTAREA" || (t.tagName === "INPUT" && t.type === "text"))) return;
  e.preventDefault(); stopAll();
});
document.addEventListener("keyup", e => {
  if (e.code === "Space" && !(e.target && e.target.tagName === "TEXTAREA")) e.preventDefault();
});
let rt = null;
window.addEventListener("resize", () => {
  clearTimeout(rt);
  rt = setTimeout(() => { Object.values(cells).forEach(c => c.canvas && drawWave(c)); }, 150);
});
if (window.matchMedia) matchMedia("(prefers-color-scheme: dark)").addEventListener("change",
  () => Object.values(cells).forEach(c => c.canvas && drawWave(c)));

build();
document.documentElement.style.setProperty("--barh", $("#bar").offsetHeight + "px");
refreshSummary();
Object.values(cells).forEach(c => c.canvas && drawWave(c));
decodeAll();
</script>
</body>
</html>
"""


def build(root: Path):
    index = json.loads((root / "index.json").read_text(encoding="utf-8"))
    kits = index.get("kits", [])
    cues = index.get("cues", [])
    files = {}
    n_files = 0
    for kit in kits:
        files[kit["id"]] = {}
        for cue_id, rel in index.get("files", {}).get(kit["id"], {}).items():
            p = root / rel
            if not p.is_file():
                print(f"warning: missing {p}, left out", file=sys.stderr)
                continue
            files[kit["id"]][cue_id] = base64.b64encode(p.read_bytes()).decode("ascii")
            n_files += 1
    data = {"sampleRate": index.get("sampleRate"), "kits": kits, "cues": cues, "files": files}
    blob = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    return TEMPLATE.replace(PLACEHOLDER, blob), len(cues), n_files


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dir", default="build/sfx")
    ap.add_argument("--out", default=None)
    args = ap.parse_args(argv)
    root = Path(args.dir)
    out = Path(args.out) if args.out else root / "audition.html"
    try:
        html, n_cues, n_files = build(root)
    except (OSError, ValueError, KeyError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html, encoding="utf-8")
    print(f"wrote {out.resolve()}: {n_cues} cues, {n_files} files embedded")
    return 0


if __name__ == "__main__":
    sys.exit(main())
