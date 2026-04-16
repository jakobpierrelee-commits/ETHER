#!/usr/bin/env python3
"""
Generates the Ether app icon at 1024×1024, then renders all macOS required sizes.
Run: python3 generate_icon.py
Then: iconutil -c icns Ether.iconset -o Ether.icns
"""
from PIL import Image, ImageDraw, ImageFilter
import math
import os

SIZE = 1024
OUTPUT = "Ether.iconset"
os.makedirs(OUTPUT, exist_ok=True)


def lerp(a, b, t):
    return tuple(int(ax + (bx - ax) * t) for ax, bx in zip(a, b))


def make_icon(size=SIZE):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # ───────── background: dark rounded square with subtle vertical gradient ─────────
    corner_radius = int(size * 0.22)  # macOS Big Sur+ standard rounding
    bg_top = (12, 12, 18, 255)
    bg_bottom = (0, 0, 0, 255)

    # Draw gradient into a mask, then use the rounded rect as the clip
    grad = Image.new("RGBA", (size, size))
    gd = ImageDraw.Draw(grad)
    for y in range(size):
        t = y / size
        gd.line([(0, y), (size, y)], fill=lerp(bg_top, bg_bottom, t))

    mask = Image.new("L", (size, size), 0)
    mdraw = ImageDraw.Draw(mask)
    mdraw.rounded_rectangle(
        [(0, 0), (size - 1, size - 1)],
        radius=corner_radius,
        fill=255,
    )
    img.paste(grad, (0, 0), mask=mask)

    # ───────── inner edge highlight (subtle) ─────────
    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hd = ImageDraw.Draw(highlight)
    hd.rounded_rectangle(
        [(3, 3), (size - 4, size - 4)],
        radius=corner_radius - 2,
        outline=(255, 255, 255, 28),
        width=2,
    )
    img.alpha_composite(highlight)

    # ───────── the EQ curve ─────────
    # A stylized EQ response: gentle cut in mids, bump in upper-mids, air lift at top
    n_points = 200
    pad_x = size * 0.18
    mid_y = size * 0.52
    amp = size * 0.18
    points = []
    for i in range(n_points):
        t = i / (n_points - 1)
        x = pad_x + t * (size - 2 * pad_x)
        # Shape: slight dip then ascending peaks
        y_off = (
            math.sin(t * math.pi * 1.2) * 0.3
            - math.sin(t * math.pi * 2.7) * 0.45
            + math.sin(t * math.pi * 5.1 - 0.6) * 0.25
        )
        y = mid_y + y_off * amp
        points.append((x, y))

    # Glow pass — thick, blurred, cyan
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    glow_color = (0, 235, 255, 180)
    gdraw.line(points, fill=glow_color, width=int(size * 0.035), joint="curve")
    glow = glow.filter(ImageFilter.GaussianBlur(radius=size * 0.022))
    img.alpha_composite(glow)

    # Inner brighter line
    inner_glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    igdraw = ImageDraw.Draw(inner_glow)
    igdraw.line(points, fill=(180, 250, 255, 230), width=int(size * 0.018), joint="curve")
    inner_glow = inner_glow.filter(ImageFilter.GaussianBlur(radius=size * 0.006))
    img.alpha_composite(inner_glow)

    # Crisp top edge stroke
    edge = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    edraw = ImageDraw.Draw(edge)
    edraw.line(points, fill=(255, 255, 255, 245), width=int(size * 0.008), joint="curve")
    img.alpha_composite(edge)

    # ───────── small EQ handle dots on the curve ─────────
    handle_positions = [0.05, 0.25, 0.5, 0.72, 0.95]
    band_colors = [
        (84, 140, 255, 255),   # blue
        (120, 210, 255, 255),  # light cyan
        (130, 240, 180, 255),  # green
        (255, 180, 120, 255),  # orange
        (255, 120, 200, 255),  # pink
    ]
    for t_pos, color in zip(handle_positions, band_colors):
        idx = int(t_pos * (n_points - 1))
        cx, cy = points[idx]
        r = size * 0.028
        # outer halo
        halo = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        hd = ImageDraw.Draw(halo)
        hd.ellipse(
            [(cx - r * 2.4, cy - r * 2.4), (cx + r * 2.4, cy + r * 2.4)],
            fill=(color[0], color[1], color[2], 80),
        )
        halo = halo.filter(ImageFilter.GaussianBlur(radius=size * 0.012))
        img.alpha_composite(halo)
        # solid dot
        draw.ellipse([(cx - r, cy - r), (cx + r, cy + r)], fill=color)
        # inner highlight
        inner_r = r * 0.45
        draw.ellipse(
            [
                (cx - inner_r, cy - inner_r - r * 0.25),
                (cx + inner_r, cy + inner_r - r * 0.25),
            ],
            fill=(255, 255, 255, 140),
        )

    return img


def save_sized(base_img, size, filename):
    resized = base_img.resize((size, size), Image.LANCZOS)
    resized.save(os.path.join(OUTPUT, filename), "PNG")


base = make_icon(SIZE)

# macOS iconset convention
sizes = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for px, name in sizes:
    save_sized(base, px, name)

# Also save the master
base.save("Ether_1024.png", "PNG")
print("Generated iconset in", OUTPUT)
print("Run: iconutil -c icns Ether.iconset -o Ether.icns")
