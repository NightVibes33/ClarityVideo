#!/usr/bin/env python3
"""
Extract embedded ELF images (including CUDA cubins) from a user-supplied
nvngx_dlssnr.dll for interoperability research.

The tool never downloads NVIDIA files. It only analyzes a local runtime supplied
by the user and writes carved images to a directory they choose.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import struct
import sys
from dataclasses import dataclass, asdict

ELF_MAGIC = b"\x7fELF"
EM_CUDA = 190


@dataclass
class EmbeddedELF:
    offset: int
    size: int
    elf_class: int
    endian: int
    machine: int
    machine_name: str
    sha256: str
    output_file: str


def u16(data: bytes, off: int, endian: str) -> int:
    return struct.unpack_from(endian + "H", data, off)[0]


def u32(data: bytes, off: int, endian: str) -> int:
    return struct.unpack_from(endian + "I", data, off)[0]


def u64(data: bytes, off: int, endian: str) -> int:
    return struct.unpack_from(endian + "Q", data, off)[0]


def machine_name(machine: int) -> str:
    if machine == EM_CUDA:
        return "CUDA"
    return f"ELF_MACHINE_{machine}"


def elf_extent(data: bytes, start: int) -> tuple[int, int, int, int] | None:
    if start + 0x40 > len(data) or data[start:start + 4] != ELF_MAGIC:
        return None

    elf_class = data[start + 4]
    data_encoding = data[start + 5]
    if data_encoding == 1:
        endian = "<"
    elif data_encoding == 2:
        endian = ">"
    else:
        return None

    try:
        machine = u16(data, start + 18, endian)
        if elf_class == 2:  # ELF64
            phoff = u64(data, start + 32, endian)
            shoff = u64(data, start + 40, endian)
            phentsize = u16(data, start + 54, endian)
            phnum = u16(data, start + 56, endian)
            shentsize = u16(data, start + 58, endian)
            shnum = u16(data, start + 60, endian)
            sh_offset_field = 24
            sh_size_field = 32
            sh_field_size = 8
            p_offset_field = 8
            p_filesz_field = 32
            p_field_size = 8
        elif elf_class == 1:  # ELF32
            phoff = u32(data, start + 28, endian)
            shoff = u32(data, start + 32, endian)
            phentsize = u16(data, start + 42, endian)
            phnum = u16(data, start + 44, endian)
            shentsize = u16(data, start + 46, endian)
            shnum = u16(data, start + 48, endian)
            sh_offset_field = 16
            sh_size_field = 20
            sh_field_size = 4
            p_offset_field = 4
            p_filesz_field = 16
            p_field_size = 4
        else:
            return None

        max_end = 0
        for i in range(phnum):
            off = start + phoff + i * phentsize
            if off < start or off + phentsize > len(data):
                break
            if p_field_size == 8:
                file_off = u64(data, off + p_offset_field, endian)
                file_size = u64(data, off + p_filesz_field, endian)
            else:
                file_off = u32(data, off + p_offset_field, endian)
                file_size = u32(data, off + p_filesz_field, endian)
            max_end = max(max_end, file_off + file_size)

        for i in range(shnum):
            off = start + shoff + i * shentsize
            if off < start or off + shentsize > len(data):
                break
            if sh_field_size == 8:
                file_off = u64(data, off + sh_offset_field, endian)
                file_size = u64(data, off + sh_size_field, endian)
            else:
                file_off = u32(data, off + sh_offset_field, endian)
                file_size = u32(data, off + sh_size_field, endian)
            max_end = max(max_end, file_off + file_size)

        header_end = max(
            0x40 if elf_class == 2 else 0x34,
            phoff + phentsize * phnum,
            shoff + shentsize * shnum,
        )
        size = max(max_end, header_end)
        if size <= 0 or start + size > len(data):
            return None
        return size, elf_class, data_encoding, machine
    except (struct.error, OverflowError):
        return None


def scan(data: bytes, output_dir: str) -> list[EmbeddedELF]:
    os.makedirs(output_dir, exist_ok=True)
    results: list[EmbeddedELF] = []
    cursor = 0
    seen_hashes: set[str] = set()

    while True:
        offset = data.find(ELF_MAGIC, cursor)
        if offset < 0:
            break
        cursor = offset + 1
        parsed = elf_extent(data, offset)
        if parsed is None:
            continue
        size, elf_class, endian, machine = parsed
        blob = data[offset:offset + size]
        digest = hashlib.sha256(blob).hexdigest()
        if digest in seen_hashes:
            continue
        seen_hashes.add(digest)

        kind = "cuda" if machine == EM_CUDA else f"elf{machine}"
        filename = f"{len(results):04d}_{kind}_0x{offset:08x}_{digest[:12]}.elf"
        destination = os.path.join(output_dir, filename)
        with open(destination, "wb") as handle:
            handle.write(blob)

        results.append(
            EmbeddedELF(
                offset=offset,
                size=size,
                elf_class=elf_class,
                endian=endian,
                machine=machine,
                machine_name=machine_name(machine),
                sha256=digest,
                output_file=filename,
            )
        )
    return results


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Carve embedded ELF/CUDA cubin images from a local nvngx_dlssnr.dll"
    )
    parser.add_argument("runtime", help="path to the user-supplied nvngx_dlssnr.dll")
    parser.add_argument("output_dir", help="directory for extracted ELF images")
    args = parser.parse_args(argv)

    try:
        with open(args.runtime, "rb") as handle:
            data = handle.read()
        results = scan(data, args.output_dir)
    except OSError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    manifest = {
        "runtime": os.path.abspath(args.runtime),
        "runtime_sha256": hashlib.sha256(data).hexdigest(),
        "embedded_elf_count": len(results),
        "cuda_cubin_count": sum(1 for item in results if item.machine == EM_CUDA),
        "images": [asdict(item) for item in results],
    }
    manifest_path = os.path.join(args.output_dir, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")

    print(f"runtime sha256: {manifest['runtime_sha256']}")
    print(f"embedded ELF images: {manifest['embedded_elf_count']}")
    print(f"CUDA cubins: {manifest['cuda_cubin_count']}")
    print(f"manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
