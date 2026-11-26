#!/usr/bin/env bash
# ==============================================================================
# OnyxOS 2.3 (Plasma Edition) - Live ISO builder
#
# Nouveautés v2.3 :
#   * Barre unique moderne en bas (44 px, flottante)
#   * Papirus-Dark teinté violet + logo cubique OnyxOS + Breeze noir sans bordures
#   * Fond d'écran abstrait minimaliste noir/violet + raccourcis Meta+E/V/Shift+S
#   * Wine complet 64-bit + 32-bit i686 vérifié dans le chroot + Configuration Wine
#   * Timeshift préinstallé & suppression complète logos Fedora (Plymouth/Anaconda/Cockpit)
# ==============================================================================
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ISO="$BASE_DIR/Fedora-KDE-Desktop-Live-45-1.4.x86_64.iso"
OUTPUT_NAME="OnyxOS-2.3-live-x86_64.iso"
OUTPUT_ISO="$BASE_DIR/$OUTPUT_NAME"
BUILD_DIR="${ONYXOS_BUILD_DIR:-/var/tmp/onyxos-live-build}"
ISO_TREE="$BUILD_DIR/iso"
ROOT_TREE="$BUILD_DIR/root"
MOUNT_TREE="$BUILD_DIR/mnt"
WORK_ISO="$BUILD_DIR/$OUTPUT_NAME"
KEEP_BUILD="${KEEP_BUILD:-0}"

PURPLE='\033[38;2;139;92;246m'
GREEN='\033[38;2;16;185;129m'
AMBER='\033[38;2;245;158;11m'
RED='\033[38;2;244;63;94m'
RESET='\033[0m'

log()  { printf '%b[ONYX-BUILD]%b %s\n' "$PURPLE" "$RESET" "$*"; }
ok()   { printf '%b[ONYX-OK]%b %s\n'   "$GREEN"  "$RESET" "$*"; }
warn() { printf '%b[ONYX-WARN]%b %s\n' "$AMBER"  "$RESET" "$*"; }
die()  { printf '%b[ONYX-ERR]%b %s\n'  "$RED"    "$RESET" "$*" >&2; exit 1; }

if [[ $EUID -ne 0 ]]; then
    exec sudo -E bash "$0" "$@"
fi

need() { command -v "$1" >/dev/null 2>&1 || die "Outil manquant : $1"; }
for tool in xorriso erofsfuse fusermount3 mkfs.erofs python3 chroot mountpoint; do
    need "$tool"
done
[[ -f "$SOURCE_ISO" ]] || die "ISO source introuvable : $SOURCE_ISO"

umount_chroot() {
    [[ -d "$ROOT_TREE" ]] || return 0
    local target
    for target in run dev/pts dev sys proc; do
        if mountpoint -q "$ROOT_TREE/$target" 2>/dev/null; then
            umount -l "$ROOT_TREE/$target" 2>/dev/null || true
        fi
    done
    if [[ -f "$ROOT_TREE/etc/resolv.conf.onyxlink" ]]; then
        local orig_link
        orig_link="$(cat "$ROOT_TREE/etc/resolv.conf.onyxlink")"
        rm -f "$ROOT_TREE/etc/resolv.conf" "$ROOT_TREE/etc/resolv.conf.onyxlink"
        ln -s "$orig_link" "$ROOT_TREE/etc/resolv.conf" 2>/dev/null || true
    elif [[ -f "$ROOT_TREE/etc/resolv.conf.onyxbuild" ]]; then
        mv -f "$ROOT_TREE/etc/resolv.conf.onyxbuild" "$ROOT_TREE/etc/resolv.conf" 2>/dev/null || true
    else
        rm -f "$ROOT_TREE/etc/resolv.conf"
        ln -s ../run/systemd/resolve/stub-resolv.conf "$ROOT_TREE/etc/resolv.conf" 2>/dev/null || true
    fi
}

umount_erofs() {
    if mountpoint -q "$MOUNT_TREE" 2>/dev/null; then
        umount -l "$MOUNT_TREE" 2>/dev/null || umount "$MOUNT_TREE" 2>/dev/null || fusermount3 -uz "$MOUNT_TREE" 2>/dev/null || true
    fi
    pkill -9 -f "erofsfuse" 2>/dev/null || true
}

cleanup() {
    umount_chroot || true
    umount_erofs || true
    if mountpoint -q "$MOUNT_TREE" 2>/dev/null; then
        umount -l "$MOUNT_TREE" 2>/dev/null || true
    fi
    if [[ "$KEEP_BUILD" == "1" ]]; then
        warn "Dossier de build conservé : $BUILD_DIR"
    else
        rm -rf "$BUILD_DIR" 2>/dev/null || true
    fi
}
trap cleanup EXIT

mount_chroot() {
    mkdir -p "$ROOT_TREE/proc" "$ROOT_TREE/sys" "$ROOT_TREE/dev/pts" "$ROOT_TREE/run"
    mount -t proc proc "$ROOT_TREE/proc"
    mount --bind /sys  "$ROOT_TREE/sys"
    mount --bind /dev  "$ROOT_TREE/dev"
    mount --bind /dev/pts "$ROOT_TREE/dev/pts" 2>/dev/null || true
    mount --bind /run  "$ROOT_TREE/run"  2>/dev/null || true
    if [[ -L "$ROOT_TREE/etc/resolv.conf" ]]; then
        readlink "$ROOT_TREE/etc/resolv.conf" > "$ROOT_TREE/etc/resolv.conf.onyxlink"
    elif [[ -f "$ROOT_TREE/etc/resolv.conf" && ! -f "$ROOT_TREE/etc/resolv.conf.onyxbuild" ]]; then
        cp -a "$ROOT_TREE/etc/resolv.conf" "$ROOT_TREE/etc/resolv.conf.onyxbuild" 2>/dev/null || true
    fi
    rm -f "$ROOT_TREE/etc/resolv.conf"
    if [[ -f /etc/resolv.conf ]]; then
        cp -L /etc/resolv.conf "$ROOT_TREE/etc/resolv.conf" 2>/dev/null || true
    else
        printf 'nameserver 1.1.1.1\nnameserver 9.9.9.9\n' > "$ROOT_TREE/etc/resolv.conf"
    fi
}

# ==============================================================================
# 0. Ressources visuelles v2.3
# ==============================================================================
if [[ "${ONYXOS_REGEN_ASSETS:-0}" == "1" || ! -f "$BASE_DIR/assets/onyxos-logo.png" \
      || ! -f "$BASE_DIR/assets/onyxos-logo-cube.svg" \
      || ! -f "$BASE_DIR/assets/onyxos-logo-transparent.png" ]]; then
    log "Étape 0/9 : génération des ressources visuelles v2.3 (Obsidian Matte)"
    python3 "$BASE_DIR/assets/generate_assets.py"
    ok "Ressources v2.3 générées."
else
    log "Étape 0/9 : ressources visuelles déjà présentes"
fi

# ==============================================================================
# 1. Extraction ISO + EROFS
# ==============================================================================
log "Étape 1/9 : extraction de l'ISO Fedora KDE"
rm -rf "$BUILD_DIR"
mkdir -p "$ISO_TREE"
xorriso -osirrox on -indev "$SOURCE_ISO" -extract / "$ISO_TREE" >/dev/null
[[ -f "$ISO_TREE/LiveOS/squashfs.img" ]] || die "LiveOS/squashfs.img absent de l'ISO."
ok "ISO extraite."

log "Étape 2/9 : extraction du système live EROFS (xattrs préservés)"
rm -rf "$ROOT_TREE" 2>/dev/null || true
if mountpoint -q "$MOUNT_TREE" 2>/dev/null; then
    umount -l "$MOUNT_TREE" 2>/dev/null || fusermount3 -uz "$MOUNT_TREE" 2>/dev/null || true
fi
rm -rf "$MOUNT_TREE" 2>/dev/null || true
mkdir -p "$ROOT_TREE" "$MOUNT_TREE"
erofsfuse "$ISO_TREE/LiveOS/squashfs.img" "$MOUNT_TREE" 2>/dev/null
cp -a "$MOUNT_TREE/." "$ROOT_TREE/"
umount_erofs
if mountpoint -q "$MOUNT_TREE" 2>/dev/null; then
    umount -l "$MOUNT_TREE" 2>/dev/null || true
fi
rm -rf "$MOUNT_TREE" 2>/dev/null || true
[[ -e "$ROOT_TREE/usr/lib/os-release" ]] || die "Racine EROFS invalide."
ok "Racine live extraite."

KVER="$(ls -1 "$ROOT_TREE/lib/modules" 2>/dev/null | sort -V | tail -n1 || true)"
[[ -n "$KVER" ]] || die "Aucun module noyau trouvé dans la racine live."
log "Noyau cible : $KVER"

# ==============================================================================
# 3. Identité système OnyxOS 2.3
# ==============================================================================
log "Étape 3/9 : identité système OnyxOS 2.3"
install -Dm644 "$BASE_DIR/config/os-release" "$ROOT_TREE/usr/lib/os-release"
rm -f "$ROOT_TREE/etc/os-release"
ln -s ../usr/lib/os-release "$ROOT_TREE/etc/os-release"

printf 'OnyxOS release 2.3 (Obsidian)\n' > "$ROOT_TREE/etc/onyxos-release"
rm -f "$ROOT_TREE/etc/fedora-release" "$ROOT_TREE/etc/system-release" \
      "$ROOT_TREE/etc/redhat-release" "$ROOT_TREE/usr/lib/fedora-release"
ln -s onyxos-release "$ROOT_TREE/etc/system-release"
ln -s onyxos-release "$ROOT_TREE/etc/redhat-release"

printf 'OnyxOS 2.3 \\r (\\l)\n' > "$ROOT_TREE/etc/issue"
printf 'OnyxOS 2.3 \\r (\\l)\n' > "$ROOT_TREE/etc/issue.net"
printf 'Bienvenue sur OnyxOS 2.3 (Obsidian Matte & Electric Violet)\n' > "$ROOT_TREE/etc/motd"
find "$ROOT_TREE/etc/motd.d" -type f -delete 2>/dev/null || true
printf 'onyxos\n' > "$ROOT_TREE/etc/hostname"
install -Dm644 "$BASE_DIR/config/kcm-about-distrorc" "$ROOT_TREE/etc/xdg/kcm-about-distrorc"

: > "$ROOT_TREE/etc/machine-id"
if [[ -d "$ROOT_TREE/var/lib/dbus" ]]; then
    rm -f "$ROOT_TREE/var/lib/dbus/machine-id"
    ln -s /etc/machine-id "$ROOT_TREE/var/lib/dbus/machine-id"
fi
rm -f "$ROOT_TREE"/etc/ssh/ssh_host_* 2>/dev/null || true

sed -i 's/hostnamectl set-hostname "localhost-live"/hostnamectl set-hostname "onyxos"/' \
    "$ROOT_TREE/usr/libexec/livesys/livesys-main" 2>/dev/null || true
ok "Identité système OnyxOS 2.3 appliquée."

# ==============================================================================
# 4. Locale & clavier français
# ==============================================================================
log "Étape 4/9 : localisation française"
cat > "$ROOT_TREE/etc/locale.conf" <<'EOF'
LANG=fr_FR.UTF-8
LC_TIME=fr_FR.UTF-8
LC_MESSAGES=fr_FR.UTF-8
EOF

cat > "$ROOT_TREE/etc/vconsole.conf" <<'EOF'
KEYMAP=fr
FONT=eurlatgr
EOF

mkdir -p "$ROOT_TREE/etc/xdg"
cat > "$ROOT_TREE/etc/xdg/kxkbrc" <<'EOF'
[Layout]
DisplayNames=
LayoutList=fr
Model=pc105
Options=
ResetOldOptions=false
ShowFlag=false
ShowLabel=true
ShowLayoutIndicator=true
ShowSingle=false
SwitchMode=Global
UseConfigFile=true
VariantList=
EOF
ok "Locale fr_FR.UTF-8 et clavier AZERTY configurés."

# ==============================================================================
# 5. Identité visuelle : KDE Plasma 6 "Obsidian Matte" (SANS FLOU)
# ==============================================================================
log "Étape 5/9 : bureau KDE Plasma 6 épuré (Obsidian Matte, sans flou)"

# --- Schémas de couleurs et konsole ---
install -Dm644 "$BASE_DIR/theme/OnyxDark.colors" \
    "$ROOT_TREE/usr/share/color-schemes/OnyxDark.colors"
install -Dm644 "$BASE_DIR/theme/OnyxKonsole.colorscheme" \
    "$ROOT_TREE/usr/share/konsole/OnyxKonsole.colorscheme"

# --- Logos ---
install -Dm644 "$BASE_DIR/assets/onyxos-logo-cube.svg" \
    "$ROOT_TREE/usr/share/pixmaps/onyxos-logo.svg"
install -Dm644 "$BASE_DIR/assets/onyxos-logo-transparent.png" \
    "$ROOT_TREE/usr/share/pixmaps/onyxos-logo.png"
install -Dm644 "$BASE_DIR/assets/onyxos-logo-transparent.png" \
    "$ROOT_TREE/usr/share/pixmaps/system-logo-white.png"

# --- Fond d'écran abstrait moderne ---
install -Dm644 "$BASE_DIR/assets/wallpaper-1920x1080.png" \
    "$ROOT_TREE/usr/share/wallpapers/OnyxOS/contents/images/1920x1080.png"
install -Dm644 "$BASE_DIR/assets/wallpaper-3840x2160.png" \
    "$ROOT_TREE/usr/share/wallpapers/OnyxOS/contents/images/3840x2160.png"
cat > "$ROOT_TREE/usr/share/wallpapers/OnyxOS/metadata.json" <<'EOF'
{
    "KPlugin": {
        "Authors": [{"Name": "OnyxOS"}],
        "Id": "OnyxOS",
        "Name": "OnyxOS",
        "License": "CC-BY-SA-4.0"
    }
}
EOF

# --- Thème Plasma 6 (OnyxTheme - Obsidian Matte, zéro flou) ---
if [[ -d "$BASE_DIR/assets/plasma/desktoptheme/OnyxTheme" ]]; then
    mkdir -p "$ROOT_TREE/usr/share/plasma/desktoptheme"
    cp -a "$BASE_DIR/assets/plasma/desktoptheme/OnyxTheme" "$ROOT_TREE/usr/share/plasma/desktoptheme/"
    ok "Thème de bureau OnyxTheme (Obsidian Matte) installé."
fi

# --- Pack d'icônes OnyxIcons (enfant de Papirus-Dark teinté violet, logo cubique menu Démarrer) ---
ONYXICONS="$ROOT_TREE/usr/share/icons/OnyxIcons"
rm -rf "$ONYXICONS"
mkdir -p "$ONYXICONS/scalable/places" "$ONYXICONS/48x48/places" "$ONYXICONS/64x64/places"
cat > "$ONYXICONS/index.theme" <<'EOF'
[Icon Theme]
Name=OnyxIcons
Comment=OnyxOS Modern Icon Theme (Papirus-Dark Violet child)
Inherits=Papirus-Dark,Papirus,breeze-dark,hicolor
Directories=scalable/places,48x48/places,64x64/places

[scalable/places]
Size=48
MinSize=16
MaxSize=512
Type=Scalable

[48x48/places]
Size=48
Type=Fixed

[64x64/places]
Size=64
Type=Fixed
EOF

for icon_name in start-here-kde start-here distributor-logo; do
    install -Dm644 "$BASE_DIR/assets/onyxos-logo-cube.svg" "$ONYXICONS/scalable/places/${icon_name}.svg"
    install -Dm644 "$BASE_DIR/assets/onyxos-logo-cube.svg" "$ONYXICONS/48x48/places/${icon_name}.svg"
    install -Dm644 "$BASE_DIR/assets/onyxos-logo-cube.svg" "$ONYXICONS/64x64/places/${icon_name}.svg"
done
ok "Pack OnyxIcons (Papirus-Dark Violet + logo cubique) configuré."

# --- Configuration KWin SANS FLOU & Fenêtres Breeze noires épurées ---
cat > "$ROOT_TREE/etc/xdg/kwinrc" <<'EOF'
[Plugins]
blurEnabled=false
contrastEnabled=false

[org.kde.kdecoration2]
library=org.kde.breeze
theme=Breeze
BorderSize=None
BorderSizeAuto=false

[NightColor]
Active=true
Mode=Location
LatitudeFixed=48.85
LongitudeFixed=2.35

[Compositing]
AnimationSpeed=1
GLCore=true
OpenGLIsUnsafe=false
EOF

cat > "$ROOT_TREE/etc/xdg/breezerc" <<'EOF'
[Common]
OutlineIntensity=OutlineOff

[Windeco]
DrawBackgroundGradient=false
DrawBorderOnMaximizedWindows=false
DrawSizeGrip=false
EOF

# --- Raccourcis globaux ergonomiques (Meta+E, Meta+V, Meta+Shift+S) ---
cat > "$ROOT_TREE/etc/xdg/kglobalshortcutsrc" <<'EOF'
[org.kde.dolphin.desktop]
_k_friendly_name=Dolphin
_launch=Meta+E,none,Dolphin

[org.kde.spectacle.desktop]
RectangularRegionScreenShot=Meta+Shift+S,Meta+Print,Capture Rectangular Region
_k_friendly_name=Spectacle

[plasmashell]
_k_friendly_name=Plasma
show-on-mouse-pos=Meta+V,Meta+V,Open Klipper at Mouse Position
EOF

# --- Look-and-feel Plasma avec BARRE UNIQUE MODERNE EN BAS (44px, flottante) ---
LNF="$ROOT_TREE/usr/share/plasma/look-and-feel/org.onyxos.desktop"
mkdir -p "$LNF/contents/layouts"
cat > "$LNF/metadata.json" <<'EOF'
{
    "KPackageStructure": "Plasma/LookAndFeel",
    "KPlugin": {
        "Authors": [{"Name": "OnyxOS Team"}],
        "Description": "OnyxOS 2.3 Obsidian Matte look and feel — Barre unique en bas sans flou",
        "Id": "org.onyxos.desktop",
        "License": "GPLv2+",
        "Name": "OnyxOS"
    }
}
EOF

cat > "$LNF/contents/defaults" <<'EOF'
[kdeglobals][KDE]
widgetStyle=Breeze

[kdeglobals][General]
ColorScheme=OnyxDark
AnimationDurationFactor=0.5

[kdeglobals][Icons]
Theme=OnyxIcons

[plasmarc][Theme]
name=OnyxTheme

[Wallpaper]
Image=OnyxOS

[kcminputrc][Mouse]
cursorTheme=breeze_cursors

[kwinrc][org.kde.kdecoration2]
library=org.kde.breeze
theme=Breeze
BorderSize=None
BorderSizeAuto=false

[kwinrc][Plugins]
blurEnabled=false
contrastEnabled=false

[ksplashrc][KSplash]
Theme=org.kde.breeze.desktop
EOF

cat > "$LNF/contents/layouts/org.kde.plasma.desktop-layout.js" <<'JSEOF'
var desktopActivity = activities()[0];

// ─── Barre unique moderne en bas (44px, flottante) ─────────────────────────────
var bottomPanel = new Panel;
bottomPanel.location = "bottom";
bottomPanel.height   = 44;
bottomPanel.hiding   = "none";
bottomPanel.floating = true;

// 1. Menu Démarrer OnyxOS à gauche
var launcher = bottomPanel.addWidget("org.kde.plasma.kickoff");
launcher.currentConfigGroup = ["General"];
launcher.writeConfig("icon", "start-here-kde");
launcher.currentConfigGroup = ["Shortcuts"];
launcher.writeConfig("global", "Alt+F1");

bottomPanel.addWidget("org.kde.plasma.spacer");

// 2. Applications épinglées et fenêtres ouvertes (centrées)
var tasks = bottomPanel.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:org.mozilla.firefox.desktop",
    "applications:org.kde.konsole.desktop",
    "applications:org.kde.discover.desktop",
    "applications:systemsettings.desktop"
]);

bottomPanel.addWidget("org.kde.plasma.spacer");

// 3. Zone système, disposition clavier et horloge tout à droite
bottomPanel.addWidget("org.kde.plasma.systemtray");
bottomPanel.addWidget("org.kde.plasma.keyboardlayout");

var clock = bottomPanel.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", false);
clock.writeConfig("showSeconds", "Never");

// Fond d'écran abstrait moderne
desktopActivity.wallpaperPlugin = "org.kde.image";
desktopActivity.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
desktopActivity.writeConfig("Image", "file:///usr/share/wallpapers/OnyxOS/contents/images/1920x1080.png");
JSEOF

# --- kdeglobals global ---
cat > "$ROOT_TREE/etc/xdg/kdeglobals" <<'EOF'
[General]
ColorScheme=OnyxDark
AnimationDurationFactor=0.5

[KDE]
LookAndFeelPackage=org.onyxos.desktop
widgetStyle=Breeze

[Icons]
Theme=OnyxIcons

[Locale]
Language=fr_FR
Country=FR
EOF

# --- Configuration Konsole sans flou ---
mkdir -p "$ROOT_TREE/usr/share/konsole"
cat > "$ROOT_TREE/usr/share/konsole/OnyxOS.profile" <<'EOF'
[Appearance]
ColorScheme=OnyxKonsole
Font=JetBrains Mono,11,-1,5,50,0,0,0,0,0

[General]
Name=OnyxOS
Parent=FALLBACK/

[Terminal Features]
BlinkingCursorEnabled=true

[Interaction Options]
AutoCopySelectedText=true
EOF

cat > "$ROOT_TREE/etc/xdg/konsolerc" <<'EOF'
[Desktop Entry]
DefaultProfile=OnyxOS.profile
EOF

# Fastfetch violet dans le terminal
if [[ -d "$ROOT_TREE/usr/share/fastfetch" || -f "$ROOT_TREE/usr/bin/fastfetch" ]]; then
    mkdir -p "$ROOT_TREE/etc/fastfetch"
    cat > "$ROOT_TREE/etc/fastfetch/config.jsonc" <<'FASTFETCH_EOF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": {
        "type": "small",
        "source": "onyxos",
        "color": {
            "1": "magenta",
            "2": "blue"
        }
    },
    "display": {
        "separator": " → ",
        "color": { "output": "magenta" }
    },
    "modules": [
        {"type": "title", "format": "\\e[1;35m{user-name}\\e[0m @ \\e[1;34m{host-name}\\e[0m"},
        "separator",
        {"type": "os",      "key": "OS",      "keyColor": "magenta"},
        {"type": "kernel",  "key": "Kernel",  "keyColor": "magenta"},
        {"type": "uptime",  "key": "Uptime",  "keyColor": "magenta"},
        {"type": "packages","key": "Pkgs",    "keyColor": "magenta"},
        {"type": "de",      "key": "DE",      "keyColor": "magenta"},
        {"type": "terminal","key": "Term",    "keyColor": "magenta"},
        {"type": "cpu",     "key": "CPU",     "keyColor": "magenta"},
        {"type": "gpu",     "key": "GPU",     "keyColor": "magenta"},
        {"type": "memory",  "key": "Memory",  "keyColor": "magenta"},
        "break",
        {"type": "colors",  "symbol": "circle"}
    ]
}
FASTFETCH_EOF
    cat > "$ROOT_TREE/etc/profile.d/onyxos-fastfetch.sh" <<'EOF'
#!/bin/sh
if [ -n "$PS1" ] && command -v fastfetch >/dev/null 2>&1; then
    fastfetch --config /etc/fastfetch/config.jsonc 2>/dev/null || true
fi
EOF
    chmod 0755 "$ROOT_TREE/etc/profile.d/onyxos-fastfetch.sh"
fi

# Thème SDDM
install -d "$ROOT_TREE/usr/share/sddm/themes"
cp -a "$BASE_DIR/assets/sddm/onyxos" "$ROOT_TREE/usr/share/sddm/themes/"
install -d "$ROOT_TREE/etc/sddm.conf.d"
cat > "$ROOT_TREE/etc/sddm.conf.d/onyxos.conf" <<'EOF'
[Theme]
Current=onyxos
CursorTheme=breeze_cursors

[Autologin]
User=liveuser
Session=plasmawayland
Relogin=false
EOF

# Remplacement des images Fedora par OnyxOS (système, icônes, Anaconda WebUI, Cockpit)
replace_image() {
    local file="$1" lower="${1,,}"
    case "$lower" in
        *.png) install -m644 "$BASE_DIR/assets/onyxos-logo-transparent.png" "$file" ;;
        *.svg) install -m644 "$BASE_DIR/assets/onyxos-logo-cube.svg" "$file" ;;
        *.ico)
            python3 - "$BASE_DIR/assets/onyxos-logo-transparent.png" "$file" <<'PY'
import sys
from PIL import Image
Image.open(sys.argv[1]).convert("RGBA").save(
    sys.argv[2], format="ICO",
    sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)],
)
PY
            ;;
        *.icns | *.vol) rm -f "$file" ;;
        *) ;;
    esac
}

while IFS= read -r -d '' image; do
    replace_image "$image"
done < <(find "$ROOT_TREE/usr/share/pixmaps" "$ROOT_TREE/usr/share/icons" \
              "$ROOT_TREE/usr/share/fedora-logos" \
              "$ROOT_TREE/usr/share/cockpit/branding/fedora" \
              "$ROOT_TREE/usr/share/anaconda/webui" \
              "$ROOT_TREE/usr/share/anaconda/pixmaps" -type f \
              \( -iname '*fedora*' -o -iname 'org.fedoraproject.*' -o -iname '*logo*' \) -print0 2>/dev/null)

# Remplacement explicite des logos Fedora dans Cockpit / Anaconda / Pixmaps
for target_logo in \
    "$ROOT_TREE/usr/share/cockpit/branding/fedora/logo.svg" \
    "$ROOT_TREE/usr/share/cockpit/branding/fedora/favicon.svg" \
    "$ROOT_TREE/usr/share/pixmaps/fedora-logo-small.png" \
    "$ROOT_TREE/usr/share/pixmaps/fedora-logo.png" \
    "$ROOT_TREE/usr/share/pixmaps/fedora-logo-sprite.png" \
    "$ROOT_TREE/usr/share/pixmaps/fedora-logo-sprite.svg" \
    "$ROOT_TREE/usr/share/pixmaps/system-logo-white.png"; do
    if [[ -e "$target_logo" || -d "$(dirname "$target_logo")" ]]; then
        replace_image "$target_logo"
    fi
done

rm -rf "$ROOT_TREE/usr/share/plasma/look-and-feel/"org.fedoraproject.* 2>/dev/null || true
rm -rf "$ROOT_TREE/usr/share/wallpapers/Fedora" 2>/dev/null || true
find "$ROOT_TREE/usr/share/backgrounds" -maxdepth 1 -iname '*fedora*' -exec rm -rf {} + 2>/dev/null || true
find "$ROOT_TREE/usr/share/doc" -maxdepth 1 -iname '*fedora*' -exec rm -rf {} + 2>/dev/null || true
find "$ROOT_TREE/usr/share/plasma" -maxdepth 3 -iname '*fedora*' -exec rm -rf {} + 2>/dev/null || true
find "$ROOT_TREE/usr/share/color-schemes" -maxdepth 1 -iname '*fedora*' -delete 2>/dev/null || true
find "$ROOT_TREE/usr/share/konsole" -maxdepth 1 -iname '*fedora*' -delete 2>/dev/null || true
find "$ROOT_TREE/usr/share/applications" -maxdepth 1 -iname '*fedora*' -delete 2>/dev/null || true
rm -f "$ROOT_TREE/usr/share/applications/org.fedoraproject.MediaWriter.desktop" 2>/dev/null || true

ok "Bureau KDE Plasma 6 v2.3 appliqué avec succès."

# ==============================================================================
# 6. Plymouth boot splash (démarrage + extinction sans logo Fedora)
# ==============================================================================
log "Étape 6/9 : splash Plymouth OnyxOS + initramfs"
install -d "$ROOT_TREE/usr/share/plymouth/themes/onyxos" "$ROOT_TREE/etc/plymouth"
cp -a "$BASE_DIR/assets/plymouth/onyxos/." "$ROOT_TREE/usr/share/plymouth/themes/onyxos/"
install -m644 "$BASE_DIR/assets/onyxos-logo-transparent.png" \
    "$ROOT_TREE/usr/share/plymouth/themes/onyxos/watermark.png"

for pdir in spinner bgrt; do
    if [[ -d "$ROOT_TREE/usr/share/plymouth/themes/$pdir" ]]; then
        install -m644 "$BASE_DIR/assets/onyxos-logo-transparent.png" \
            "$ROOT_TREE/usr/share/plymouth/themes/$pdir/watermark.png"
        while IFS= read -r -d '' pimg; do
            replace_image "$pimg"
        done < <(find "$ROOT_TREE/usr/share/plymouth/themes/$pdir" -type f \
            \( -iname '*fedora*' -o -iname '*logo*' -o -iname 'watermark*' \) -print0 2>/dev/null)
    fi
done
install -Dm644 "$BASE_DIR/assets/onyxos-logo-transparent.png" \
    "$ROOT_TREE/usr/share/pixmaps/system-logo-white.png"

chown -R root:root "$ROOT_TREE/usr/share/plymouth/themes/onyxos"
find "$ROOT_TREE/usr/share/plymouth/themes/onyxos" -type d -exec chmod 0755 {} +
find "$ROOT_TREE/usr/share/plymouth/themes/onyxos" -type f -exec chmod 0644 {} +
find "$ROOT_TREE/usr/share/plymouth/themes/onyxos" -type f \
    \( -name '*.plymouth' -o -name '*.conf' \) -exec sed -i 's/\r$//' {} +

cat > "$ROOT_TREE/etc/plymouth/plymouthd.conf" <<'EOF'
[Daemon]
Theme=onyxos
ShowDelay=0
EOF

mount_chroot
trap cleanup EXIT
mkdir -p "$ROOT_TREE/var/tmp"
chroot "$ROOT_TREE" /usr/bin/plymouth-set-default-theme onyxos

# Initramfs (reconstruit après le changement de thème Plymouth pour l'extinction et le démarrage)
cp -f "$ISO_TREE/boot/x86_64/loader/initrd" "$ROOT_TREE/var/tmp/onyxos-orig-initrd"
chroot "$ROOT_TREE" /usr/bin/dracut -f --no-hostonly \
    --add "dmsquash-live plymouth systemd" \
    "/var/tmp/onyxos-initramfs.img" "$KVER"
[[ -s "$ROOT_TREE/var/tmp/onyxos-initramfs.img" ]] || die "dracut n'a pas produit d'initramfs."
install -m644 "$ROOT_TREE/var/tmp/onyxos-initramfs.img" "$ISO_TREE/boot/x86_64/loader/initrd"
rm -f "$ROOT_TREE/var/tmp/onyxos-initramfs.img" "$ROOT_TREE/var/tmp/onyxos-orig-initrd"
umount_chroot
ok "Splash Plymouth embarqué (démarrage + extinction)."

# ==============================================================================
# 7. Mises à jour DNF5, Performances, RPM Fusion, Flathub, Sysctl & Sécurité
# ==============================================================================
log "Étape 7/9 : optimisations DNF5, performances, multimédia, sécurité"

# --- DNF ultra-rapide (10 téléchargements parallèles, miroir rapide, SANS EXCLUDE BLOQUANT) ---
if [[ -f "$ROOT_TREE/etc/dnf/dnf.conf" ]]; then
    # Retirer les vieux excludes
    sed -i '/^exclude=/d' "$ROOT_TREE/etc/dnf/dnf.conf" 2>/dev/null || true
    # Ajouter max_parallel_downloads et fastestmirror s'ils n'y sont pas
    grep -q 'max_parallel_downloads=' "$ROOT_TREE/etc/dnf/dnf.conf" || \
        echo 'max_parallel_downloads=10' >> "$ROOT_TREE/etc/dnf/dnf.conf"
    grep -q 'fastestmirror=' "$ROOT_TREE/etc/dnf/dnf.conf" || \
        echo 'fastestmirror=True' >> "$ROOT_TREE/etc/dnf/dnf.conf"
fi
rm -f "$ROOT_TREE/etc/dnf/conf.d/onyxos-protect.conf" 2>/dev/null || true

# --- Hook DNF5 transparent (laisse passer 100% des mises à jour Fedora) ---
mkdir -p "$ROOT_TREE/etc/dnf/libdnf5-plugins/actions.d"
cat > "$ROOT_TREE/etc/dnf/libdnf5-plugins/actions.d/onyxos-rebrand.actions" <<'EOF'
# Réapplique l'identité OnyxOS automatiquement après chaque transaction DNF5
post_trans:any:/usr/local/bin/onyxos-rebrand-hook
EOF

cat > "$ROOT_TREE/usr/local/bin/onyxos-rebrand-hook" <<'EOF'
#!/bin/sh
# Hook OnyxOS post-transaction DNF5
[ -f /usr/lib/os-release ] && sed -i \
    -e 's/^NAME=.*/NAME="OnyxOS"/' \
    -e 's/^PRETTY_NAME=.*/PRETTY_NAME="OnyxOS 2.3 (Obsidian Matte)"/' \
    -e 's/^ID=.*/ID=onyxos/' \
    -e 's/^VERSION=.*/VERSION="2.3"/' \
    -e 's/^VERSION_ID=.*/VERSION_ID="2.3"/' \
    /usr/lib/os-release 2>/dev/null || true
[ -L /etc/os-release ] || ln -sf ../usr/lib/os-release /etc/os-release 2>/dev/null || true
[ -f /etc/hostname ] || echo "onyxos" > /etc/hostname

# Réappliquer les logos OnyxOS si une mise à jour Fedora les a écrasés
if [ -f /usr/share/pixmaps/onyxos-logo.png ]; then
    cp -f /usr/share/pixmaps/onyxos-logo.png /usr/share/pixmaps/system-logo-white.png 2>/dev/null || true
    cp -f /usr/share/pixmaps/onyxos-logo.png /usr/share/pixmaps/fedora-logo.png 2>/dev/null || true
    cp -f /usr/share/pixmaps/onyxos-logo.png /usr/share/pixmaps/fedora-logo-small.png 2>/dev/null || true
    for pdir in /usr/share/plymouth/themes/spinner /usr/share/plymouth/themes/bgrt; do
        [ -d "$pdir" ] && cp -f /usr/share/pixmaps/onyxos-logo.png "$pdir/watermark.png" 2>/dev/null || true
    done
fi
if [ -f /usr/share/pixmaps/onyxos-logo.svg ]; then
    [ -d /usr/share/cockpit/branding/fedora ] && \
        cp -f /usr/share/pixmaps/onyxos-logo.svg /usr/share/cockpit/branding/fedora/logo.svg 2>/dev/null || true
    for fdir in /usr/share/anaconda/webui /usr/share/anaconda/pixmaps; do
        [ -d "$fdir" ] && find "$fdir" -type f \( -iname '*fedora*' -o -iname '*logo*' \) -name '*.svg' \
            -exec cp -f /usr/share/pixmaps/onyxos-logo.svg {} \; 2>/dev/null || true
    done
fi
exit 0
EOF
chmod 0755 "$ROOT_TREE/usr/local/bin/onyxos-rebrand-hook"

# --- Dépôt OnyxOS GitHub ---
cat > "$ROOT_TREE/etc/yum.repos.d/onyxos.repo" <<'EOF'
[onyxos]
name=OnyxOS Updates (GitHub)
baseurl=https://gael66666.github.io/Onyxos/repo-updates/
enabled=1
skip_if_unavailable=True
gpgcheck=0
priority=90
EOF

# --- Raccourci onyxos-update propre sans freeze ---
cat > "$ROOT_TREE/usr/local/bin/onyxos-update" <<'EOF'
#!/bin/sh
# Mise à jour complète OnyxOS avec rafraîchissement des miroirs
exec sudo dnf upgrade --refresh -y "$@"
EOF
chmod 0755 "$ROOT_TREE/usr/local/bin/onyxos-update"

# --- Sysctl basse latence, jeux (vm.max_map_count) & réseau BBR ---
cat > "$ROOT_TREE/etc/sysctl.d/99-onyxos-performance.conf" <<'EOF'
# OnyxOS 2.3 — Performances jeux, mémoire basse latence et BBR
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.max_map_count = 2147483642
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_default = 262144
net.core.wmem_default = 262144
kernel.sched_latency_ns = 4000000
kernel.sched_min_granularity_ns = 500000
EOF

# --- DNS rapide Cloudflare / Quad9 dans systemd-resolved ---
mkdir -p "$ROOT_TREE/etc/systemd"
cat > "$ROOT_TREE/etc/systemd/resolved.conf" <<'EOF'
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net
FallbackDNS=1.0.0.1 149.112.112.112
DNSOverTLS=opportunistic
EOF

# --- Bluetooth activé au démarrage ---
mkdir -p "$ROOT_TREE/etc/bluetooth"
cat > "$ROOT_TREE/etc/bluetooth/main.conf" <<'EOF'
[General]
Name = OnyxOS

[Policy]
AutoEnable = true
EOF

# --- zram-generator zstd ---
cat > "$ROOT_TREE/etc/systemd/zram-generator.conf" <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF

# --- Services d'optimisation ---
SYSTEMD_MASK="$ROOT_TREE/etc/systemd/system"
mkdir -p "$SYSTEMD_MASK"
for svc in NetworkManager-wait-online.service \
           abrtd.service abrt-journal-core.service abrt-oops.service \
           abrt-xorg.service abrt-vmcore.service; do
    ln -sf /dev/null "$SYSTEMD_MASK/$svc" 2>/dev/null || true
done
mkdir -p "$ROOT_TREE/etc/systemd/system/timers.target.wants"
ln -sf /usr/lib/systemd/system/fstrim.timer "$ROOT_TREE/etc/systemd/system/timers.target.wants/fstrim.timer" 2>/dev/null || true

# --- Paquets dans le chroot (RPM Fusion, codecs, Wine 32/64-bit, Papirus Violet, Timeshift) ---
mount_chroot
chroot "$ROOT_TREE" bash -c "
    set -e
    dnf install -y --nogpgcheck --skip-unavailable \
        https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-45.noarch.rpm \
        https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-45.noarch.rpm || true

    dnf install -y --nogpgcheck --allowerasing --skip-unavailable \
        ffmpeg gstreamer1-plugins-good gstreamer1-plugins-bad-free gstreamer1-plugins-ugly mesa-va-drivers \
        gamemode mesa-vulkan-drivers \
        papirus-icon-theme timeshift \
        rsms-inter-fonts google-noto-sans-fonts jetbrains-mono-fonts-all \
        ffmpegthumbs kdegraphics-thumbnailers \
        kde-connect spectacle ark p7zip p7zip-plugins unrar \
        libdnf5-plugin-actions

    # Pile Wine complète 64-bit + 32-bit i686
    dnf install -y --nogpgcheck --allowerasing --skip-unavailable \
        wine wine-core.i686 wine-mono wine-gecko winetricks \
        glibc.i686 libgcc.i686 libstdc++.i686 \
        mesa-dri-drivers.i686 mesa-vulkan-drivers.i686 \
        freetype.i686 gnutls.i686 pipewire-alsa.i686

    # Teinte violette des dossiers Papirus-Dark
    if [ -d /usr/share/icons/Papirus-Dark ]; then
        curl -fsSL https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/master/papirus-folders -o /tmp/papirus-folders
        chmod +x /tmp/papirus-folders
        /tmp/papirus-folders -C violet --theme Papirus-Dark || true
        rm -f /tmp/papirus-folders
    fi

    if command -v flatpak >/dev/null 2>&1; then
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
    fi
"

# Vérification obligatoire de Wine dans le chroot
test -x "$ROOT_TREE/usr/bin/winecfg" || die "winecfg introuvable après installation Wine."
chroot "$ROOT_TREE" wine --version || die "Échec d'exécution de wine --version dans le chroot."
ok "Wine 64-bit/32-bit vérifié avec succès."
umount_chroot

# --- Association MIME .exe & Menu Démarrer propre (Configuration Wine) ---
if [[ -f "$ROOT_TREE/usr/share/applications/wine.desktop" ]]; then
    if grep -q '^NoDisplay=' "$ROOT_TREE/usr/share/applications/wine.desktop"; then
        sed -i 's/^NoDisplay=.*/NoDisplay=true/' "$ROOT_TREE/usr/share/applications/wine.desktop"
    else
        echo 'NoDisplay=true' >> "$ROOT_TREE/usr/share/applications/wine.desktop"
    fi
fi

mkdir -p "$ROOT_TREE/usr/share/mime/packages"
cat > "$ROOT_TREE/usr/share/mime/packages/wine-exe.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
    <mime-type type="application/x-ms-dos-executable">
        <comment>Programme Windows (.exe)</comment>
        <comment xml:lang="fr">Programme Windows (.exe)</comment>
        <glob pattern="*.exe"/>
        <glob pattern="*.EXE"/>
    </mime-type>
</mime-info>
EOF

cat > "$ROOT_TREE/usr/share/applications/wine-exe.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Wine Windows Program Loader
Name[fr]=Lanceur Wine (.exe)
Comment=Run Windows programs with Wine
Comment[fr]=Lance les programmes Windows avec Wine
Exec=wine %f
Icon=wine
MimeType=application/x-ms-dos-executable;application/x-msdos-program;
Categories=System;Emulator;
NoDisplay=true
EOF

cat > "$ROOT_TREE/usr/share/applications/winecfg.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Wine Configuration
Name[fr]=Configuration Wine
Comment=Configure Wine Windows compatibility environment
Comment[fr]=Configurer l'environnement Windows Wine
Exec=winecfg
Icon=wine
Categories=System;Emulator;Settings;
NoDisplay=false
EOF

cat >> "$ROOT_TREE/usr/share/applications/mimeapps.list" <<'EOF' 2>/dev/null || true
[Default Applications]
application/x-ms-dos-executable=wine-exe.desktop
application/x-msdos-program=wine-exe.desktop
EOF

# --- Firefox : zéro télémétrie, langue FR, favoris nettoyés ---
FIREFOX_DEFAULTS="$ROOT_TREE/usr/lib64/firefox/browser/defaults/preferences"
mkdir -p "$FIREFOX_DEFAULTS"
cat > "$FIREFOX_DEFAULTS/onyxos.js" <<'EOF'
pref("browser.bookmarks.restore_default_bookmarks", false);
pref("browser.bookmarks.addedImportButton", true);
pref("distribution.id", "OnyxOS");
pref("distribution.version", "2.3");
pref("browser.newtabpage.activity-stream.feeds.topsites", false);
pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
pref("browser.newtabpage.activity-stream.showSponsored", false);
pref("browser.startup.homepage", "about:home");
pref("browser.places.importBookmarksHTML", false);
pref("intl.accept_languages", "fr,fr-FR,en-US,en");
pref("general.useragent.locale", "fr");
pref("datareporting.healthreport.uploadEnabled", false);
pref("datareporting.policy.dataSubmissionEnabled", false);
pref("toolkit.telemetry.enabled", false);
pref("toolkit.telemetry.unified", false);
pref("toolkit.telemetry.archive.enabled", false);
pref("browser.discovery.enabled", false);
EOF

# Allègement documentation non essentielle
find "$ROOT_TREE/usr/share/doc" -mindepth 2 \
    \( -name 'COPYING' -o -name 'LICENSE' -o -name 'copyright' \) -prune \
    -o -type f -delete 2>/dev/null || true
find "$ROOT_TREE/usr/share/man" -mindepth 1 -maxdepth 1 -type d \
    ! -name 'man1' ! -name 'man5' ! -name 'fr' ! -name 'fr_FR' \
    -exec rm -rf {} + 2>/dev/null || true
find "$ROOT_TREE/usr/share/locale" -mindepth 1 -maxdepth 1 -type d \
    ! -name 'fr' ! -name 'fr_FR' ! -name 'en' ! -name 'en_US' \
    -exec rm -rf {} + 2>/dev/null || true

ok "Optimisations système et multimédia appliquées."

# ==============================================================================
# 8. Reconstruction EROFS en ZSTD,15 & Libération immédiate d'espace disque
# ==============================================================================
log "Étape 8/9 : reconstruction EROFS rapide (zstd,15)"
rm -f "$ISO_TREE/LiveOS/squashfs.img"
CONTEXTS="$ROOT_TREE/etc/selinux/targeted/contexts/files/file_contexts"

build_erofs() {
    mkfs.erofs -z zstd,15 -L OnyxOS-Live "$@" \
        "$ISO_TREE/LiveOS/squashfs.img" "$ROOT_TREE"
}

if [[ -f "$CONTEXTS" ]]; then
    if ! build_erofs --file-contexts="$CONTEXTS"; then
        warn "mkfs.erofs n'a pas accepté file_contexts ; reprise sans relabel."
        rm -f "$ISO_TREE/LiveOS/squashfs.img"
        build_erofs
    fi
else
    build_erofs
fi
[[ -s "$ISO_TREE/LiveOS/squashfs.img" ]] || die "squashfs non généré."
ok "Système live reconstruit ($(du -h "$ISO_TREE/LiveOS/squashfs.img" | cut -f1)) — zstd,15."

# LIBÉRATION IMMÉDIATE DU ROOTFS POUR LE SCELLAGE ISO
log "Libération de l'espace disque : suppression du rootfs temporaire"
umount_chroot || true
umount_erofs || true
rm -rf "$ROOT_TREE"
ok "Espace disque libéré (~15 Go récupérés avant scellage ISO)."

# ==============================================================================
# 9. GRUB menu & Scellage compact de l'ISO
# ==============================================================================
log "Étape 9a/9 : menu GRUB — profil VMware/hardware"
GRUB_CONFIG="$ISO_TREE/boot/grub2/grub.cfg"
[[ -f "$GRUB_CONFIG" ]] || die "grub.cfg introuvable : $GRUB_CONFIG"

sed -i \
    -e 's/^set default="1"/set default="0"/' \
    -e 's/Fedora-KDE-Desktop-Live/OnyxOS 2.3 (Plasma Edition)/g' \
    -e 's/Fedora-KDE-Live-45/ONYXOS_KDE_LIVE/g' \
    -e 's/--class fedora/--class onyxos/g' \
    "$GRUB_CONFIG"

sed -i \
    -e 's/\s*noapic//g' \
    -e 's/\s*console=ttyS0,[0-9]*//g' \
    -e 's/\s*console=tty0//g' \
    -e 's/\s*systemd\.setenv=QT_QUICK_BACKEND=software//g' \
    -e 's/\s*systemd\.setenv=LIBGL_ALWAYS_SOFTWARE=1//g' \
    "$GRUB_CONFIG"

GRUB_FLAGS_PROD="preempt=full systemd.mask=abrtd.service systemd.mask=abrt-journal-core.service systemd.mask=abrt-oops.service systemd.mask=abrt-xorg.service systemd.mask=abrt-vmcore.service"

if grep -q 'quiet rhgb' "$GRUB_CONFIG"; then
    sed -i "s/quiet rhgb/quiet rhgb $GRUB_FLAGS_PROD/g" "$GRUB_CONFIG"
else
    sed -i "/^[[:space:]]*linux[[:space:]]/ s|\$| quiet rhgb $GRUB_FLAGS_PROD|" "$GRUB_CONFIG"
fi
ok "GRUB rebrandé (quiet rhgb preempt=full)."

log "Étape 9b/9 : scellage de l'ISO OnyxOS (image compacte ~3,5 Go)"
rm -f "$WORK_ISO"

xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "ONYXOS_KDE_LIVE" \
    --grub2-mbr --interval:local_fs:0s-15s:zero_mbrpt,zero_gpt:"$SOURCE_ISO" \
    --protective-msdos-label \
    -partition_cyl_align off \
    -partition_offset 16 \
    -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b --interval:local_fs:6859596d-6921035d::"$SOURCE_ISO" \
    -appended_part_as_gpt \
    -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
    -b boot/x86_64/loader/eltorito.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
    -eltorito-alt-boot \
    -e '--interval:appended_partition_2_start_1714899s_size_61440d:all::' \
    -no-emul-boot -boot-load-size 61440 \
    -o "$WORK_ISO" \
    "$ISO_TREE"

[[ -s "$WORK_ISO" ]] || die "xorriso n'a pas produit d'ISO."
rm -f "$OUTPUT_ISO"
cp -f "$WORK_ISO" "$OUTPUT_ISO"
chmod 0666 "$OUTPUT_ISO" 2>/dev/null || true
(
    cd "$BASE_DIR"
    sha256sum "$OUTPUT_NAME" > "$OUTPUT_NAME.sha256"
    chmod 0666 "$OUTPUT_NAME.sha256" 2>/dev/null || true
)
ok "ISO finale : $OUTPUT_ISO ($(du -h "$OUTPUT_ISO" | cut -f1))"
ok "SHA256 : $(cut -d' ' -f1 "$OUTPUT_NAME.sha256")"

printf '\n%b==========================================================%b\n' "$GREEN" "$RESET"
printf '%b      ONYXOS 2.3 (PLASMA EDITION) EST PRÊTE             %b\n' "$GREEN" "$RESET"
printf '%b==========================================================%b\n' "$GREEN" "$RESET"

umount_chroot
umount_erofs || true
trap - EXIT
cleanup
exit 0
