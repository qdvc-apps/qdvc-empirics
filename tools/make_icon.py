#!/usr/bin/env python3
"""Generate the app icon: Resources/AppIcon.svg (vector master) and
Resources/AppIcon.icns (every macOS size, rendered natively from the vector).

The design is a well-worked book: open on two pages of text swept with
highlighter, margin notes and a circled word in pen, a sticky note on the
right-hand page, more sticky notes and paper flags poking out of its edges,
and two ribbon bookmarks hanging from the spine, all on a pale cantaloupe
gradient. It keeps the family's construction (QDVC Response Letter,
Progress, Meetings…): Apple's tile, a soft glow and sheen, tinted shadows.

Geometry follows Apple's macOS icon template: a 1024x1024 canvas holding an
824x824 tile (100 px transparent margin) with a 185.4 px continuous-curvature
("squircle") corner, plus a soft drop shadow. The corner is the curve UIKit
draws for continuous corners, as reverse-engineered and published by PaintCode
(https://www.paintcodeapp.com/blogpost/code-for-ios-7-rounded-rectangles).

Usage:

    python3 tools/make_icon.py            # writes Resources/AppIcon.{svg,icns}
    python3 tools/make_icon.py --preview  # also writes build/icon-preview.png

Requires rsvg-convert (macOS: `brew install librsvg`; Debian/Ubuntu:
`apt install librsvg2-bin`). No other dependencies; the .icns is written
directly, so Apple's iconutil is not needed.
"""

import argparse
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Resources"

# ---------------------------------------------------------------------------
# Palette: pale cantaloupe, with a deep teal cover for contrast.

BG_TOP = "#FFF1E0"
BG_DEEP = "#F7B07A"
SHADOW_TINT = "#B9612A"

COVER, COVER_DARK = "#2E6E72", "#1E4C50"
PAPER, PAPER_SHADE = "#FFFDF8", "#EFE6D8"
INK = "#A9A39A"
HIGHLIGHTS = ["#FFD84D", "#FF9EC0", "#9EE37D", "#7FD0FF"]
PEN_RED, PEN_BLUE = "#D9433B", "#2F5AA8"
NOTES = ["#FFE066", "#FF9EC0", "#8FD3FF", "#A8E6A1", "#FFB86B"]
RIBBONS = ["#C7372F", "#E3A72F"]

# ---------------------------------------------------------------------------
# Apple's template geometry.

TILE_ORIGIN, TILE_SIZE, CORNER_RADIUS = 100, 824, 185.4
SHADOW_BLUR_RADIUS, SHADOW_OFFSET_Y, SHADOW_OPACITY = 28, 12, 0.5

# Continuous-corner segments around the top-right corner, in units of the
# radius: (distance from the right edge, distance from the top edge).
_CORNER = [
    ("L", (1.52866471, 0.0)),
    ("C", (1.08849323, 0.0), (0.86840689, 0.0), (0.66993427, 0.06549600)),
    ("L", (0.63149399, 0.07491100)),
    ("C", (0.37282392, 0.16905899), (0.16906013, 0.37282401), (0.07491176, 0.63149399)),
    ("C", (0.0, 0.86840701), (0.0, 1.08849299), (0.0, 1.52866483)),
]


def continuous_rounded_rect(x, y, w, h, r):
    """SVG path of a rounded rectangle with Apple's continuous corners."""
    r = min(r, min(w, h) / 2 / 1.52866483)
    corners = [
        lambda u, v: (x + w - u * r, y + v * r),        # top-right
        lambda u, v: (x + w - v * r, y + h - u * r),    # bottom-right
        lambda u, v: (x + u * r, y + h - v * r),        # bottom-left
        lambda u, v: (x + v * r, y + u * r),            # top-left
    ]

    def fmt(p):
        return f"{p[0]:.2f},{p[1]:.2f}"

    d = [f"M{fmt((x + 1.52866483 * r, y))}"]
    for corner in corners:
        for seg in _CORNER:
            if seg[0] == "L":
                d.append("L" + fmt(corner(*seg[1])))
            else:
                d.append("C" + " ".join(fmt(corner(*p)) for p in seg[1:]))
    d.append("Z")
    return " ".join(d)


TILE = continuous_rounded_rect(TILE_ORIGIN, TILE_ORIGIN, TILE_SIZE, TILE_SIZE, CORNER_RADIUS)


def _note(x, y, w, h, angle, colour, lines=0):
    """A sticky note: a square with a darker fold at the bottom edge and,
    optionally, scribbled lines."""
    cx, cy = x + w / 2, y + h / 2
    parts = [f'<g transform="rotate({angle} {cx:.1f} {cy:.1f})" filter="url(#note)">',
             f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="5" fill="{colour}"/>',
             f'<rect x="{x}" y="{y + h - 12}" width="{w}" height="12" rx="5" fill="#000000" fill-opacity="0.07"/>']
    for i in range(lines):
        ly = y + 26 + i * 18
        lw = w * (0.72 if i % 2 == 0 else 0.5)
        parts.append(f'<path d="M{x + 14} {ly} q{lw / 4:.1f} -6 {lw / 2:.1f} 0 t{lw / 2:.1f} 0" fill="none" '
                     f'stroke="{PEN_BLUE}" stroke-opacity="0.75" stroke-width="5" stroke-linecap="round"/>')
    parts.append('</g>')
    return parts


def _book():
    """The open book, with its notes, flags, ribbons and markings."""
    left, right, spine = 196, 828, 512
    top, bottom = 352, 760
    parts = []
    # Sticky notes and flags tucked between the pages (drawn first, so the
    # pages cover their lower parts).
    parts += _note(258, 262, 92, 120, -9, NOTES[2])
    parts += _note(566, 248, 96, 130, 7, NOTES[0])
    parts += _note(682, 272, 86, 112, -4, NOTES[1])
    for i, (y, colour) in enumerate([(430, NOTES[3]), (500, NOTES[4]), (570, NOTES[1])]):
        parts.append(f'<rect x="{right - 40}" y="{y}" width="{118 - i * 12}" height="34" rx="6" fill="{colour}" '
                     'filter="url(#note)"/>')
    # Ribbons from the spine.
    for i, (dx, length, colour) in enumerate([(-22, 150, RIBBONS[0]), (8, 118, RIBBONS[1])]):
        x0 = spine + dx
        y1 = bottom + length
        parts.append(f'<path d="M{x0} {bottom - 30} L{x0 + 20} {bottom - 30} L{x0 + 20} {y1} L{x0 + 10} {y1 - 14} '
                     f'L{x0} {y1} Z" fill="{colour}"/>')
    # The cover, under the pages.
    parts.append(f'<path d="M{left - 22} {top + 8} Q{(left + spine) / 2} {top - 8} {spine} {top + 26} '
                 f'Q{(spine + right) / 2} {top - 8} {right + 22} {top + 8} L{right + 22} {bottom + 34} '
                 f'Q{(spine + right) / 2} {bottom + 14} {spine} {bottom + 44} Q{(left + spine) / 2} {bottom + 14} '
                 f'{left - 22} {bottom + 34} Z" fill="url(#cover)"/>')
    # Page edges (the block of paper), then the two pages.
    for k in (3, 2, 1):
        o = k * 6
        parts.append(f'<path d="M{left - o / 2} {top + o} Q{(left + spine) / 2} {top - 14 + o} {spine} {top + 16 + o} '
                     f'L{spine} {bottom + 14 + o} Q{(left + spine) / 2} {bottom - 14 + o} {left - o / 2} {bottom + o} Z" '
                     f'fill="{PAPER_SHADE}"/>')
        parts.append(f'<path d="M{right + o / 2} {top + o} Q{(spine + right) / 2} {top - 14 + o} {spine} {top + 16 + o} '
                     f'L{spine} {bottom + 14 + o} Q{(spine + right) / 2} {bottom - 14 + o} {right + o / 2} {bottom + o} Z" '
                     f'fill="{PAPER_SHADE}"/>')
    parts.append(f'<path d="M{left} {top} Q{(left + spine) / 2} {top - 22} {spine} {top + 14} L{spine} {bottom + 14} '
                 f'Q{(left + spine) / 2} {bottom - 22} {left} {bottom} Z" fill="url(#pageL)"/>')
    parts.append(f'<path d="M{right} {top} Q{(spine + right) / 2} {top - 22} {spine} {top + 14} L{spine} {bottom + 14} '
                 f'Q{(spine + right) / 2} {bottom - 22} {right} {bottom} Z" fill="url(#pageR)"/>')
    # Text, with highlights behind some lines.
    line_h, gap = 13, 25
    left_lines = [(1.0, None), (0.94, 0), (0.98, 0), (0.6, None), (1.0, None), (0.9, 2), (0.97, None), (0.7, None),
                  (1.0, 1), (0.55, None)]
    right_lines = [(0.95, None), (1.0, 3), (0.8, None), (1.0, None), (0.6, None), (0.92, 1), (1.0, None), (0.85, 2),
                   (0.5, None)]
    def text_block(x0, width, lines):
        out = []
        for i, (frac, hl) in enumerate(lines):
            y = top + 58 + i * (line_h + gap)
            w = width * frac
            if hl is not None:
                out.append(f'<rect x="{x0 - 8}" y="{y - 9}" width="{w + 16:.1f}" height="{line_h + 18}" rx="7" '
                           f'fill="{HIGHLIGHTS[hl]}" fill-opacity="0.75"/>')
            out.append(f'<rect x="{x0}" y="{y}" width="{w:.1f}" height="{line_h}" rx="6.5" fill="{INK}"/>')
        return out
    parts += text_block(left + 62, spine - left - 104, left_lines)
    parts += text_block(spine + 42, right - spine - 104, right_lines)
    # Pen: a margin bracket and squiggle on the left page, an underline, a
    # circled word and a star on the right.
    parts.append(f'<path d="M{left + 34} {top + 96} q-12 0 -12 14 v52 q0 8 -8 10 q8 2 8 10 v52 q0 14 12 14" '
                 f'fill="none" stroke="{PEN_RED}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>')
    parts.append(f'<path d="M{left + 62} {top + 345} q20 -12 40 0 t40 0 t40 0 t40 0" fill="none" stroke="{PEN_RED}" '
                 'stroke-width="6" stroke-linecap="round"/>')
    parts.append(f'<ellipse cx="{spine + 150}" cy="{top + 141}" rx="70" ry="26" fill="none" stroke="{PEN_BLUE}" '
                 'stroke-width="6" transform="rotate(-4 662 493)"/>')
    sx, sy = right - 32, top + 236
    star = " ".join(f"{sx + r * __import__('math').cos(__import__('math').radians(a)):.1f},"
                    f"{sy + r * __import__('math').sin(__import__('math').radians(a)):.1f}"
                    for a, r in zip(range(-90, 270, 36), [20, 8] * 5))
    parts.append(f'<polygon points="{star}" fill="none" stroke="{PEN_RED}" stroke-width="5" stroke-linejoin="round"/>')
    # A sticky note stuck on the right-hand page, with writing on it.
    parts += _note(spine + 166, top + 268, 112, 104, 5, NOTES[0], lines=3)
    # The shadow in the gutter.
    parts.append(f'<rect x="{spine - 26}" y="{top}" width="52" height="{bottom - top + 16}" fill="url(#gutter)"/>')
    return parts


def icon_svg():
    sigma = SHADOW_BLUR_RADIUS / 2
    defs = [
        f'<linearGradient id="bg" x1="0" y1="0" x2="0.3" y2="1">'
        f'<stop offset="0" stop-color="{BG_TOP}"/><stop offset="1" stop-color="{BG_DEEP}"/></linearGradient>',
        '<radialGradient id="glow" cx="0.30" cy="0.18" r="0.75">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.45"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>',
        '<linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.20"/>'
        '<stop offset="0.40" stop-color="#FFFFFF" stop-opacity="0.03"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>',
        '<linearGradient id="edge" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.8"/>'
        '<stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.15"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0.35"/></linearGradient>',
        f'<linearGradient id="cover" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{COVER}"/>'
        f'<stop offset="1" stop-color="{COVER_DARK}"/></linearGradient>',
        f'<linearGradient id="pageL" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{PAPER}"/>'
        f'<stop offset="0.85" stop-color="{PAPER}"/><stop offset="1" stop-color="{PAPER_SHADE}"/></linearGradient>',
        f'<linearGradient id="pageR" x1="1" y1="0" x2="0" y2="0"><stop offset="0" stop-color="{PAPER}"/>'
        f'<stop offset="0.85" stop-color="{PAPER}"/><stop offset="1" stop-color="{PAPER_SHADE}"/></linearGradient>',
        '<linearGradient id="gutter" x1="0" y1="0" x2="1" y2="0">'
        '<stop offset="0" stop-color="#000000" stop-opacity="0"/>'
        '<stop offset="0.5" stop-color="#000000" stop-opacity="0.16"/>'
        '<stop offset="1" stop-color="#000000" stop-opacity="0"/></linearGradient>',
        f'<clipPath id="clip"><path d="{TILE}"/></clipPath>',
        '<filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">'
        f'<feGaussianBlur in="SourceAlpha" stdDeviation="{sigma}"/><feOffset dy="{SHADOW_OFFSET_Y}"/>'
        f'<feComponentTransfer><feFuncA type="linear" slope="{SHADOW_OPACITY}"/></feComponentTransfer>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
        '<filter id="objshadow" x="-30%" y="-30%" width="160%" height="160%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="16"/><feOffset dx="0" dy="18"/>'
        f'<feFlood flood-color="{SHADOW_TINT}" flood-opacity="0.45"/><feComposite operator="in" in2="SourceAlpha"/>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
        '<filter id="note" x="-30%" y="-30%" width="160%" height="160%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="4"/><feOffset dx="0" dy="4"/>'
        '<feComponentTransfer><feFuncA type="linear" slope="0.25"/></feComponentTransfer>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
    ]
    parts = [
        f'<g filter="url(#shadow)"><path d="{TILE}" fill="url(#bg)"/></g>',
        '<g clip-path="url(#clip)">',
        '<rect x="100" y="100" width="824" height="824" fill="url(#glow)"/>',
        '<g filter="url(#objshadow)">', *_book(), '</g>',
        '<rect x="100" y="100" width="824" height="824" fill="url(#sheen)"/>',
        '</g>',
        f'<path d="{TILE}" fill="none" stroke="url(#edge)" stroke-width="6"/>',
    ]
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs>{"".join(defs)}</defs>{"".join(parts)}</svg>\n')


# ---------------------------------------------------------------------------
# .icns writing. These are the element types `iconutil` emits for a standard
# .iconset; all of them hold PNG data.

ICNS_ELEMENTS = [
    ("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64),
    ("ic07", 128), ("ic13", 256), ("ic08", 256), ("ic14", 512),
    ("ic09", 512), ("ic10", 1024),
]


def render_png(svg_path, size, out_path):
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(svg_path), "-o", str(out_path)],
                   check=True)


def write_icns(pngs_by_size, out_path):
    chunks = b""
    for code, size in ICNS_ELEMENTS:
        data = pngs_by_size[size]
        chunks += code.encode("ascii") + struct.pack(">I", len(data) + 8) + data
    out_path.write_bytes(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)


def main():
    parser = argparse.ArgumentParser(description="Generate Resources/AppIcon.svg and AppIcon.icns.")
    parser.add_argument("--preview", action="store_true",
                        help="also write build/icon-preview.png (1024 px)")
    args = parser.parse_args()

    try:
        subprocess.run(["rsvg-convert", "--version"], check=True, capture_output=True)
    except (OSError, subprocess.CalledProcessError):
        sys.exit("error: rsvg-convert not found (macOS: brew install librsvg)")

    RESOURCES.mkdir(exist_ok=True)
    svg_path = RESOURCES / "AppIcon.svg"
    svg_path.write_text(icon_svg())

    with tempfile.TemporaryDirectory() as tmp:
        pngs = {}
        for size in sorted({s for _, s in ICNS_ELEMENTS}):
            png = Path(tmp) / f"icon_{size}.png"
            render_png(svg_path, size, png)
            pngs[size] = png.read_bytes()
        write_icns(pngs, RESOURCES / "AppIcon.icns")

    if args.preview:
        (ROOT / "build").mkdir(exist_ok=True)
        render_png(svg_path, 1024, ROOT / "build" / "icon-preview.png")
    print(f"Wrote {svg_path.relative_to(ROOT)} and Resources/AppIcon.icns")


if __name__ == "__main__":
    main()
