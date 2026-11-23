#!/usr/bin/env python3
"""
OnyxOS Asset Generator v2.0
Génère : logos, fonds d'écran, thème Plymouth, thème SDDM, icônes OnyxIcons.
Palette :
  #0B0A10  Deep Black     (11,  10,  16)
  #151320  Anthracite     (21,  19,  32)
  #8B5CF6  Electric Violet(139, 92, 246)
  #A855F7  Vivid Purple   (168, 85, 247)
  #C084FC  Light Violet   (192,132, 252)
  #EDE9FE  Lavender White (237,233, 254)

Usage :
  python3 generate_assets.py              # tout générer
  python3 generate_assets.py --icons-only # uniquement les icônes OnyxIcons
"""

import argparse
import math
import os
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError:
    print("ERREUR : Pillow requis → pip install Pillow", file=sys.stderr)
    sys.exit(1)

OUTPUT_DIR  = Path(__file__).resolve().parent
PROJECT_DIR = OUTPUT_DIR.parent
ASSETS_DIR  = OUTPUT_DIR
THEME_DIR   = PROJECT_DIR / "theme"

# Palette OnyxOS
COLOR_DEEP_BLACK = (11,  10,  16)
COLOR_ANTHRACITE = (21,  19,  32)
COLOR_SURFACE    = (30,  27,  46)
COLOR_VIOLET_1   = (139, 92, 246)   # #8B5CF6
COLOR_VIOLET_2   = (168, 85, 247)   # #A855F7
COLOR_VIOLET_3   = (192,132, 252)   # #C084FC
COLOR_TEXT_LIGHT = (237,233, 254)   # #EDE9FE
COLOR_GLOW       = (139, 92, 246, 60)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
    "C:/Windows/Fonts/segoeuib.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
]

def load_font(size: int):
    for candidate in FONT_CANDIDATES:
        if os.path.isfile(candidate):
            try:
                return ImageFont.truetype(candidate, size)
            except OSError:
                continue
    try:
        return ImageFont.load_default(size)
    except TypeError:
        return ImageFont.load_default()

def render_gemstone(draw, cx, cy, radius):
    pts = [(cx + radius * math.cos(math.radians(60*i - 30)),
            cy + radius * math.sin(math.radians(60*i - 30))) for i in range(6)]
    inner = [(cx + radius * 0.55 * math.cos(math.radians(60*i - 30)),
              cy + radius * 0.55 * math.sin(math.radians(60*i - 30))) for i in range(6)]
    facets = [
        (139, 92, 246), (168, 85, 247), (76,  29, 149),
        (91,  33, 182), (124, 58, 237), (192,132, 252),
    ]
    for i in range(6):
        draw.polygon([pts[i], pts[(i+1)%6], (cx, cy)], fill=facets[i])
    for i in range(6):
        draw.line([inner[i], inner[(i+1)%6]], fill=COLOR_VIOLET_3, width=2)
        draw.line([pts[i], inner[i]], fill=COLOR_TEXT_LIGHT, width=2)
    for i in range(6):
        draw.line([pts[i], pts[(i+1)%6]], fill=COLOR_VIOLET_2, width=3)
    draw.ellipse([cx-8, cy-8, cx+8, cy+8], fill=COLOR_TEXT_LIGHT)

# ---------------------------------------------------------------------------
# SVG Logo
# ---------------------------------------------------------------------------

def create_svg_logo(output_path: Path):
    svg = """\
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">
  <defs>
    <linearGradient id="bgGlow" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#151320"/>
      <stop offset="50%" stop-color="#0B0A10"/>
      <stop offset="100%" stop-color="#151320"/>
    </linearGradient>
    <linearGradient id="purpleGrad1" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#C084FC"/>
      <stop offset="50%" stop-color="#A855F7"/>
      <stop offset="100%" stop-color="#8B5CF6"/>
    </linearGradient>
    <linearGradient id="purpleGrad2" x1="100%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#8B5CF6"/>
      <stop offset="100%" stop-color="#4C1D95"/>
    </linearGradient>
    <linearGradient id="facetHighlight" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#EDE9FE" stop-opacity="0.8"/>
      <stop offset="100%" stop-color="#A855F7" stop-opacity="0.2"/>
    </linearGradient>
    <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="16" result="blur"/>
      <feComposite in="SourceGraphic" in2="blur" operator="over"/>
    </filter>
  </defs>
  <rect width="512" height="512" rx="100" fill="url(#bgGlow)"/>
  <rect width="504" height="504" x="4" y="4" rx="96" fill="none"
        stroke="#8B5CF6" stroke-width="2" stroke-opacity="0.4"/>
  <g filter="url(#glow)">
    <polygon points="256,60 410,150 410,330 256,420 102,330 102,150"
             fill="none" stroke="#A855F7" stroke-width="6" stroke-linejoin="round"/>
    <polygon points="256,60 256,240 102,150" fill="url(#purpleGrad1)" fill-opacity="0.9"/>
    <polygon points="256,60 410,150 256,240" fill="url(#purpleGrad2)" fill-opacity="0.8"/>
    <polygon points="102,150 256,240 102,330" fill="#3B186B" fill-opacity="0.95"/>
    <polygon points="102,330 256,240 256,420" fill="url(#purpleGrad1)" fill-opacity="0.75"/>
    <polygon points="256,420 256,240 410,330" fill="#2E1065" fill-opacity="0.9"/>
    <polygon points="410,330 256,240 410,150" fill="url(#purpleGrad2)" fill-opacity="0.85"/>
    <polygon points="256,120 330,195 330,285 256,360 182,285 182,195"
             fill="none" stroke="url(#facetHighlight)" stroke-width="4"/>
    <circle cx="256" cy="240" r="14" fill="#EDE9FE"/>
  </g>
  <text x="256" y="475" text-anchor="middle"
        font-family="system-ui,-apple-system,sans-serif" font-weight="800" font-size="34"
        fill="#EDE9FE" letter-spacing="8">ONYXOS</text>
</svg>
"""
    with open(output_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(svg)
    print(f"[OK] SVG logo : {output_path}")

# ---------------------------------------------------------------------------
# PNG Logo
# ---------------------------------------------------------------------------

def generate_logo_png(output_path: Path, size=512):
    img = Image.new("RGBA", (size, size), COLOR_DEEP_BLACK + (255,))
    glow_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_img)
    glow_draw.ellipse([size*0.15, size*0.15, size*0.85, size*0.85], fill=(139, 92, 246, 35))
    glow_img = glow_img.filter(ImageFilter.GaussianBlur(30))
    img = Image.alpha_composite(img, glow_img)
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle([8, 8, size-8, size-8], radius=size//6, outline=COLOR_VIOLET_1, width=3)
    render_gemstone(draw, size//2, int(size*0.44), int(size*0.28))
    sub_y = int(size*0.80)
    draw.line([size*0.25, sub_y, size*0.75, sub_y], fill=COLOR_VIOLET_1, width=2)
    img.save(output_path, "PNG")
    print(f"[OK] PNG logo : {output_path}")

# ---------------------------------------------------------------------------
# Wallpaper
# ---------------------------------------------------------------------------

def generate_wallpaper(output_path: Path, width=1920, height=1080):
    print(f"[*] Wallpaper {width}x{height}…")
    img = Image.new("RGB", (width, height), COLOR_DEEP_BLACK)
    draw = ImageDraw.Draw(img)
    polygons = [
        [(0, 0), (int(width*.35), 0), (int(width*.2), int(height*.45)), (0, int(height*.3))],
        [(int(width*.35), 0), (width, 0), (int(width*.8), int(height*.5)), (int(width*.5), int(height*.2))],
        [(width, int(height*.3)), (width, height), (int(width*.65), height), (int(width*.7), int(height*.6))],
        [(0, int(height*.5)), (int(width*.25), int(height*.6)), (int(width*.15), height), (0, height)],
        [(int(width*.2), height), (int(width*.7), height), (int(width*.5), int(height*.75))],
    ]
    for poly in polygons:
        draw.polygon(poly, fill=COLOR_ANTHRACITE)
    for poly in polygons:
        for i in range(len(poly)):
            draw.line([poly[i], poly[(i+1)%len(poly)]], fill=COLOR_SURFACE, width=2)
    ambient = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    adr = ImageDraw.Draw(ambient)
    cx, cy = width//2, height//2
    gr = int(min(width, height)*0.4)
    adr.ellipse([cx-gr, cy-gr, cx+gr, cy+gr], fill=(139, 92, 246, 25))
    ambient = ambient.filter(ImageFilter.GaussianBlur(60))
    img.paste(ambient, (0, 0), ambient)
    draw = ImageDraw.Draw(img)
    render_gemstone(draw, cx, cy-20, int(min(width, height)*0.12))
    img.save(output_path, "PNG", optimize=True)
    print(f"[OK] Wallpaper : {output_path}")

# ---------------------------------------------------------------------------
# Plymouth
# ---------------------------------------------------------------------------

def generate_plymouth_watermark(output_path: Path):
    width, height = 460, 132
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    render_gemstone(draw, 66, height//2, 50)
    font = load_font(46)
    text = "ONYXOS"
    bbox = draw.textbbox((0, 0), text, font=font)
    draw.text((150, (height-(bbox[3]-bbox[1]))//2 - bbox[1]), text, font=font, fill=COLOR_TEXT_LIGHT)
    tw = bbox[2] - bbox[0]
    draw.text((150+tw+12, height//2-12), "1.0", font=load_font(18), fill=COLOR_VIOLET_3)
    img.save(output_path, "PNG")
    print(f"[OK] Plymouth watermark : {output_path}")

def generate_plymouth_background(output_path: Path, width=1920, height=1080):
    img = Image.new("RGB", (width, height), COLOR_DEEP_BLACK)
    draw = ImageDraw.Draw(img)
    for y in range(height):
        t = y / height
        draw.line([(0, y), (width, y)], fill=(int(11+t*10), int(10+t*9), int(16+t*16)))
    glow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    r = int(min(width, height)*0.45)
    gd.ellipse([width//2-r, height//2-r, width//2+r, height//2+r], fill=(139, 92, 246, 38))
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    img.paste(glow, (0, 0), glow)
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, height-4, width, height], fill=COLOR_VIOLET_1)
    img.save(output_path, "PNG", optimize=True)
    print(f"[OK] Plymouth background : {output_path}")

def generate_plymouth_throbber(output_dir: Path, frames=24, size=64):
    for index in range(frames):
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        start = (index * 360) // frames
        box = [8, 8, size-8, size-8]
        draw.arc(box, start, start+250, fill=COLOR_VIOLET_1+(255,), width=7)
        draw.arc(box, start+250, start+320, fill=COLOR_VIOLET_3+(255,), width=7)
        angle = math.radians(start)
        cx = size/2 + (size/2-12)*math.cos(angle)
        cy = size/2 + (size/2-12)*math.sin(angle)
        draw.ellipse([cx-4, cy-4, cx+4, cy+4], fill=COLOR_TEXT_LIGHT+(255,))
        img.save(output_dir / f"throbber-{index+1:04d}.png", "PNG")
    print(f"[OK] {frames} frames Plymouth throbber générées.")

def generate_plymouth_theme(output_dir: Path):
    plymouth_dir = output_dir / "plymouth" / "onyxos"
    if plymouth_dir.exists():
        for f in plymouth_dir.iterdir():
            if f.is_file():
                f.unlink()
    plymouth_dir.mkdir(parents=True, exist_ok=True)
    conf = """\
[Plymouth Theme]
Name=OnyxOS
Description=OnyxOS 1.0 boot splash
ModuleName=two-step

[two-step]
ImageDir=/usr/share/plymouth/themes/onyxos
ScaleBackgroundImage=true
UseFirmwareBackground=false
BackgroundStartColor=0x0B0A10
BackgroundEndColor=0x151320
ProgressBarBackgroundColor=0x1E1B2E
ProgressBarForegroundColor=0x8B5CF6
ProgressBarHorizontalAlignment=.5
ProgressBarVerticalAlignment=.86
WatermarkHorizontalAlignment=.5
WatermarkVerticalAlignment=.46
TitleHorizontalAlignment=.5
TitleVerticalAlignment=.34
Font=Cantarell 12
TitleFont=Cantarell Light 30
MessageBelowAnimation=true

[boot-up]
UseEndAnimation=false
UseProgressBar=true

[shutdown]
UseEndAnimation=false
"""
    with open(plymouth_dir / "onyxos.plymouth", "w", encoding="utf-8", newline="\n") as f:
        f.write(conf)
    generate_plymouth_background(plymouth_dir / "background.png")
    generate_plymouth_watermark(plymouth_dir / "watermark.png")
    generate_plymouth_throbber(plymouth_dir)
    print(f"[OK] Thème Plymouth : {plymouth_dir}")

# ---------------------------------------------------------------------------
# SDDM
# ---------------------------------------------------------------------------

def generate_sddm_theme(output_dir: Path):
    sddm_dir = output_dir / "sddm" / "onyxos"
    sddm_dir.mkdir(parents=True, exist_ok=True)
    metadata = """\
[SddmGreeterTheme]
Name=OnyxOS
Description=OnyxOS 1.0 KDE Plasma Login Greeter
Author=OnyxOS Team
Theme-Id=onyxos
Theme-API=2.0
Website=https://github.com/Gael66666/Onyxos
License=GPL
Type=sddm-theme
ConfigFile=theme.conf
MainScript=Main.qml
"""
    with open(sddm_dir / "metadata.desktop", "w", encoding="utf-8", newline="\n") as f:
        f.write(metadata)
    conf = """\
[General]
background=sddm-background.png
type=image
color=#0B0A10
fontSize=10
font=Noto Sans
headerColor=#8B5CF6
accentColor=#A855F7
"""
    with open(sddm_dir / "theme.conf", "w", encoding="utf-8", newline="\n") as f:
        f.write(conf)
    generate_wallpaper(sddm_dir / "sddm-background.png", 1920, 1080)
    print(f"[OK] Thème SDDM : {sddm_dir}")

# ---------------------------------------------------------------------------
# OnyxIcons : icônes SVG noir/violet sur mesure
# ---------------------------------------------------------------------------

def _svg_folder(color_fill: str, color_accent: str, label: str = "") -> str:
    """Génère un SVG d'icône de dossier OnyxOS (noir & violet)."""
    return f"""\
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" width="48" height="48">
  <defs>
    <linearGradient id="fg" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="{color_accent}"/>
      <stop offset="100%" stop-color="{color_fill}"/>
    </linearGradient>
  </defs>
  <!-- Dossier arrière -->
  <rect x="2" y="12" width="44" height="32" rx="4" fill="#0B0A10" stroke="{color_accent}" stroke-width="1.5"/>
  <!-- Onglet dossier -->
  <path d="M2 12 Q2 8 6 8 L18 8 Q22 8 24 12 Z" fill="url(#fg)"/>
  <!-- Corps dossier -->
  <rect x="2" y="12" width="44" height="32" rx="4" fill="url(#fg)" fill-opacity="0.85"/>
  <!-- Reflet -->
  <rect x="4" y="14" width="40" height="8" rx="2" fill="white" fill-opacity="0.08"/>
  <!-- Contour -->
  <rect x="2" y="12" width="44" height="32" rx="4" fill="none" stroke="{color_accent}" stroke-width="1.2"/>
</svg>
"""

def _svg_app_icon(shape: str, color: str, bg: str = "#0B0A10") -> str:
    """Icône d'application générique (cercle + forme)."""
    shapes = {
        "terminal": '<rect x="12" y="16" width="24" height="16" rx="2" fill="none" stroke="{c}" stroke-width="2"/><text x="24" y="27" text-anchor="middle" font-family="monospace" font-size="9" fill="{c}">$_</text>',
        "files":    '<path d="M14 10 h12 l6 6 v22 H14 Z" fill="none" stroke="{c}" stroke-width="2"/><line x1="18" y1="20" x2="30" y2="20" stroke="{c}" stroke-width="1.5"/><line x1="18" y1="25" x2="30" y2="25" stroke="{c}" stroke-width="1.5"/><line x1="18" y1="30" x2="26" y2="30" stroke="{c}" stroke-width="1.5"/>',
        "settings": '<circle cx="24" cy="24" r="6" fill="none" stroke="{c}" stroke-width="2"/><path d="M24 10 v4 M24 34 v4 M10 24 h4 M34 24 h4 M14.1 14.1 l2.8 2.8 M31.1 31.1 l2.8 2.8 M31.1 14.1 l-2.8 2.8 M14.1 31.1 l-2.8 2.8" stroke="{c}" stroke-width="2"/>',
        "browser":  '<circle cx="24" cy="24" r="12" fill="none" stroke="{c}" stroke-width="2"/><path d="M12 24 h24 M24 12 Q18 24 24 36 Q30 24 24 12" stroke="{c}" stroke-width="1.5" fill="none"/>',
    }
    s = shapes.get(shape, shapes["files"]).replace("{c}", color)
    return f"""\
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" width="48" height="48">
  <rect width="48" height="48" rx="10" fill="{bg}"/>
  {s}
</svg>
"""

def generate_onyxicons(base_dir: Path):
    """Génère le pack d'icônes OnyxIcons dans assets/icons/."""
    icons_dir = base_dir / "icons"

    # Dossiers de tailles standard
    sizes = [16, 22, 32, 48, 64, 128]
    # Dossiers = places (violet électrique), apps = noir/violet
    folder_configs = [
        ("folder",          COLOR_VIOLET_2, "#8B5CF6"),
        ("folder-open",     COLOR_VIOLET_1, "#A855F7"),
        ("folder-home",     (100, 60, 200), "#8B5CF6"),
        ("folder-download", (80,  40, 180), "#6D28D9"),
        ("folder-music",    (120, 80, 220), "#9333EA"),
        ("folder-pictures", (140, 90, 240), "#7C3AED"),
        ("folder-videos",   (90,  50, 190), "#7C3AED"),
        ("folder-documents",(110, 70, 210), "#8B5CF6"),
    ]
    app_icons = [
        ("utilities-terminal",   "terminal"),
        ("system-file-manager",  "files"),
        ("preferences-system",   "settings"),
        ("internet-web-browser", "browser"),
    ]

    for size in sizes:
        # Places (dossiers)
        places_dir = icons_dir / f"{size}x{size}" / "places"
        places_dir.mkdir(parents=True, exist_ok=True)
        for name, fc, fa in folder_configs:
            rgb_fill = fc if isinstance(fc, str) else "#{:02X}{:02X}{:02X}".format(*fc)
            svg = _svg_folder(rgb_fill, fa)
            (places_dir / f"{name}.svg").write_text(svg, encoding="utf-8")

        # Apps
        apps_dir = icons_dir / f"{size}x{size}" / "apps"
        apps_dir.mkdir(parents=True, exist_ok=True)
        for name, shape in app_icons:
            svg = _svg_app_icon(shape, "#8B5CF6")
            (apps_dir / f"{name}.svg").write_text(svg, encoding="utf-8")

        # Status
        status_dir = icons_dir / f"{size}x{size}" / "status"
        status_dir.mkdir(parents=True, exist_ok=True)

    print(f"[OK] OnyxIcons SVG générées dans {icons_dir}")

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="OnyxOS Asset Generator v2.0")
    parser.add_argument("--icons-only", action="store_true",
                        help="Générer uniquement le pack d'icônes OnyxIcons")
    args = parser.parse_args()

    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    THEME_DIR.mkdir(parents=True, exist_ok=True)

    if args.icons_only:
        generate_onyxicons(ASSETS_DIR)
        return

    print("=== OnyxOS Asset Pipeline v2.0 ===")

    # 1. Logos
    create_svg_logo(ASSETS_DIR / "onyxos-logo.svg")
    generate_logo_png(ASSETS_DIR / "onyxos-logo.png", size=512)

    # 2. Wallpapers
    generate_wallpaper(ASSETS_DIR / "wallpaper-1920x1080.png", 1920, 1080)
    generate_wallpaper(ASSETS_DIR / "wallpaper-3840x2160.png", 3840, 2160)

    # 3. Plymouth
    generate_plymouth_theme(ASSETS_DIR)

    # 4. SDDM
    generate_sddm_theme(ASSETS_DIR)

    # 5. OnyxIcons
    generate_onyxicons(ASSETS_DIR)

    print("=== Tous les assets OnyxOS générés avec succès ===")

if __name__ == "__main__":
    main()
