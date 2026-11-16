#!/usr/bin/env python3
"""
Injecte les grub.cfg OnyxOS directement dans l'ISO binaire.
Les fichiers grub.cfg sont stockés non-compressés dans l'ISO9660.
"""
import struct, sys
from pathlib import Path

ISO = Path(r"C:\Users\OHL\.gemini\antigravity\scratch\onyxos\OnyxOS-1.0-final.iso")
EXTRACTED = Path(r"C:\Users\OHL\.gemini\antigravity\scratch\onyxos\work\iso_extracted")

# Nouveaux contenus grub.cfg (propres, 100% OnyxOS)
BIOS_GRUB = b"""set default="0"
set timeout=10
# OnyxOS 1.0 Boot Menu

menuentry 'Start OnyxOS 1.0 - KDE Plasma (Live)' --class onyxos --class gnu-linux --class gnu --class os {
    linux /images/pxeboot/vmlinuz root=live:CDLABEL=OnyxOS-KDE-Live-10 rd.live.image quiet rhgb rd.luks=0 rd.md=0 rd.dm=0
    initrd /images/pxeboot/initrd.img
}
menuentry 'OnyxOS 1.0 - Mode sans echec' --class onyxos --class gnu-linux {
    linux /images/pxeboot/vmlinuz root=live:CDLABEL=OnyxOS-KDE-Live-10 rd.live.image rd.luks=0 rd.md=0 rd.dm=0 nomodeset 3
    initrd /images/pxeboot/initrd.img
}
menuentry 'Verifier le support OnyxOS' --class onyxos {
    linux /images/pxeboot/vmlinuz root=live:CDLABEL=OnyxOS-KDE-Live-10 rd.live.image rd.live.check quiet
    initrd /images/pxeboot/initrd.img
}
"""

EFI_GRUB = b"""set default="0"
set timeout=10
# OnyxOS 1.0 Boot Menu

menuentry 'Start OnyxOS 1.0 - KDE Plasma (Live)' --class onyxos --class gnu-linux --class gnu --class os {
    linuxefi /images/pxeboot/vmlinuz root=live:CDLABEL=OnyxOS-KDE-Live-10 rd.live.image quiet rhgb rd.luks=0 rd.md=0 rd.dm=0
    initrdefi /images/pxeboot/initrd.img
}
menuentry 'OnyxOS 1.0 - Mode sans echec' --class onyxos --class gnu-linux {
    linuxefi /images/pxeboot/vmlinuz root=live:CDLABEL=OnyxOS-KDE-Live-10 rd.live.image rd.luks=0 rd.md=0 rd.dm=0 nomodeset 3
    initrdefi /images/pxeboot/initrd.img
}
menuentry 'Verifier le support OnyxOS' --class onyxos {
    linuxefi /images/pxeboot/vmlinuz root=live:CDLABEL=OnyxOS-KDE-Live-10 rd.live.image rd.live.check quiet
    initrdefi /images/pxeboot/initrd.img
}
"""

EARLYBOOT = b'search --no-floppy --set=root -l "OnyxOS-KDE-Live-10"\n'

def find_and_inject(iso_data: bytearray, old_content: bytes, new_content: bytes, label: str):
    """Cherche old_content dans iso_data, remplace par new_content (même taille)."""
    idx = iso_data.find(old_content)
    if idx == -1:
        print(f"  NOT FOUND: {label}")
        return False
    # Pad ou tronquer new_content à la taille de old_content
    if len(new_content) < len(old_content):
        new_padded = new_content + b'\n' * (len(old_content) - len(new_content))
    else:
        new_padded = new_content[:len(old_content)]
    iso_data[idx:idx+len(old_content)] = new_padded
    print(f"  INJECTED at 0x{idx:08X}: {label} ({len(old_content)} bytes)")
    return True

print("=== Injection grub.cfg dans l'ISO ===")
print(f"ISO: {ISO} ({ISO.stat().st_size:,} bytes)")

# Lire les anciens contenus depuis les fichiers extraits
old_grub_bios    = (EXTRACTED / "boot" / "grub2" / "grub.cfg").read_bytes()
old_grub_efi     = (EXTRACTED / "EFI" / "BOOT" / "grub.cfg").read_bytes()
old_grub_efi_fed = (EXTRACTED / "EFI" / "fedora" / "grub.cfg").read_bytes()
old_earlyboot    = (EXTRACTED / "boot" / "grub2" / "earlyboot.cfg").read_bytes()

print(f"\nAncien BIOS grub.cfg  ({len(old_grub_bios)} bytes):\n{old_grub_bios[:200]!r}\n")
print(f"Ancien EFI grub.cfg   ({len(old_grub_efi)} bytes):\n{old_grub_efi[:200]!r}\n")
print(f"Ancien earlyboot.cfg  ({len(old_earlyboot)} bytes):\n{old_earlyboot!r}\n")

# Charger l'ISO en mémoire (3.5 GB — peut prendre du temps)
print("\nChargement ISO en mémoire (3.5 GB)...")
iso_data = bytearray(ISO.read_bytes())
print(f"Chargé: {len(iso_data):,} bytes")

# Injecter chaque fichier
n = 0
n += find_and_inject(iso_data, old_grub_bios,    BIOS_GRUB, "boot/grub2/grub.cfg (BIOS)")
n += find_and_inject(iso_data, old_grub_efi,     EFI_GRUB,  "EFI/BOOT/grub.cfg")
n += find_and_inject(iso_data, old_grub_efi_fed, EFI_GRUB,  "EFI/fedora/grub.cfg")
n += find_and_inject(iso_data, old_earlyboot,    EARLYBOOT,  "boot/grub2/earlyboot.cfg")

if n > 0:
    print(f"\nÉcriture ISO ({len(iso_data):,} bytes)...")
    ISO.write_bytes(iso_data)
    print(f"✓ {n} fichier(s) injecté(s) → {ISO}")
else:
    print("\nATTENTION: Aucune injection — les fichiers ont peut-être déjà été mis à jour.")

del iso_data
print("\nTerminé !")
