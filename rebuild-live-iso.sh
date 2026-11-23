#!/usr/bin/env bash
# ==============================================================================
# OnyxOS 2.1 (Plasma Edition) - Live ISO builder
#
# Nouveautés v2.1 "Obsidian Matte & Electric Violet" (sans flou) :
#   * Compression EROFS accélérée en zstd,15 (~5 min de build au lieu de 4h30)
#   * Libération immédiate du rootfs avant scellage xorriso (+15 Go libres)
#   * DNF5 ultra-rapide (max_parallel_downloads=10, fastestmirror=True)
#   * Hook DNF5 transparent (/etc/dnf/libdnf5-plugins/actions.d/onyxos-rebrand.actions)
#     laissant passer 100% des mises à jour Fedora sans conflit de branding
#   * OnyxAurorae : Décoration de fenêtres épurée sans bordures latérales
#   * OnyxTheme : Thème Plasma 6 noir profond mat (#0F0D18) net sans flou
#   * Barre supérieure flottante 28 px & dock flottant 62 px avec lanceurs épinglés
#   * Konsole noir mat (#0D0B14) sans flou, police JetBrains Mono
#   * RPM Fusion Free/Nonfree, codecs ffmpeg/gstreamer, Flathub préconfiguré
#   * KDE Connect, Spectacle, Ark+p7zip, Night Color et Bluetooth auto-activés
#   * Sysctl basse latence optimisé (vm.max_map_count=2147483642, BBR)
#   * DNS rapide Cloudflare/Quad9 dans systemd-resolved et télémétrie Firefox coupée
#
# Règles d'or conservées :
#   * Ne jamais toucher à l'ISO source Fedora-KDE-Desktop-Live-45-1.4.x86_64.iso
#   * Extraction EROFS via erofsfuse + cp -a
#   * Scellage mkisofs compact (BIOS + UEFI El Torito partition 2)
#   * Fichiers texte Linux en LF
# ==============================================================================
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ISO="$BASE_DIR/Fedora-KDE-Desktop-Live-45-1.4.x86_64.iso"
OUTPUT_NAME="OnyxOS-2.1-live-x86_64.iso"
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
    if [[ -f "$ROOT_TREE/etc/resolv.conf.onyxbuild" ]]; then
        mv -f "$ROOT_TREE/etc/resolv.conf.onyxbuild" "$ROOT_TREE/etc/resolv.conf" 2>/dev/null || true
    fi
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
    if [[ -f /etc/resolv.conf ]]; then
        if [[ ! -f "$ROOT_TREE/etc/resolv.conf.onyxbuild" ]]; then
            cp -L "$ROOT_TREE/etc/resolv.conf" "$ROOT_TREE/etc/resolv.conf.onyxbuild" 2>/dev/null || true
        fi
        cp -L /etc/resolv.conf "$ROOT_TREE/etc/resolv.conf" 2>/dev/null || true
    fi
}

# ==============================================================================
# 0. Ressources visuelles v2.1
# ==============================================================================
if [[ "${ONYXOS_REGEN_ASSETS:-0}" == "1" || ! -f "$BASE_DIR/assets/onyxos-logo.png" \
      || ! -f "$BASE_DIR/assets/aurorae/OnyxAurorae/themerc" ]]; then
    log "Étape 0/9 : génération des ressources visuelles v2.1 (Obsidian Matte, sans flou)"
    python3 "$BASE_DIR/assets/generate_assets.py"
    ok "Ressources v2.1 générées."
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
ok "Racine live extraite."

KVER="$(ls -1 "$ROOT_TREE/lib/modules" 2>/dev/null | sort -V | tail -n1 || true)"
[[ -n "$KVER" ]] || die "Aucun module noyau trouvé dans la racine live."
log "Noyau cible : $KVER"

# ==============================================================================
# 3. Identité système OnyxOS 2.1
# ==============================================================================
log "Étape 3/9 : identité système OnyxOS 2.1"
install -Dm644 "$BASE_DIR/config/os-release" "$ROOT_TREE/usr/lib/os-release"
rm -f "$ROOT_TREE/etc/os-release"
ln -s ../usr/lib/os-release "$ROOT_TREE/etc/os-release"

printf 'OnyxOS release 2.1 (Obsidian)\n' > "$ROOT_TREE/etc/onyxos-release"
rm -f "$ROOT_TREE/etc/fedora-release" "$ROOT_TREE/etc/system-release" \
      "$ROOT_TREE/etc/redhat-release" "$ROOT_TREE/usr/lib/fedora-release"
ln -s onyxos-release "$ROOT_TREE/etc/system-release"
ln -s onyxos-release "$ROOT_TREE/etc/redhat-release"

printf 'OnyxOS 2.1 \\r (\\l)\n' > "$ROOT_TREE/etc/issue"
printf 'OnyxOS 2.1 \\r (\\l)\n' > "$ROOT_TREE/etc/issue.net"
printf 'Bienvenue sur OnyxOS 2.1 (Obsidian Matte & Electric Violet)\n' > "$ROOT_TREE/etc/motd"
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
ok "Identité système OnyxOS 2.1 appliquée."

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
install -Dm644 "$BASE_DIR/assets/onyxos-logo.svg" \
    "$ROOT_TREE/usr/share/pixmaps/onyxos-logo.svg"
install -Dm644 "$BASE_DIR/assets/onyxos-logo.png" \
    "$ROOT_TREE/usr/share/pixmaps/onyxos-logo.png"

# --- Fond d'écran net ---
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

# --- Thème de fenêtres Aurorae (OnyxAurorae sans bordures latérales) ---
if [[ -d "$BASE_DIR/assets/aurorae/OnyxAurorae" ]]; then
    mkdir -p "$ROOT_TREE/usr/share/aurorae/themes"
    cp -a "$BASE_DIR/assets/aurorae/OnyxAurorae" "$ROOT_TREE/usr/share/aurorae/themes/"
    ok "Thème de fenêtres OnyxAurorae installé."
fi

# --- Thème Plasma 6 (OnyxTheme - Obsidian Matte, zéro flou) ---
if [[ -d "$BASE_DIR/assets/plasma/desktoptheme/OnyxTheme" ]]; then
    mkdir -p "$ROOT_TREE/usr/share/plasma/desktoptheme"
    cp -a "$BASE_DIR/assets/plasma/desktoptheme/OnyxTheme" "$ROOT_TREE/usr/share/plasma/desktoptheme/"
    ok "Thème de bureau OnyxTheme (Obsidian Matte) installé."
fi

# --- Pack d'icônes OnyxIcons (enfant de Papirus-Dark) ---
ONYXICONS="$ROOT_TREE/usr/share/icons/OnyxIcons"
mkdir -p "$ONYXICONS"
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

if [[ -d "$BASE_DIR/assets/icons" ]]; then
    cp -a "$BASE_DIR/assets/icons/." "$ONYXICONS/"
fi
ok "Pack OnyxIcons installé."

# --- Configuration KWin SANS FLOU & Night Color ---
cat > "$ROOT_TREE/etc/xdg/kwinrc" <<'EOF'
[Plugins]
blurEnabled=false
contrastEnabled=false

[org.kde.kdecoration2]
library=org.kde.kwin.aurorae
theme=OnyxAurorae
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

# --- Look-and-feel Plasma avec barre 28px + dock 62px FLOTTANTS ---
LNF="$ROOT_TREE/usr/share/plasma/look-and-feel/org.onyxos.desktop"
mkdir -p "$LNF/contents/layouts"
cat > "$LNF/metadata.json" <<'EOF'
{
    "KPackageStructure": "Plasma/LookAndFeel",
    "KPlugin": {
        "Authors": [{"Name": "OnyxOS Team"}],
        "Description": "OnyxOS 2.1 Obsidian Matte look and feel — Barre et dock flottants sans flou",
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
library=org.kde.kwin.aurorae
theme=OnyxAurorae
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

// ─── Barre supérieure fine 28px flottante ─────────────────────────────────────
var topPanel = new Panel;
topPanel.location   = "top";
topPanel.height     = 28;
topPanel.alignment  = "center";
topPanel.hiding     = "none";
topPanel.floating   = true;

var launcher = topPanel.addWidget("org.kde.plasma.kickoff");
launcher.currentConfigGroup = ["Shortcuts"];
launcher.writeConfig("global", "");
topPanel.addWidget("org.kde.plasma.appmenu");
topPanel.addWidget("org.kde.plasma.spacer");
var clock = topPanel.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", false);
clock.writeConfig("showSeconds", "Never");
topPanel.addWidget("org.kde.plasma.spacer");
topPanel.addWidget("org.kde.plasma.systemtray");
topPanel.addWidget("org.kde.plasma.keyboardlayout");

// ─── Dock centré flottant 62px avec icônes épinglées ──────────────────────────
var dock = new Panel;
dock.location   = "bottom";
dock.height     = 62;
dock.alignment  = "center";
dock.hiding     = "none";
dock.floating   = true;
dock.minimumLength = 420;
dock.maximumLength = 850;

var tasks = dock.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:org.mozilla.firefox.desktop",
    "applications:org.kde.konsole.desktop",
    "applications:org.kde.discover.desktop",
    "applications:systemsettings.desktop"
]);

// Fond d'écran net
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

# Remplacement des images Fedora par OnyxOS
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
find "$ROOT_TREE/usr/share/backgrounds" -maxdepth 1 -iname '*fedora*' -exec rm -rf {} + 2>/dev/null || true
find "$ROOT_TREE/usr/share/doc" -maxdepth 1 -iname '*fedora*' -exec rm -rf {} + 2>/dev/null || true
find "$ROOT_TREE/usr/share/plasma" -maxdepth 3 -iname '*fedora*' -exec rm -rf {} + 2>/dev/null || true
find "$ROOT_TREE/usr/share/color-schemes" -maxdepth 1 -iname '*fedora*' -delete 2>/dev/null || true
find "$ROOT_TREE/usr/share/konsole" -maxdepth 1 -iname '*fedora*' -delete 2>/dev/null || true
find "$ROOT_TREE/usr/share/applications" -maxdepth 1 -iname '*fedora*' -delete 2>/dev/null || true
rm -f "$ROOT_TREE/usr/share/applications/org.fedoraproject.MediaWriter.desktop" 2>/dev/null || true

ok "Bureau KDE Plasma 6 v2.1 appliqué avec succès."

# ==============================================================================
# 6. Plymouth boot splash
# ==============================================================================
log "Étape 6/9 : splash Plymouth OnyxOS + initramfs"
install -d "$ROOT_TREE/usr/share/plymouth/themes/onyxos" "$ROOT_TREE/etc/plymouth"
cp -a "$BASE_DIR/assets/plymouth/onyxos/." "$ROOT_TREE/usr/share/plymouth/themes/onyxos/"
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
chroot "$ROOT_TREE" /usr/bin/plymouth-set-default-theme onyxos 2>/dev/null || true

# Initramfs
cp -f "$ISO_TREE/boot/x86_64/loader/initrd" "$ROOT_TREE/var/tmp/onyxos-orig-initrd"
chroot "$ROOT_TREE" /usr/bin/dracut -f --no-hostonly \
    --add "dmsquash-live plymouth systemd" \
    "/var/tmp/onyxos-initramfs.img" "$KVER"
[[ -s "$ROOT_TREE/var/tmp/onyxos-initramfs.img" ]] || die "dracut n'a pas produit d'initramfs."
install -m644 "$ROOT_TREE/var/tmp/onyxos-initramfs.img" "$ISO_TREE/boot/x86_64/loader/initrd"
rm -f "$ROOT_TREE/var/tmp/onyxos-initramfs.img" "$ROOT_TREE/var/tmp/onyxos-orig-initrd"
umount_chroot
ok "Splash Plymouth embarqué."

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
    -e 's/^PRETTY_NAME=.*/PRETTY_NAME="OnyxOS 2.1 (Obsidian Matte)"/' \
    -e 's/^ID=.*/ID=onyxos/' \
    -e 's/^VERSION=.*/VERSION="2.1"/' \
    -e 's/^VERSION_ID=.*/VERSION_ID="2.1"/' \
    /usr/lib/os-release 2>/dev/null || true
[ -L /etc/os-release ] || ln -sf ../usr/lib/os-release /etc/os-release 2>/dev/null || true
[ -f /etc/hostname ] || echo "onyxos" > /etc/hostname
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
# OnyxOS 2.1 — Performances jeux, mémoire basse latence et BBR
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

# --- Paquets dans le chroot (RPM Fusion, codecs, outils, polices) ---
mount_chroot
chroot "$ROOT_TREE" bash -c "
    dnf install -y --nogpgcheck --skip-broken \
        https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-45.noarch.rpm \
        https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-45.noarch.rpm 2>/dev/null || true

    dnf install -y --nogpgcheck --skip-broken \
        ffmpeg gstreamer1-plugins-good gstreamer1-plugins-bad-free gstreamer1-plugins-ugly mesa-va-drivers \
        wine winetricks gamemode mesa-vulkan-drivers \
        inter-fonts google-noto-sans-fonts jetbrains-mono-fonts-all \
        ffmpegthumbs kdegraphics-thumbnailers \
        kde-connect spectacle ark p7zip p7zip-plugins unrar \
        libdnf5-plugin-actions 2>/dev/null || true

    if command -v flatpak >/dev/null 2>&1; then
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    fi
" 2>/dev/null || warn "Téléchargement de certains paquets en ligne ignoré dans l'environnement de build."
umount_chroot

# --- Association MIME .exe pour Wine ---
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
pref("distribution.version", "2.1");
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
    -e 's/Fedora-KDE-Desktop-Live/OnyxOS 2.1 (Plasma Edition)/g' \
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
printf '%b      ONYXOS 2.1 (PLASMA EDITION) EST PRÊTE             %b\n' "$GREEN" "$RESET"
printf '%b==========================================================%b\n' "$GREEN" "$RESET"

umount_chroot
umount_erofs || true
trap - EXIT
cleanup
exit 0
