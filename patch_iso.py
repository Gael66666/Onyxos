#!/usr/bin/env python3
"""
OnyxOS ISO Branding Patcher
Remplace TOUS les strings Fedora par OnyxOS dans l'ISO (hors squashfs compressé).
Travaille en lecture/écriture directe sur le fichier ISO.
"""

import sys
import os
import shutil
from datetime import datetime

ISO_SRC = r"C:\Users\OHL\.gemini\antigravity\scratch\onyxos\onyxos-1.0-x86_64.iso"
ISO_BAK = r"C:\Users\OHL\.gemini\antigravity\scratch\onyxos\onyxos-1.0-x86_64.iso.bak"

# -----------------------------------------------------------------------
# Table de remplacement : (ancien, nouveau) — MÊME LONGUEUR OBLIGATOIRE
# Ordre important : les plus longs en premier
# -----------------------------------------------------------------------
REPLACEMENTS = [
    # Volume label ISO9660 + CDLABEL dans cmdline kernel
    (b"Fedora-KDE-Live-45",  b"OnyxOS-KDE-Live-10"),   # 18 chars

    # GRUB menuentry class
    (b"--class fedora",      b"--class onyxos"),        # 14 chars

    # os-release / affichage
    (b"Fedora Linux",        b"OnyxOS 1.0  "),          # 12 chars
    (b"NAME=Fedora",         b"NAME=OnyxOS "),          # 11 chars

    # Générique (après les spécifiques)
    (b"fedora-kde",          b"onyxos-kde"),            # 10 chars — ATTENTION longueur diff -> skip
    # Remplacements 6-chars purs (sûrs)
    (b"Fedora",              b"OnyxOS"),                # 6 chars
    (b"fedora",              b"onyxos"),                # 6 chars
]

# Vérifie que chaque paire a la même longueur
print("=== Vérification des longueurs ===")
valid_replacements = []
for old, new in REPLACEMENTS:
    if len(old) == len(new):
        print(f"  OK  {old!r} ({len(old)}) → {new!r}")
        valid_replacements.append((old, new))
    else:
        print(f"  SKIP (longueur différente: {len(old)} vs {len(new)}): {old!r}")

CHUNK = 4 * 1024 * 1024   # 4 MB par chunk
OVERLAP = 64               # Chevauchement pour ne pas manquer de string à la frontière

def patch_iso(path):
    size = os.path.getsize(path)
    print(f"\n=== Ouverture {path} ({size:,} bytes = {size/1e9:.2f} GB) ===")

    total_patches = {r[0]: 0 for r in valid_replacements}
    pos = 0

    with open(path, "r+b") as f:
        while pos < size:
            # Lire le chunk courant (avec chevauchement sur le précédent)
            read_start = max(0, pos - OVERLAP)
            f.seek(read_start)
            chunk = f.read(CHUNK + OVERLAP)
            if not chunk:
                break

            modified = bytearray(chunk)
            patches_in_chunk = 0

            for old, new in valid_replacements:
                search_start = 0
                while True:
                    idx = modified.find(old, search_start)
                    if idx == -1:
                        break
                    # Offset absolu dans le fichier
                    abs_offset = read_start + idx
                    modified[idx:idx+len(old)] = new
                    total_patches[old] += 1
                    patches_in_chunk += 1
                    print(f"  PATCHED 0x{abs_offset:08X}: {old!r} → {new!r}")
                    search_start = idx + len(new)

            if patches_in_chunk > 0:
                # Réécrire le chunk modifié
                f.seek(read_start)
                f.write(bytes(modified))

            # Avancer (en tenant compte du chevauchement)
            pos = read_start + len(chunk)
            # Affichage progression
            pct = min(100, pos * 100 // size)
            if pct % 5 == 0 or patches_in_chunk > 0:
                print(f"  ... {pct}% ({pos:,} / {size:,} bytes)", flush=True)

    print("\n=== RÉSUMÉ ===")
    for old, count in total_patches.items():
        status = "✓" if count > 0 else "○"
        print(f"  {status} {old!r}: {count} remplacement(s)")
    total = sum(total_patches.values())
    print(f"\n  TOTAL: {total} patch(es) appliqué(s)")
    return total

# --- Sauvegarde si pas déjà faite ---
if not os.path.exists(ISO_BAK):
    print(f"Création backup → {ISO_BAK}")
    print("(peut prendre quelques minutes pour 3.5 GB...)")
    shutil.copy2(ISO_SRC, ISO_BAK)
    print("Backup OK")
else:
    print(f"Backup existant trouvé : {ISO_BAK}")

# --- Patch ---
t0 = datetime.now()
n = patch_iso(ISO_SRC)
elapsed = (datetime.now() - t0).total_seconds()
print(f"\nTerminé en {elapsed:.1f}s — {n} patches au total")

if n == 0:
    print("ATTENTION : Aucun patch appliqué — l'ISO était déjà propre ou les strings n'ont pas été trouvés en clair.")
