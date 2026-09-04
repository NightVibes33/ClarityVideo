#!/usr/bin/env python3
"""
Static-analysis helper for a user-supplied NVIDIA nvngx_dlssnr.dll.

This tool does NOT download, bundle, redistribute, patch, or execute NVIDIA binaries.
It inventories the PE image so ClarityVideo's DLSS 5 rehosting work can compare
runtime versions and identify the regions that require deeper interoperability work.

Usage:
    python Tools/dlss5_runtime_probe.py /path/to/nvngx_dlssnr.dll
    python Tools/dlss5_runtime_probe.py /path/to/nvngx_dlssnr.dll --json report.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import struct
import sys
from dataclasses import asdict, dataclass
from typing import Iterable


DLSSNR_KEY_RE = re.compile(rb"DLSSNR\.[A-Za-z0-9_.]{2,96}\x00")
ASCII_RE = re.compile(rb"[ -~]{6,}")

# CUDA fatbin wrapper magic values observed across CUDA toolchains. These are
# inventory hints only; a match is not treated as proof that a complete cubin
# begins at that byte without further parsing.
CUDA_FATBIN_MAGICS = {
    0x466243B1: "cuda-fatbin-v1",
    0xBA55ED50: "cuda-fatbin-wrapper",
}

ELF_MAGIC = b"\x7fELF"
PTX_MARKERS = (b".version ", b".target sm_", b".entry ")
SM_RE = re.compile(rb"sm_[0-9]{2,3}")
COMPUTE_RE = re.compile(rb"compute_[0-9]{2,3}")


@dataclass
class PESection:
    name: str
    virtual_address: int
    virtual_size: int
    raw_offset: int
    raw_size: int
    characteristics: int


@dataclass
class Marker:
    kind: str
    offset: int
    detail: str


@dataclass
class RuntimeReport:
    path: str
    size: int
    sha256: str
    machine: str
    pe_timestamp: int
    image_base: int
    sections: list[PESection]
    exports: list[str]
    dlssnr_keys: list[str]
    architecture_strings: list[str]
    cuda_markers: list[Marker]
    elf_markers: list[Marker]
    ptx_markers: list[Marker]
    notable_strings: list[str]


def u16(data: bytes, off: int) -> int:
    return struct.unpack_from("<H", data, off)[0]


def u32(data: bytes, off: int) -> int:
    return struct.unpack_from("<I", data, off)[0]


def u64(data: bytes, off: int) -> int:
    return struct.unpack_from("<Q", data, off)[0]


def c_string(data: bytes, off: int, limit: int = 512) -> str:
    if off < 0 or off >= len(data):
        return ""
    end = data.find(b"\x00", off, min(len(data), off + limit))
    if end < 0:
        end = min(len(data), off + limit)
    return data[off:end].decode("utf-8", errors="replace")


def machine_name(machine: int) -> str:
    return {
        0x014C: "x86",
        0x8664: "x86_64",
        0xAA64: "arm64",
    }.get(machine, f"0x{machine:04x}")


def parse_pe(data: bytes) -> tuple[int, int, int, list[PESection], int, int]:
    if len(data) < 0x100 or data[:2] != b"MZ":
        raise ValueError("not a PE file: missing MZ header")
    pe_off = u32(data, 0x3C)
    if pe_off + 24 > len(data) or data[pe_off:pe_off + 4] != b"PE\x00\x00":
        raise ValueError("not a PE file: missing PE signature")

    coff = pe_off + 4
    machine = u16(data, coff)
    section_count = u16(data, coff + 2)
    timestamp = u32(data, coff + 4)
    optional_size = u16(data, coff + 16)
    optional = coff + 20
    magic = u16(data, optional)
    if magic == 0x20B:
        image_base = u64(data, optional + 24)
        data_dir = optional + 112
    elif magic == 0x10B:
        image_base = u32(data, optional + 28)
        data_dir = optional + 96
    else:
        raise ValueError(f"unsupported PE optional-header magic 0x{magic:04x}")

    export_rva = u32(data, data_dir)
    export_size = u32(data, data_dir + 4)

    section_table = optional + optional_size
    sections: list[PESection] = []
    for index in range(section_count):
        off = section_table + index * 40
        if off + 40 > len(data):
            break
        raw_name = data[off:off + 8].split(b"\x00", 1)[0]
        name = raw_name.decode("ascii", errors="replace")
        sections.append(
            PESection(
                name=name,
                virtual_size=u32(data, off + 8),
                virtual_address=u32(data, off + 12),
                raw_size=u32(data, off + 16),
                raw_offset=u32(data, off + 20),
                characteristics=u32(data, off + 36),
            )
        )
    return machine, timestamp, image_base, sections, export_rva, export_size


def rva_to_offset(rva: int, sections: Iterable[PESection]) -> int | None:
    for section in sections:
        span = max(section.virtual_size, section.raw_size)
        if section.virtual_address <= rva < section.virtual_address + span:
            delta = rva - section.virtual_address
            if delta >= section.raw_size:
                return None
            return section.raw_offset + delta
    return None


def parse_exports(data: bytes, sections: list[PESection], export_rva: int, export_size: int) -> list[str]:
    if not export_rva or not export_size:
        return []
    export_off = rva_to_offset(export_rva, sections)
    if export_off is None or export_off + 40 > len(data):
        return []

    name_count = u32(data, export_off + 24)
    names_rva = u32(data, export_off + 32)
    names_off = rva_to_offset(names_rva, sections)
    if names_off is None:
        return []

    result: list[str] = []
    for index in range(min(name_count, 100_000)):
        ptr_off = names_off + index * 4
        if ptr_off + 4 > len(data):
            break
        name_rva = u32(data, ptr_off)
        name_off = rva_to_offset(name_rva, sections)
        if name_off is None:
            continue
        name = c_string(data, name_off)
        if name:
            result.append(name)
    return sorted(set(result))


def find_u32_markers(data: bytes) -> list[Marker]:
    markers: list[Marker] = []
    for magic, label in CUDA_FATBIN_MAGICS.items():
        needle = struct.pack("<I", magic)
        start = 0
        while True:
            off = data.find(needle, start)
            if off < 0:
                break
            markers.append(Marker(label, off, f"magic=0x{magic:08x}"))
            start = off + 1
    return markers


def find_elf_markers(data: bytes) -> list[Marker]:
    result: list[Marker] = []
    start = 0
    while True:
        off = data.find(ELF_MAGIC, start)
        if off < 0:
            break
        detail = "embedded ELF"
        if off + 20 <= len(data):
            klass = data[off + 4]
            endian = data[off + 5]
            detail += f" class={klass} endian={endian}"
        result.append(Marker("elf", off, detail))
        start = off + 1
    return result


def find_ptx_markers(data: bytes) -> list[Marker]:
    result: list[Marker] = []
    for marker in PTX_MARKERS:
        start = 0
        while True:
            off = data.find(marker, start)
            if off < 0:
                break
            result.append(Marker("ptx-text", off, marker.decode("ascii", errors="replace").strip()))
            start = off + 1
    return result


def unique_ascii_matches(regex: re.Pattern[bytes], data: bytes) -> list[str]:
    values = {
        match.group(0).rstrip(b"\x00").decode("ascii", errors="replace")
        for match in regex.finditer(data)
    }
    return sorted(values)


def notable_strings(data: bytes) -> list[str]:
    needles = (
        "DLSSNR",
        "CUDA",
        "cubin",
        "fatbin",
        "Tensor",
        "tensor",
        "network",
        "Network",
        "model",
        "Model",
        "NVSDK_NGX",
    )
    values: set[str] = set()
    for match in ASCII_RE.finditer(data):
        text = match.group(0).decode("ascii", errors="ignore")
        if any(needle in text for needle in needles):
            values.add(text[:300])
    return sorted(values)


def build_report(path: str) -> RuntimeReport:
    with open(path, "rb") as handle:
        data = handle.read()

    machine, timestamp, image_base, sections, export_rva, export_size = parse_pe(data)
    exports = parse_exports(data, sections, export_rva, export_size)
    dlssnr_keys = unique_ascii_matches(DLSSNR_KEY_RE, data)
    architectures = sorted(
        set(unique_ascii_matches(SM_RE, data) + unique_ascii_matches(COMPUTE_RE, data))
    )

    return RuntimeReport(
        path=os.path.abspath(path),
        size=len(data),
        sha256=hashlib.sha256(data).hexdigest(),
        machine=machine_name(machine),
        pe_timestamp=timestamp,
        image_base=image_base,
        sections=sections,
        exports=exports,
        dlssnr_keys=dlssnr_keys,
        architecture_strings=architectures,
        cuda_markers=find_u32_markers(data),
        elf_markers=find_elf_markers(data),
        ptx_markers=find_ptx_markers(data),
        notable_strings=notable_strings(data),
    )


def print_report(report: RuntimeReport) -> None:
    print("DLSS 5 runtime static inventory")
    print(f"path:        {report.path}")
    print(f"size:        {report.size:,} bytes")
    print(f"sha256:      {report.sha256}")
    print(f"machine:     {report.machine}")
    print(f"PE timestamp: 0x{report.pe_timestamp:08x}")
    print(f"image base:  0x{report.image_base:x}")
    print()

    print("PE sections:")
    for section in report.sections:
        print(
            f"  {section.name:8} RVA=0x{section.virtual_address:08x} "
            f"VSZ=0x{section.virtual_size:08x} RAW=0x{section.raw_offset:08x}+0x{section.raw_size:08x} "
            f"flags=0x{section.characteristics:08x}"
        )

    print(f"\nexports ({len(report.exports)}):")
    for value in report.exports:
        if "NGX" in value or "Snippet" in value or "Feature" in value:
            print(f"  {value}")

    print(f"\nDLSSNR parameter keys ({len(report.dlssnr_keys)}):")
    for value in report.dlssnr_keys:
        print(f"  {value}")

    print(f"\nGPU architecture strings ({len(report.architecture_strings)}):")
    for value in report.architecture_strings:
        print(f"  {value}")

    print(f"\nCUDA fatbin-like markers: {len(report.cuda_markers)}")
    for marker in report.cuda_markers[:200]:
        print(f"  0x{marker.offset:08x} {marker.kind} {marker.detail}")

    print(f"embedded ELF markers: {len(report.elf_markers)}")
    for marker in report.elf_markers[:200]:
        print(f"  0x{marker.offset:08x} {marker.detail}")

    print(f"PTX markers: {len(report.ptx_markers)}")
    for marker in report.ptx_markers[:200]:
        print(f"  0x{marker.offset:08x} {marker.detail}")

    if report.notable_strings:
        print(f"\nnotable strings ({len(report.notable_strings)}):")
        for value in report.notable_strings[:300]:
            print(f"  {value}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Inventory a user-supplied nvngx_dlssnr.dll")
    parser.add_argument("runtime", help="path to nvngx_dlssnr.dll")
    parser.add_argument("--json", dest="json_path", help="write machine-readable report")
    args = parser.parse_args(argv)

    try:
        report = build_report(args.runtime)
    except (OSError, ValueError, struct.error) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    print_report(report)
    if args.json_path:
        with open(args.json_path, "w", encoding="utf-8") as handle:
            json.dump(asdict(report), handle, indent=2, sort_keys=True)
            handle.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
