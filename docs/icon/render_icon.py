"""Renders the petty: Tracker app icon in the Enve Hearth style: ember bars, mantel shelf, glowing receipt.

Usage: python3 render_icon.py <ios AppIcon.png> <android ic_launcher_large.png>
"""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 2048
def u(v): return int(round(v * S / 1024))
def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))

def vgrad(w, h, top, bottom):
    strip = Image.new("RGBA", (1, h))
    for y in range(h): strip.putpixel((0, y), lerp(top, bottom, y / max(1, h - 1)))
    return strip.resize((w, h))

def radial(size, center, radius, inner, outer):
    img = Image.new("RGBA", size, outer)
    d = ImageDraw.Draw(img)
    for i in range(160, 0, -1):
        t = i / 160; r = radius * t
        d.ellipse([center[0]-r, center[1]-r, center[0]+r, center[1]+r], fill=lerp(inner, outer, t))
    return img.filter(ImageFilter.GaussianBlur(u(10)))

def tinted(mask, color):
    layer = Image.new("RGBA", mask.size, color); layer.putalpha(mask); return layer

def glow(mask, color, radius, strength=1.0):
    return tinted(mask.filter(ImageFilter.GaussianBlur(radius)).point(lambda v: min(255, int(v * strength))), color)

def filled(mask, top, bottom):
    g = vgrad(S, S, top, bottom); g.putalpha(mask); return g

def background():
    bg = Image.new("RGBA", (S, S), (21, 17, 15, 255))
    bg = Image.alpha_composite(bg, radial((S, S), (S/2, u(400)), u(560), (52, 32, 17, 255), (21, 17, 15, 255)))
    grain = Image.new("RGBA", (S, S), (0, 0, 0, 0)); gd = ImageDraw.Draw(grain)
    for i, x in enumerate(range(0, S, u(19))):
        gd.rectangle([x, 0, x + u(1), S], fill=(255, 225, 190, 5 if i % 4 else 9))
    return Image.alpha_composite(bg, grain)

def ember_bars():
    heights = [0.5, 0.76, 1.0, 0.76, 0.5]
    width, gap = u(48), u(40)
    x0 = (S - (len(heights) * width + (len(heights) - 1) * gap)) // 2
    base, tallest = u(694), u(600)
    bars = Image.new("RGBA", (S, S), (0, 0, 0, 0)); mask_all = Image.new("L", (S, S), 0)
    for i, h in enumerate(heights):
        x = x0 + i * (width + gap); top = base - int(tallest * h); hgt = base - top
        m = Image.new("L", (width, hgt), 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, width - 1, hgt + width], radius=width // 2, fill=255)
        fade = Image.linear_gradient("L").resize((width, hgt)).point(lambda v: int(255 * min(1, 1.35 * (1 - v / 255)) ** 1.1))
        m = ImageChops.multiply(m, fade)
        bar = vgrad(width, hgt, (255, 160, 52, 255), (226, 104, 16, 255)); bar.putalpha(m)
        bars.alpha_composite(bar, (x, top)); mask_all.paste(m, (x, top), m)
    out = glow(mask_all, (255, 128, 24, 255), u(34), 0.8)
    return Image.alpha_composite(out, bars)

def shelf():
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    left, right = u(76), u(948)
    top_y, front_y, mold_y, bottom_y = u(704), u(738), u(752), u(800)
    sh = Image.new("L", (S, S), 0)
    ImageDraw.Draw(sh).rounded_rectangle([left + u(20), u(770), right - u(20), u(900)], radius=u(40), fill=170)
    layer.alpha_composite(tinted(sh.filter(ImageFilter.GaussianBlur(u(36))), (0, 0, 0, 255)))
    apron = Image.new("L", (S, S), 0)  # one molded apron with a shallow arch, like the family's mantels
    ad = ImageDraw.Draw(apron)
    ad.rounded_rectangle([left + u(40), bottom_y - u(10), right - u(40), bottom_y + u(58)], radius=u(18), fill=255)
    ad.ellipse([left + u(150), bottom_y + u(26), right - u(150), bottom_y + u(150)], fill=0)
    layer.alpha_composite(filled(apron, (64, 48, 37, 255), (34, 25, 19, 255)))
    topm = Image.new("L", (S, S), 0)
    ImageDraw.Draw(topm).polygon([(left + u(30), top_y), (right - u(30), top_y), (right, front_y), (left, front_y)], fill=255)
    layer.alpha_composite(filled(topm, (116, 90, 70, 255), (88, 66, 50, 255)))
    front = Image.new("L", (S, S), 0)
    ImageDraw.Draw(front).rounded_rectangle([left, front_y, right, bottom_y], radius=u(10), fill=255)
    layer.alpha_composite(filled(front, (80, 60, 46, 255), (46, 34, 26, 255)))
    d = ImageDraw.Draw(layer)
    d.line([(left + u(4), front_y), (right - u(4), front_y)], fill=(176, 136, 104, 255), width=u(3))
    d.line([(left + u(6), mold_y), (right - u(6), mold_y)], fill=(24, 15, 10, 255), width=u(3))
    d.line([(left + u(6), mold_y + u(3)), (right - u(6), mold_y + u(3))], fill=(92, 62, 40, 255), width=u(2))
    return layer

def shelf_light(width=340):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).ellipse([u(512 - width / 2), u(690), u(512 + width / 2), u(750)], fill=190)
    return tinted(m.filter(ImageFilter.GaussianBlur(u(28))), (255, 150, 48, 255))

class Canvas:
    """Masks for an object's bronze frame, glowing rims, lit glass and white-hot core."""
    def __init__(self):
        self.masks = {k: Image.new("L", (S, S), 0) for k in ("frame", "shade", "lit", "rim", "core")}
        self.d = {k: ImageDraw.Draw(v) for k, v in self.masks.items()}

    def compose(self):
        m = self.masks
        out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        out = Image.alpha_composite(out, glow(ImageChops.lighter(m["lit"], m["rim"]), (255, 124, 20, 255), u(54), 1.0))
        out = Image.alpha_composite(out, filled(m["frame"], (176, 102, 40, 255), (82, 46, 18, 255)))
        out = Image.alpha_composite(out, filled(m["lit"], (255, 214, 130, 255), (242, 128, 24, 255)))
        out = Image.alpha_composite(out, tinted(m["shade"], (58, 28, 8, 255)))
        out = Image.alpha_composite(out, glow(m["rim"], (255, 160, 50, 255), u(9), 1.3))
        out = Image.alpha_composite(out, filled(m["rim"], (255, 196, 96, 255), (240, 132, 30, 255)))
        out = Image.alpha_composite(out, glow(m["core"], (255, 232, 180, 255), u(14), 1.5))
        return Image.alpha_composite(out, tinted(m["core"], (255, 250, 234, 255)))

def rrect_outline(d, box, r, w):
    d.rounded_rectangle(box, radius=r, outline=255, width=w)

def receipt(c):
    x0, x1, y0, y1 = u(396), u(628), u(446), u(706)
    teeth, w = 8, (x1 - x0) / 8
    pts = [(x0, y0), (x1, y0), (x1, y1 - u(20))]
    for i in range(teeth): pts += [(x1 - w * (i + 0.5), y1), (x1 - w * (i + 1), y1 - u(20))]
    c.d["lit"].polygon(pts, fill=255)
    c.d["rim"].line(pts + [pts[0]], fill=255, width=u(5), joint="curve")
    roll = [x0 - u(24), y0 - u(28), x1 + u(24), y0 + u(16)]
    c.d["frame"].rounded_rectangle(roll, radius=u(22), fill=255)
    rrect_outline(c.d["rim"], roll, u(22), u(6))
    c.d["shade"].rectangle([x0 + u(3), y0 + u(16), x1 - u(3), y0 + u(26)], fill=150)
    for i, y in enumerate([u(496), u(530), u(564)]):
        c.d["shade"].rounded_rectangle([x0 + u(32), y, x1 - u(32) - (u(66) if i == 1 else 0), y + u(13)], radius=u(6), fill=210)
    cx, cy, r = u(512), u(632), u(42)
    c.d["shade"].ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    c.d["core"].line([(cx - u(20), cy + u(1)), (cx - u(5), cy + u(16)), (cx + u(22), cy - u(14))], fill=255, width=u(11), joint="curve")
    for p in ((cx - u(20), cy + u(1)), (cx + u(22), cy - u(14))):
        c.d["core"].ellipse([p[0] - u(5.5), p[1] - u(5.5), p[0] + u(5.5), p[1] + u(5.5)], fill=255)

def render(path, size):
    c = Canvas(); receipt(c)
    img = background()
    for layer in (ember_bars(), shelf(), shelf_light(), c.compose()):
        img = Image.alpha_composite(img, layer)
    img = Image.alpha_composite(img, radial((S, S), (S / 2, u(470)), u(860), (0, 0, 0, 0), (0, 0, 0, 140)))
    img.convert("RGB").resize((size, size), Image.LANCZOS).save(path)


if __name__ == "__main__":
    render(sys.argv[1], 1024)
    render(sys.argv[2], 512)
