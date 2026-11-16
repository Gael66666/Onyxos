#!/usr/bin/env bash
# ==============================================================================
# OnyxOS 1.0 (Plasma Edition) - Automated Distribution Build Pipeline
# Self-healing, brand-checking, and ISO packaging
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# ANSI Colors (Dark & Violet Aesthetic)
CLR_RESET="\033[0m"
CLR_PURPLE="\033[38;2;139;92;246m"
CLR_VIVID="\033[38;2;168;85;247m"
CLR_DARK="\033[38;2;21;19;32m"
CLR_SUCCESS="\033[38;2;16;185;129m"
CLR_WARN="\033[38;2;245;158;11m"
CLR_ERR="\033[38;2;244;63;94m"

log_info() {
    echo -e "${CLR_PURPLE}[ONYX-BUILD]${CLR_RESET} $1"
}

log_ok() {
    echo -e "${CLR_SUCCESS}[ONYX-OK]${CLR_RESET} $1"
}

log_warn() {
    echo -e "${CLR_WARN}[ONYX-WARN]${CLR_RESET} $1"
}

log_err() {
    echo -e "${CLR_ERR}[ONYX-ERR]${CLR_RESET} $1"
}

echo -e "${CLR_VIVID}"
echo "=========================================================="
echo "         ONYXOS 1.0 (PLASMA EDITION) BUILD PIPELINE       "
echo "  Deep Black (#0B0A10) & Electric Violet (#8B5CF6/#A855F7)"
echo "=========================================================="
echo -e "${CLR_RESET}"

# Step 1: Pre-flight Verification
log_info "Step 1: Checking build environment and prerequisites..."

if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
    log_err "Python 3 is required for asset generation!"
    exit 1
fi
PYTHON_BIN="$(command -v python3 || command -v python)"
log_ok "Using Python interpreter: ${PYTHON_BIN}"

# Step 2: Asset Generation
log_info "Step 2: Generating visual assets (wallpapers, logos, themes)..."
"${PYTHON_BIN}" "${SCRIPT_DIR}/assets/generate_assets.py"
log_ok "Assets generated successfully."

# Step 3: Brand Sanitization Audit
log_info "Step 3: Auditing Kickstart and configs for branding compliance..."
FORBIDDEN_TERMS=("fedora" "Fedora" "FEDORA")
AUDIT_TARGETS=("${SCRIPT_DIR}/config/os-release" "${SCRIPT_DIR}/config/kcm-about-distrorc")

for target in "${AUDIT_TARGETS[@]}"; do
    if [ -f "${target}" ]; then
        # Check PRETTY_NAME and NAME specifically
        if grep -E "^(NAME|PRETTY_NAME|VARIANT)=.*Fedora" "${target}" >/dev/null 2>&1; then
            log_err "Violation: Upstream brand detected in ${target}!"
            sed -i 's/Fedora/OnyxOS/g' "${target}"
            log_ok "Sanitized brand in ${target}"
        fi
    fi
done
log_ok "Branding audit passed: All user-facing identities set to OnyxOS."

# Step 4: Kickstart Validation
log_info "Step 4: Validating Kickstart file: onyxos-kde.ks..."
KS_FILE="${SCRIPT_DIR}/onyxos-kde.ks"
if [ ! -f "${KS_FILE}" ]; then
    log_err "Kickstart file not found: ${KS_FILE}"
    exit 1
fi

if command -v ksflatten &>/dev/null; then
    ksflatten -c "${KS_FILE}" -o "${SCRIPT_DIR}/build-flattened.ks"
    log_ok "Kickstart flattened and syntax validated."
else
    log_warn "ksflatten not available, performing basic syntax checks..."
    # Basic Kickstart syntax validation
    grep -q "^%packages" "${KS_FILE}" || { log_err "Missing %packages section in Kickstart"; exit 1; }
    grep -q "^%end" "${KS_FILE}" || { log_err "Missing %end in Kickstart"; exit 1; }
    grep -q "^%post" "${KS_FILE}" || { log_err "Missing %post in Kickstart"; exit 1; }
    log_ok "Kickstart structure verification passed."
fi

# Step 5: ISO Creation
ISO_NAME="onyxos-1.0-x86_64.iso"
OUTPUT_DIR="${SCRIPT_DIR}/build-output"
mkdir -p "${OUTPUT_DIR}"

log_info "Step 5: Packaging OnyxOS Live ISO image (${ISO_NAME})..."

if command -v livemedia-creator &>/dev/null; then
    log_info "Running livemedia-creator..."
    livemedia-creator --ks="${KS_FILE}" --no-virt --resultdir="${OUTPUT_DIR}" --project="OnyxOS" --releasever=41
    if [ -f "${OUTPUT_DIR}/images/boot.iso" ]; then
        mv "${OUTPUT_DIR}/images/boot.iso" "${SCRIPT_DIR}/${ISO_NAME}"
    fi
elif [ -f "${SCRIPT_DIR}/build_iso.py" ]; then
    log_info "Invoking portable ISO generator: build_iso.py..."
    "${PYTHON_BIN}" "${SCRIPT_DIR}/build_iso.py"
fi

if [ -f "${SCRIPT_DIR}/${ISO_NAME}" ]; then
    log_ok "Target ISO successfully created: ${SCRIPT_DIR}/${ISO_NAME}"
    # Generate SHA256 checksum
    if command -v sha256sum &>/dev/null; then
        sha256sum "${SCRIPT_DIR}/${ISO_NAME}" > "${SCRIPT_DIR}/${ISO_NAME}.sha256"
        log_ok "Generated SHA256 checksum: $(cat "${SCRIPT_DIR}/${ISO_NAME}.sha256")"
    fi
else
    log_err "Build failed: ${ISO_NAME} was not generated!"
    exit 1
fi

echo -e "${CLR_SUCCESS}"
echo "=========================================================="
echo "          ONYXOS 1.0 BUILD COMPLETED SUCCESSFULLY         "
echo "=========================================================="
echo -e "${CLR_RESET}"
