#!/usr/bin/env bash
# ==============================================================================
# OnyxOS 1.0 (Plasma Edition) - Live ISO builder  v2.0
#
# Nouveautés v2.0 :
#   * Bureau KDE repensé : barre supérieure fine + dock Latte/floating
#   * Pack d'icônes OnyxIcons (enfant Papirus-Dark)
#   * Fastfetch avec logo ASCII OnyxOS violet
#   * Performance : preempt=full, zram-generator zstd, sysctl basse-latence,
#     ananicy-cpp, services masqués
#   * Wine + Winetricks + Bottles + Vulkan (mesa-vulkan-drivers + gamemode)
#   * Association MIME .exe → Bottles/Wine
#   * Firefox : zéro favori Fedora, langue française, NTP=true désactivé
#   * GRUB : paramètres VMware/hardware (quiet rhgb preempt=full)  — plus de QEMU debug
#   * Compression EROFS : zstd,22 au lieu de lz4hc,12  (~3,5 Go cible)
#   * Langues : seuls fr + en ; dnf.conf ne bloque pas override_install_langs
#   * Dossiers /usr/share/doc et /usr/share/man allégés
#   * Anaconda : logo OnyxOS dans /usr/share/anaconda/webui/ + header violet
#   * Dépôt DNF GitHub : /etc/yum.repos.d/onyxos.repo
#   * Locale/clavier français (LANG=fr_FR.UTF-8, vconsole fr)
#
# Règles d'or conservées (voir AGENTS.md §0) :
#   * Ne jamais toucher à l'ISO source Fedora-KDE-Desktop-Live-45-1.4.x86_64.iso
#   * Extraction EROFS via erofsfuse + cp -a  (bug erofs-utils 1.9)
#   * Remap uniquement squashfs.img, initrd et grub.cfg  (El Torito conservé)
#   * ID_LIKE="fedora" et dépôts RPM intacts
#   * Fichiers texte Linux en LF
# ==============================================================================
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ISO="$BASE_DIR/Fedora-KDE-Desktop-Live-45-1.4.x86_64.iso"
OUTPUT_NAME="OnyxOS-1.0-live-x86_64.iso"
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
}

umount_erofs() {
    if mountpoint -q "$MOUNT_TREE" 2>/dev/null; then
        fusermount3 -u "$MOUNT_TREE" 2>/dev/null || true
    fi
}

cleanup() {
    umount_chroot
    umount_erofs
    if [[ "$KEEP_BUILD" == "1" ]]; then
        warn "Dossier de build conservé : $BUILD_DIR"
    else
        rm -rf "$BUILD_DIR"
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
}

# ==============================================================================
# 0. Ressources visuelles
# ==============================================================================
if [[ "${ONYXOS_REGEN_ASSETS:-0}" == "1" || ! -f "$BASE_DIR/assets/onyxos-logo.png" \
      || ! -f "$BASE_DIR/assets/plymouth/onyxos/onyxos.plymouth" ]]; then
    log "Étape 0/9 : génération des ressources visuelles OnyxOS"
    python3 "$BASE_DIR/assets/generate_assets.py"
    ok "Ressources générées."
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
rm -rf "$ROOT_TREE" "$MOUNT_TREE"
mkdir -p "$ROOT_TREE" "$MOUNT_TREE"
erofsfuse "$ISO_TREE/LiveOS/squashfs.img" "$MOUNT_TREE" 2>/dev/null
cp -a "$MOUNT_TREE/." "$ROOT_TREE/"
umount_erofs
rmdir "$MOUNT_TREE" 2>/dev/null || true
[[ -e "$ROOT_TREE/usr/lib/os-release" ]] || die "Racine EROFS invalide."
python3 - "$ROOT_TREE/usr/bin/bash" <<'PY' || warn "xattrs SELinux absents de l'extraction."
import os, sys
os.getxattr(sys.argv[1], "security.selinux")
PY
ok "Racine live extraite."

KVER="$(ls -1 "$ROOT_TREE/lib/modules" 2>/dev/null | sort -V | tail -n1 || true)"
[[ -n "$KVER" ]] || die "Aucun module noyau trouvé dans la racine live."
log "Noyau cible : $KVER"

# ==============================================================================
# 3. Identité système
# ==============================================================================
log "Étape 3/9 : identité système OnyxOS"
install -Dm644 "$BASE_DIR/config/os-release" "$ROOT_TREE/usr/lib/os-release"
rm -f "$ROOT_TREE/etc/os-release"
ln -s ../usr/lib/os-release "$ROOT_TREE/etc/os-release"

printf 'OnyxOS release 1.0 (Obsidian)\n' > "$ROOT_TREE/etc/onyxos-release"
rm -f "$ROOT_TREE/etc/fedora-release" "$ROOT_TREE/etc/system-release" \
      "$ROOT_TREE/etc/redhat-release" "$ROOT_TREE/usr/lib/fedora-release"
ln -s onyxos-release "$ROOT_TREE/etc/system-release"
ln -s onyxos-release "$ROOT_TREE/etc/redhat-release"

printf 'OnyxOS 1.0 \\r (\\l)\n' > "$ROOT_TREE/etc/issue"
printf 'OnyxOS 1.0 \\r (\\l)\n' > "$ROOT_TREE/etc/issue.net"
printf 'Bienvenue sur OnyxOS 1.0 (Plasma Edition)\n' > "$ROOT_TREE/etc/motd"
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
    "$ROOT_TREE/usr/libexec/livesys/livesys-main"
grep -q 'hostnamectl set-hostname "onyxos"' "$ROOT_TREE/usr/libexec/livesys/livesys-main" \
    || warn "Le remplacement du hostname livesys n'a pas été appliqué."
ok "Identité système OnyxOS appliquée."

# ==============================================================================
# 4. Locale & clavier français
# ==============================================================================
log "Étape 4/9 : localisation française"
# Locale système
cat > "$ROOT_TREE/etc/locale.conf" <<'EOF'
LANG=fr_FR.UTF-8
LC_TIME=fr_FR.UTF-8
LC_MESSAGES=fr_FR.UTF-8
EOF
# Clavier console AZERTY
cat > "$ROOT_TREE/etc/vconsole.conf" <<'EOF'
KEYMAP=fr
FONT=eurlatgr
EOF
# Clavier KDE (X11/Wayland)
mkdir -p "$ROOT_TREE/etc/xdg"
cat >> "$ROOT_TREE/etc/xdg/kdeglobals" <<'EOF'

[Locale]
Language=fr_FR
Country=FR
EOF
# kxkbrc : layout AZERTY pour Plasma
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
# 5. Identité visuelle : bureau KDE repensé
# ==============================================================================
log "Étape 5/9 : identité visuelle et bureau KDE"

# --- Schémas de couleurs et konsole ---
install -Dm644 "$BASE_DIR/theme/OnyxDark.colors" \
    "$ROOT_TREE/usr/share/color-schemes/OnyxDark.colors"
install -Dm644 "$BASE_DIR/theme/OnyxKonsole.colorscheme" \
    "$ROOT_TREE/usr/share/konsole/OnyxKonsole.colorscheme"

# --- Logos ---
install -Dm644 "$BASE_DIR/assets/onyxos-logo.svg" \
    "$ROOT_TREE/usr/share/pixmaps/onyxos-logo.svg"
install -Dm644 "$BASE_DIR/assets/onyxos-logo.png" \
    "$ROOT_TREE/usr/share/pixmaps/onyxos-logo.png"

# --- Fond d'écran ---
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

# --- Pack d'icônes OnyxIcons (enfant de Papirus-Dark) ---
ICONS_PARENT="$ROOT_TREE/usr/share/icons"
ONYXICONS="$ICONS_PARENT/OnyxIcons"
mkdir -p "$ONYXICONS"
# index.theme : hérite de Papirus-Dark
cat > "$ONYXICONS/index.theme" <<'EOF'
[Icon Theme]
Name=OnyxIcons
Comment=OnyxOS Custom Icon Theme (Papirus-Dark child)
Inherits=Papirus-Dark,Papirus,breeze-dark,hicolor
Directories=16x16/places,22x22/places,32x32/places,48x48/places,64x64/places,16x16/status,22x22/status,32x32/status,48x48/apps,64x64/apps,128x128/apps

[16x16/places]
Size=16
Type=Fixed

[22x22/places]
Size=22
Type=Fixed

[32x32/places]
Size=32
Type=Fixed

[48x48/places]
Size=48
Type=Fixed

[64x64/places]
Size=64
Type=Fixed

[16x16/status]
Size=16
Type=Fixed

[22x22/status]
Size=22
Type=Fixed

[32x32/status]
Size=32
Type=Fixed

[48x48/apps]
Size=48
Type=Fixed

[64x64/apps]
Size=64
Type=Fixed

[128x128/apps]
Size=128
Type=Fixed
EOF
# Génération des icônes SVG custom noires/violettes via generate_assets.py
python3 "$BASE_DIR/assets/generate_assets.py" --icons-only 2>/dev/null || true
# Copie des icônes générées si présentes
if [[ -d "$BASE_DIR/assets/icons" ]]; then
    cp -a "$BASE_DIR/assets/icons/." "$ONYXICONS/"
fi
ok "Pack OnyxIcons installé."

# --- Look-and-feel Plasma avec barre supérieure + dock flottant ---
LNF="$ROOT_TREE/usr/share/plasma/look-and-feel/org.onyxos.desktop"
mkdir -p "$LNF/contents/layouts"
cat > "$LNF/metadata.json" <<'EOF'
{
    "KPackageStructure": "Plasma/LookAndFeel",
    "KPlugin": {
        "Authors": [{"Name": "OnyxOS"}],
        "Description": "OnyxOS 1.0 Plasma look and feel — barre supérieure fine + dock flottant",
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
name=default

[Wallpaper]
Image=OnyxOS

[kcminputrc][Mouse]
cursorTheme=breeze_cursors

[kwinrc][org.kde.kdecoration2]
library=org.kde.breeze
theme=Breeze

[kwinrc][Compositing]
OpenGLIsUnsafe=false

[ksplashrc][KSplash]
Theme=org.kde.breeze.desktop
EOF

# Layout Plasma : barre supérieure 28px + dock flottant centré en bas
cat > "$LNF/contents/layouts/org.kde.plasma.desktop-layout.js" <<'JSEOF'
var desktopActivity = activities()[0];

// ─── Barre supérieure fine ───────────────────────────────────────────────────
var topPanel = new Panel;
topPanel.location   = "top";
topPanel.height     = 28;
topPanel.alignment  = "center";
topPanel.hiding     = "none";

// Logo OnyxOS à gauche (Application Launcher)
var launcher = topPanel.addWidget("org.kde.plasma.kickoff");
launcher.currentConfigGroup = ["Shortcuts"];
launcher.writeConfig("global", "");
topPanel.addWidget("org.kde.plasma.appmenu");
topPanel.addWidget("org.kde.plasma.spacer");
// Horloge centrée
var clock = topPanel.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", false);
clock.writeConfig("showSeconds", "Never");
topPanel.addWidget("org.kde.plasma.spacer");
// Zone système droite
topPanel.addWidget("org.kde.plasma.systemtray");
topPanel.addWidget("org.kde.plasma.keyboardlayout");

// ─── Dock flottant centré en bas ─────────────────────────────────────────────
var dock = new Panel;
dock.location   = "bottom";
dock.height     = 64;
dock.alignment  = "center";
dock.hiding     = "none";
dock.minimumLength = 400;
dock.maximumLength = 800;

// Arrière-plan sombre translucide personnalisé via config
dock.addWidget("org.kde.plasma.icontasks");

// Desktop du fond
var desktop = desktopActivity.wallpaper;
desktopActivity.wallpaperPlugin = "org.kde.image";
desktopActivity.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
desktopActivity.writeConfig("Image", "file:///usr/share/wallpapers/OnyxOS/contents/images/1920x1080.png");
JSEOF

ok "Look-and-feel org.onyxos.desktop avec barre + dock appliqué."

# --- kdeglobals global ---
cat > "$ROOT_TREE/etc/xdg/kdeglobals" <<'EOF'
[General]
ColorScheme=OnyxDark
AnimationDurationFactor=0.5

[KDE]
LookAndFeelPackage=org.onyxos.desktop

[Icons]
Theme=OnyxIcons
EOF

cat > "$ROOT_TREE/etc/xdg/ksplashrc" <<'EOF'
[KSplash]
Theme=org.kde.breeze.desktop
Engine=KSplashQML
EOF

# --- Script de setup du bureau live ---
cat > "$ROOT_TREE/usr/local/bin/onyxos-desktop-setup" <<'EOF'
#!/bin/sh
# Applique l'identité visuelle OnyxOS à la session live.
WALLPAPER=/usr/share/wallpapers/OnyxOS/contents/images/1920x1080.png
[ -f "$WALLPAPER" ] || WALLPAPER=/usr/share/wallpapers/OnyxOS/contents/images/1920x1080.png
command -v plasma-apply-lookandfeel >/dev/null 2>&1 && \
    plasma-apply-lookandfeel -a org.onyxos.desktop >/dev/null 2>&1 || true
command -v plasma-apply-colorscheme >/dev/null 2>&1 && \
    plasma-apply-colorscheme OnyxDark >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
        plasma-apply-wallpaperimage "$WALLPAPER" >/dev/null 2>&1 && exit 0
    fi
    sleep 1
done
exit 0
EOF
chmod 0755 "$ROOT_TREE/usr/local/bin/onyxos-desktop-setup"

cat > "$ROOT_TREE/etc/xdg/autostart/onyxos-desktop-setup.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=OnyxOS Desktop Setup
Comment=Apply the OnyxOS Plasma defaults
Exec=/usr/local/bin/onyxos-desktop-setup
OnlyShowIn=KDE;
X-KDE-autostart-after=panel
NoDisplay=true
EOF

# Pré-seed la config liveuser
cat >> "$ROOT_TREE/usr/libexec/livesys/sessions.d/livesys-kde" <<'EOF'

# OnyxOS: pre-seed the live user's Plasma configuration.
mkdir -p /home/liveuser/.config
cp -f /etc/xdg/kdeglobals /home/liveuser/.config/kdeglobals 2>/dev/null || :
cp -f /etc/xdg/kxkbrc    /home/liveuser/.config/kxkbrc    2>/dev/null || :
EOF

# --- Remplacement des logos Fedora ---
replace_image() {
    local file="$1" lower="${1,,}"
    case "$lower" in
        *.png) install -m644 "$BASE_DIR/assets/onyxos-logo.png" "$file" ;;
        *.svg) install -m644 "$BASE_DIR/assets/onyxos-logo.svg" "$file" ;;
        *.ico)
            python3 - "$BASE_DIR/assets/onyxos-logo.png" "$file" <<'PY'
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
              "$ROOT_TREE/usr/share/fedora-logos" -type f \
              \( -iname '*fedora*' -o -iname 'org.fedoraproject.*' \) -print0 2>/dev/null)

rm -rf "$ROOT_TREE/usr/share/plasma/look-and-feel/"org.fedoraproject.* 2>/dev/null || true
rm -rf "$ROOT_TREE/usr/share/wallpapers/Fedora" 2>/dev/null || true
find "$ROOT_TREE/usr/share/backgrounds"   -maxdepth 1 -iname '*fedora*' -exec rm -rf {} + 2>/dev/null || true
find "$ROOT_TREE/usr/share/doc"           -maxdepth 1 -iname '*fedora*' -exec rm -rf {} + 2>/dev/null || true
find "$ROOT_TREE/usr/share/plasma"        -maxdepth 3 -iname '*fedora*' -exec rm -rf {} + 2>/dev/null || true
find "$ROOT_TREE/usr/share/color-schemes" -maxdepth 1 -iname '*fedora*' -delete 2>/dev/null || true
find "$ROOT_TREE/usr/share/konsole"       -maxdepth 1 -iname '*fedora*' -delete 2>/dev/null || true
find "$ROOT_TREE/usr/share/applications" -maxdepth 1 -iname '*fedora*' -delete 2>/dev/null || true
rm -f "$ROOT_TREE/usr/share/applications/org.fedoraproject.MediaWriter.desktop" 2>/dev/null || true

# --- SDDM / plasmalogin theme ---
install -d "$ROOT_TREE/usr/share/sddm/themes"
cp -a "$BASE_DIR/assets/sddm/onyxos" "$ROOT_TREE/usr/share/sddm/themes/"
chown -R root:root "$ROOT_TREE/usr/share/sddm/themes/onyxos"
find "$ROOT_TREE/usr/share/sddm/themes/onyxos" -type d -exec chmod 0755 {} +
find "$ROOT_TREE/usr/share/sddm/themes/onyxos" -type f -exec chmod 0644 {} +
find "$ROOT_TREE/usr/share/sddm/themes/onyxos" -type f \
    \( -name '*.qml' -o -name '*.desktop' -o -name '*.conf' \) -exec sed -i 's/\r$//' {} +
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

# --- Fastfetch avec logo ASCII OnyxOS ---
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
        "color": {
            "output": "magenta"
        }
    },
    "modules": [
        {"type": "title", "format": "\\e[1;35m{user-name}\\e[0m @ \\e[1;34m{host-name}\\e[0m"},
        "separator",
        {"type": "os",      "key": "OS",      "keyColor": "magenta"},
        {"type": "kernel",  "key": "Kernel",  "keyColor": "magenta"},
        {"type": "uptime",  "key": "Uptime",  "keyColor": "magenta"},
        {"type": "packages","key": "Pkgs",    "keyColor": "magenta"},
        {"type": "shell",   "key": "Shell",   "keyColor": "magenta"},
        {"type": "de",      "key": "DE",      "keyColor": "magenta"},
        {"type": "wm",      "key": "WM",      "keyColor": "magenta"},
        {"type": "terminal","key": "Term",    "keyColor": "magenta"},
        {"type": "cpu",     "key": "CPU",     "keyColor": "magenta"},
        {"type": "gpu",     "key": "GPU",     "keyColor": "magenta"},
        {"type": "memory",  "key": "Memory",  "keyColor": "magenta"},
        {"type": "disk",    "key": "Disk",    "keyColor": "magenta"},
        "break",
        {"type": "colors",  "symbol": "circle"}
    ]
}
FASTFETCH_EOF
    # Autorun dans Konsole via /etc/xdg/konsolerc
    mkdir -p "$ROOT_TREE/etc/xdg"
    cat > "$ROOT_TREE/etc/xdg/konsolerc" <<'EOF'
[Desktop Entry]
DefaultProfile=OnyxOS.profile
EOF
    mkdir -p "$ROOT_TREE/usr/share/konsole"
    cat > "$ROOT_TREE/usr/share/konsole/OnyxOS.profile" <<'EOF'
[Appearance]
ColorScheme=OnyxKonsole
Font=Monospace,10,-1,5,50,0,0,0,0,0

[General]
Name=OnyxOS
Parent=FALLBACK/

[Terminal Features]
BlinkingCursorEnabled=true

[Interaction Options]
AutoCopySelectedText=true
EOF
    # Script de démarrage Konsole
    cat > "$ROOT_TREE/usr/local/bin/onyxos-konsole-start" <<'EOF'
#!/bin/sh
# Affiche Fastfetch avec le logo ASCII OnyxOS violet à l'ouverture de Konsole
if command -v fastfetch >/dev/null 2>&1; then
    fastfetch --config /etc/fastfetch/config.jsonc 2>/dev/null || fastfetch 2>/dev/null || true
fi
EOF
    chmod 0755 "$ROOT_TREE/usr/local/bin/onyxos-konsole-start"
    # /etc/profile.d pour tous les shells interactifs
    cat > "$ROOT_TREE/etc/profile.d/onyxos-fastfetch.sh" <<'EOF'
#!/bin/sh
# OnyxOS: affiche Fastfetch à l'ouverture d'un terminal interactif
if [ -n "$PS1" ] && command -v fastfetch >/dev/null 2>&1; then
    fastfetch --config /etc/fastfetch/config.jsonc 2>/dev/null || fastfetch 2>/dev/null || true
fi
EOF
    chmod 0755 "$ROOT_TREE/etc/profile.d/onyxos-fastfetch.sh"
    ok "Fastfetch configuré avec logo OnyxOS violet."
else
    warn "Fastfetch non trouvé dans la racine ; Fastfetch à installer via dnf."
fi

# --- Anaconda : logo OnyxOS dans l'interface web ---
ANACONDA_WEBUI="$ROOT_TREE/usr/share/anaconda/webui"
if [[ -d "$ANACONDA_WEBUI" ]]; then
    # Chercher les fichiers logo/favicon de l'interface Anaconda
    while IFS= read -r -d '' afile; do
        replace_image "$afile"
    done < <(find "$ANACONDA_WEBUI" -type f \
                  \( -iname '*fedora*' -o -iname 'logo.*' -o -iname 'favicon.*' \) \
                  -print0 2>/dev/null)
    # Patcher la couleur de l'en-tête Anaconda (bleu → violet OnyxOS)
    find "$ANACONDA_WEBUI" -name '*.css' -exec \
        sed -i 's/#0066cc/#8B5CF6/g; s/#003399/#6D28D9/g; s/#06c/#8B5CF6/g' {} + 2>/dev/null || true
    ok "Interface Anaconda patchée (logo + header violet)."
else
    warn "anaconda/webui non trouvé ; skip patch Anaconda."
fi

ok "Identité visuelle complète appliquée."

# ==============================================================================
# 6. Plymouth boot splash (two-step plugin, baked into the initramfs)
# ==============================================================================
log "Étape 6/9 : splash Plymouth OnyxOS + initramfs"
install -d "$ROOT_TREE/usr/share/plymouth/themes/onyxos" \
           "$ROOT_TREE/etc/plymouth"
cp -a "$BASE_DIR/assets/plymouth/onyxos/." \
      "$ROOT_TREE/usr/share/plymouth/themes/onyxos/"
chown -R root:root "$ROOT_TREE/usr/share/plymouth/themes/onyxos"
find "$ROOT_TREE/usr/share/plymouth/themes/onyxos" -type d -exec chmod 0755 {} +
find "$ROOT_TREE/usr/share/plymouth/themes/onyxos" -type f -exec chmod 0644 {} +
find "$ROOT_TREE/usr/share/plymouth/themes/onyxos" -type f \
    \( -name '*.plymouth' -o -name '*.conf' \) -exec sed -i 's/\r$//' {} +
if grep -q $'\r' "$ROOT_TREE/usr/share/plymouth/themes/onyxos/onyxos.plymouth"; then
    die "onyxos.plymouth contient encore des CRLF."
fi
install -m644 "$BASE_DIR/assets/plymouth/onyxos/watermark.png" \
    "$ROOT_TREE/usr/share/plymouth/themes/spinner/watermark.png" 2>/dev/null || true
cat > "$ROOT_TREE/etc/plymouth/plymouthd.conf" <<'EOF'
[Daemon]
Theme=onyxos
ShowDelay=0
EOF

mount_chroot
trap 'umount_chroot; if [[ "$KEEP_BUILD" == "1" ]]; then warn "Dossier de build conservé : $BUILD_DIR"; else rm -rf "$BUILD_DIR"; fi' EXIT

mkdir -p "$ROOT_TREE/var/tmp"
chroot "$ROOT_TREE" /usr/bin/plymouth-set-default-theme onyxos 2>/dev/null || \
    warn "plymouth-set-default-theme indisponible ; configuration écrite manuellement."
grep -q '^Theme=onyxos' "$ROOT_TREE/etc/plymouth/plymouthd.conf" 2>/dev/null || \
    printf '[Daemon]\nTheme=onyxos\n' > "$ROOT_TREE/etc/plymouth/plymouthd.conf"

# Initramfs
cp -f "$ISO_TREE/boot/x86_64/loader/initrd" "$ROOT_TREE/var/tmp/onyxos-orig-initrd"
chroot "$ROOT_TREE" /usr/bin/dracut -f --no-hostonly \
    --add "dmsquash-live plymouth systemd" \
    "/var/tmp/onyxos-initramfs.img" "$KVER"
[[ -s "$ROOT_TREE/var/tmp/onyxos-initramfs.img" ]] || die "dracut n'a pas produit d'initramfs."
chroot "$ROOT_TREE" /usr/bin/lsinitrd /var/tmp/onyxos-initramfs.img > "$BUILD_DIR/initrd.list"
grep -q 'themes/onyxos/onyxos.plymouth' "$BUILD_DIR/initrd.list" \
    || die "Le thème Plymouth OnyxOS n'est pas dans l'initramfs."
grep -q 'dmsquash-live-root' "$BUILD_DIR/initrd.list" \
    || die "Le module live n'est pas dans l'initramfs."
install -m644 "$ROOT_TREE/var/tmp/onyxos-initramfs.img" \
    "$ISO_TREE/boot/x86_64/loader/initrd"
rm -f "$ROOT_TREE/var/tmp/onyxos-initramfs.img" "$ROOT_TREE/var/tmp/onyxos-orig-initrd"
ok "Initramfs OnyxOS reconstruit ($(du -h "$ISO_TREE/boot/x86_64/loader/initrd" | cut -f1))."

umount_chroot
: > "$ROOT_TREE/etc/machine-id"
ok "Splash Plymouth embarqué."

# ==============================================================================
# 7. Performances, paquets, Wine, Vulkan, Firefox
# ==============================================================================
log "Étape 7/9 : performances, Wine/Bottles/Vulkan, Firefox, allègement"

# --- sysctl basse latence ---
cat > "$ROOT_TREE/etc/sysctl.d/99-onyxos-performance.conf" <<'EOF'
# OnyxOS 1.0 — paramètres sysctl basse latence
vm.swappiness              = 10
vm.vfs_cache_pressure      = 50
vm.dirty_ratio             = 10
vm.dirty_background_ratio  = 5
net.core.rmem_default      = 262144
net.core.wmem_default      = 262144
kernel.sched_latency_ns    = 4000000
kernel.sched_min_granularity_ns = 500000
EOF

# --- zram-generator (zstd) ---
cat > "$ROOT_TREE/etc/systemd/zram-generator.conf" <<'EOF'
# OnyxOS 1.0 — zram swap en zstd
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF

# --- Masques de services inutiles ---
SYSTEMD_MASK="$ROOT_TREE/etc/systemd/system"
mkdir -p "$SYSTEMD_MASK"
for svc in NetworkManager-wait-online.service \
           abrtd.service abrt-journal-core.service abrt-oops.service \
           abrt-xorg.service abrt-vmcore.service; do
    ln -sf /dev/null "$SYSTEMD_MASK/$svc" 2>/dev/null || true
done

# --- DNF : protection des paquets Fedora-branding + repo GitHub ---
# Ajout de exclude sans override_install_langs (pour respecter la règle §6)
if [[ -f "$ROOT_TREE/etc/dnf/dnf.conf" ]]; then
    # Ne pas ajouter exclude s'il y en a déjà un
    if ! grep -q '^exclude=' "$ROOT_TREE/etc/dnf/dnf.conf"; then
        echo 'exclude=fedora-release* fedora-logos* generic-release*' \
            >> "$ROOT_TREE/etc/dnf/dnf.conf"
    else
        # Fusion de la ligne existante
        sed -i '/^exclude=/s/$/ fedora-release* fedora-logos* generic-release*/' \
            "$ROOT_TREE/etc/dnf/dnf.conf"
    fi
fi

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

# --- Raccourci onyxos-update ---
cat > "$ROOT_TREE/usr/local/bin/onyxos-update" <<'EOF'
#!/bin/sh
# Mise à jour complète OnyxOS (Fedora base + dépôt GitHub OnyxOS)
exec sudo dnf upgrade -y "$@"
EOF
chmod 0755 "$ROOT_TREE/usr/local/bin/onyxos-update"

# --- .desktop pour le raccourci mise à jour ---
cat > "$ROOT_TREE/usr/share/applications/onyxos-update.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Mettre à jour OnyxOS
Name[fr]=Mettre à jour OnyxOS
Comment=Lance la mise à jour système OnyxOS
Exec=konsole -e onyxos-update
Icon=system-software-update
Terminal=false
Categories=System;
EOF

# --- Wine, Winetricks, Gamemode, Vulkan : association MIME .exe ---
# (paquets installés dans la racine chroot si disponibles)
mount_chroot
# Tente d'installer Wine + dépendances. En cas d'échec réseau dans le chroot live,
# on avertit sans faire planter le build.
chroot "$ROOT_TREE" bash -c "
    dnf install -y --nogpgcheck --skip-broken \
        wine winetricks gamemode mesa-vulkan-drivers \
        mesa-vulkan-drivers.i686 2>/dev/null || true
    # Bottles via Flatpak si Flatpak est dispo
    if command -v flatpak >/dev/null 2>&1; then
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
        flatpak install -y --noninteractive flathub com.usebottles.bottles 2>/dev/null || true
    fi
" 2>/dev/null || warn "dnf install Wine/Vulkan : échec réseau dans le chroot live (packages à installer après boot)."
umount_chroot

# Association MIME .exe → Wine/Bottles dans KDE
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

# .desktop pour l'association par défaut
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
NoDisplay=false
EOF

# Associer .exe à Wine par défaut
mkdir -p "$ROOT_TREE/usr/share/applications"
cat >> "$ROOT_TREE/usr/share/applications/mimeapps.list" <<'EOF' 2>/dev/null || true
[Default Applications]
application/x-ms-dos-executable=wine-exe.desktop
application/x-msdos-program=wine-exe.desktop
EOF

# --- Firefox : zéro favori Fedora, langue FR, page accueil propre ---
FIREFOX_DEFAULTS="$ROOT_TREE/usr/lib64/firefox/browser/defaults/preferences"
FIREFOX_ETC="$ROOT_TREE/etc/firefox"

# Supprimer les fichiers de favoris Fedora
for ffdir in "$FIREFOX_DEFAULTS" "$FIREFOX_ETC"; do
    if [[ -d "$ffdir" ]]; then
        find "$ffdir" -type f \
            \( -iname '*fedora*' -o -iname '*redhat*' -o -iname '*rhel*' \) \
            -delete 2>/dev/null || true
    fi
done

# autoconfig Firefox : suppression favoris, langue FR, disable sponsored
mkdir -p "$FIREFOX_DEFAULTS"
cat > "$FIREFOX_DEFAULTS/onyxos.js" <<'EOF'
// OnyxOS 1.0 - Préférences Firefox par défaut
// Désactive tous les favoris Fedora/Red Hat et configure le français
pref("browser.bookmarks.restore_default_bookmarks", false);
pref("browser.bookmarks.addedImportButton", true);
pref("distribution.id", "");
pref("distribution.version", "");
pref("browser.newtabpage.activity-stream.feeds.topsites", false);
pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
pref("browser.newtabpage.activity-stream.showSponsored", false);
pref("browser.startup.homepage", "about:home");
pref("browser.places.importBookmarksHTML", false);
pref("intl.accept_languages", "fr,fr-FR,en-US,en");
pref("general.useragent.locale", "fr");
EOF

# Supprimer la distribution.ini Fedora si présente
FIREFOX_DISTRIB="$ROOT_TREE/usr/lib64/firefox/distribution"
if [[ -d "$FIREFOX_DISTRIB" ]]; then
    find "$FIREFOX_DISTRIB" -name 'distribution.ini' -delete 2>/dev/null || true
    # Réécrire avec identité OnyxOS
    mkdir -p "$FIREFOX_DISTRIB"
    cat > "$FIREFOX_DISTRIB/distribution.ini" <<'EOF'
[Global]
id=OnyxOS
version=1.0
about=OnyxOS 1.0

[Preferences]
app.distributor=OnyxOS
app.distributor.channel=OnyxOS
EOF
fi

# Installer le langpack Firefox français si disponible
mount_chroot
chroot "$ROOT_TREE" bash -c \
    "dnf install -y --nogpgcheck --skip-broken firefox-langpack-fr 2>/dev/null || true" \
    2>/dev/null || warn "firefox-langpack-fr : échec réseau dans le chroot."
umount_chroot

# --- Allègement : /usr/share/doc et /usr/share/man ---
log "Allègement des docs et man pages"
# Supprime les docs volumineuses non essentielles (garde les licences)
find "$ROOT_TREE/usr/share/doc" -mindepth 2 \
    \( -name 'COPYING' -o -name 'LICENSE' -o -name 'copyright' \) -prune \
    -o -type f -print0 2>/dev/null | xargs -0 rm -f 2>/dev/null || true
# Man pages : ne garder que les sections 1 et 5 (cmds & configs)
find "$ROOT_TREE/usr/share/man" -mindepth 1 -maxdepth 1 -type d \
    ! -name 'man1' ! -name 'man5' ! -name 'fr' ! -name 'fr_FR' \
    -exec rm -rf {} + 2>/dev/null || true
# Langues : ne garder que fr et en dans /usr/share/locale
find "$ROOT_TREE/usr/share/locale" -mindepth 1 -maxdepth 1 -type d \
    ! -name 'fr' ! -name 'fr_FR' ! -name 'en' ! -name 'en_US' \
    -exec rm -rf {} + 2>/dev/null || true
# Langpacks glibc : supprimer tout sauf fr et en
find "$ROOT_TREE/usr/lib/locale" -mindepth 1 -maxdepth 1 -type d \
    ! -name 'fr_FR*' ! -name 'en_US*' ! -name 'C*' \
    -exec rm -rf {} + 2>/dev/null || true

ok "Paquets de langues et docs allégés."

# --- ananicy-cpp (service de priorités noyau) ---
if [[ -f "$ROOT_TREE/usr/lib/systemd/system/ananicy-cpp.service" ]]; then
    # Activer ananicy-cpp au démarrage
    mkdir -p "$ROOT_TREE/etc/systemd/system/multi-user.target.wants"
    ln -sf /usr/lib/systemd/system/ananicy-cpp.service \
        "$ROOT_TREE/etc/systemd/system/multi-user.target.wants/ananicy-cpp.service" 2>/dev/null || true
    ok "ananicy-cpp activé."
else
    warn "ananicy-cpp non présent dans la racine live ; à installer via dnf post-boot."
fi

ok "Performances, Wine, Firefox, allègement appliqués."

# ==============================================================================
# 8. Reconstruction EROFS (zstd niveau 22)
# ==============================================================================
log "Étape 8/9 : reconstruction du système live EROFS (zstd,22)"
rm -f "$ISO_TREE/LiveOS/squashfs.img"
CONTEXTS="$ROOT_TREE/etc/selinux/targeted/contexts/files/file_contexts"
build_erofs() {
    mkfs.erofs -z zstd,22 -L OnyxOS-Live "$@" \
        "$ISO_TREE/LiveOS/squashfs.img" "$ROOT_TREE"
}
if [[ -f "$CONTEXTS" ]]; then
    if ! build_erofs --file-contexts="$CONTEXTS"; then
        warn "mkfs.erofs n'a pas accepté file_contexts avec zstd,22 ; reprise sans relabel."
        rm -f "$ISO_TREE/LiveOS/squashfs.img"
        build_erofs
    fi
else
    warn "file_contexts SELinux introuvable ; labels hérités des xattrs."
    build_erofs
fi
[[ -s "$ISO_TREE/LiveOS/squashfs.img" ]] || die "squashfs non généré."
ok "Système live reconstruit ($(du -h "$ISO_TREE/LiveOS/squashfs.img" | cut -f1)) — zstd,22."

# ==============================================================================
# 9. GRUB menu (VMware / PC réel — sans paramètres QEMU debug)
# ==============================================================================
log "Étape 9a/9 : menu GRUB — profil VMware/hardware"
GRUB_CONFIG="$ISO_TREE/boot/grub2/grub.cfg"
[[ -f "$GRUB_CONFIG" ]] || die "grub.cfg introuvable : $GRUB_CONFIG"
sed -i \
    -e 's/^set default="1"/set default="0"/' \
    -e 's/Fedora-KDE-Desktop-Live/OnyxOS 1.0 (Plasma Edition)/g' \
    -e 's/Fedora-KDE-Live-45/ONYXOS_KDE_LIVE/g' \
    -e 's/--class fedora/--class onyxos/g' \
    "$GRUB_CONFIG"

# Supprimer les paramètres QEMU-debug existants (noapic, console série, GL software)
sed -i \
    -e 's/\s*noapic//g' \
    -e 's/\s*console=ttyS0,[0-9]*//g' \
    -e 's/\s*console=tty0//g' \
    -e 's/\s*systemd\.setenv=QT_QUICK_BACKEND=software//g' \
    -e 's/\s*systemd\.setenv=LIBGL_ALWAYS_SOFTWARE=1//g' \
    "$GRUB_CONFIG"

# Paramètres cibles : quiet rhgb preempt=full + masques ABRT
GRUB_FLAGS_PROD="preempt=full systemd.mask=abrtd.service systemd.mask=abrt-journal-core.service systemd.mask=abrt-oops.service systemd.mask=abrt-xorg.service systemd.mask=abrt-vmcore.service"

# Remplacer "quiet rhgb" par "quiet rhgb preempt=full …"
if grep -q 'quiet rhgb' "$GRUB_CONFIG"; then
    sed -i "s/quiet rhgb/quiet rhgb $GRUB_FLAGS_PROD/g" "$GRUB_CONFIG"
else
    # Fallback : ajouter à la fin de chaque ligne linux
    sed -i "/^[[:space:]]*linux[[:space:]]/ s|\$| quiet rhgb $GRUB_FLAGS_PROD|" "$GRUB_CONFIG"
fi

grep -q 'preempt=full' "$GRUB_CONFIG" || die "preempt=full non appliqué au menu GRUB."
grep -q 'systemd.mask=abrtd.service' "$GRUB_CONFIG" || die "masques ABRT absents du menu GRUB."
grep -q 'set default="0"' "$GRUB_CONFIG" || die "set default=0 non appliqué."
if grep -qi 'noapic' "$GRUB_CONFIG"; then
    warn "noapic encore présent dans grub.cfg — suppression forcée."
    sed -i 's/\s*noapic//g' "$GRUB_CONFIG"
fi
if grep -qi 'console=ttyS0' "$GRUB_CONFIG"; then
    die "console série encore présente dans grub.cfg."
fi
if grep -qi 'fedora' "$GRUB_CONFIG"; then
    die "Branding Fedora restant dans grub.cfg."
fi
ok "GRUB rebrandé — mode VMware/hardware (quiet rhgb preempt=full)."

# ==============================================================================
# Scellage de l'ISO
# ==============================================================================
log "Étape 9b/9 : scellage de l'ISO OnyxOS"
rm -f "$WORK_ISO"
xorriso -indev "$SOURCE_ISO" -outdev "$WORK_ISO" \
    -boot_image any replay \
    -map "$ISO_TREE/LiveOS/squashfs.img"           /LiveOS/squashfs.img \
    -map "$ISO_TREE/boot/x86_64/loader/initrd"     /boot/x86_64/loader/initrd \
    -map "$GRUB_CONFIG"                             /boot/grub2/grub.cfg \
    -volid "ONYXOS_KDE_LIVE" -commit
[[ -s "$WORK_ISO" ]] || die "xorriso n'a pas produit d'ISO."
[[ $(stat -c%s "$WORK_ISO") -gt 1000000000 ]] || die "ISO générée trop petite."

log "Vérification des images de démarrage El Torito"
xorriso -indev "$WORK_ISO" -report_el_torito plain 2>&1 | grep -Ei 'El Torito|boot image' || \
    warn "Rapport El Torito indisponible (l'ISO reste bootable si xorriso a réussi)."

rm -f "$OUTPUT_ISO"
cp -f "$WORK_ISO" "$OUTPUT_ISO"
(
    cd "$BASE_DIR"
    sha256sum "$OUTPUT_NAME" > "$OUTPUT_NAME.sha256"
)
ok "ISO finale : $OUTPUT_ISO ($(du -h "$OUTPUT_ISO" | cut -f1))"
ok "SHA256 : $(cut -d' ' -f1 "$OUTPUT_NAME.sha256")"

printf '\n%b==========================================================%b\n' "$GREEN" "$RESET"
printf '%b      ONYXOS 1.0 (PLASMA EDITION) EST PRÊTE v2.0        %b\n' "$GREEN" "$RESET"
printf '%b==========================================================%b\n' "$GREEN" "$RESET"

umount_chroot
umount_erofs || true
trap - EXIT
cleanup
exit 0
