from PIL import Image, ImageDraw, ImageFilter, ImageFont
import math

S = 2
W, H = 720 * S, 450 * S

SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
SANSB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
f = lambda p, sz: ImageFont.truetype(p, int(sz * S))

LAND = (242, 239, 233)
WATER = (170, 211, 223)
PARK = (199, 226, 190)
ROAD = (255, 255, 255)
ROAD_EDGE = (226, 222, 214)
BUILDING = (231, 227, 219)
TINT = (0, 122, 255)
LABEL = (110, 106, 100)


def base_map():
    img = Image.new("RGB", (W, H), LAND)
    d = ImageDraw.Draw(img, "RGBA")

    d.polygon([(0, 356 * S), (230 * S, 330 * S), (400 * S, 372 * S),
               (720 * S, 342 * S), (720 * S, 450 * S), (0, 450 * S)], fill=WATER)
    d.polygon([(430 * S, 34 * S), (592 * S, 22 * S), (630 * S, 128 * S),
               (476 * S, 154 * S)], fill=PARK)
    d.polygon([(48 * S, 78 * S), (168 * S, 60 * S), (190 * S, 146 * S),
               (66 * S, 164 * S)], fill=PARK)

    for x in range(20, 720, 26):
        for y in range(20, 300, 22):
            if 430 < x < 630 and 20 < y < 155:
                continue
            if abs(x - 300) < 16 or abs(y - 200) < 12:
                continue
            d.rectangle([x * S, y * S, (x + 13) * S, (y + 10) * S], fill=BUILDING)

    roads = [
        ([(0, 205), (720, 182)], 11),
        ([(288, 0), (322, 300)], 11),
        ([(0, 118), (300, 98), (410, 236), (720, 214)], 7),
        ([(524, 0), (486, 300)], 7),
        ([(0, 258), (720, 238)], 5),
        ([(116, 0), (146, 300)], 5),
        ([(640, 0), (622, 300)], 5),
        ([(0, 62), (720, 46)], 4),
    ]
    for pts, w in roads:
        p = [(x * S, y * S) for x, y in pts]
        d.line(p, fill=ROAD_EDGE, width=int((w + 2) * S), joint="curve")
    for pts, w in roads:
        p = [(x * S, y * S) for x, y in pts]
        d.line(p, fill=ROAD, width=int(w * S), joint="curve")

    small = f(SANS, 8)
    for txt, x, y in [("Bd du Maréchal Juin", 430, 176), ("Orne", 300, 396),
                      ("Parc Saint-Pierre", 492, 92), ("Rue de Bayeux", 60, 196)]:
        d.text((x * S, y * S), txt, font=small, fill=LABEL)
    return img


def glass(img, box, radius, tint=None, strength=16):
    x0, y0, x1, y1 = [int(v * S) for v in box]
    r = int(radius * S)
    region = img.crop((x0, y0, x1, y1)).filter(ImageFilter.GaussianBlur(strength))

    wash = Image.new("RGB", region.size, (255, 255, 255))
    region = Image.blend(region, wash, 0.52)
    if tint:
        region = Image.blend(region, Image.new("RGB", region.size, tint), 0.16)

    mask = Image.new("L", region.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, region.size[0] - 1, region.size[1] - 1],
                                           radius=r, fill=255)
    img.paste(region, (x0, y0), mask)

    d = ImageDraw.Draw(img, "RGBA")
    d.rounded_rectangle([x0, y0, x1 - 1, y1 - 1], radius=r,
                        outline=(255, 255, 255, 200), width=int(1.2 * S))
    d.rounded_rectangle([x0 + S, y0 + S, x1 - 1 - S, y1 - 1 - S], radius=r - S,
                        outline=(255, 255, 255, 70), width=S)


img = base_map()
d = ImageDraw.Draw(img, "RGBA")

for i, c in enumerate([(255, 95, 87), (254, 188, 46), (40, 201, 64)]):
    cx = (20 + i * 20) * S
    d.ellipse([cx - 6 * S, 14 * S, cx + 6 * S, 26 * S], fill=c)

glass(img, (20, 46, 280, 200), 22)
glass(img, (34, 60, 266, 92), 16)
d.ellipse([46 * S, 69 * S, 56 * S, 79 * S], outline=(120, 116, 110), width=max(1, int(1.4 * S)))
d.line([(55 * S, 78 * S), (59 * S, 82 * S)], fill=(120, 116, 110), width=max(1, int(1.4 * S)))
d.text((66 * S, 70 * S), "Rechercher un lieu", font=f(SANS, 11), fill=(120, 116, 110))
d.text((40 * S, 104 * S), "RÉCENTS", font=f(SANSB, 8), fill=(130, 126, 120))
for i, txt in enumerate(["Caen, Calvados", "Tokyo, Japon", "Trajet matin.gpx"]):
    d.text((40 * S, (122 + i * 22) * S), txt, font=f(SANS, 11), fill=(38, 36, 34))

glass(img, (664, 46, 700, 178), 18)
cx = 682 * S
d.text((cx - 6 * S, 56 * S), "+", font=f(SANS, 15), fill=(40, 38, 36))
d.line([(670 * S, 82 * S), (694 * S, 82 * S)], fill=(0, 0, 0, 40), width=max(1, S // 2))
d.text((cx - 5 * S, 90 * S), "\u2212", font=f(SANS, 15), fill=(40, 38, 36))
d.line([(670 * S, 116 * S), (694 * S, 116 * S)], fill=(0, 0, 0, 40), width=max(1, S // 2))
d.text((cx - 9 * S, 124 * S), "3D", font=f(SANSB, 10), fill=(40, 38, 36))
d.text((cx - 4 * S, 152 * S), "N", font=f(SANSB, 10), fill=(40, 38, 36))

img_bare = img.copy()
dot = (360 * S, 214 * S)
for rad, alpha in [(34, 34), (26, 46)]:
    d.ellipse([dot[0] - rad * S, dot[1] - rad * S, dot[0] + rad * S, dot[1] + rad * S],
              fill=(TINT[0], TINT[1], TINT[2], alpha))
d.ellipse([dot[0] - 11 * S, dot[1] - 11 * S, dot[0] + 11 * S, dot[1] + 11 * S],
          fill=(255, 255, 255))
d.ellipse([dot[0] - 8 * S, dot[1] - 8 * S, dot[0] + 8 * S, dot[1] + 8 * S], fill=TINT)

glass(img, (196, 380, 452, 426), 23, tint=TINT)
d.ellipse([(214 - 6) * S, (398 - 6) * S, (214 + 6) * S, (398 + 6) * S], fill=TINT)
d.text((232 * S, 388 * S), "49.18290, -0.37070", font=f(MONO, 11), fill=(28, 26, 24))
d.text((232 * S, 406 * S), "iPhone 17 Pro · simulation active", font=f(SANS, 8.5),
       fill=(96, 92, 88))
d.text((432 * S, 396 * S), "\u2715", font=f(SANS, 10), fill=(80, 76, 72))

glass(img, (468, 380, 512, 424), 22)
gc = (490 * S, 402 * S)
d.ellipse([gc[0] - 17 * S, gc[1] - 17 * S, gc[0] + 17 * S, gc[1] + 17 * S],
          outline=(120, 116, 110, 130), width=max(1, int(0.8 * S)))
ang = math.radians(38)
kx, ky = gc[0] + math.sin(ang) * 11 * S, gc[1] - math.cos(ang) * 11 * S
d.ellipse([kx - 8 * S, ky - 8 * S, kx + 8 * S, ky + 8 * S], fill=TINT)

corner = Image.new("L", (W, H), 0)
ImageDraw.Draw(corner).rounded_rectangle([0, 0, W - 1, H - 1], radius=14 * S, fill=255)
out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
out.paste(img, (0, 0), corner)
out.save("/mnt/user-data/outputs/mirage-v0.2-connected.png")

# --- État 2 : aucun iPhone détecté ---
img2 = img_bare.copy()
d2 = ImageDraw.Draw(img2, "RGBA")
d2.rectangle([0, 0, W, H], fill=(0, 0, 0, 46))

glass(img2, (216, 130, 504, 320), 28, strength=22)
gx = 360 * S

d2.rounded_rectangle([(gx - 17 * S), 156 * S, (gx + 17 * S), 176 * S],
                     radius=9 * S, outline=(140, 136, 130), width=max(1, int(1.6 * S)))
d2.line([(gx - 26 * S, 166 * S), (gx - 17 * S, 166 * S)], fill=(140, 136, 130),
        width=max(1, int(1.6 * S)))
d2.line([(gx + 17 * S, 166 * S), (gx + 26 * S, 166 * S)], fill=(140, 136, 130),
        width=max(1, int(1.6 * S)))

def centered(txt, y, font, fill):
    w = d2.textlength(txt, font=font)
    d2.text((gx - w / 2, y * S), txt, font=font, fill=fill)

centered("Aucun iPhone détecté", 194, f(SANS, 15), (26, 24, 22))
centered("Branche ton iPhone en USB, déverrouille-le, puis", 220, f(SANS, 10), (104, 100, 96))
centered("approuve la connexion si macOS le demande.", 236, f(SANS, 10), (104, 100, 96))

bw, bh = 84, 28
left0, left1 = gx - (bw + 5) * S, gx - 5 * S
right0, right1 = gx + 5 * S, gx + (bw + 5) * S
d2.rounded_rectangle([left0, 268 * S, left1, (268 + bh) * S], radius=14 * S, fill=TINT)
t, ft = "Réessayer", f(SANS, 10)
d2.text(((left0 + left1 - d2.textlength(t, font=ft)) / 2, 276 * S), t, font=ft,
        fill=(255, 255, 255))
d2.rounded_rectangle([right0, 268 * S, right1, (268 + bh) * S], radius=14 * S,
                     fill=(255, 255, 255, 140), outline=(255, 255, 255, 215),
                     width=max(1, S))
t, ft = "Mode développeur", f(SANS, 9.5)
d2.text(((right0 + right1 - d2.textlength(t, font=ft)) / 2, 277 * S), t, font=ft,
        fill=(40, 38, 36))

out2 = Image.new("RGBA", (W, H), (0, 0, 0, 0))
out2.paste(img2, (0, 0), corner)
out2.save("/mnt/user-data/outputs/mirage-v0.2-no-device.png")

# --- État 3 : trajet en cours ---
img3 = img_bare.copy()
d3 = ImageDraw.Draw(img3, "RGBA")

route = [(300, 96), (322, 150), (352, 206), (392, 250), (452, 244),
         (520, 236), (592, 230), (646, 224)]
rp = [(x * S, y * S) for x, y in route]
d3.line(rp, fill=(255, 255, 255, 235), width=int(11 * S), joint="curve")
d3.line(rp, fill=TINT, width=int(7 * S), joint="curve")

px, py = 392 * S, 250 * S
for rad, alpha in [(30, 34), (22, 46)]:
    d3.ellipse([px - rad * S, py - rad * S, px + rad * S, py + rad * S],
               fill=(TINT[0], TINT[1], TINT[2], alpha))
d3.ellipse([px - 11 * S, py - 11 * S, px + 11 * S, py + 11 * S], fill=(255, 255, 255))
d3.ellipse([px - 8 * S, py - 8 * S, px + 8 * S, py + 8 * S], fill=TINT)

ex, ey = 646 * S, 224 * S
d3.ellipse([ex - 12 * S, ey - 12 * S, ex + 12 * S, ey + 12 * S], fill=(235, 62, 54))
d3.ellipse([ex - 4 * S, ey - 6 * S, ex + 4 * S, ey + 2 * S], fill=(255, 255, 255))

glass(img3, (252, 306, 468, 396), 22)
mx = 360 * S

seg = [("car", True), ("tram", False), ("bike", False), ("walk", False)]
sw = 46
for i, (name, active) in enumerate(seg):
    x0 = mx - 2 * sw * S + i * sw * S
    x1 = x0 + sw * S
    if active:
        d3.rounded_rectangle([x0 + 2 * S, 316 * S, x1 - 2 * S, 338 * S],
                             radius=7 * S, fill=(255, 255, 255, 225))
    cx2 = (x0 + x1) / 2
    col = (24, 22, 20) if active else (120, 116, 112)
    if name == "car":
        d3.rounded_rectangle([cx2 - 10 * S, 322 * S, cx2 + 10 * S, 331 * S],
                             radius=3 * S, fill=col)
        d3.rounded_rectangle([cx2 - 6 * S, 318 * S, cx2 + 6 * S, 324 * S],
                             radius=2 * S, fill=col)
    elif name == "tram":
        d3.rounded_rectangle([cx2 - 7 * S, 318 * S, cx2 + 7 * S, 332 * S],
                             radius=3 * S, outline=col, width=max(1, int(1.6 * S)))
        d3.line([(cx2 - 7 * S, 326 * S), (cx2 + 7 * S, 326 * S)], fill=col,
                width=max(1, int(1.6 * S)))
    elif name == "bike":
        d3.ellipse([cx2 - 11 * S, 322 * S, cx2 - 3 * S, 330 * S], outline=col,
                   width=max(1, int(1.5 * S)))
        d3.ellipse([cx2 + 3 * S, 322 * S, cx2 + 11 * S, 330 * S], outline=col,
                   width=max(1, int(1.5 * S)))
        d3.line([(cx2 - 7 * S, 326 * S), (cx2 - 1 * S, 319 * S), (cx2 + 7 * S, 326 * S)],
                fill=col, width=max(1, int(1.5 * S)))
    else:
        d3.ellipse([cx2 - 2 * S, 317 * S, cx2 + 2 * S, 321 * S], fill=col)
        d3.line([(cx2, 321 * S), (cx2, 327 * S)], fill=col, width=max(1, int(1.6 * S)))
        d3.line([(cx2, 327 * S), (cx2 - 4 * S, 333 * S)], fill=col, width=max(1, int(1.6 * S)))
        d3.line([(cx2, 327 * S), (cx2 + 4 * S, 333 * S)], fill=col, width=max(1, int(1.6 * S)))

info = "4,8 km · 11 min · 26 km/h"
fi = f(SANS, 10.5)
d3.text((mx - d3.textlength(info, font=fi) / 2, 346 * S), info, font=fi, fill=(30, 28, 26))

d3.rounded_rectangle([mx - 88 * S, 364 * S, mx + 88 * S, 368 * S], radius=2 * S,
                     fill=(0, 0, 0, 40))
d3.rounded_rectangle([mx - 88 * S, 364 * S, mx - 88 * S + 104 * S, 368 * S],
                     radius=2 * S, fill=TINT)

d3.rounded_rectangle([mx - 70 * S, 378 * S, mx + 30 * S, 404 * S], radius=13 * S, fill=TINT)
t = "Trajet en cours"
d3.text((mx - 70 * S + (100 * S - d3.textlength(t, font=f(SANS, 10))) / 2, 385 * S), t,
        font=f(SANS, 10), fill=(255, 255, 255))
d3.rounded_rectangle([mx + 38 * S, 378 * S, mx + 70 * S, 404 * S], radius=13 * S,
                     fill=(255, 255, 255, 150), outline=(255, 255, 255, 215), width=max(1, S))
d3.rectangle([mx + 50 * S, 387 * S, mx + 58 * S, 395 * S], fill=(40, 38, 36))

glass(img3, (196, 414, 452, 444), 15, tint=TINT)
d3.text((216 * S, 421 * S), "49.18612, -0.36104", font=f(MONO, 10), fill=(28, 26, 24))
d3.text((372 * S, 422 * S), "26 km/h", font=f(SANS, 9), fill=(70, 66, 62))

out3 = Image.new("RGBA", (W, H), (0, 0, 0, 0))
out3.paste(img3, (0, 0), corner)
out3.save("/mnt/user-data/outputs/mirage-v0.3-route.png")
print("ok")
