#!/usr/bin/env bash
# Rebuild a Fedora KDE live ISO as OnyxOS without binary patching.
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ISO="${BASE_DIR}/Fedora-KDE-Desktop-Live-45-1.4.x86_64.iso"
OUTPUT_ISO="${BASE_DIR}/OnyxOS-1.0-live-x86_64.iso"
BUILD_DIR="/var/tmp/onyxos-live-build"
ISO_TREE="${BUILD_DIR}/iso"
ROOT_TREE="${BUILD_DIR}/root"
MOUNT_TREE="${BUILD_DIR}/mount"

need() { command -v "$1" >/dev/null || { echo "Outil manquant : $1" >&2; exit 1; }; }
for tool in xorriso erofsfuse fusermount3 mkfs.erofs python3; do need "$tool"; done
[[ -f "$SOURCE_ISO" ]] || { echo "ISO Fedora introuvable : $SOURCE_ISO" >&2; exit 1; }

cleanup() {
  if mountpoint -q "$MOUNT_TREE"; then fusermount3 -u "$MOUNT_TREE" || true; fi
  rm -rf "$BUILD_DIR"
}
trap cleanup EXIT
cleanup
mkdir -p "$ISO_TREE" "$ROOT_TREE" "$MOUNT_TREE"

echo "[1/6] Génération des ressources visuelles OnyxOS"
python3 "${BASE_DIR}/assets/generate_assets.py"

echo "[2/6] Extraction de l'ISO Fedora"
xorriso -osirrox on -indev "$SOURCE_ISO" -extract / "$ISO_TREE" >/dev/null

echo "[3/6] Extraction du système live EROFS"
erofsfuse "$ISO_TREE/LiveOS/squashfs.img" "$MOUNT_TREE" >/dev/null
cp -a "$MOUNT_TREE/." "$ROOT_TREE/"
fusermount3 -u "$MOUNT_TREE"

echo "[4/6] Application de l'identité OnyxOS"
install -Dm644 "${BASE_DIR}/config/os-release" "$ROOT_TREE/etc/os-release"
printf 'OnyxOS release 1.0 (Obsidian)\n' > "$ROOT_TREE/etc/system-release"
printf 'OnyxOS \\r (\\l)\n' > "$ROOT_TREE/etc/issue"
printf 'OnyxOS \\r (\\l)\n' > "$ROOT_TREE/etc/issue.net"
printf 'onyxos\n' > "$ROOT_TREE/etc/hostname"
install -Dm644 "${BASE_DIR}/config/kcm-about-distrorc" "$ROOT_TREE/etc/xdg/kcm-about-distrorc"
install -Dm644 "${BASE_DIR}/theme/OnyxDark.colors" "$ROOT_TREE/usr/share/color-schemes/OnyxDark.colors"
install -Dm644 "${BASE_DIR}/theme/OnyxKonsole.colorscheme" "$ROOT_TREE/usr/share/konsole/OnyxKonsole.colorscheme"
install -Dm644 "${BASE_DIR}/assets/onyxos-logo.svg" "$ROOT_TREE/usr/share/pixmaps/onyxos-logo.svg"
install -Dm644 "${BASE_DIR}/assets/onyxos-logo.png" "$ROOT_TREE/usr/share/pixmaps/onyxos-logo.png"
install -Dm644 "${BASE_DIR}/assets/wallpaper-1920x1080.png" "$ROOT_TREE/usr/share/wallpapers/OnyxOS/wallpaper-1920x1080.png"
install -d "$ROOT_TREE/usr/share/plymouth/themes" "$ROOT_TREE/usr/share/sddm/themes"
cp -a "${BASE_DIR}/assets/plymouth/onyxos" "$ROOT_TREE/usr/share/plymouth/themes/"
cp -a "${BASE_DIR}/assets/sddm/onyxos" "$ROOT_TREE/usr/share/sddm/themes/"

cat > "$ROOT_TREE/etc/xdg/kdeglobals" <<'EOF'
[General]
ColorScheme=OnyxDark
Name=Onyx Dark
[KDE]
contrast=7
[Colors:Window]
BackgroundNormal=11,10,16
BackgroundAlternate=21,19,32
ForegroundNormal=237,233,254
ForegroundActive=168,85,247
[Colors:Selection]
BackgroundNormal=139,92,246
ForegroundNormal=255,255,255
EOF
mkdir -p "$ROOT_TREE/etc/sddm.conf.d"
cat > "$ROOT_TREE/etc/sddm.conf.d/onyxos.conf" <<'EOF'
[Theme]
Current=onyxos
[Autologin]
User=liveuser
Session=plasmawayland
Relogin=false
EOF
mkdir -p "$ROOT_TREE/etc/xdg/autostart"
cat > "$ROOT_TREE/etc/xdg/autostart/onyxos-wallpaper.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=OnyxOS Wallpaper
Exec=plasma-apply-wallpaperimage /usr/share/wallpapers/OnyxOS/wallpaper-1920x1080.png
OnlyShowIn=KDE;
EOF

echo "[5/6] Création du nouveau système live"
rm -f "$ISO_TREE/LiveOS/squashfs.img"
mkfs.erofs -z lz4hc,level=12 -L OnyxOS-Live "$ISO_TREE/LiveOS/squashfs.img" "$ROOT_TREE" >/dev/null

echo "[6/6] Reconstruction de l'ISO hybride BIOS/UEFI"
rm -f "$OUTPUT_ISO"
xorriso -indev "$SOURCE_ISO" -outdev "$OUTPUT_ISO" \
  -map "$ISO_TREE" / -boot_image any replay -volid "OnyxOS-KDE-Live" -commit >/dev/null

sha256sum "$OUTPUT_ISO" > "${OUTPUT_ISO}.sha256"
echo "ISO prête : $OUTPUT_ISO"
