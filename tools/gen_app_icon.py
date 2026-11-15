#!/usr/bin/env python3
"""Home-screen app icons for the web build (PWA manifest + apple-touch-icon).

Draws the donut (assets/art/d5_donut.svg) on the mint wall, opaque and
full-bleed, because iOS fills transparent icon pixels with black and both
platforms apply their own corner mask. Writes assets/app_icon/icon_{512,180,144}.png,
which export_presets.cfg points the Web preset's PWA icons at.

    python3 tools/gen_app_icon.py

Needs only the Python standard library, Google Chrome (or Chromium) and macOS `sips`.
"""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "app_icon")
SIZE = 512
CHROME_CANDIDATES = [
    os.environ.get("CHROME", ""),
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    shutil.which("google-chrome") or "",
    shutil.which("chromium") or "",
]


def main() -> None:
    chrome = next((c for c in CHROME_CANDIDATES if c and os.path.exists(c)), None)
    if not chrome:
        sys.exit("Google Chrome or Chromium not found (set CHROME=/path/to/chrome)")
    with open(os.path.join(ROOT, "assets", "art", "d5_donut.svg")) as f:
        donut = f.read()

    html = f"""<!doctype html><html><head><style>
html, body {{ margin: 0; width: {SIZE}px; height: {SIZE}px; overflow: hidden; }}
body {{
  display: grid; place-items: center;
  background:
    radial-gradient(ellipse at 30% 10%, rgba(255,244,208,.55), rgba(255,244,208,0) 60%),
    linear-gradient(#CDEFE7, #AEE0D8 50%, #8ACCC4);
}}
.wrap {{ position: relative; width: 92%; height: 92%; }}
.wrap svg {{ position: relative; width: 100%; height: 100%; display: block; transform: rotate(-8deg); }}
.wrap::after {{
  content: ''; position: absolute; left: 22%; right: 22%; bottom: 9%; height: 6%;
  border-radius: 50%; background: rgba(40, 90, 84, .22);
}}
</style></head><body><div class="wrap">{donut}</div></body></html>"""

    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        page = os.path.join(tmp, "icon.html")
        with open(page, "w") as f:
            f.write(html)
        shot = os.path.join(tmp, "icon.png")
        subprocess.run([
            chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars",
            "--force-device-scale-factor=1", f"--window-size={SIZE},{SIZE}",
            f"--screenshot={shot}", "file://" + page,
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for px in (512, 180, 144):
            dest = os.path.join(OUT, f"icon_{px}.png")
            shutil.copy(shot, dest)
            if px != SIZE:
                subprocess.run(["sips", "-z", str(px), str(px), dest],
                               check=True, stdout=subprocess.DEVNULL)
            print("wrote", os.path.relpath(dest, ROOT))


if __name__ == "__main__":
    main()
