# ==============================================================================
# OnyxOS 1.0 (Plasma Edition) - Kickstart LiveCD Configuration
# Target: x86_64 KDE Plasma Desktop Live System
# Visual identity: Deep Black (#0B0A10), Anthracite (#151320), Electric Violet (#8B5CF6)
# Brand policy: 100% OnyxOS branding - zero visible upstream Fedora markers
# ==============================================================================

# System Authorization & Language
lang fr_FR.UTF-8
keyboard fr
timezone Europe/Paris --utc
authselect select minimal
selinux --enforcing
firewall --enabled --service=mdns

# Network & Live System Services
network --bootproto=dhcp --device=link --activate --onboot=on
services --enabled=NetworkManager,sddm,sshd

# Storage Layout for Live Media
bootloader --location=mbr --append="quiet splash rhgb console=tty0 console=ttyS0,115200"
zerombr
clearpart --all --initlabel
part / --size=16384 --fstype=ext4 --label=onyxos-root

# Repositories (Fedora base & updates for package resolution)
repo --name=fedora --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-41&arch=x86_64
repo --name=updates --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=updates-released-f41&arch=x86_64

# ==============================================================================
# Package Manifest
# ==============================================================================
%packages
@core
@standard
@base-x
@fonts
@multimedia
@hardware-support

# KDE Plasma Desktop Environment
@kde-desktop
plasma-workspace-wayland
plasma-workspace
plasma-desktop
plasma-systemmonitor
plasma-nm
plasma-pa
kcm-about-distro
kwin-wayland
konsole
dolphin
ark
kate
kwrite
kdegraphics-thumbnailers
ffmpegthumbs

# Display Manager & Boot Themes
sddm
sddm-kcm
sddm-wayland-plasma
plymouth
plymouth-plugin-script
plymouth-system-theme

# Kernel & Bootloader
kernel
kernel-modules
kernel-modules-extra
grub2-efi-x64
grub2-pc
shim-x64
efibootmgr
livecd-tools
dracut-live

# Core Utilities
sudo
curl
wget
git
pciutils
usbutils
htop
neofetch
fastfetch

# Brand Replacement: Remove upstream Fedora branding, install generic/custom
-fedora-release
-fedora-release-identity-basic
-fedora-release-identity-kde
-fedora-logos
-fedora-bookmarks
generic-release
generic-logos

%end

# ==============================================================================
# Post-Installation Configuration (chroot)
# ==============================================================================
%post
set -x

echo "[*] Applying OnyxOS 1.0 System Identity..."

# 1. System Identity (/etc/os-release & /etc/system-release)
cat << 'EOF' > /etc/os-release
NAME="OnyxOS"
VERSION="1.0"
ID=onyxos
ID_LIKE="fedora"
VERSION_ID="1.0"
VERSION_CODENAME="Obsidian"
PRETTY_NAME="OnyxOS 1.0 (Plasma Edition)"
ANSI_COLOR="0;35"
LOGO="onyxos-logo"
CPE_NAME="cpe:/o:onyxos:onyxos:1.0"
HOME_URL="https://onyxos.internal"
DOCUMENTATION_URL="https://onyxos.internal/docs"
SUPPORT_URL="https://onyxos.internal/support"
BUG_REPORT_URL="https://onyxos.internal/bugs"
PRIVACY_POLICY_URL="https://onyxos.internal/privacy"
DEFAULT_HOSTNAME="onyxos"
VARIANT="Plasma Edition"
VARIANT_ID=plasma
EOF

echo "OnyxOS release 1.0 (Obsidian)" > /etc/system-release
echo "OnyxOS \r (\l)" > /etc/issue
echo "OnyxOS \r (\l)" > /etc/issue.net
echo "onyxos" > /etc/hostname

# 2. KDE System Settings (About this System)
mkdir -p /etc/xdg
cat << 'EOF' > /etc/xdg/kcm-about-distrorc
[General]
Name=OnyxOS
Version=1.0 (Plasma Edition)
LogoPath=/usr/share/pixmaps/onyxos-logo.svg
Website=https://onyxos.internal
SupportUrl=https://onyxos.internal/support
PrivacyPolicyUrl=https://onyxos.internal/privacy
DocumentationUrl=https://onyxos.internal/docs
BugReportUrl=https://onyxos.internal/bugs
EOF

# 3. KDE Plasma Global Defaults (Deep Black & Electric Violet)
cat << 'EOF' > /etc/xdg/kdeglobals
[General]
ColorScheme=OnyxDark
Name=Onyx Dark

[KDE]
contrast=7

[Colors:Window]
BackgroundNormal=11,10,16
BackgroundAlternate=21,19,32
ForegroundNormal=237,233,254
ForegroundInactive=148,163,184
ForegroundActive=168,85,247
ForegroundLink=139,92,246
ForegroundVisited=168,85,247
ForegroundNegative=244,63,94
ForegroundNeutral=245,158,11
ForegroundPositive=16,185,129
DecorationFocus=139,92,246
DecorationHover=168,85,247

[Colors:View]
BackgroundNormal=11,10,16
BackgroundAlternate=21,19,32
ForegroundNormal=237,233,254
ForegroundInactive=148,163,184
ForegroundActive=168,85,247
ForegroundLink=139,92,246
ForegroundVisited=168,85,247
ForegroundNegative=244,63,94
ForegroundNeutral=245,158,11
ForegroundPositive=16,185,129
DecorationFocus=139,92,246
DecorationHover=168,85,247

[Colors:Button]
BackgroundNormal=21,19,32
BackgroundAlternate=32,28,48
ForegroundNormal=237,233,254
ForegroundInactive=148,163,184
ForegroundActive=168,85,247
ForegroundLink=139,92,246
ForegroundVisited=168,85,247
ForegroundNegative=244,63,94
ForegroundNeutral=245,158,11
ForegroundPositive=16,185,129
DecorationFocus=139,92,246
DecorationHover=168,85,247

[Colors:Selection]
BackgroundNormal=139,92,246
BackgroundAlternate=168,85,247
ForegroundNormal=255,255,255
ForegroundInactive=237,233,254
ForegroundActive=255,255,255
ForegroundLink=245,158,11
ForegroundVisited=216,180,254
DecorationFocus=168,85,247
DecorationHover=192,132,252
EOF

# 4. SDDM Login Greeter Configuration
mkdir -p /etc/sddm.conf.d
cat << 'EOF' > /etc/sddm.conf.d/onyxos.conf
[Theme]
Current=onyxos
CursorTheme=breeze_cursors

[Users]
MaximumUid=60000
MinimumUid=1000
RememberLastUser=true

[Autologin]
User=liveuser
Session=plasmawayland
Relogin=false
EOF

# 5. Create Live User & Sudo permissions
useradd -m -c "OnyxOS Live User" -G wheel,audio,video,dialout liveuser
passwd -d liveuser
cat << 'EOF' > /etc/sudoers.d/liveuser
liveuser ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/liveuser

# 6. Apply Plymouth Boot Splash
if [ -d /usr/share/plymouth/themes/onyxos ]; then
    plymouth-set-default-theme onyxos -R || true
fi

# 7. Brand Sanitization (Ensure zero visible Fedora UI references)
sed -i 's/Fedora/OnyxOS/g' /etc/motd 2>/dev/null || true
rm -rf /usr/share/doc/fedora* 2>/dev/null || true

echo "[OK] OnyxOS Kickstart post-installation completed successfully."
%end

# ==============================================================================
# Non-Chroot Post-Installation Configuration
# ==============================================================================
%post --nochroot
set -x

INSTALL_ROOT=/mnt/sysimage
SRC_DIR="$(pwd)"

echo "[*] Injecting OnyxOS Assets from ${SRC_DIR} to ${INSTALL_ROOT}..."

# Copy Theme & Wallpapers
mkdir -p ${INSTALL_ROOT}/usr/share/color-schemes
mkdir -p ${INSTALL_ROOT}/usr/share/konsole
mkdir -p ${INSTALL_ROOT}/usr/share/wallpapers/OnyxOS
mkdir -p ${INSTALL_ROOT}/usr/share/pixmaps
mkdir -p ${INSTALL_ROOT}/usr/share/plymouth/themes/onyxos
mkdir -p ${INSTALL_ROOT}/usr/share/sddm/themes/onyxos

# Inject themes
[ -f "${SRC_DIR}/theme/OnyxDark.colors" ] && cp -vf "${SRC_DIR}/theme/OnyxDark.colors" ${INSTALL_ROOT}/usr/share/color-schemes/
[ -f "${SRC_DIR}/theme/OnyxKonsole.colorscheme" ] && cp -vf "${SRC_DIR}/theme/OnyxKonsole.colorscheme" ${INSTALL_ROOT}/usr/share/konsole/

# Inject assets
[ -f "${SRC_DIR}/assets/onyxos-logo.svg" ] && cp -vf "${SRC_DIR}/assets/onyxos-logo.svg" ${INSTALL_ROOT}/usr/share/pixmaps/
[ -f "${SRC_DIR}/assets/wallpaper-1920x1080.png" ] && cp -vf "${SRC_DIR}/assets/wallpaper-1920x1080.png" ${INSTALL_ROOT}/usr/share/wallpapers/OnyxOS/
[ -d "${SRC_DIR}/assets/plymouth/onyxos" ] && cp -rfa "${SRC_DIR}/assets/plymouth/onyxos/"* ${INSTALL_ROOT}/usr/share/plymouth/themes/onyxos/
[ -d "${SRC_DIR}/assets/sddm/onyxos" ] && cp -rfa "${SRC_DIR}/assets/sddm/onyxos/"* ${INSTALL_ROOT}/usr/share/sddm/themes/onyxos/

echo "[OK] OnyxOS non-chroot asset injection finished."
%end
