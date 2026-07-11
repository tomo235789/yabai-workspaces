#!/usr/bin/env python3
"""Assemble a self-contained HTML report from test logs + rendered screenshots.

Reads (via env): OUT (report dir), IMG (screenshot dir), UNIT_RC, E2E_RC.
Writes: $OUT/report.html
"""
import os, re, json, base64, html, datetime, pathlib

OUT = os.environ["OUT"]
IMG = os.environ["IMG"]
unit_log = pathlib.Path(OUT, "unit.log").read_text(errors="replace") if pathlib.Path(OUT, "unit.log").exists() else ""
e2e_log = pathlib.Path(OUT, "e2e.log").read_text(errors="replace") if pathlib.Path(OUT, "e2e.log").exists() else ""


def parse_unit(log):
    # Overall: last "Executed N tests, with M failures"
    totals = re.findall(r"Executed (\d+) tests?, with (\d+) failures?", log)
    total, failures = (int(totals[-1][0]), int(totals[-1][1])) if totals else (0, 0)
    # Per-suite lines: Test Suite 'X' passed/failed ... Executed N tests
    suites = []
    for m in re.finditer(r"Test Suite '([^']+)' (passed|failed)", log):
        name = m.group(1)
        if name.endswith(".xctest") or name == "All tests" or name == "Selected tests":
            continue
        suites.append((name, m.group(2)))
    # de-dup keep last status per suite
    seen = {}
    for n, s in suites:
        seen[n] = s
    return total, failures, seen


def parse_e2e(log):
    m = re.search(r"e2e: (\d+) passed, (\d+) failed", log)
    passed, failed = (int(m.group(1)), int(m.group(2))) if m else (0, 0)
    checks = re.findall(r"^\s*([✓✗]) (.+)$", log, re.MULTILINE)
    return passed, failed, checks


u_total, u_fail, u_suites = parse_unit(unit_log)
e_pass, e_fail, e_checks = parse_e2e(e2e_log)

# Screenshots + manifest
manifest = []
mf = pathlib.Path(IMG, "manifest.json")
if mf.exists():
    manifest = json.loads(mf.read_text())
else:
    manifest = [{"file": p.name, "caption": p.stem} for p in sorted(pathlib.Path(IMG).glob("*.png"))]

shots_html = ""
for item in manifest:
    p = pathlib.Path(IMG, item["file"])
    if not p.exists():
        continue
    b64 = base64.b64encode(p.read_bytes()).decode()
    shots_html += (
        f'<figure><img alt="{html.escape(item["caption"])}" '
        f'src="data:image/png;base64,{b64}"/>'
        f'<figcaption>{html.escape(item["caption"])}</figcaption></figure>\n'
    )

shot_rc = int(os.environ.get("SHOT_RC", "1"))
overall_ok = (
    u_fail == 0 and e_fail == 0
    and int(os.environ.get("UNIT_RC", "1")) == 0
    and int(os.environ.get("E2E_RC", "1")) == 0
    and shot_rc == 0 and len(manifest) > 0
)
badge = ("PASS", "#3FB950") if overall_ok else ("FAIL", "#F85149")
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

suite_rows = "\n".join(
    f'<tr><td>{html.escape(n)}</td><td class="{"ok" if s=="passed" else "bad"}">{s}</td></tr>'
    for n, s in sorted(u_suites.items())
) or '<tr><td colspan="2">no suites parsed</td></tr>'

check_rows = "\n".join(
    f'<li class="{"ok" if sym=="✓" else "bad"}">{html.escape(txt)}</li>' for sym, txt in e_checks
) or "<li>no checks parsed</li>"

doc = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ywr — test &amp; UI report</title>
<style>
  :root {{ color-scheme: light dark; --bg:#ffffff; --fg:#1e1e1e; --muted:#666; --card:#f6f6f7; --border:#e3e3e6; }}
  @media (prefers-color-scheme: dark) {{ :root {{ --bg:#1a1a1b; --fg:#eaeaea; --muted:#9a9a9a; --card:#242426; --border:#333; }} }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; font:15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; color:var(--fg); background:var(--bg); }}
  .wrap {{ max-width:960px; margin:0 auto; padding:32px 20px 64px; }}
  header {{ display:flex; align-items:center; gap:14px; flex-wrap:wrap; }}
  h1 {{ font-size:22px; margin:0; }}
  .badge {{ color:#fff; font-weight:700; padding:4px 12px; border-radius:999px; font-size:13px; letter-spacing:.04em; }}
  .ts {{ color:var(--muted); font-size:13px; }}
  h2 {{ font-size:17px; margin:36px 0 12px; }}
  .cards {{ display:flex; gap:14px; flex-wrap:wrap; margin:16px 0; }}
  .card {{ background:var(--card); border:1px solid var(--border); border-radius:12px; padding:16px 18px; min-width:150px; }}
  .card .n {{ font-size:26px; font-weight:700; }}
  .card .l {{ color:var(--muted); font-size:13px; }}
  table {{ width:100%; border-collapse:collapse; font-size:14px; }}
  td {{ padding:7px 10px; border-bottom:1px solid var(--border); }}
  ul.checks {{ list-style:none; padding:0; margin:0; font-size:14px; column-gap:28px; }}
  ul.checks li {{ padding:3px 0 3px 22px; position:relative; }}
  ul.checks li::before {{ position:absolute; left:0; }}
  .ok {{ color:#2ea043; }} .bad {{ color:#e5534b; font-weight:600; }}
  ul.checks li.ok::before {{ content:"✓"; color:#2ea043; }}
  ul.checks li.bad::before {{ content:"✗"; color:#e5534b; }}
  .gallery {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(220px,1fr)); gap:18px; }}
  figure {{ margin:0; background:var(--card); border:1px solid var(--border); border-radius:12px; padding:12px; }}
  figure img {{ width:100%; height:auto; border-radius:8px; display:block; }}
  figcaption {{ color:var(--muted); font-size:13px; margin-top:8px; }}
  details {{ margin-top:12px; }} summary {{ cursor:pointer; color:var(--muted); font-size:13px; }}
  pre {{ overflow-x:auto; background:var(--card); border:1px solid var(--border); border-radius:10px; padding:12px; font-size:12px; }}
</style></head><body><div class="wrap">
<header>
  <h1>ywr — test &amp; UI report</h1>
  <span class="badge" style="background:{badge[1]}">{badge[0]}</span>
  <span class="ts">generated {now}</span>
</header>

<h2>Summary</h2>
<div class="cards">
  <div class="card"><div class="n">{u_total - u_fail}/{u_total}</div><div class="l">unit tests passed</div></div>
  <div class="card"><div class="n">{e_pass}/{e_pass + e_fail}</div><div class="l">end-to-end checks passed</div></div>
  <div class="card"><div class="n {'ok' if shot_rc == 0 else 'bad'}">{len(manifest)}</div><div class="l">UI screenshots{'' if shot_rc == 0 else ' — render failed'}</div></div>
</div>

<h2>Unit tests (XCTest)</h2>
<table><tbody>{suite_rows}</tbody></table>
<details><summary>raw log</summary><pre>{html.escape(unit_log[-6000:])}</pre></details>

<h2>End-to-end (real binary vs. fake yabai)</h2>
<ul class="checks">{check_rows}</ul>
<details><summary>raw log</summary><pre>{html.escape(e2e_log[-6000:])}</pre></details>

<h2>Menu-bar UI screenshots</h2>
<p class="ts">Rendered headlessly from the real SwiftUI views via <code>ImageRenderer</code>.</p>
<div class="gallery">{shots_html}</div>
</div></body></html>"""

pathlib.Path(OUT, "report.html").write_text(doc)
print(f"unit {u_total-u_fail}/{u_total}, e2e {e_pass}/{e_pass+e_fail}, shots {len(manifest)}")
