"""Renders the petty: Tracker app icon: a flat teal receipt on cool gray, in the Petty style.

The glyph shares its paths with android/app/src/main/res/drawable/ic_launcher_monochrome.xml.
Usage: python3 render_icon.py <output AppIcon.png>   (needs rsvg-convert)
"""
import subprocess
import sys

ROLL = "M35,27 H73 A4,4 0 0 1 77,31 V33 A4,4 0 0 1 73,37 H35 A4,4 0 0 1 31,33 V31 A4,4 0 0 1 35,27 Z"
PAPER = "M37,39 H71 V80 L68.875,77 L66.75,80 L64.625,77 L62.5,80 L60.375,77 L58.25,80 L56.125,77 L54,80 L51.875,77 L49.75,80 L47.625,77 L45.5,80 L43.375,77 L41.25,80 L39.125,77 L37,80 Z M42,45 H66 V48 H42 Z M42,51 H58 V54 H42 Z M42,57 H66 V60 H42 Z M54,61 A7,7 0 1 1 53.99,61 Z M50.3,67.6 L53,70.3 L57.7,65.6 L59.3,67.2 L53,73.5 L48.7,69.2 Z"
ACCENT = "#0F7A8A"

SVG = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108" width="1024" height="1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#F7F9FA"/>
      <stop offset="1" stop-color="#E1E7EA"/>
    </linearGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="1.2" stdDeviation="1.6" flood-color="#0B2A30" flood-opacity="0.16"/>
    </filter>
  </defs>
  <rect width="108" height="108" fill="url(#bg)"/>
  <g transform="translate(54 54) scale(1.18) translate(-54 -53.5)" filter="url(#shadow)" fill="{ACCENT}">
    <path d="{ROLL}"/>
    <path d="{PAPER}" fill-rule="evenodd"/>
  </g>
</svg>"""

if __name__ == "__main__":
    subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", "-o", sys.argv[1]], input=SVG.encode(), check=True)
