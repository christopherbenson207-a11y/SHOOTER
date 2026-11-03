"""Refresh the browser test of the Endless mode (docs/endless/endless-test.html) from the Roblox
house layout, so both play the same map.

Usage: python tools/endless_web.py                    (rewrites the layout block in the page)
       python tools/endless_web.py --artifact OUT.html (also writes a copy without the outer
                                                        html/head/body tags, for publishing)
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from endless_house import LAYOUT, parse  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGE = os.path.join(ROOT, "docs", "endless", "endless-test.html")
WRAPPER = {
    "<!doctype html>", '<html lang="en">', "<head>", '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">',
    "</head>", "<body>", "</body>", "</html>",
}


def main():
    with open(LAYOUT, encoding="utf-8") as f:
        layout = json.dumps(parse(f.read()), separators=(",", ":"))
    with open(PAGE, encoding="utf-8") as f:
        page = f.read()
    page, n = re.subn(r"/\*LAYOUT-BEGIN\*/.*?/\*LAYOUT-END\*/", lambda _: "/*LAYOUT-BEGIN*/" + layout + "/*LAYOUT-END*/", page, flags=re.S)
    if n != 1:
        raise SystemExit("layout markers not found in " + PAGE)
    with open(PAGE, "w", encoding="utf-8", newline="\n") as f:
        f.write(page)
    print("layout written into", os.path.relpath(PAGE, ROOT))
    if "--artifact" in sys.argv:
        out = sys.argv[sys.argv.index("--artifact") + 1]
        body = "\n".join(line for line in page.split("\n") if line.strip() not in WRAPPER)
        with open(out, "w", encoding="utf-8", newline="\n") as f:
            f.write(body)
        print("artifact copy written to", out)


if __name__ == "__main__":
    main()
