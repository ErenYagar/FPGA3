from html import escape
from pathlib import Path
import re
import sys


def read_metrics(text):
    match = re.search(
        r"^\s*(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s+"
        r"(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s+"
        r"(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$",
        text,
        re.MULTILINE,
    )
    if not match:
        raise ValueError("Design Timing Summary row was not found")
    names = (
        "WNS", "TNS", "TNS Failing Endpoints", "TNS Total Endpoints",
        "WHS", "THS", "THS Failing Endpoints", "THS Total Endpoints",
        "WPWS", "TPWS", "TPWS Failing Endpoints", "TPWS Total Endpoints",
    )
    return dict(zip(names, match.groups()))


def check_rows(text):
    rows = []
    seen = set()
    pattern = re.compile(r"^(\d+)\. checking ([^()]+) \((\d+)\)$", re.MULTILINE)
    for number, name, count in pattern.findall(text):
        if name in seen:
            continue
        count = int(count)
        rows.append((number, name.strip(), count, count == 0))
        seen.add(name)
    return rows


def metric_card(label, value, tone):
    return f'<article class="metric {tone}"><span>{escape(label)}</span><strong>{escape(value)}</strong></article>'


def render(source):
    text = source.read_text(encoding="ascii", errors="replace")
    metrics = read_metrics(text)
    checks = check_rows(text)
    title = source.stem.replace("_", " ").title()
    failing = int(metrics["TNS Failing Endpoints"])
    cards = "".join([
        metric_card("WNS / worst setup", f'{metrics["WNS"]} ns', "bad" if float(metrics["WNS"]) < 0 else "good"),
        metric_card("TNS / total setup", f'{metrics["TNS"]} ns', "bad" if float(metrics["TNS"]) < 0 else "good"),
        metric_card("Failing endpoints", metrics["TNS Failing Endpoints"], "bad" if failing else "good"),
        metric_card("WHS / worst hold", f'{metrics["WHS"]} ns', "good" if float(metrics["WHS"]) >= 0 else "bad"),
    ])
    check_html = "".join(
        f'<tr><td>{number}</td><td>{escape(name)}</td><td class="count {"bad" if count else "good"}">{count}</td>'
        f'<td><span class="pill {"good" if passed else "warn"}">{"PASS" if passed else "REVIEW"}</span></td></tr>'
        for number, name, count, passed in checks
    )
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{escape(title)}</title><style>
:root {{ color-scheme: dark; --bg:#101416; --panel:#182024; --line:#2c383d; --ink:#edf3f1; --muted:#91a29f; --mint:#5de0b5; --amber:#f5c76b; --red:#ff756d; }}
* {{ box-sizing:border-box; }} body {{ margin:0; background:radial-gradient(circle at 85% 0%,#25463e 0,transparent 32rem),var(--bg); color:var(--ink); font:15px/1.5 ui-sans-serif,system-ui,sans-serif; }}
main {{ max-width:1180px; margin:auto; padding:48px 24px 72px; }} header {{ display:flex; justify-content:space-between; gap:24px; align-items:end; border-bottom:1px solid var(--line); padding-bottom:28px; }}
.eyebrow {{ color:var(--mint); font-size:12px; font-weight:700; letter-spacing:.12em; text-transform:uppercase; }} h1 {{ margin:8px 0 0; font:700 clamp(28px,5vw,56px)/1.05 Georgia,serif; }} .source {{ color:var(--muted); font:12px ui-monospace,monospace; text-align:right; }}
.metrics {{ display:grid; grid-template-columns:repeat(4,1fr); gap:12px; margin:28px 0 40px; }} .metric {{ background:var(--panel); border:1px solid var(--line); border-top:3px solid var(--muted); padding:18px; min-height:122px; }} .metric.bad {{ border-top-color:var(--red); }} .metric.good {{ border-top-color:var(--mint); }} .metric span {{ color:var(--muted); display:block; font-size:12px; text-transform:uppercase; letter-spacing:.06em; }} .metric strong {{ display:block; font:700 31px/1.1 ui-monospace,monospace; margin-top:18px; }}
section {{ margin-top:30px; }} h2 {{ font-size:20px; margin:0 0 12px; }} .table-wrap {{ overflow:auto; border:1px solid var(--line); }} table {{ border-collapse:collapse; min-width:560px; width:100%; }} th,td {{ padding:11px 14px; border-bottom:1px solid var(--line); text-align:left; }} th {{ color:var(--muted); font-size:12px; text-transform:uppercase; letter-spacing:.06em; background:#202b2f; }} tr:last-child td {{ border-bottom:0; }} td:first-child,.count {{ font-family:ui-monospace,monospace; }} .count {{ font-weight:700; }} .good {{ color:var(--mint); }} .bad {{ color:var(--red); }} .warn {{ color:var(--amber); }} .pill {{ border:1px solid currentColor; border-radius:999px; padding:2px 8px; font-size:11px; font-weight:700; }} details {{ background:var(--panel); border:1px solid var(--line); }} summary {{ cursor:pointer; padding:14px 16px; color:var(--mint); font-weight:700; }} pre {{ border-top:1px solid var(--line); margin:0; padding:20px; overflow:auto; color:#c9d4d1; font:12px/1.55 ui-monospace,SFMono-Regular,Consolas,monospace; }}
@media (max-width:720px) {{ main {{ padding:28px 14px 48px; }} header {{ display:block; }} .source {{ text-align:left; margin-top:14px; }} .metrics {{ grid-template-columns:repeat(2,1fr); }} .metric strong {{ font-size:23px; }} }}
</style></head><body><main><header><div><div class="eyebrow">Vivado timing report</div><h1>{escape(title)}</h1></div><div class="source">Generated from<br>{escape(source.name)}</div></header>
<div class="metrics">{cards}</div><section><h2>Timing checks</h2><div class="table-wrap"><table><thead><tr><th>#</th><th>Check</th><th>Issues</th><th>Status</th></tr></thead><tbody>{check_html}</tbody></table></div></section>
<section><h2>Full source report</h2><details><summary>Open raw Vivado output</summary><pre>{escape(text)}</pre></details></section></main></body></html>'''


if __name__ == "__main__":
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("docs/report/figures/vivado_native/01_synthesis_timing_summary.rpt")
    target = source.with_suffix(".html")
    target.write_text(render(source), encoding="utf-8")
    print(f"Wrote {target}")