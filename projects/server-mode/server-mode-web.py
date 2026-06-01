#!/usr/bin/env python3

from __future__ import annotations

import argparse
import html
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs

SCRIPT_DIR = Path(__file__).resolve().parent
STATUS_SCRIPT = SCRIPT_DIR / "server-mode-status.sh"
TOGGLE_SCRIPT = SCRIPT_DIR / "server-mode-toggle.sh"
EXIT_SCRIPT = SCRIPT_DIR / "exit-server-mode.sh"


def run_status() -> dict[str, str]:
    output = subprocess.check_output([str(STATUS_SCRIPT), "--json"], text=True)
    return json.loads(output)


def can_control() -> bool:
    return os.geteuid() == 0


def run_action(action: str) -> str:
    if not can_control():
      return "Control actions require running server-mode-web.py as root."

    if action == "toggle":
        subprocess.check_call([str(TOGGLE_SCRIPT)])
        return "Toggled server mode."
    if action == "restart-tailscaled":
        subprocess.check_call(["systemctl", "restart", "tailscaled"])
        return "Restarted tailscaled."
    if action == "restart-ssh":
        ssh_service = run_status()["ssh_service"]
        subprocess.check_call(["systemctl", "restart", ssh_service])
        return f"Restarted {ssh_service}."
    if action == "exit":
        subprocess.check_call([str(EXIT_SCRIPT)])
        return "Restored state and exited server mode."
    if action == "reboot":
        subprocess.Popen(["systemctl", "reboot"])
        return "Reboot requested."
    if action == "poweroff":
        subprocess.Popen(["systemctl", "poweroff"])
        return "Poweroff requested."

    return f"Unknown action: {action}"


def stat_card(title: str, value: str, hint: str = "") -> str:
    hint_html = f"<p>{html.escape(hint)}</p>" if hint else ""
    return (
        f"<section class='card'><span class='label'>{html.escape(title)}</span>"
        f"<strong>{html.escape(value or 'unknown')}</strong>{hint_html}</section>"
    )


def action_button(action: str, label: str, danger: bool = False) -> str:
    klass = "action danger" if danger else "action"
    return (
        "<form method='post' class='action-form' "
        f"onsubmit=\"return confirm('Confirm {html.escape(label)}?');\">"
        f"<input type='hidden' name='action' value='{html.escape(action)}'>"
        f"<button class='{klass}' type='submit'>{html.escape(label)}</button></form>"
    )


def render_page(message: str = "") -> bytes:
    status = run_status()
    warning = status.get("firewall_warning", "unknown")
    message_html = f"<div class='flash'>{html.escape(message)}</div>" if message else ""
    warning_html = (
        f"<div class='warning'>{html.escape(warning)}</div>"
        if warning not in {"none", "unknown", ""}
        else ""
    )
    controls = "".join(
        [
            action_button("toggle", "Toggle Server Mode"),
            action_button("restart-tailscaled", "Restart Tailscale"),
            action_button("restart-ssh", "Restart SSH"),
            action_button("exit", "Exit Server Mode", danger=True),
            action_button("reboot", "Reboot Laptop", danger=True),
            action_button("poweroff", "Power Off Laptop", danger=True),
        ]
    )

    html_doc = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Remote Terminal Control Panel</title>
  <meta http-equiv="refresh" content="10">
  <style>
    :root {{
      --bg: #0f1720;
      --panel: #16212d;
      --panel-2: #1d2c3a;
      --text: #edf4ff;
      --muted: #98a8bb;
      --accent: #47d1c8;
      --ok: #5ee07f;
      --warn: #ffbe55;
      --danger: #ff6b6b;
      --border: rgba(255,255,255,0.08);
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: "Segoe UI", "Helvetica Neue", sans-serif;
      color: var(--text);
      background:
        radial-gradient(circle at top left, rgba(71,209,200,0.18), transparent 32%),
        linear-gradient(160deg, #0b1218, #101922 40%, #131e29);
      min-height: 100vh;
    }}
    .wrap {{
      max-width: 1120px;
      margin: 0 auto;
      padding: 24px 16px 48px;
    }}
    .hero {{
      display: grid;
      gap: 12px;
      margin-bottom: 20px;
    }}
    h1 {{
      margin: 0;
      font-size: clamp(2rem, 6vw, 3.6rem);
      letter-spacing: 0.02em;
    }}
    .subtitle, .meta {{
      color: var(--muted);
      margin: 0;
    }}
    .flash, .warning {{
      padding: 14px 16px;
      border-radius: 16px;
      margin: 16px 0;
      backdrop-filter: blur(6px);
    }}
    .flash {{ background: rgba(94,224,127,0.14); border: 1px solid rgba(94,224,127,0.35); }}
    .warning {{ background: rgba(255,190,85,0.12); border: 1px solid rgba(255,190,85,0.35); }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 14px;
      margin: 18px 0 24px;
    }}
    .card, .panel {{
      background: linear-gradient(180deg, rgba(255,255,255,0.03), rgba(255,255,255,0.015));
      border: 1px solid var(--border);
      border-radius: 20px;
      padding: 18px;
      box-shadow: 0 14px 34px rgba(0,0,0,0.22);
    }}
    .label {{
      display: block;
      color: var(--muted);
      font-size: 0.82rem;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      margin-bottom: 8px;
    }}
    strong {{
      display: block;
      font-size: 1.24rem;
      line-height: 1.2;
    }}
    .sections {{
      display: grid;
      grid-template-columns: 2fr 1fr;
      gap: 16px;
    }}
    .actions {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 10px;
    }}
    .action-form {{ margin: 0; }}
    .action {{
      width: 100%;
      border: 0;
      border-radius: 14px;
      padding: 12px 14px;
      color: #081117;
      background: linear-gradient(135deg, var(--accent), #8de7d8);
      font-weight: 700;
      cursor: pointer;
    }}
    .action.danger {{
      background: linear-gradient(135deg, #ff9a7a, var(--danger));
      color: white;
    }}
    ul {{
      margin: 0;
      padding-left: 18px;
      color: var(--muted);
    }}
    li + li {{ margin-top: 8px; }}
    @media (max-width: 820px) {{
      .sections {{ grid-template-columns: 1fr; }}
      .wrap {{ padding: 16px 12px 36px; }}
    }}
  </style>
</head>
<body>
  <main class="wrap">
    <header class="hero">
      <p class="subtitle">Remote Terminal Control Panel</p>
      <h1>{html.escape(status["hostname"])}</h1>
      <p class="meta">Phase: {html.escape(status["phase"])} | Updated: {html.escape(status["phase_updated_at"])}</p>
      <p class="meta">Health: {html.escape(status["health_status"])} | Last healthy: {html.escape(status["health_last_ok_at"])}</p>
    </header>
    {message_html}
    {warning_html}
    <section class="grid">
      {stat_card("Tailscale", f'{status["tailscaled_active"]} / {status["tailscaled_enabled"]}', status["tailscale_ip"])}
      {stat_card(status["ssh_service"], f'{status["ssh_active"]} / {status["ssh_enabled"]}', "SSH service")}
      {stat_card("AC Power", status["ac_state"], status["battery_summary"])}
      {stat_card("Memory", status["memory_summary"], f'{status["memory_percent"]}% used')}
      {stat_card("Disk", status["disk_summary"], f'{status["disk_percent"]}% used')}
      {stat_card("CPU Temp", status["cpu_temperature"], status["load_average"])}
      {stat_card("Uptime", status["uptime"], "Auto-refresh every 10s")}
      {stat_card("Firewall", status["firewall_warning"], "none means no warning")}
      {stat_card("Web UI", status["web_ui_status"], status["publish_url"])}
    </section>
    <section class="sections">
      <section class="panel">
        <span class="label">Controls</span>
        <div class="actions">{controls}</div>
      </section>
      <section class="panel">
        <span class="label">Notes</span>
        <ul>
          <li>Run this server as root if you want the control buttons to work.</li>
          <li>The interface is mobile-friendly and safe by default when bound to 127.0.0.1.</li>
          <li>For remote phone access, prefer an SSH tunnel or Tailscale-served localhost instead of exposing the port publicly.</li>
        </ul>
      </section>
    </section>
  </main>
</body>
</html>
"""
    return html_doc.encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        body = render_page()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        data = parse_qs(self.rfile.read(length).decode("utf-8"))
        action = data.get("action", [""])[0]
        message = run_action(action)
        body = render_page(message)
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        return


def main() -> None:
    parser = argparse.ArgumentParser(description="Remote Terminal web dashboard")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8788)
    args = parser.parse_args()

    with ThreadingHTTPServer((args.host, args.port), Handler) as server:
        print(f"Remote Terminal web UI listening on http://{args.host}:{args.port}")
        server.serve_forever()


if __name__ == "__main__":
    main()
