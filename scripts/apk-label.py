#!/usr/bin/env python3
"""Print an APK's application label, read from its binary AndroidManifest.xml
and, when the label is a string resource, its resources.arsc.

Apps without a launcher icon (a keyboard, a system service) aren't named by
`scrcpy --list-apps`, and no adb shell command prints a label, so the Sound
tab reads it from the APK the device runs. The default-locale string wins,
then English, then any other.

Usage: apk-label.py base.apk → "Samsung Keyboard"
"""
import struct
import sys
import zipfile

XML_START_ELEMENT = 0x0102
XML_RESOURCE_MAP = 0x0180
STRING_POOL = 0x0001
TABLE_PACKAGE = 0x0200
TABLE_TYPE = 0x0201
UTF8_FLAG = 0x100
ATTR_LABEL = 0x01010001
TYPE_REFERENCE = 0x01
TYPE_STRING = 0x03
ENTRY_COMPLEX = 0x0001
ENTRY_COMPACT = 0x0008
TYPE_SPARSE = 0x01
TYPE_OFFSET16 = 0x02
NO_ENTRY = 0xFFFFFFFF
MAX_LABEL = 60


class ApkError(Exception):
    pass


def chunks(blob: bytes, start: int, end: int):
    """Yield (type, offset, header size, size) for each chunk in blob[start:end].

    Example: for kind, at, header, size in chunks(arsc, 12, len(arsc)): ...
    """
    while start + 8 <= end:
        kind, header, size = struct.unpack_from("<HHI", blob, start)
        if size < 8 or start + size > end:
            raise ApkError(f"chunk 0x{kind:04x} at {start} has size {size}; expected 8..{end - start}")
        yield kind, start, header, size
        start += size


def string_length(blob: bytes, at: int, utf8: bool) -> tuple[int, int]:
    """(length, bytes used) of a pool string's length prefix."""
    if utf8:
        first = blob[at]
        return ((first & 0x7F) << 8 | blob[at + 1], 2) if first & 0x80 else (first, 1)
    first = struct.unpack_from("<H", blob, at)[0]
    if first & 0x8000:
        return (first & 0x7FFF) << 16 | struct.unpack_from("<H", blob, at + 2)[0], 4
    return first, 2


def read_pool(blob: bytes, at: int) -> list[str]:
    """Decode the string pool chunk at `at`.

    Example: read_pool(manifest, 8)[0] → "versionCode"
    """
    _, header, _, count, _, flags, strings_start, _ = struct.unpack_from("<HHIIIIII", blob, at)
    utf8 = bool(flags & UTF8_FLAG)
    offsets = struct.unpack_from(f"<{count}I", blob, at + header)
    return [pool_string(blob, at + strings_start + offset, utf8) for offset in offsets]


def pool_string(blob: bytes, at: int, utf8: bool) -> str:
    if utf8:
        _, used = string_length(blob, at, True)  # length in UTF-16 units
        size, more = string_length(blob, at + used, True)
        start = at + used + more
        return blob[start : start + size].decode("utf-8", "replace")
    size, used = string_length(blob, at, False)
    return blob[at + used : at + used + 2 * size].decode("utf-16-le", "replace")


def manifest_label(manifest: bytes) -> tuple[int, int | str]:
    """(TYPE_STRING, text) or (TYPE_REFERENCE, resource id) of <application
    android:label>, found by its attribute resource id, as obfuscated
    manifests may drop attribute names.

    Example: manifest_label(zip.read("AndroidManifest.xml")) → (1, 0x7F0F0012)
    """
    strings: list[str] = []
    ids: tuple[int, ...] = ()
    for kind, at, header, size in chunks(manifest, 8, len(manifest)):
        if kind == STRING_POOL:
            strings = read_pool(manifest, at)
        elif kind == XML_RESOURCE_MAP:
            ids = struct.unpack_from(f"<{(size - header) // 4}I", manifest, at + header)
        elif kind == XML_START_ELEMENT and element_name(manifest, at + header, strings) == "application":
            return application_label(manifest, at + header, strings, ids)
    raise ApkError("the manifest has no <application> element")


def element_name(manifest: bytes, ext: int, strings: list[str]) -> str:
    name = struct.unpack_from("<I", manifest, ext + 4)[0]
    return strings[name] if name < len(strings) else ""


def application_label(manifest: bytes, ext: int, strings: list[str], ids: tuple[int, ...]) -> tuple[int, int | str]:
    start, size, count = struct.unpack_from("<HHH", manifest, ext + 8)
    for index in range(count):
        at = ext + start + index * size
        name, raw, kind, value = struct.unpack_from("<4xII3xBI", manifest, at)
        if name >= len(ids) or ids[name] != ATTR_LABEL:
            continue
        if kind == TYPE_REFERENCE:
            return TYPE_REFERENCE, value
        if kind == TYPE_STRING or raw != NO_ENTRY:
            return TYPE_STRING, strings[value if kind == TYPE_STRING else raw]
    raise ApkError("<application> has no android:label")


def table_values(arsc: bytes, resource: int) -> tuple[list[str], list[tuple[bytes, int, int]]]:
    """The table's global string pool, and (language, value type, value data)
    of `resource` in every config of resources.arsc.

    Example: table_values(arsc, 0x7F0F0012) → (pool, [(b"\\0\\0", 3, 41), (b"pt", 3, 42)])
    """
    package, kind, entry = resource >> 24, (resource >> 16) & 0xFF, resource & 0xFFFF
    pool: list[str] = []
    found: list[tuple[bytes, int, int]] = []
    for chunk, at, header, size in chunks(arsc, 12, len(arsc)):
        if chunk == STRING_POOL:
            pool = read_pool(arsc, at)
        elif chunk == TABLE_PACKAGE and struct.unpack_from("<I", arsc, at + 8)[0] == package:
            found += package_values(arsc, at + header, at + size, kind, entry)
    return pool, found


def package_values(arsc: bytes, start: int, end: int, kind: int, entry: int) -> list[tuple[bytes, int, int]]:
    found = []
    for chunk, at, header, _ in chunks(arsc, start, end):
        if chunk != TABLE_TYPE or arsc[at + 8] != kind:
            continue
        value = type_entry(arsc, at, header, entry)
        if value is not None:
            found.append((arsc[at + 20 + 8 : at + 20 + 10], *value))
    return found


def entry_offset(arsc: bytes, at: int, header: int, entry: int) -> int | None:
    """Byte offset of `entry` from the type chunk's entries, or None."""
    flags, count = arsc[at + 9], struct.unpack_from("<I", arsc, at + 12)[0]
    if flags & TYPE_SPARSE:
        for index in range(count):
            key, offset = struct.unpack_from("<HH", arsc, at + header + 4 * index)
            if key == entry:
                return offset * 4
        return None
    if entry >= count:
        return None
    if flags & TYPE_OFFSET16:
        offset = struct.unpack_from("<H", arsc, at + header + 2 * entry)[0]
        return None if offset == 0xFFFF else offset * 4
    offset = struct.unpack_from("<I", arsc, at + header + 4 * entry)[0]
    return None if offset == NO_ENTRY else offset


def type_entry(arsc: bytes, at: int, header: int, entry: int) -> tuple[int, int] | None:
    """(value type, data) of a simple entry in one type chunk, or None."""
    offset = entry_offset(arsc, at, header, entry)
    if offset is None:
        return None
    where = at + struct.unpack_from("<I", arsc, at + 16)[0] + offset
    size, flags = struct.unpack_from("<HH", arsc, where)
    if flags & ENTRY_COMPACT:
        return flags >> 8, struct.unpack_from("<I", arsc, where + 4)[0]
    if flags & ENTRY_COMPLEX:
        return None
    return struct.unpack_from("<3xBI", arsc, where + size)


def preferred(values: list[tuple[bytes, int, int]]) -> tuple[int, int]:
    """Default locale first, then English, then whatever is there."""
    rank = {b"\0\0": 0, b"en": 1}
    _, kind, data = min(values, key=lambda value: rank.get(value[0], 2))
    return kind, data


def resource_string(arsc: bytes, resource: int) -> str:
    """Follow `resource` (and up to 4 references) to a string.

    Example: resource_string(arsc, 0x7F0F0012) → "Samsung Keyboard"
    """
    for _ in range(5):
        pool, values = table_values(arsc, resource)
        if not values:
            raise ApkError(f"resource 0x{resource:08x} isn't in resources.arsc")
        kind, data = preferred(values)
        if kind == TYPE_STRING and data < len(pool):
            return pool[data]
        if kind != TYPE_REFERENCE:
            raise ApkError(f"resource 0x{resource:08x} has value type 0x{kind:02x}; expected a string")
        resource = data
    raise ApkError(f"resource 0x{resource:08x} references too deep")


def apk_label(path: str) -> str:
    """The label of the APK at `path`, on one line.

    Example: apk_label("/tmp/base.apk") → "Samsung Keyboard"
    """
    with zipfile.ZipFile(path) as apk:
        kind, label = manifest_label(apk.read("AndroidManifest.xml"))
        if kind == TYPE_REFERENCE:
            label = resource_string(apk.read("resources.arsc"), label)
    # One line for the status output: control characters become spaces.
    label = " ".join("".join(c if c.isprintable() else " " for c in str(label)).split())[:MAX_LABEL]
    if not label:
        raise ApkError("the label is empty")
    return label


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: apk-label.py APK; got {sys.argv[1:]}", file=sys.stderr)
        return 1
    try:
        print(apk_label(sys.argv[1]))
    except (ApkError, KeyError, OSError, zipfile.BadZipFile, struct.error, IndexError, UnicodeError) as error:
        print(f"{sys.argv[1]}: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
