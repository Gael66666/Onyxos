#!/usr/bin/env python3
"""
OnyxOS Asset Generator
Generates branding assets, wallpapers, Plymouth splash theme, SDDM theme, and icons
Palette:
- #0B0A10 (Deep Black / Noir profond)
- #151320 (Anthracite)
- #8B5CF6 (Electric Violet / Violet électrique)
- #A855F7 (Vivid Purple)
- #C084FC (Light Violet Accent)
- #EDE9FE (Lavender White Text)
"""

import os
import sys
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUTPUT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = OUTPUT_DIR.parent
ASSETS_DIR = OUTPUT_DIR
THEME_DIR = PROJECT_DIR / "theme"

COLOR_DEEP_BLACK = (11, 10, 16)      # #0B0A10
COLOR_ANTHRACITE = (21, 19, 32)      # #151320
COLOR_SURFACE    = (30, 27, 46)      # #1E1B2E
COLOR_VIOLET_1   = (139, 92, 246)    # #8B5CF6
COLOR_VIOLET_2   = (168, 85, 247)    # #A855F7
COLOR_VIOLET_3   = (192, 132, 252)   # #C084FC
COLOR_TEXT_LIGHT = (237, 233, 254)   # #EDE9FE
COLOR_GLOW       = (139, 92, 246, 60)

def create_svg_logo(output_path: Path):
    """Generates a high-quality SVG vector logo for OnyxOS."""
    svg_content = """<?xml version="1.0" encoding="UTF-8"?>
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

  <!-- Background Shield/Rounded Hexagon -->
  <rect width="512" height="512" rx="100" fill="url(#bgGlow)"/>
  <rect width="504" height="504" x="4" y="4" rx="96" fill="none" stroke="#8B5CF6" stroke-width="2" stroke-opacity="0.4"/>

  <!-- Onyx Gemstone Geometric Polygons (Faceted Hexagonal Crystal) -->
  <g filter="url(#glow)">
    <!-- Outer Glow Silhouette -->
    <polygon points="256,60 410,150 410,330 256,420 102,330 102,150"
             fill="none" stroke="#A855F7" stroke-width="6" stroke-linejoin="round"/>

    <!-- Facet 1: Top Upper Left -->
    <polygon points="256,60 256,240 102,150" fill="url(#purpleGrad1)" fill-opacity="0.9"/>

    <!-- Facet 2: Top Upper Right -->
    <polygon points="256,60 410,150 256,240" fill="url(#purpleGrad2)" fill-opacity="0.8"/>

    <!-- Facet 3: Lower Left -->
    <polygon points="102,150 256,240 102,330" fill="#3B186B" fill-opacity="0.95"/>

    <!-- Facet 4: Bottom Left -->
    <polygon points="102,330 256,240 256,420" fill="url(#purpleGrad1)" fill-opacity="0.75"/>

    <!-- Facet 5: Bottom Right -->
    <polygon points="256,420 256,240 410,330" fill="#2E1065" fill-opacity="0.9"/>

    <!-- Facet 6: Lower Right -->
    <polygon points="410,330 256,240 410,150" fill="url(#purpleGrad2)" fill-opacity="0.85"/>

    <!-- Center Gem Facet Highlight -->
    <polygon points="256,120 330,195 330,285 256,360 182,285 182,195"
             fill="none" stroke="url(#facetHighlight)" stroke-width="4"/>

    <!-- Core Radiant Star -->
    <circle cx="256" cy="240" r="14" fill="#EDE9FE"/>
  </g>

  <!-- Typography: ONYXOS -->
  <text x="256" y="475" text-anchor="middle"
        font-family="system-ui, -apple-system, sans-serif" font-weight="800" font-size="34"
        fill="#EDE9FE" letter-spacing="8">ONYXOS</text>
</svg>
"""
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(svg_content)
    print(f"[OK] Generated SVG logo: {output_path}")

def render_gemstone(draw, cx, cy, radius, glow=True):
    """Draws an intricate geometric faceted onyx crystal onto PIL draw context."""
    points = []
    for i in range(6):
        angle = math.radians(60 * i - 30)
        px = cx + radius * math.cos(angle)
        py = cy + radius * math.sin(angle)
        points.append((px, py))

    # Inner facets
    inner_points = []
    inner_rad = radius * 0.55
    for i in range(6):
        angle = math.radians(60 * i - 30)
        px = cx + inner_rad * math.cos(angle)
        py = cy + inner_rad * math.sin(angle)
        inner_points.append((px, py))

    # Facet coloring
    facet_colors = [
        (139, 92, 246, 220), # Violet 1
        (168, 85, 247, 200), # Violet 2
        (76, 29, 149, 230),  # Deep violet
        (91, 33, 182, 230),  # Dark purple
        (124, 58, 237, 210), # Medium violet
        (192, 132, 252, 220),# Light violet
    ]

    for i in range(6):
        p1 = points[i]
        p2 = points[(i + 1) % 6]
        c = (cx, cy)
        draw.polygon([p1, p2, c], fill=facet_colors[i][:3])

    # Inner facet overlay
    for i in range(6):
        p1 = inner_points[i]
        p2 = inner_points[(i + 1) % 6]
        draw.line([p1, p2], fill=COLOR_VIOLET_3, width=2)
        draw.line([points[i], inner_points[i]], fill=COLOR_TEXT_LIGHT, width=2)

    # Outer border
    for i in range(6):
        draw.line([points[i], points[(i + 1) % 6]], fill=COLOR_VIOLET_2, width=3)

    # Core spark
    draw.ellipse([cx - 8, cy - 8, cx + 8, cy + 8], fill=COLOR_TEXT_LIGHT)

def generate_logo_png(output_path: Path, size=512):
    """Generates PNG logo with deep black background and electric violet emblem."""
    img = Image.new("RGBA", (size, size), COLOR_DEEP_BLACK + (255,))
    draw = ImageDraw.Draw(img)

    # Subtle background gradient circle
    glow_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_img)
    glow_draw.ellipse([size * 0.15, size * 0.15, size * 0.85, size * 0.85], fill=(139, 92, 246, 35))
    glow_img = glow_img.filter(ImageFilter.GaussianBlur(30))
    img = Image.alpha_composite(img, glow_img)

    draw = ImageDraw.Draw(img)
    # Border
    draw.rounded_rectangle([8, 8, size - 8, size - 8], radius=size // 6, outline=COLOR_VIOLET_1, width=3)

    # Draw Gemstone in center
    render_gemstone(draw, size // 2, int(size * 0.44), int(size * 0.28))

    # Sub-branding line
    sub_y = int(size * 0.80)
    draw.line([size * 0.25, sub_y, size * 0.75, sub_y], fill=COLOR_VIOLET_1, width=2)

    # Save
    img.save(output_path, "PNG")
    print(f"[OK] Generated PNG logo: {output_path}")

def generate_wallpaper(output_path: Path, width=1920, height=1080):
    """Generates an ultra-clean, modern geometric dark/purple wallpaper."""
    print(f"[*] Rendering wallpaper ({width}x{height})...")
    img = Image.new("RGB", (width, height), COLOR_DEEP_BLACK)
    draw = ImageDraw.Draw(img)

    # Layer 1: Abstract polygonal facets with #151320
    polygons = [
        [(0, 0), (int(width * 0.35), 0), (int(width * 0.2), int(height * 0.45)), (0, int(height * 0.3))],
        [(int(width * 0.35), 0), (width, 0), (int(width * 0.8), int(height * 0.5)), (int(width * 0.5), int(height * 0.2))],
        [(width, int(height * 0.3)), (width, height), (int(width * 0.65), height), (int(width * 0.7), int(height * 0.6))],
        [(0, int(height * 0.5)), (int(width * 0.25), int(height * 0.6)), (int(width * 0.15), height), (0, height)],
        [(int(width * 0.2), height), (int(width * 0.7), height), (int(width * 0.5), int(height * 0.75))]
    ]
    for poly in polygons:
        draw.polygon(poly, fill=COLOR_ANTHRACITE)

    # Layer 2: Glowing electric purple subtle mesh lines
    for poly in polygons:
        for i in range(len(poly)):
            p1 = poly[i]
            p2 = poly[(i + 1) % len(poly)]
            draw.line([p1, p2], fill=COLOR_SURFACE, width=2)

    # Central ambient glow
    ambient = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    ambient_draw = ImageDraw.Draw(ambient)
    cx, cy = width // 2, height // 2
    glow_radius = int(min(width, height) * 0.4)
    ambient_draw.ellipse([cx - glow_radius, cy - glow_radius, cx + glow_radius, cy + glow_radius],
                         fill=(139, 92, 246, 25))
    ambient = ambient.filter(ImageFilter.GaussianBlur(60))
    img.paste(ambient, (0, 0), ambient)

    # Central Onyx Gemstone
    draw = ImageDraw.Draw(img)
    gem_radius = int(min(width, height) * 0.12)
    render_gemstone(draw, cx, cy - 20, gem_radius)

    img.save(output_path, "PNG", optimize=True)
    print(f"[OK] Generated Wallpaper: {output_path}")

def generate_plymouth_theme(output_dir: Path):
    """Generates Plymouth boot theme configuration and splash assets."""
    plymouth_dir = output_dir / "plymouth" / "onyxos"
    plymouth_dir.mkdir(parents=True, exist_ok=True)

    # Plymouth config
    plymouth_conf = """[Plymouth Theme]
Name=OnyxOS Dark Purple
Description=OnyxOS 1.0 Boot Splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/onyxos
ScriptFile=/usr/share/plymouth/themes/onyxos/onyxos.script
"""
    with open(plymouth_dir / "onyxos.plymouth", "w", encoding="utf-8") as f:
        f.write(plymouth_conf)

    # Plymouth script
    plymouth_script = """# OnyxOS Plymouth Theme Script
Window.SetBackgroundTopColor(0.043, 0.039, 0.063); # #0B0A10
Window.SetBackgroundBottomColor(0.082, 0.075, 0.125); # #151320

logo.image = Image("splash-logo.png");
logo.sprite = Sprite(logo.image);
logo.opacity = 1.0;

logo.x = Window.GetX() + Window.GetWidth() / 2 - logo.image.GetWidth() / 2;
logo.y = Window.GetY() + Window.GetHeight() / 2 - logo.image.GetHeight() / 2;
logo.sprite.SetPosition(logo.x, logo.y, 10);

progress = 0;
fun refresh_callback () {
    progress++;
}
Plymouth.SetRefreshFunction(refresh_callback);
"""
    with open(plymouth_dir / "onyxos.script", "w", encoding="utf-8") as f:
        f.write(plymouth_script)

    # Generate splash logo (256x256)
    generate_logo_png(plymouth_dir / "splash-logo.png", size=256)
    print(f"[OK] Generated Plymouth theme in: {plymouth_dir}")

def generate_sddm_theme(output_dir: Path):
    """Generates SDDM login greeter theme for OnyxOS."""
    sddm_dir = output_dir / "sddm" / "onyxos"
    sddm_dir.mkdir(parents=True, exist_ok=True)

    metadata = """[SddmGreeterTheme]
Name=OnyxOS
Description=OnyxOS 1.0 KDE Plasma Login Greeter
Author=OnyxOS Team
Theme-Id=onyxos
Theme-API=2.0
Website=https://onyxos.internal
License=GPL
Type=sddm-theme
ConfigFile=theme.conf
MainScript=Main.qml
"""
    with open(sddm_dir / "metadata.desktop", "w", encoding="utf-8") as f:
        f.write(metadata)

    theme_conf = """[General]
background=sddm-background.png
type=image
color=#0B0A10
fontSize=10
font=Noto Sans
headerColor=#8B5CF6
accentColor=#A855F7
"""
    with open(sddm_dir / "theme.conf", "w", encoding="utf-8") as f:
        f.write(theme_conf)

    # SDDM Background
    generate_wallpaper(sddm_dir / "sddm-background.png", width=1920, height=1080)
    print(f"[OK] Generated SDDM theme in: {sddm_dir}")

def main():
    print("=== OnyxOS Asset Pipeline Starting ===")
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Logos
    svg_logo = ASSETS_DIR / "onyxos-logo.svg"
    png_logo = ASSETS_DIR / "onyxos-logo.png"
    create_svg_logo(svg_logo)
    generate_logo_png(png_logo, size=512)

    # 2. Wallpapers
    generate_wallpaper(ASSETS_DIR / "wallpaper-1920x1080.png", 1920, 1080)
    generate_wallpaper(ASSETS_DIR / "wallpaper-3840x2160.png", 3840, 2160)

    # 3. Themes
    generate_plymouth_theme(ASSETS_DIR)
    generate_sddm_theme(ASSETS_DIR)

    print("=== All OnyxOS Assets Generated Successfully ===")

if __name__ == "__main__":
    main()
