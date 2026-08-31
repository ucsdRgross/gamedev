# -*- coding: utf-8 -*-
"""Render the effect design-space taxonomy as a standalone review page."""
import html, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from taxonomy_data import AXES, FAMILIES

def E(t):
    return html.escape(t).encode("ascii","xmlcharrefreplace").decode("ascii")
def A(t):
    return t.encode("ascii","xmlcharrefreplace").decode("ascii")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "taxonomy.html")

n_classes = sum(len(f[3]) for f in FAMILIES)
counts = {"rich": 0, "thin": 0, "none": 0}
for f in FAMILIES:
    for i in f[3]:
        counts[i[2]] += 1

COVER_LABEL = {"rich": "covered", "thin": "thin", "none": "unexplored"}

# ---- axes strip -------------------------------------------------------------
axes_html = []
for name, blurb, items in AXES:
    rows = "\n".join(
        f'<div class="ax-row"><span class="ax-k">{E(k)}</span>'
        f'<span class="ax-v">{E(v)}</span></div>'
        for k, v in items
    )
    axes_html.append(
        f'<section class="axis">'
        f'<h3>{E(name)} <span class="ax-n">{len(items)}</span></h3>'
        f'<p class="axis-blurb">{E(blurb)}</p>'
        f'<div class="ax-list">{rows}</div>'
        f'</section>'
    )
axes_html = "\n".join(axes_html)

# ---- families ---------------------------------------------------------------
fam_html, nav_html = [], []
for code, title, blurb, items in FAMILIES:
    c = {"rich": 0, "thin": 0, "none": 0}
    for i in items:
        c[i[2]] += 1
    rows = "\n".join(
        f'<li class="cls" data-cov="{cov}">'
        f'<span class="cls-code">{E(cid)}</span>'
        f'<span class="cls-name">{E(cname)}</span>'
        f'<span class="cls-desc">{E(desc)}</span>'
        f'<span class="dot dot-{cov}" title="{COVER_LABEL[cov]}"></span>'
        f'</li>'
        for cid, cname, cov, desc in items
    )
    gap = c["none"]
    badge = f'<span class="badge">{gap} unexplored</span>' if gap else ""
    fam_html.append(
        f'<section class="fam" id="fam-{code}" data-none="{gap}">'
        f'<header class="fam-head">'
        f'<span class="fam-code">{code}</span>'
        f'<h2>{E(title)}</h2>'
        f'{badge}'
        f'</header>'
        f'<p class="fam-blurb">{E(blurb)}</p>'
        f'<ul class="cls-list">{rows}</ul>'
        f'</section>'
    )
    dots = "".join(f'<i class="ndot ndot-{k}" style="--n:{c[k]}"></i>' for k in ("rich", "thin", "none") if c[k])
    nav_html.append(
        f'<a href="#fam-{code}"><span class="nv-code">{code}</span>'
        f'<span class="nv-title">{E(title.split(" — ")[0])}</span>'
        f'<span class="nv-dots">{dots}</span></a>'
    )
fam_html = "\n".join(fam_html)
nav_html = "\n".join(nav_html)

CSS = """
:root{
  --ground:#eceff0; --panel:#f7f9f9; --edge:#ccd6d8; --edge-soft:#dde5e6;
  --ink:#101c20; --ink-2:#43585f; --ink-3:#6b8188;
  --brass:#9a6c14; --ember:#bf3f18; --arc:#1f7c92;
  --rich:#7f9aa1; --thin:#c08a2e; --none:#d4502a;
  --rail:#e3e9ea;
}
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){
    --ground:#0b1417; --panel:#111e22; --edge:#22383f; --edge-soft:#1a2b31;
    --ink:#e6eeef; --ink-2:#a3b8bd; --ink-3:#748f96;
    --brass:#d6a344; --ember:#f0673a; --arc:#61c3da;
    --rich:#4a636a; --thin:#c08a2e; --none:#e05a2c;
    --rail:#15252a;
  }
}
:root[data-theme="dark"]{
  --ground:#0b1417; --panel:#111e22; --edge:#22383f; --edge-soft:#1a2b31;
  --ink:#e6eeef; --ink-2:#a3b8bd; --ink-3:#748f96;
  --brass:#d6a344; --ember:#f0673a; --arc:#61c3da;
  --rich:#4a636a; --thin:#c08a2e; --none:#e05a2c;
  --rail:#15252a;
}
*{box-sizing:border-box}
body{
  margin:0; background:var(--ground); color:var(--ink);
  font-family:"IBM Plex Sans",system-ui,-apple-system,"Segoe UI",sans-serif;
  font-size:15px; line-height:1.5; -webkit-font-smoothing:antialiased;
}
.wrap{max-width:1240px;margin:0 auto;padding:0 24px 96px}

/* ---- masthead ---- */
.mast{padding:52px 0 26px;border-bottom:2px solid var(--ink);}
.eyebrow{
  font-family:"IBM Plex Mono",ui-monospace,monospace; font-size:11px;
  letter-spacing:.18em; text-transform:uppercase; color:var(--arc); margin:0 0 14px;
}
h1{
  font-family:"Archivo Narrow","Arial Narrow",sans-serif; font-weight:700;
  font-size:clamp(38px,6.2vw,68px); line-height:.98; letter-spacing:-.01em;
  margin:0; text-wrap:balance; text-transform:uppercase;
}
.dek{max-width:64ch;color:var(--ink-2);margin:18px 0 0;font-size:16.5px}
.tally{display:flex;flex-wrap:wrap;gap:0;margin:28px 0 0;border-top:1px solid var(--edge)}
.tally div{
  flex:1 1 150px;padding:14px 18px 14px 0;border-right:1px solid var(--edge-soft);
}
.tally div:last-child{border-right:0}
.tally b{
  display:block;font-family:"Archivo Narrow","Arial Narrow",sans-serif;font-weight:700;
  font-size:34px;line-height:1;font-variant-numeric:tabular-nums;
}
.tally span{
  display:block;font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:10.5px;
  letter-spacing:.14em;text-transform:uppercase;color:var(--ink-3);margin-top:6px;
}
.t-none b{color:var(--none)} .t-thin b{color:var(--thin)}

/* ---- how to read ---- */
.howto{
  margin:34px 0 0;padding:20px 22px;background:var(--panel);
  border-left:3px solid var(--brass);
}
.howto h4{
  margin:0 0 10px;font-family:"IBM Plex Mono",ui-monospace,monospace;
  font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--brass);font-weight:600;
}
.howto p{margin:0 0 9px;color:var(--ink-2);max-width:72ch}
.howto p:last-child{margin-bottom:0}
.howto code{
  font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.86em;
  background:var(--rail);padding:1px 5px;border-radius:2px;color:var(--ink)
}

/* ---- axes ---- */
.sec-rule{
  display:flex;align-items:baseline;gap:14px;margin:64px 0 24px;
  border-bottom:1px solid var(--ink);padding-bottom:8px;
}
.sec-rule h2{
  font-family:"Archivo Narrow","Arial Narrow",sans-serif;font-weight:700;
  text-transform:uppercase;letter-spacing:.02em;font-size:26px;margin:0;
}
.sec-rule p{margin:0;color:var(--ink-3);font-size:13.5px}
.axes{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:1px;background:var(--edge-soft)}
.axis{background:var(--ground);padding:20px 20px 22px}
.axis h3{
  margin:0 0 4px;font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:12px;
  letter-spacing:.16em;color:var(--arc);font-weight:600;
}
.ax-n{color:var(--ink-3);font-weight:400;margin-left:4px}
.axis-blurb{margin:0 0 14px;font-size:13px;color:var(--ink-3);max-width:44ch}
.ax-list{display:flex;flex-direction:column;gap:7px}
.ax-row{display:grid;grid-template-columns:minmax(96px,auto) 1fr;gap:12px;align-items:baseline}
.ax-k{
  font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:11.5px;color:var(--ink);
  font-weight:500;word-break:break-word;
}
.ax-v{font-size:13px;color:var(--ink-2);line-height:1.4}

/* ---- filter ---- */
.filter{
  position:sticky;top:0;z-index:20;background:var(--ground);
  display:flex;flex-wrap:wrap;gap:10px;align-items:center;
  padding:12px 0;border-bottom:1px solid var(--edge);margin-bottom:4px;
}
.filter span.lbl{
  font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:10.5px;
  letter-spacing:.14em;text-transform:uppercase;color:var(--ink-3);margin-right:2px;
}
.filter button{
  font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:11.5px;letter-spacing:.06em;
  padding:6px 13px;border:1px solid var(--edge);background:transparent;color:var(--ink-2);
  cursor:pointer;border-radius:0;
}
.filter button:hover{border-color:var(--ink-3);color:var(--ink)}
.filter button:focus-visible{outline:2px solid var(--arc);outline-offset:2px}
.filter button[aria-pressed="true"]{background:var(--ink);color:var(--ground);border-color:var(--ink)}

/* ---- body grid ---- */
.body{display:grid;grid-template-columns:212px 1fr;gap:44px;align-items:start;margin-top:20px}
nav.rail{position:sticky;top:64px;display:flex;flex-direction:column;border-top:1px solid var(--edge-soft)}
nav.rail a{
  display:grid;grid-template-columns:20px 1fr auto;gap:8px;align-items:center;
  padding:6px 2px;border-bottom:1px solid var(--edge-soft);
  text-decoration:none;color:var(--ink-2);font-size:12.5px;
}
nav.rail a:hover{color:var(--ink)}
nav.rail a:focus-visible{outline:2px solid var(--arc);outline-offset:1px}
.nv-code{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:11px;color:var(--brass);font-weight:600}
.nv-title{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.nv-dots{display:flex;gap:2px}
.ndot{width:5px;height:5px;border-radius:50%;display:block}
.ndot-rich{background:var(--rich)} .ndot-thin{background:var(--thin)} .ndot-none{background:var(--none)}

/* ---- families ---- */
.fam{margin:0 0 42px;scroll-margin-top:76px}
.fam-head{display:flex;align-items:baseline;gap:12px;flex-wrap:wrap;border-bottom:1px solid var(--edge);padding-bottom:7px}
.fam-code{
  font-family:"Archivo Narrow","Arial Narrow",sans-serif;font-weight:700;font-size:30px;
  line-height:1;color:var(--brass);min-width:24px;
}
.fam-head h2{
  font-family:"Archivo Narrow","Arial Narrow",sans-serif;font-weight:700;
  font-size:23px;margin:0;letter-spacing:.005em;flex:1 1 auto;text-wrap:balance;
}
.badge{
  font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:10.5px;letter-spacing:.08em;
  text-transform:uppercase;color:var(--none);border:1px solid var(--none);padding:2px 7px;white-space:nowrap;
}
.fam-blurb{margin:10px 0 14px;color:var(--ink-2);font-size:13.5px;max-width:78ch}
.cls-list{list-style:none;margin:0;padding:0;display:flex;flex-direction:column}
.cls{
  display:grid;grid-template-columns:44px minmax(150px,200px) 1fr 10px;
  gap:14px;align-items:baseline;padding:7px 0;border-bottom:1px solid var(--edge-soft);
}
.cls-code{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:11.5px;color:var(--ink-3);font-variant-numeric:tabular-nums}
.cls-name{font-weight:500;font-size:14px}
.cls-desc{color:var(--ink-2);font-size:13.5px;line-height:1.45}
.dot{width:8px;height:8px;border-radius:50%;align-self:center;justify-self:end}
.dot-rich{background:var(--rich)} .dot-thin{background:var(--thin)} .dot-none{background:var(--none)}
body.f-gaps .cls[data-cov="rich"]{display:none}
body.f-none .cls[data-cov="rich"],body.f-none .cls[data-cov="thin"]{display:none}
body.f-none .fam[data-none="0"]{display:none}

footer{margin-top:72px;padding-top:20px;border-top:2px solid var(--ink);color:var(--ink-3);font-size:13px;max-width:76ch}
footer b{color:var(--ink)}

@media (max-width:900px){
  .body{grid-template-columns:1fr;gap:0}
  nav.rail{position:static;margin-bottom:32px}
  .cls{grid-template-columns:40px 1fr 10px;gap:2px 12px}
  .cls-name{grid-column:2;grid-row:1}
  .dot{grid-column:3;grid-row:1}
  .cls-desc{grid-column:2 / 4;grid-row:2}
}
"""

JS = """
const btns=[...document.querySelectorAll('.filter button')];
btns.forEach(b=>b.addEventListener('click',()=>{
  btns.forEach(x=>x.setAttribute('aria-pressed', String(x===b)));
  document.body.classList.remove('f-gaps','f-none');
  if(b.dataset.f) document.body.classList.add(b.dataset.f);
}));
"""

HTML = f"""<title>Effect Design Space</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo+Narrow:wght@600;700&family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<style>{CSS}</style>

<div class="wrap">
  <header class="mast">
    <p class="eyebrow">Solatro · pre-questionnaire review</p>
    <h1>The Effect<br>Design Space</h1>
    <p class="dek">Every kind of thing an effect can BE, before we start deciding which
    ones to build. Read it looking for the family that is missing, not the entry that is
    wrong &mdash; a missing family means several hundred questions never get asked.</p>
    <div class="tally">
      <div><b>{len(FAMILIES)}</b><span>families</span></div>
      <div><b>{n_classes}</b><span>effect classes</span></div>
      <div class="t-thin"><b>{counts['thin']}</b><span>thinly covered</span></div>
      <div class="t-none"><b>{counts['none']}</b><span>unexplored</span></div>
      <div><b>{len(AXES)}</b><span>structural axes</span></div>
    </div>
    <div class="howto">
      <h4>How to read this</h4>
      <p>Two independent things are listed. The <b>axes</b> are the structural
      dimensions every effect has &mdash; which slot it lives in, when it fires, how far it
      reaches. The <b>families</b> are what an effect actually DOES. An effect is a point in
      the axes crossed with one family class.</p>
      <p>Each class carries a coverage dot: <span class="dot dot-rich"
      style="display:inline-block;vertical-align:middle"></span> already well represented in
      the corpus &middot; <span class="dot dot-thin"
      style="display:inline-block;vertical-align:middle"></span> a few examples, mostly
      written before the 5&times;5 grid overhaul &middot; <span class="dot dot-none"
      style="display:inline-block;vertical-align:middle"></span> essentially unexplored, so
      the questionnaire has to generate here rather than mine.</p>
      <p>Coverage is judged against the repo corpus &mdash; <code>CARD_CATALOG.csv</code>,
      <code>gam draft.txt</code>, the two design docs and the two loose effect sheets &mdash;
      not against what is implemented in code.</p>
    </div>
  </header>

  <div class="sec-rule"><h2>The axes</h2><p>what every effect has, independent of what it does</p></div>
  <div class="axes">{axes_html}</div>

  <div class="sec-rule"><h2>The families</h2><p>what an effect does</p></div>
  <div class="filter">
    <span class="lbl">Show</span>
    <button data-f="" aria-pressed="true">everything</button>
    <button data-f="f-gaps" aria-pressed="false">thin + unexplored</button>
    <button data-f="f-none" aria-pressed="false">unexplored only</button>
  </div>
  <div class="body">
    <nav class="rail">{nav_html}</nav>
    <main>{fam_html}</main>
  </div>

  <footer>
    <p><b>What happens next.</b> Every effect mined out of the repo docs and the Balatro /
    Cryptid reference wikis gets tagged into exactly one family class. Classes with nothing
    mined into them are where new effects get invented. Then the questionnaire: one question
    per effect, three variants plus reject plus write-your-own, upgrades ordered directly
    after the effect they upgrade.</p>
  </footer>
</div>
<script>{JS}</script>
"""

with open(OUT, "w", encoding="utf-8") as f:
    f.write(A(HTML))
print("wrote", OUT, len(HTML), "bytes")
print("families", len(FAMILIES), "classes", n_classes, counts)
