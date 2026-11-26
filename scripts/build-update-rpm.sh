#!/usr/bin/env bash
# ==============================================================================
# OnyxOS — build-update-rpm.sh v2.1
# Crée / incrémente le paquet onyxos-release-<VER>.rpm et régénère le dépôt
# DNF GitHub dans repo-updates/.
#
# Nouveautés v2.1 :
#   - Hook DNF5 automatique (/etc/dnf/libdnf5-plugins/actions.d/onyxos-rebrand.actions)
#   - Zéro exclude bloquant (laisse passer 100% des mises à jour Fedora)
#   - Réapplication automatique de l'identité OnyxOS post-transaction
# ==============================================================================
set -euo pipefail

PURPLE='\033[38;2;139;92;246m'
GREEN='\033[38;2;16;185;129m'
RED='\033[38;2;244;63;94m'
RESET='\033[0m'
log()  { printf '%b[RPM-BUILD]%b %s\n' "$PURPLE" "$RESET" "$*"; }
ok()   { printf '%b[OK]%b %s\n'        "$GREEN"  "$RESET" "$*"; }
die()  { printf '%b[ERR]%b %s\n'       "$RED"    "$RESET" "$*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$REPO_ROOT/repo-updates"
BUILD_ROOT="/tmp/onyxos-rpm-build"

# Version : argument ou auto-incrémentation
if [[ "${1:-}" =~ ^[0-9]+\.[0-9]+$ ]]; then
    PKG_VERSION="$1"
else
    last_rpm=$(find "$REPO_DIR" -name "onyxos-release-*.noarch.rpm" 2>/dev/null | sort -V | tail -n1 || true)
    if [[ -n "$last_rpm" ]]; then
        last_ver=$(basename "$last_rpm" | sed 's/onyxos-release-//; s/-[0-9]*\.noarch\.rpm//')
        major="${last_ver%%.*}"
        minor="${last_ver##*.}"
        PKG_VERSION="${major}.$((minor + 1))"
    else
        PKG_VERSION="2.1"
    fi
fi
PKG_RELEASE="1"
PKG_NAME="onyxos-release"

log "Construction du paquet ${PKG_NAME}-${PKG_VERSION}-${PKG_RELEASE}.noarch.rpm"

command -v rpmbuild   >/dev/null 2>&1 || die "rpmbuild manquant : apt-get install rpm"
command -v createrepo_c >/dev/null 2>&1 || die "createrepo_c manquant : apt-get install createrepo-c"

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"/{SPECS,BUILD,RPMS,SRPMS,SOURCES}

SOURCES_DIR="$BUILD_ROOT/SOURCES"
PKG_SRCDIR="$SOURCES_DIR/${PKG_NAME}-${PKG_VERSION}"
mkdir -p "$PKG_SRCDIR/etc/yum.repos.d" \
         "$PKG_SRCDIR/etc/dnf/libdnf5-plugins/actions.d" \
         "$PKG_SRCDIR/usr/local/bin"

# 1. Dépôt GitHub OnyxOS
cat > "$PKG_SRCDIR/etc/yum.repos.d/onyxos.repo" <<'EOF'
[onyxos]
name=OnyxOS Updates (GitHub)
baseurl=https://gael66666.github.io/Onyxos/repo-updates/
enabled=1
skip_if_unavailable=True
gpgcheck=0
priority=90
EOF

# 2. Hook DNF5 automatique (libdnf5-plugin-actions)
cat > "$PKG_SRCDIR/etc/dnf/libdnf5-plugins/actions.d/onyxos-rebrand.actions" <<'EOF'
# Réapplique l'identité OnyxOS après toute mise à jour sans rien bloquer
post_transaction::::/usr/local/bin/onyxos-rebrand-hook
EOF

# 3. Script de réapplication d'identité
cat > "$PKG_SRCDIR/usr/local/bin/onyxos-rebrand-hook" <<'EOF'
#!/bin/sh
# Réapplique l'identité OnyxOS après une transaction DNF
[ -f /usr/lib/os-release ] && sed -i \
    -e 's/^NAME=.*/NAME="OnyxOS"/' \
    -e 's/^PRETTY_NAME=.*/PRETTY_NAME="OnyxOS 2.4 (Obsidian Matte)"/' \
    -e 's/^ID=.*/ID=onyxos/' \
    -e 's/^VERSION=.*/VERSION="2.4"/' \
    -e 's/^VERSION_ID=.*/VERSION_ID="2.4"/' \
    /usr/lib/os-release 2>/dev/null || true
[ -L /etc/os-release ] || ln -sf ../usr/lib/os-release /etc/os-release 2>/dev/null || true
[ -f /etc/hostname ] || echo "onyxos" > /etc/hostname

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
chmod 0755 "$PKG_SRCDIR/usr/local/bin/onyxos-rebrand-hook"

(cd "$SOURCES_DIR" && tar czf "${PKG_NAME}-${PKG_VERSION}.tar.gz" "${PKG_NAME}-${PKG_VERSION}")

cat > "$BUILD_ROOT/SPECS/${PKG_NAME}.spec" <<SPEC
Name:       ${PKG_NAME}
Version:    ${PKG_VERSION}
Release:    ${PKG_RELEASE}%{?dist}
Summary:    OnyxOS release files, update repository and DNF5 hook
License:    GPLv2+
URL:        https://github.com/Gael66666/Onyxos
Source0:    %{name}-%{version}.tar.gz
BuildArch:  noarch

%description
Fournit la configuration officielle d'OnyxOS ${PKG_VERSION} :
- Configuration du dépôt DNF GitHub (gael66666.github.io/Onyxos/repo-updates)
- Hook DNF5 transparent qui laisse passer 100%% des mises à jour Fedora
  et maintient l'identité OnyxOS intacte sans aucun blocage.

%prep
%setup -q

%install
install -Dm644 etc/yum.repos.d/onyxos.repo \
    %{buildroot}/%{_sysconfdir}/yum.repos.d/onyxos.repo
install -Dm644 etc/dnf/libdnf5-plugins/actions.d/onyxos-rebrand.actions \
    %{buildroot}/%{_sysconfdir}/dnf/libdnf5-plugins/actions.d/onyxos-rebrand.actions
install -Dm755 usr/local/bin/onyxos-rebrand-hook \
    %{buildroot}/%{_bindir}/onyxos-rebrand-hook

%files
%{_sysconfdir}/yum.repos.d/onyxos.repo
%{_sysconfdir}/dnf/libdnf5-plugins/actions.d/onyxos-rebrand.actions
%{_bindir}/onyxos-rebrand-hook

%changelog
* $(LC_ALL=C date '+%a %b %d %Y') OnyxOS Team <noreply@onyxos> - ${PKG_VERSION}-${PKG_RELEASE}
- OnyxOS release ${PKG_VERSION} — Hook DNF5 transparent et dépôt GitHub
SPEC

rpmbuild -bb \
    --define "_topdir $BUILD_ROOT" \
    --define "_rpmdir $BUILD_ROOT/RPMS" \
    "$BUILD_ROOT/SPECS/${PKG_NAME}.spec"

mkdir -p "$REPO_DIR"
find "$BUILD_ROOT/RPMS" -name "*.rpm" -exec cp -f {} "$REPO_DIR/" \;
ok "RPM copié dans $REPO_DIR"

createrepo_c --update "$REPO_DIR"
ok "Index repodata régénéré dans $REPO_DIR"

echo ""
log "Contenu de repo-updates/ :"
ls -lh "$REPO_DIR"/*.rpm 2>/dev/null || true
echo ""
ok "Dépôt OnyxOS prêt."
