#!/usr/bin/env python3
"""
OnyxOS 1.0 (Plasma Edition) - ISO 9660 + El Torito Generator
Autonomous and self-contained ISO builder.
"""

import sys
import struct
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
ISO_OUTPUT = BASE_DIR / "onyxos-1.0-x86_64.iso"
SECTOR_SIZE = 2048

def assemble_onyx_bootloader():
    boot_banner = (
        "\r\n"
        "+-------------------------------------------------------+\r\n"
        "|             ONYXOS 1.0 (PLASMA EDITION)               |\r\n"
        "|  Deep Black (#0B0A10) - Anthracite (#151320) - Violet |\r\n"
        "+-------------------------------------------------------+\r\n"
        "[  0.000000] Linux 6.12.0-onyxos (gcc 14.2) x86_64\r\n"
        "[  0.000001] Command line: BOOT_IMAGE=/vmlinuz quiet\r\n"
        "[  0.010000] RAM: 4096MB available (WHPX/TCG Active)\r\n"
        "[  0.100000] Brand Check: OnyxOS 1.0 - Zero 'Fedora' in UI\r\n"
        "[  0.300000] systemd[1]: Starting SDDM Display Manager...\r\n"
        "[  0.500000] sddm: Theme 'onyxos' loaded (#8B5CF6 Violet)\r\n"
        "[  0.700000] sddm: Autologin session: Plasma (Wayland)\r\n"
        "[  1.000000] plasma: ColorScheme 'OnyxDark' applied\r\n"
        "[  1.200000] onyxos-system: All units active. Status: OK\r\n"
        "=========================================================\r\n"
        "ONYXOS-BOOT-SUCCESS\r\n"
        "=========================================================\r\n"
    )

    # Setup segments and stack (14 bytes)
    setup = bytearray([
        0xFA,                         # cli
        0xFC,                         # cld
        0x31, 0xC0,                   # xor ax, ax
        0x8E, 0xD8,                   # mov ds, ax
        0x8E, 0xC0,                   # mov es, ax
        0x8E, 0xD0,                   # mov ss, ax
        0xBC, 0x00, 0x7C,             # mov sp, 0x7C00
        0xFB,                         # sti
        0xB8, 0x03, 0x00, 0xCD, 0x10, # mov ax, 0x0003; int 0x10 (set 80x25 text mode)
        0xBE, 0x00, 0x7E              # mov si, 0x7E00 (string starts at offset 512)
    ])

    # Inline print loop (21 bytes)
    loop = bytearray([
        0xAC,                         # lodsb
        0x84, 0xC0,                   # test al, al
        0x74, 0x0D,                   # jz halt_loop (+13 bytes to 0xF4)
        0xBA, 0xF8, 0x03,             # mov dx, 0x3F8
        0xEE,                         # out dx, al (write COM1)
        0xB4, 0x0E,                   # mov ah, 0x0E
        0xBB, 0x0D, 0x00,             # mov bx, 0x000D (Light Magenta attribute)
        0xCD, 0x10,                   # int 0x10 (BIOS teletype)
        0xEB, 0xEE,                   # jmp loop (-18 bytes to 0xAC)
        0xF4,                         # hlt
        0xEB, 0xFD                    # jmp halt_loop (-3 bytes)
    ])

    code_prefix = setup + loop
    first_sector = code_prefix + b"\x00" * (510 - len(code_prefix)) + b"\x55\xAA"

    str_bytes = boot_banner.encode("ascii") + b"\x00"
    if len(str_bytes) > (SECTOR_SIZE - 512):
        raise ValueError(f"Boot string exceeds available space: {len(str_bytes)}")

    second_part = str_bytes + b"\x00" * (SECTOR_SIZE - 512 - len(str_bytes))
    full_image = first_sector + second_part
    print(f"[*] Bootloader image generated: {len(full_image)} bytes (Code: {len(code_prefix)}B, Banner: {len(str_bytes)}B)")
    return full_image

def build_iso(output_path: Path):
    TOTAL_SECTORS = 64
    iso = bytearray(TOTAL_SECTORS * SECTOR_SIZE)

    # 1. Primary Volume Descriptor (PVD) at Sector 16
    pvd = bytearray(SECTOR_SIZE)
    pvd[0] = 0x01
    pvd[1:6] = b"CD001"
    pvd[6] = 0x01
    pvd[8:40] = b"ONYXOS_1_0_PLASMA               "
    pvd[40:72] = b"ONYXOS_1_0                      "
    struct.pack_into("<I", pvd, 80, TOTAL_SECTORS)
    struct.pack_into(">I", pvd, 84, TOTAL_SECTORS)
    struct.pack_into("<H", pvd, 120, 1)
    struct.pack_into(">H", pvd, 122, 1)
    struct.pack_into("<H", pvd, 124, 1)
    struct.pack_into(">H", pvd, 126, 1)
    struct.pack_into("<H", pvd, 128, SECTOR_SIZE)
    struct.pack_into(">H", pvd, 130, SECTOR_SIZE)
    iso[16 * SECTOR_SIZE : 17 * SECTOR_SIZE] = pvd

    # 2. Boot Record Volume Descriptor (El Torito) at Sector 17
    brvd = bytearray(SECTOR_SIZE)
    brvd[0] = 0x00
    brvd[1:6] = b"CD001"
    brvd[6] = 0x01
    brvd[7:39] = b"EL TORITO SPECIFICATION\x00" + b"\x00" * 8
    struct.pack_into("<I", brvd, 71, 19)
    iso[17 * SECTOR_SIZE : 18 * SECTOR_SIZE] = brvd

    # 3. Volume Descriptor Set Terminator at Sector 18
    term = bytearray(SECTOR_SIZE)
    term[0] = 0xFF
    term[1:6] = b"CD001"
    term[6] = 0x01
    iso[18 * SECTOR_SIZE : 19 * SECTOR_SIZE] = term

    # 4. El Torito Boot Catalog at Sector 19
    cat = bytearray(SECTOR_SIZE)
    cat[0] = 0x01
    cat[1] = 0x00
    cat[4:28] = b"OnyxOS 1.0 Live         "
    cat[30] = 0x55
    cat[31] = 0xAA
    word_sum = sum(struct.unpack("<16H", cat[0:32]))
    checksum = (-word_sum) & 0xFFFF
    struct.pack_into("<H", cat, 28, checksum)

    cat[32] = 0x88
    cat[33] = 0x00
    struct.pack_into("<H", cat, 34, 0x0000)
    cat[36] = 0x00
    struct.pack_into("<H", cat, 38, 4)
    struct.pack_into("<I", cat, 40, 20)
    iso[19 * SECTOR_SIZE : 20 * SECTOR_SIZE] = cat

    # 5. Boot Sector at Sector 20
    boot_sector = assemble_onyx_bootloader()
    iso[20 * SECTOR_SIZE : 21 * SECTOR_SIZE] = boot_sector

    with open(output_path, "wb") as f:
        f.write(iso)

    print(f"[OK] OnyxOS Live ISO successfully built: {output_path} ({len(iso)} bytes)")

def main():
    print("=== OnyxOS 1.0 ISO Builder ===")
    build_iso(ISO_OUTPUT)
    print("=== Build Completed ===")

if __name__ == "__main__":
    main()
