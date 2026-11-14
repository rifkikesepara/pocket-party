"""Build the approved B monogram, wordmark, app icon and splash vector masters.

Requires fontTools. Run from the project root, then run Godot with
--headless --script tools/render_splash.gd to refresh the PNG exports.
The monogram's two P outlines and shared smile are editable paths.
"""
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "assets/branding"
CREAM, PEACH, BLUE = "#fff6df", "#ffac80", "#081b9d"


def lettering(text, x, y, size, color=CREAM, italic=False, width=None):
    name = "BlackItalic" if italic else "ExtraBold"
    font = TTFont(ROOT / f"assets/fonts/BarlowCondensed-{name}.ttf")
    glyphs, cmap = font.getGlyphSet(), font.getBestCmap()
    scale = size / font["head"].unitsPerEm
    advance = sum(glyphs[cmap[ord(char)]].width for char in text)
    scale_x = width / advance if width else scale
    parts = [f'<g fill="{color}" transform="translate({x} {y}) scale({scale_x} {-scale})">']
    cursor = 0
    for character in text:
        glyph = glyphs[cmap[ord(character)]]
        pen = SVGPathPen(glyphs)
        glyph.draw(pen)
        parts.append(f'<path transform="translate({cursor} 0)" d="{pen.getCommands()}"/>')
        cursor += glyph.width
    parts.append('</g>')
    font.close()
    return ''.join(parts)


def monogram():
    # Counter paths are real holes. No matte, background removal or image mask.
    return f'''<g fill-rule="evenodd">
    <path fill="{PEACH}" d="M155 329L204 132C210 106 224 90 246 84L323 63C360 53 379 70 370 106L340 221C335 240 324 249 304 254L239 270L224 311Q223 315 218 316Z
    M258 139Q259 134 266 132L309 120Q318 118 315 129L302 178Q300 185 293 187L251 199Q242 201 245 191Z"/>
    <path fill="{CREAM}" d="M19 290L68 93C73 72 83 61 103 55L202 29C237 20 253 35 245 68L211 200C206 218 195 229 176 233L95 253L87 284Q86 289 81 289Z
    M114 116Q116 110 122 108L179 93Q188 90 185 101L170 157Q168 164 162 165L105 181Q96 183 99 173Z"/>
    </g>
    <path fill="{BLUE}" transform="translate(0 -18)" d="M130 224C163 237 208 243 251 229Q262 225 258 236C243 268 215 282 188 275C160 268 138 251 129 232Q125 223 130 224Z"/>'''


def wordmark(color=CREAM):
    return lettering("POCKET", 4, 118, 163, color, True, 520) + lettering("PARTY", 4, 254, 163, color, True, 484)


def write_svg(name, width, height, content, density=3):
    TARGET.mkdir(parents=True, exist_ok=True)
    (TARGET / name).write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width*density}" height="{height*density}" viewBox="0 0 {width} {height}">{content}</svg>\n', encoding='utf-8')


def main():
    mark = monogram()
    write_svg('pp-monogram.svg', 400, 360, mark)
    write_svg('pp-wordmark.svg', 540, 270, wordmark())
    write_svg('pp-logo.svg', 1000, 360,
              mark + '<g transform="translate(420 45)">' + wordmark() + '</g>')
    # Full opaque square: iOS applies its own rounded mask at installation.
    write_svg('pp-icon.svg', 1024, 1024,
              f'<path fill="{BLUE}" d="M0 0H1024V1024H0Z"/>'
              f'<g transform="translate(92 110) scale(2.1)">{mark}</g>', density=1)
    background = f'''<path fill="{BLUE}" d="M0 0H420V760H0Z"/>
    <path fill="{PEACH}" d="M0 0H265L0 82ZM0 720L420 649V760H0Z"/>
    <path fill="{BLUE}" d="M45 760L150 685L106 760Z"/>'''
    # Stacked lockup keeps the monogram and lettering legible on portrait screens.
    splash = background + '<g transform="translate(56 128) scale(.78)">' + mark + '</g>'
    splash += '<g transform="translate(35 422) scale(.65)">' + wordmark() + '</g>'
    splash += lettering('PARTİ BAŞLIYOR.', 114, 637, 29)
    write_svg('splash.svg', 420, 760, splash)


if __name__ == '__main__':
    main()
