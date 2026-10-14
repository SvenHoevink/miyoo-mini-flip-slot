#!/usr/bin/env python3
"""Regenerate slot-ui's sticker wordmark as outlined paths.

Upstream's wordmark.svg is "ANBERNIC RG SP" with the glyphs already converted
to paths -- dark letters (#231f20) over a white stroke -- so the sticker needs
no font at render time. This port's sticker names the Miyoo instead, and this
script is how that asset was made: Open Sans Bold (assets/label.ttf, already
shipped and already credited on the sticker), the first word obliqued the way
upstream slants "ANBERNIC".

    python3 tools/wordmark.py label.ttf > wordmark.svg
"""
import sys
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.misc.transform import Identity

TEXT = [("MIYOO", 0.16), (" ", 0.0), ("MINI FLIP", 0.0)]  # (run, oblique)
CAP = 100.0          # cap height in output units, as upstream's paths use
TRACK = 0.0          # extra letter spacing, in output units
PAD = 22.5           # upstream's margin, left/right and top/bottom
BASE = 122.5


def main(path):
    font = TTFont(path)
    gs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = CAP / font["OS/2"].sCapHeight

    paths, x = [], 0.0
    for run, slant in TEXT:
        for ch in run:
            g = cmap[ord(ch)]
            adv = gs[g].width * scale
            if ch != " ":
                # skew about the baseline, then place: y is already flipped by
                # the enclosing scale(1 -1), so the shear sign is as written.
                t = Identity.translate(x, 0).scale(scale).skew(0).transform(
                    (1, 0, slant, 1, 0, 0)
                )
                pen = SVGPathPen(gs)
                gs[g].draw(TransformPen(pen, t))
                d = pen.getCommands()
                if d:
                    paths.append(d)
            x += adv + (TRACK if ch != " " else 0.0)

    w = round(x + PAD * 2, 1)
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} 145.0">']
    out.append(f'  <g transform="translate({PAD:.2f} {BASE:.2f}) scale(1 -1)">')
    out.append(
        '    <g fill="none" stroke="#ffffff" stroke-width="17.00"'
        ' stroke-linejoin="round" stroke-linecap="round">'
    )
    for d in paths:
        out.append(f'      <path d="{d}"/>')
    out.append("    </g>")
    out.append('    <g fill="#231f20">')
    for d in paths:
        out.append(f'      <path d="{d}"/>')
    out.append("    </g>")
    out.append("  </g>")
    out.append("</svg>")
    print("\n".join(out))


if __name__ == "__main__":
    main(sys.argv[1])
