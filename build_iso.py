#!/usr/bin/env python3
"""Build the OnyxOS live ISO from the bundled Fedora KDE ISO.

On Windows the actual work runs inside WSL (Ubuntu by default) as root.
On Linux the rebuild script is executed directly.
"""

import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
SOURCE_ISO = BASE_DIR / "Fedora-KDE-Desktop-Live-45-1.4.x86_64.iso"
OUTPUT_ISO = BASE_DIR / "OnyxOS-1.0-live-x86_64.iso"
BUILD_SCRIPT = BASE_DIR / "rebuild-live-iso.sh"
WSL_DISTRO = os.environ.get("ONYXOS_WSL_DISTRO", "Ubuntu")
MIN_ISO_BYTES = 1024 * 1024 * 1024


def error(message: str) -> int:
    print(message, file=sys.stderr)
    return 1


def run_in_wsl() -> int:
    wsl = shutil.which("wsl.exe") or shutil.which("wsl")
    if not wsl:
        return error("WSL est requis pour construire l'ISO sur Windows.")

    windows_path = str(BASE_DIR).replace(os.sep, "/")
    try:
        translated = subprocess.run(
            [wsl, "-d", WSL_DISTRO, "-u", "root", "--", "wslpath", "-a", windows_path],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        return error(
            f"Impossible de traduire le chemin via WSL (distro '{WSL_DISTRO}'): {exc}"
        )

    if not translated:
        return error("WSL n'a pas renvoyé de chemin Linux valide.")

    command = f"cd -- {shlex.quote(translated)} && bash ./rebuild-live-iso.sh"
    build_command = [wsl, "-d", WSL_DISTRO, "-u", "root", "--", "bash", "-lc", command]
    try:
        completed = subprocess.run(build_command, cwd=BASE_DIR)
    except OSError as exc:
        return error(f"Impossible de lancer WSL : {exc}")
    return completed.returncode


def main() -> int:
    if not SOURCE_ISO.is_file():
        return error(f"ISO Fedora source introuvable : {SOURCE_ISO}")
    if not BUILD_SCRIPT.is_file():
        return error(f"Script de construction introuvable : {BUILD_SCRIPT}")

    if os.name == "nt":
        result = run_in_wsl()
    else:
        try:
            result = subprocess.run(["bash", str(BUILD_SCRIPT)], cwd=BASE_DIR).returncode
        except OSError as exc:
            return error(f"Impossible de lancer le script de construction : {exc}")

    if result != 0:
        if not (OUTPUT_ISO.is_file() and OUTPUT_ISO.stat().st_size >= MIN_ISO_BYTES):
            return result or 1
        print(
            f"Avertissement : le script a renvoyé {result}, mais l'ISO est valide.",
            file=sys.stderr,
        )

    if not OUTPUT_ISO.is_file():
        return error(f"L'ISO n'a pas été produite : {OUTPUT_ISO}")
    if OUTPUT_ISO.stat().st_size < MIN_ISO_BYTES:
        return error(f"ISO invalide (trop petite) : {OUTPUT_ISO}")

    print(f"ISO OnyxOS prête : {OUTPUT_ISO} ({OUTPUT_ISO.stat().st_size} octets)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
