#!/usr/bin/env bash
# ==============================================================================
# OnyxOS 1.0 (Plasma Edition) - Live ISO builder
#
# Rebrands the Fedora KDE live root filesystem (keeping the Fedora kernel,
# packages and KDE Plasma) and reseals a hybrid BIOS/UEFI ISO.
#
# Design notes:
#   * The live root is extracted with fsck.erofs --xattrs so SELinux labels
#     and file capabilities survive the round trip.
#   * Plymouth uses the "two-step" plugin because the Fedora live image does
#     not ship plymouth-plugin-script. The theme is baked into the initramfs.
#   * Only the squashfs, the initramfs and grub.cfg are remapped into the
#     source ISO. Remapping the whole tree loses the hidden El Torito EFI
#     image and breaks the boot.
#
# Requires: xorriso, erofs-utils, python3, chroot, root privileges.
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
ok()   { printf '%b[ONYX-OK]%b %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%b[ONYX-WARN]%b %s\n' "$AMBER" "$RESET" "$*"; }
die()  { printf '%b[ONYX-ERR]%b %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

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
    mount --bind /sys "$ROOT_TREE/sys"
    mount --bind /dev "$ROOT_TREE/dev"
    mount --bind /dev/pts "$ROOT_TREE/dev/pts" 2>/dev/null || true
    mount --bind /run "$ROOT_TREE/run" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# 0. Visual assets
# ------------------------------------------------------------------------------
if [[ "${ONYXOS_REGEN_ASSETS:-0}" == "1" || ! -f "$BASE_DIR/assets/onyxos-logo.png" \
      || ! -f "$BASE_DIR/assets/plymouth/onyxos/onyxos.plymouth" ]]; then
    log "Étape 0/8 : génération des ressources visuelles OnyxOS"
    python3 "$BASE_DIR/assets/generate_assets.py"
    ok "Ressources générées."
else
    log "Étape 0/8 : ressources visuelles déjà présentes"
fi

# ------------------------------------------------------------------------------
# 1. Extract the source ISO and the live EROFS root
# ------------------------------------------------------------------------------
log "Étape 1/8 : extraction de l'ISO Fedora KDE"
rm -rf "$BUILD_DIR"
mkdir -p "$ISO_TREE"
xorriso -osirrox on -indev "$SOURCE_ISO" -extract / "$ISO_TREE" >/dev/null
[[ -f "$ISO_TREE/LiveOS/squashfs.img" ]] || die "LiveOS/squashfs.img absent de l'ISO."
ok "ISO extraite."

log "Étape 2/8 : extraction du système live EROFS (xattrs préservés)"
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

# ------------------------------------------------------------------------------
# 2. System identity
# ------------------------------------------------------------------------------
log "Étape 3/8 : identité système OnyxOS"
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

# Fresh identity on every boot / install.
: > "$ROOT_TREE/etc/machine-id"
if [[ -d "$ROOT_TREE/var/lib/dbus" ]]; then
    rm -f "$ROOT_TREE/var/lib/dbus/machine-id"
    ln -s /etc/machine-id "$ROOT_TREE/var/lib/dbus/machine-id"
fi
rm -f "$ROOT_TREE"/etc/ssh/ssh_host_* 2>/dev/null || true

# livesys would otherwise force "localhost-live".
sed -i 's/hostnamectl set-hostname "localhost-live"/hostnamectl set-hostname "onyxos"/' \
    "$ROOT_TREE/usr/libexec/livesys/livesys-main"
grep -q 'hostnamectl set-hostname "onyxos"' "$ROOT_TREE/usr/libexec/livesys/livesys-main" \
    || warn "Le remplacement du hostname livesys n'a pas été appliqué."
ok "Identité système OnyxOS appliquée."

# ------------------------------------------------------------------------------
# 3. Visual identity: themes, wallpaper, logos, login
# ------------------------------------------------------------------------------
log "Étape 4/8 : identité visuelle (thèmes, fond d'écran, logos)"

install -Dm644 "$BASE_DIR/theme/OnyxDark.colors" \
    "$ROOT_TREE/usr/share/color-schemes/OnyxDark.colors"
install -Dm644 "$BASE_DIR/theme/OnyxKonsole.colorscheme" \
    "$ROOT_TREE/usr/share/konsole/OnyxKonsole.colorscheme"
install -Dm644 "$BASE_DIR/assets/onyxos-logo.svg" \
    "$ROOT_TREE/usr/share/pixmaps/onyxos-logo.svg"
install -Dm644 "$BASE_DIR/assets/onyxos-logo.png" \
    "$ROOT_TREE/usr/share/pixmaps/onyxos-logo.png"

# Wallpaper package (Plasma resolves "Image=OnyxOS" through /usr/share/wallpapers).
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

# OnyxOS look-and-feel package.
LNF="$ROOT_TREE/usr/share/plasma/look-and-feel/org.onyxos.desktop"
mkdir -p "$LNF/contents"
cat > "$LNF/metadata.json" <<'EOF'
{
    "KPackageStructure": "Plasma/LookAndFeel",
    "KPlugin": {
        "Authors": [{"Name": "OnyxOS"}],
        "Description": "OnyxOS 1.0 Plasma look and feel",
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

[kdeglobals][Icons]
Theme=breeze-dark

[plasmarc][Theme]
name=default

[Wallpaper]
Image=OnyxOS

[kcminputrc][Mouse]
cursorTheme=breeze_cursors

[kwinrc][org.kde.kdecoration2]
library=org.kde.breeze
theme=Breeze

[ksplashrc][KSplash]
Theme=org.kde.breeze.desktop
EOF

cat > "$ROOT_TREE/etc/xdg/kdeglobals" <<'EOF'
[General]
ColorScheme=OnyxDark

[KDE]
LookAndFeelPackage=org.onyxos.desktop

[Icons]
Theme=breeze-dark
EOF
cat > "$ROOT_TREE/etc/xdg/ksplashrc" <<'EOF'
[KSplash]
Theme=org.kde.breeze.desktop
Engine=KSplashQML
EOF

# Apply the OnyxOS look on the live session (plasma-apply-* needs a session).
cat > "$ROOT_TREE/usr/local/bin/onyxos-desktop-setup" <<'EOF'
#!/bin/sh
# Apply the OnyxOS desktop identity to the live session.
WALLPAPER=/usr/share/wallpapers/OnyxOS/contents/images/1920x1080.png
if command -v plasma-apply-lookandfeel >/dev/null 2>&1; then
    plasma-apply-lookandfeel -a org.onyxos.desktop >/dev/null 2>&1 || true
fi
if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
    plasma-apply-colorscheme OnyxDark >/dev/null 2>&1 || true
fi
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

# Give the live user the OnyxOS defaults before Plasma starts.
cat >> "$ROOT_TREE/usr/libexec/livesys/sessions.d/livesys-kde" <<'EOF'

# OnyxOS: pre-seed the live user's Plasma configuration.
mkdir -p /home/liveuser/.config
cp -f /etc/xdg/kdeglobals /home/liveuser/.config/kdeglobals 2>/dev/null || :
EOF

# Replace all Fedora-branded images with the OnyxOS logo (same file names).
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
    sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
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

# Remove remaining Fedora-only desktop assets.
rm -rf "$ROOT_TREE/usr/share/plasma/look-and-feel/"org.fedoraproject.* 2>/dev/null || true
rm -rf "$ROOT_TREE/usr/share/wallpapers/Fedora" 2>/dev/null || true
find "$ROOT_TREE/usr/share/backgrounds" -maxdepth 1 -iname '*fedora*' -exec rm -rf {} + 2>/dev/null || true
find "$ROOT_TREE/usr/share/doc" -maxdepth 1 -iname '*fedora*' -exec rm -rf {} + 2>/dev/null || true
find "$ROOT_TREE/usr/share/plasma" -maxdepth 3 -iname '*fedora*' -exec rm -rf {} + 2>/dev/null || true
find "$ROOT_TREE/usr/share/color-schemes" -maxdepth 1 -iname '*fedora*' -delete 2>/dev/null || true
find "$ROOT_TREE/usr/share/konsole" -maxdepth 1 -iname '*fedora*' -delete 2>/dev/null || true
find "$ROOT_TREE/usr/share/applications" -maxdepth 1 -iname '*fedora*' -delete 2>/dev/null || true
rm -f "$ROOT_TREE/usr/share/applications/org.fedoraproject.MediaWriter.desktop" 2>/dev/null || true

# Login greeter theme (SDDM-compatible; harmless if plasmalogin is used).
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
ok "Identité visuelle appliquée."

# ------------------------------------------------------------------------------
# 4. Plymouth boot splash (two-step plugin, baked into the initramfs)
# ------------------------------------------------------------------------------
log "Étape 5/8 : splash Plymouth OnyxOS + initramfs"
install -d "$ROOT_TREE/usr/share/plymouth/themes/onyxos" \
           "$ROOT_TREE/etc/plymouth"
cp -a "$BASE_DIR/assets/plymouth/onyxos/." \
      "$ROOT_TREE/usr/share/plymouth/themes/onyxos/"
chown -R root:root "$ROOT_TREE/usr/share/plymouth/themes/onyxos"
find "$ROOT_TREE/usr/share/plymouth/themes/onyxos" -type d -exec chmod 0755 {} +
find "$ROOT_TREE/usr/share/plymouth/themes/onyxos" -type f -exec chmod 0644 {} +
# Generated text assets may arrive with CRLF from a Windows host; Plymouth and
# KDE parse these files strictly, so normalise them before dracut runs.
find "$ROOT_TREE/usr/share/plymouth/themes/onyxos" -type f \
    \( -name '*.plymouth' -o -name '*.conf' \) -exec sed -i 's/\r$//' {} +
if grep -q $'\r' "$ROOT_TREE/usr/share/plymouth/themes/onyxos/onyxos.plymouth"; then
    die "onyxos.plymouth contient encore des CRLF."
fi
# bgrt uses the spinner theme's watermark: replace the Fedora wordmark too.
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

# Rebuild the initramfs with the live module and the OnyxOS theme.
cp -f "$ISO_TREE/boot/x86_64/loader/initrd" "$ROOT_TREE/var/tmp/onyxos-orig-initrd"
if chroot "$ROOT_TREE" /usr/bin/lsinitrd /var/tmp/onyxos-orig-initrd >/dev/null 2>&1; then
    ok "lsinitrd disponible ; reconstruction dracut avec dmsquash-live."
else
    warn "lsinitrd indisponible ; reconstruction dracut minimale."
fi

chroot "$ROOT_TREE" /usr/bin/dracut -f --no-hostonly \
    --add "dmsquash-live plymouth systemd" \
    "/var/tmp/onyxos-initramfs.img" "$KVER"
[[ -s "$ROOT_TREE/var/tmp/onyxos-initramfs.img" ]] || die "dracut n'a pas produit d'initramfs."
chroot "$ROOT_TREE" /usr/bin/lsinitrd /var/tmp/onyxos-initramfs.img > "$BUILD_DIR/initrd.list"
grep -q 'themes/onyxos/onyxos.plymouth' "$BUILD_DIR/initrd.list" \
    || die "Le thème Plymouth OnyxOS n'est pas dans l'initramfs."
grep -q 'dmsquash-live-root' "$BUILD_DIR/initrd.list" \
    || die "Le module live n'est pas dans l'initramfs."
grep -q 'systemd' "$BUILD_DIR/initrd.list" \
    || die "systemd n'est pas dans l'initramfs."
install -m644 "$ROOT_TREE/var/tmp/onyxos-initramfs.img" \
    "$ISO_TREE/boot/x86_64/loader/initrd"
rm -f "$ROOT_TREE/var/tmp/onyxos-initramfs.img" "$ROOT_TREE/var/tmp/onyxos-orig-initrd"
ok "Initramfs OnyxOS reconstruit ($(du -h "$ISO_TREE/boot/x86_64/loader/initrd" | cut -f1))."

umount_chroot
: > "$ROOT_TREE/etc/machine-id"
ok "Splash Plymouth embarqué."

# ------------------------------------------------------------------------------
# 5. Rebuild the live EROFS
# ------------------------------------------------------------------------------
log "Étape 6/8 : reconstruction du système live EROFS"
rm -f "$ISO_TREE/LiveOS/squashfs.img"
CONTEXTS="$ROOT_TREE/etc/selinux/targeted/contexts/files/file_contexts"
build_erofs() {
    mkfs.erofs -z lz4hc,level=12 -L OnyxOS-Live "$@" \
        "$ISO_TREE/LiveOS/squashfs.img" "$ROOT_TREE"
}
if [[ -f "$CONTEXTS" ]]; then
    if ! build_erofs --file-contexts="$CONTEXTS"; then
        warn "mkfs.erofs n'a pas accepté file_contexts ; reprise sans relabel."
        rm -f "$ISO_TREE/LiveOS/squashfs.img"
        build_erofs
    fi
else
    warn "file_contexts SELinux introuvable ; labels hérités des xattrs."
    build_erofs
fi
[[ -s "$ISO_TREE/LiveOS/squashfs.img" ]] || die "squashfs non généré."
ok "Système live reconstruit ($(du -h "$ISO_TREE/LiveOS/squashfs.img" | cut -f1))."

# ------------------------------------------------------------------------------
# 6. GRUB menu
# ------------------------------------------------------------------------------
log "Étape 7/8 : menu GRUB et configuration noyau"
GRUB_CONFIG="$ISO_TREE/boot/grub2/grub.cfg"
[[ -f "$GRUB_CONFIG" ]] || die "grub.cfg introuvable : $GRUB_CONFIG"
sed -i \
    -e 's/^set default="1"/set default="0"/' \
    -e 's/Fedora-KDE-Desktop-Live/OnyxOS 1.0 (Plasma Edition)/g' \
    -e 's/Fedora-KDE-Live-45/ONYXOS_KDE_LIVE/g' \
    -e 's/--class fedora/--class onyxos/g' \
    "$GRUB_CONFIG"
sed -i 's/quiet rhgb/console=ttyS0,115200 quiet rhgb/g' "$GRUB_CONFIG"
# noapic avoids the "IO-APIC + timer doesn't work" panic seen with QEMU TCG
# timer calibration while remaining harmless for a live ISO.
sed -i 's/console=ttyS0,115200/console=ttyS0,115200 noapic/g' "$GRUB_CONFIG"
grep -q 'console=ttyS0,115200' "$GRUB_CONFIG" \
    || sed -i 's|^\(\s*linux\b.*\)$|\1 console=ttyS0,115200 noapic|' "$GRUB_CONFIG"
GRUB_FLAGS="console=tty0 systemd.mask=abrtd.service systemd.mask=abrt-journal-core.service systemd.mask=abrt-oops.service systemd.mask=abrt-xorg.service systemd.mask=abrt-vmcore.service systemd.mask=upower.service systemd.setenv=QT_QUICK_BACKEND=software systemd.setenv=LIBGL_ALWAYS_SOFTWARE=1"
sed -i "/^[[:space:]]*linux[[:space:]]/ s|\$| $GRUB_FLAGS|" "$GRUB_CONFIG"
grep -q 'noapic' "$GRUB_CONFIG" || die "noapic non appliqué au menu GRUB."
grep -q 'systemd.mask=abrtd.service' "$GRUB_CONFIG" || die "masques ABRT absents du menu GRUB."
grep -q 'console=tty0' "$GRUB_CONFIG" || die "console=tty0 absente du menu GRUB."
grep -q 'set default="0"' "$GRUB_CONFIG" || die "set default=0 non appliqué."
if grep -qi 'fedora' "$GRUB_CONFIG"; then
    die "Branding Fedora restant dans grub.cfg."
fi
ok "GRUB rebrandé (console série + démarrage direct)."

# ------------------------------------------------------------------------------
# 7. Reseal the ISO
# ------------------------------------------------------------------------------
log "Étape 8/8 : scellage de l'ISO OnyxOS"
rm -f "$WORK_ISO"
xorriso -indev "$SOURCE_ISO" -outdev "$WORK_ISO" \
    -boot_image any replay \
    -map "$ISO_TREE/LiveOS/squashfs.img" /LiveOS/squashfs.img \
    -map "$ISO_TREE/boot/x86_64/loader/initrd" /boot/x86_64/loader/initrd \
    -map "$GRUB_CONFIG" /boot/grub2/grub.cfg \
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
printf '%b      ONYXOS 1.0 (PLASMA EDITION) EST PRÊTE             %b\n' "$GREEN" "$RESET"
printf '%b==========================================================%b\n' "$GREEN" "$RESET"

umount_chroot
umount_erofs || true
trap - EXIT
cleanup
exit 0
