#!/usr/bin/env bash
# ==============================================================================
# OnyxOS — build-update-rpm.sh
# Crée / incrémente le paquet onyxos-release-<VER>.rpm et régénère le dépôt
# DNF GitHub dans repo-updates/.
#
# Usage (depuis la racine du dépôt) :
#   bash scripts/build-update-rpm.sh [VERSION]
#   Ex : bash scripts/build-update-rpm.sh 1.1
#
# Dépendances (WSL Ubuntu / Fedora / RHEL) :
#   dnf install -y rpm-build createrepo_c
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

# Version : argument ou auto-incrémentation depuis le dernier RPM présent
if [[ "${1:-}" =~ ^[0-9]+\.[0-9]+$ ]]; then
    PKG_VERSION="$1"
else
    # Cherche le plus récent onyxos-release-*.rpm dans repo-updates
    last_rpm=$(find "$REPO_DIR" -name "onyxos-release-*.noarch.rpm" 2>/dev/null | sort -V | tail -n1 || true)
    if [[ -n "$last_rpm" ]]; then
        last_ver=$(basename "$last_rpm" | sed 's/onyxos-release-//; s/-[0-9]*\.noarch\.rpm//')
        # Incrémente le mineur
        major="${last_ver%%.*}"
        minor="${last_ver##*.}"
        PKG_VERSION="${major}.$((minor + 1))"
    else
        PKG_VERSION="1.0"
    fi
fi
PKG_RELEASE="1"
PKG_NAME="onyxos-release"

log "Construction du paquet ${PKG_NAME}-${PKG_VERSION}-${PKG_RELEASE}.noarch.rpm"

# Vérification des outils
command -v rpmbuild   >/dev/null 2>&1 || die "rpmbuild manquant : dnf install rpm-build"
command -v createrepo_c >/dev/null 2>&1 || die "createrepo_c manquant : dnf install createrepo_c"

# Préparation de l'arbre rpmbuild
rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"/{SPECS,BUILD,RPMS,SRPMS,SOURCES}

# --- Fichiers embarqués dans le paquet ---
SOURCES_DIR="$BUILD_ROOT/SOURCES"
PKG_SRCDIR="$SOURCES_DIR/${PKG_NAME}-${PKG_VERSION}"
mkdir -p "$PKG_SRCDIR/etc/yum.repos.d" "$PKG_SRCDIR/etc/dnf"

# Repo file
cat > "$PKG_SRCDIR/etc/yum.repos.d/onyxos.repo" <<'EOF'
[onyxos]
name=OnyxOS Updates (GitHub)
baseurl=https://gael66666.github.io/Onyxos/repo-updates/
enabled=1
skip_if_unavailable=True
gpgcheck=0
priority=90
EOF

# Ajout de l'exclude dans dnf.conf (si pas déjà présent)
cat > "$PKG_SRCDIR/etc/dnf/onyxos-protect.conf" <<'EOF'
# OnyxOS : protège le branding contre les mises à jour Fedora upstream
[main]
exclude=fedora-release* fedora-logos* generic-release*
EOF

# Créer l'archive source
(cd "$SOURCES_DIR" && tar czf "${PKG_NAME}-${PKG_VERSION}.tar.gz" "${PKG_NAME}-${PKG_VERSION}")

# --- SPEC ---
cat > "$BUILD_ROOT/SPECS/${PKG_NAME}.spec" <<SPEC
Name:       ${PKG_NAME}
Version:    ${PKG_VERSION}
Release:    ${PKG_RELEASE}%{?dist}
Summary:    OnyxOS release files and update repository
License:    GPLv2+
URL:        https://github.com/Gael66666/Onyxos
Source0:    %{name}-%{version}.tar.gz
BuildArch:  noarch

%description
Fournit les fichiers de publication d'OnyxOS 1.0 (Plasma Edition) :
configuration du dépôt DNF GitHub (gael66666.github.io/Onyxos/repo-updates)
et protection du branding contre les mises à jour Fedora.

%prep
%setup -q

%install
install -Dm644 etc/yum.repos.d/onyxos.repo \
    %{buildroot}/%{_sysconfdir}/yum.repos.d/onyxos.repo
install -Dm644 etc/dnf/onyxos-protect.conf \
    %{buildroot}/%{_sysconfdir}/dnf/conf.d/onyxos-protect.conf

%files
%{_sysconfdir}/yum.repos.d/onyxos.repo
%{_sysconfdir}/dnf/conf.d/onyxos-protect.conf

%changelog
* $(LC_ALL=C date '+%a %b %d %Y') OnyxOS Team <noreply@onyxos> - ${PKG_VERSION}-${PKG_RELEASE}
- OnyxOS release ${PKG_VERSION} — dépôt GitHub et protection branding
SPEC

# --- Build ---
rpmbuild -bb \
    --define "_topdir $BUILD_ROOT" \
    --define "_rpmdir $BUILD_ROOT/RPMS" \
    "$BUILD_ROOT/SPECS/${PKG_NAME}.spec"

# --- Copie dans repo-updates/ ---
mkdir -p "$REPO_DIR"
find "$BUILD_ROOT/RPMS" -name "*.rpm" -exec cp -f {} "$REPO_DIR/" \;
ok "RPM copié dans $REPO_DIR"

# --- Régénération du dépôt DNF ---
createrepo_c --update "$REPO_DIR"
ok "Index repodata régénéré dans $REPO_DIR"

# Afficher le contenu final
echo ""
log "Contenu de repo-updates/ :"
ls -lh "$REPO_DIR"/*.rpm 2>/dev/null || true
echo ""
ok "Dépôt OnyxOS prêt → à committer et pousser sur GitHub pour activer les MàJ."
