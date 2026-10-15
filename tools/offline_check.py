#!/usr/bin/env python3
"""Real offline check of the BUILT app (run by the deploy workflow).

Serves build/web under /morafig-tilmid/ like GitHub Pages, opens it in
Chromium, waits for the app to draw, lets the offline worker install, then
switches the network OFF, reloads and checks that the app draws again.
Writes offline_check.png (the offline screen). Exit code 0 = it opened offline.

What it proves: the built files + the worker keep the app openable without
internet in desktop Chromium. It does NOT prove a real phone or an installed
app: that is tested by hand.
"""
import functools
import http.server
import os
import sys
import threading
import time

from playwright.sync_api import sync_playwright

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "build/web")
PREFIX = "/morafig-tilmid/"


class Handler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        path = path.split("?")[0].split("#")[0]
        if not path.startswith(PREFIX):
            return "/nonexistent"
        full = os.path.join(ROOT, path[len(PREFIX):])
        return os.path.join(full, "index.html") if os.path.isdir(full) else full

    def end_headers(self):
        self.send_header("Cache-Control", "max-age=600")  # like GitHub Pages
        super().end_headers()

    def log_message(self, *args):
        pass


def drawn(page):
    return page.evaluate(
        "!!(document.querySelector('flt-glass-pane') || document.querySelector('flutter-view'))"
    )


def main():
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 8766), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:8766{PREFIX}"
    ok = True
    with sync_playwright() as p:
        browser = p.chromium.launch()
        ctx = browser.new_context(viewport={"width": 420, "height": 860})
        page = ctx.new_page()
        page.goto(url)
        page.wait_for_function(
            "!!(document.querySelector('flt-glass-pane') || document.querySelector('flutter-view'))",
            timeout=90000,
        )
        print("PASS the app draws online")
        page.wait_for_function(
            "navigator.serviceWorker.getRegistration().then(r => !!(r && r.active))",
            timeout=60000,
        )
        print("PASS the offline worker is active")
        time.sleep(3)
        page.reload()
        page.wait_for_function(
            "!!(document.querySelector('flt-glass-pane') || document.querySelector('flutter-view'))",
            timeout=90000,
        )
        ctx.set_offline(True)
        page.reload()
        try:
            page.wait_for_function(
                "!!(document.querySelector('flt-glass-pane') || document.querySelector('flutter-view'))",
                timeout=90000,
            )
            time.sleep(4)
            print("PASS the app draws with the network OFF")
        except Exception as e:  # noqa: BLE001
            ok = False
            print("FAIL the app did not draw offline:", str(e)[:200])
        page.screenshot(path="offline_check.png")
        browser.close()
    print("OFFLINE CHECK: " + ("OK" if ok else "FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
