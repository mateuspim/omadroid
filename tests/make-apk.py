#!/usr/bin/env python3
"""Write an APK fixture for apk-label.py: a binary AndroidManifest.xml (UTF-8
string pool) and, for resource labels, a resources.arsc (UTF-16 pool). Only
the chunks apk-label.py reads are filled in; the names are made up.

Usage: make-apk.py OUT.apk VARIANT
  literal   android:label="Plain Notes" written in the manifest
  default   @string/app_name: "pt" config first, then the default "Example Keys"
  english   only "pt" and "en" configs; English wins
  offset16  default, with 16-bit entry offsets
  sparse    default, with a sparse entry table
  compact   default, with compact entries
  chained   app_name references a second string resource
  nolabel   <application> without android:label
Hostile APKs, each past one of apk-label.py's caps:
  bomb      a 9 MiB manifest of zeros, deflated to a few KiB
  liar      the bomb, its central directory declaring 100 bytes
  aggregate a 7 MiB manifest and a 58 MiB table: each fits, not both
  members   an end record declaring 60001 members
  zip64     an end record behind a ZIP64 locator
  bigdir    an end record declaring a 9 MiB central directory
  hugepool  a manifest whose string pool declares 2^28 strings
"""
import struct
import sys
import zipfile

LABEL_ID = 0x7F010000
ATTR_LABEL = 0x01010001
NO_INDEX = 0xFFFFFFFF


def chunk(kind: int, header: bytes, body: bytes) -> bytes:
    return struct.pack("<HHI", kind, 8 + len(header), 8 + len(header) + len(body)) + header + body


def pool(strings: list[str], utf8: bool) -> bytes:
    data = b""
    offsets = []
    for text in strings:
        offsets.append(len(data))
        if utf8:
            raw = text.encode()
            data += bytes([len(text), len(raw)]) + raw + b"\0"
        else:
            data += struct.pack("<H", len(text)) + text.encode("utf-16-le") + b"\0\0"
    data += b"\0" * (-len(data) % 4)
    table = struct.pack(f"<{len(offsets)}I", *offsets)
    header = struct.pack("<IIIII", len(strings), 0, 0x100 if utf8 else 0, 28 + len(table), 0)
    return chunk(0x0001, header, table + data)


def element(name: int, attributes: list[tuple[int, int, int, int]]) -> bytes:
    ext = struct.pack("<IIHHHHHH", NO_INDEX, name, 20, 20, len(attributes), 0, 0, 0)
    for attr_name, raw, kind, value in attributes:
        ext += struct.pack("<IIIHBBI", NO_INDEX, attr_name, raw, 8, 0, kind, value)
    return chunk(0x0102, struct.pack("<II", 1, NO_INDEX), ext)


def manifest(variant: str) -> bytes:
    strings = ["label", "package", "manifest", "application", "com.example.keys", "Plain Notes"]
    resource_map = chunk(0x0180, b"", struct.pack("<I", ATTR_LABEL))
    label = [(0, 5, 0x03, 5)] if variant == "literal" else [(0, NO_INDEX, 0x01, LABEL_ID)]
    application = element(3, [] if variant == "nolabel" else label)
    body = pool(strings, True) + resource_map + element(2, [(1, 4, 0x03, 4)]) + application
    return chunk(0x0003, b"", body)


def entries(values: list[tuple[int, int]], variant: str) -> tuple[int, bytes, bytes]:
    """(flags, offsets, entries) of one type chunk holding `values`."""
    if variant == "compact":
        data = b"".join(struct.pack("<HHI", 0, kind << 8 | 0x8, value) for kind, value in values)
        offsets = [8 * index for index in range(len(values))]
    else:
        data = b"".join(struct.pack("<HHI", 8, 0, 0) + struct.pack("<HBBI", 8, 0, kind, value) for kind, value in values)
        offsets = [16 * index for index in range(len(values))]
    if variant == "offset16":
        table = struct.pack(f"<{len(offsets)}H", *(offset // 4 for offset in offsets))
        return 0x02, table + b"\0" * (-len(table) % 4), data
    if variant == "sparse":
        return 0x01, b"".join(struct.pack("<HH", index, offset // 4) for index, offset in enumerate(offsets)), data
    return 0x00, struct.pack(f"<{len(offsets)}I", *offsets), data


def type_chunk(language: bytes, values: list[tuple[int, int]], variant: str) -> bytes:
    flags, offsets, data = entries(values, variant)
    config = struct.pack("<IHH2s", 64, 0, 0, language) + b"\0" * 54
    header = struct.pack("<BBHII", 1, flags, 0, len(values), 8 + 12 + len(config) + len(offsets)) + config
    return chunk(0x0201, header, offsets + data)


def resources(variant: str) -> bytes:
    strings = ["Teclado", "Example Keys", "Example Keys (en)"]
    configs = [(b"pt", [(0x03, 0)]), (b"\0\0", [(0x03, 1)])]
    if variant == "english":
        configs = [(b"pt", [(0x03, 0)]), (b"en", [(0x03, 2)])]
    if variant == "chained":
        configs = [(b"\0\0", [(0x01, LABEL_ID + 1), (0x03, 1)])]
    types = b"".join(type_chunk(language, values, variant) for language, values in configs)
    name = "com.example.keys".encode("utf-16-le").ljust(256, b"\0")
    package_header = struct.pack("<I", 0x7F) + name + struct.pack("<IIIII", 0, 0, 0, 0, 0)
    package = chunk(0x0200, package_header, pool(["string"], False) + pool(["app_name"], False) + types)
    return chunk(0x0002, struct.pack("<I", 1), pool(strings, False) + package)


MIB = 1024 * 1024


def end_record(count: int, directory: int) -> bytes:
    return b"PK\x05\x06" + struct.pack("<HHHHIIH", 0, 0, count, count, directory, 0, 0)


def write_hostile(out: str, variant: str) -> bool:
    """Write a hostile variant; False when `variant` isn't one."""
    raw = {
        "members": lambda: end_record(60001, 0),
        "zip64": lambda: b"PK\x06\x07" + b"\0" * 16 + end_record(1, 0),
        "bigdir": lambda: end_record(1, 9 * MIB),
    }
    if variant in raw:
        with open(out, "wb") as apk:
            apk.write(raw[variant]())
        return True
    members = {
        "bomb": {"AndroidManifest.xml": b"\0" * 9 * MIB},
        "liar": {"AndroidManifest.xml": b"\0" * 9 * MIB},
        "aggregate": {"AndroidManifest.xml": manifest("default") + b"\0" * 7 * MIB, "resources.arsc": resources("default") + b"\0" * 58 * MIB},
        "hugepool": {"AndroidManifest.xml": bytearray(manifest("literal"))},
    }
    if variant not in members:
        return False
    if variant == "hugepool":
        # The manifest's first chunk is its string pool; its count at +8.
        struct.pack_into("<I", members[variant]["AndroidManifest.xml"], 8 + 8, 1 << 28)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as apk:
        for name, content in members[variant].items():
            apk.writestr(name, bytes(content))
    if variant == "liar":
        lie_about_size(out)
    return True


def lie_about_size(out: str) -> None:
    """Rewrite the central directory's uncompressed size to 100 bytes."""
    with open(out, "r+b") as apk:
        blob = apk.read()
        apk.seek(blob.rfind(b"PK\x01\x02") + 24)
        apk.write(struct.pack("<I", 100))


def main() -> None:
    out, variant = sys.argv[1], sys.argv[2]
    if write_hostile(out, variant):
        return
    with zipfile.ZipFile(out, "w") as apk:
        apk.writestr("AndroidManifest.xml", manifest(variant))
        if variant not in ("literal", "nolabel"):
            apk.writestr("resources.arsc", resources(variant))


if __name__ == "__main__":
    main()
