#!/usr/bin/env python3
"""Print the IAudioService binder transaction codes OmaDroid calls with
`service call audio`, read from a device's /system/framework/framework.jar.

Samsung's per-app volume and Android's master mute have no shell command, and
their codes change with every firmware, so they are read from the dex the
device runs. A wrong code calls some other audio method (a call with too few
arguments still runs, reading zeros), so this refuses anything it can't check:
every TRANSACTION_* field must decode as an int, the codes must be exactly
1..N, the interface descriptor must match, and each wanted method's proxy
signature must be the expected one.

Usage: audio-codes.py framework.jar → lines like "setAppVolume=293"
"""
import struct
import sys
import zipfile
from typing import NamedTuple

STUB = "Landroid/media/IAudioService$Stub;"
PROXY = "Landroid/media/IAudioService$Stub$Proxy;"
DESCRIPTOR = "android.media.IAudioService"
STRING = "Ljava/lang/String;"
# Method → (return type, parameter types) as `service call` arguments are written.
WANTED: dict[str, tuple[str, tuple[str, ...]]] = {
    "getStreamVolume": ("I", ("I",)),
    "getAppVolume": ("I", ("I",)),
    "setAppVolume": ("V", ("I", "I", STRING)),
    "isAppMute": ("Z", ("I",)),
    "setAppMute": ("V", ("I", "Z", STRING)),
    "isMasterMute": ("Z", ()),
    "setMasterMute": ("V", ("Z", "I", STRING, "I", STRING)),
}
VALUE_INT = 0x04
VALUE_STRING = 0x17
# Encoded values without payload bytes; misreading their size shifted every
# later field during the 2026-10-16 probe.
NO_PAYLOAD = (0x1E, 0x1F)


class DexFormatError(ValueError):
    pass


class EncodedValue(NamedTuple):
    kind: int
    value: int


class Dex:
    """Index tables of one classes*.dex. Example: Dex(data).type_name(0) → "I"."""

    def __init__(self, data: bytes) -> None:
        if not data.startswith(b"dex\n"):
            raise DexFormatError(f"not a dex file: starts with {data[:8]!r}, expected b'dex\\n'")
        self.data = data
        self.strings = self.table(0x38)
        self.types = self.table(0x40)
        self.protos = self.table(0x48)
        self.fields = self.table(0x50)
        self.methods = self.table(0x58)
        self.classes = self.table(0x60)

    def table(self, header_offset: int) -> tuple[int, int]:
        return struct.unpack_from("<II", self.data, header_offset)

    def u32(self, offset: int) -> int:
        return struct.unpack_from("<I", self.data, offset)[0]

    def string(self, index: int) -> str:
        offset = self.u32(self.strings[1] + 4 * index)
        _, offset = uleb128(self.data, offset)
        end = self.data.index(0, offset)
        return self.data[offset:end].decode("utf-8", "replace")

    def type_name(self, index: int) -> str:
        return self.string(self.u32(self.types[1] + 4 * index))

    def proto(self, index: int) -> tuple[str, tuple[str, ...]]:
        _, return_type, params = struct.unpack_from("<III", self.data, self.protos[1] + 12 * index)
        if not params:
            return self.type_name(return_type), ()
        count = self.u32(params)
        names = (self.type_name(struct.unpack_from("<H", self.data, params + 4 + 2 * k)[0]) for k in range(count))
        return self.type_name(return_type), tuple(names)

    def field(self, index: int) -> tuple[str, str]:
        _, type_index, name = struct.unpack_from("<HHI", self.data, self.fields[1] + 8 * index)
        return self.type_name(type_index), self.string(name)

    def method(self, index: int) -> tuple[str, tuple[str, tuple[str, ...]]]:
        _, proto, name = struct.unpack_from("<HHI", self.data, self.methods[1] + 8 * index)
        return self.string(name), self.proto(proto)

    def class_def(self, descriptor: str) -> tuple[int, int] | None:
        """(class_data_off, static_values_off) of a class, or None."""
        count, offset = self.classes
        for k in range(count):
            fields = struct.unpack_from("<8I", self.data, offset + 32 * k)
            if self.type_name(fields[0]) == descriptor:
                return fields[6], fields[7]
        return None


def uleb128(data: bytes, offset: int) -> tuple[int, int]:
    """Decode one ULEB128. Example: uleb128(b"\\xe5\\x8e\\x26", 0) → (624485, 3)."""
    result = shift = 0
    while True:
        byte = data[offset]
        offset += 1
        result |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:
            return result, offset


def encoded_array(data: bytes, offset: int) -> list[EncodedValue]:
    """Decode a static-values encoded_array; ints are sign-extended."""
    count, offset = uleb128(data, offset)
    values = []
    for _ in range(count):
        header = data[offset]
        offset += 1
        kind, arg = header & 0x1F, header >> 5
        if kind in NO_PAYLOAD:
            values.append(EncodedValue(kind, arg))
            continue
        if kind in (0x1C, 0x1D):
            raise DexFormatError(f"array/annotation static value at {offset - 1}; expected scalars only")
        raw = data[offset:offset + arg + 1]
        offset += arg + 1
        values.append(EncodedValue(kind, int.from_bytes(raw, "little", signed=kind == VALUE_INT)))
    return values


def class_members(dex: Dex, class_data: int) -> tuple[list[int], list[int]]:
    """Static field ids and all method ids listed in a class_data_item."""
    offset = class_data
    sizes = []
    for _ in range(4):
        size, offset = uleb128(dex.data, offset)
        sizes.append(size)
    static_fields, offset = member_ids(dex.data, offset, sizes[0], 2)
    _, offset = member_ids(dex.data, offset, sizes[1], 2)
    direct, offset = member_ids(dex.data, offset, sizes[2], 3)
    virtual, _ = member_ids(dex.data, offset, sizes[3], 3)
    return static_fields, direct + virtual


def member_ids(data: bytes, offset: int, count: int, width: int) -> tuple[list[int], int]:
    """Members are index diffs followed by width-1 more ULEB128 values each."""
    ids, index = [], 0
    for _ in range(count):
        diff, offset = uleb128(data, offset)
        for _ in range(width - 1):
            _, offset = uleb128(data, offset)
        index += diff
        ids.append(index)
    return ids, offset


def transaction_codes(dex: Dex, class_data: int, static_values: int) -> dict[str, int]:
    """TRANSACTION_<method> → code, after checking the whole table decodes cleanly."""
    field_ids, _ = class_members(dex, class_data)
    values = encoded_array(dex.data, static_values) if static_values else []
    codes, descriptor = {}, None
    for position, field_id in enumerate(field_ids):
        field_type, name = dex.field(field_id)
        value = values[position] if position < len(values) else None
        if name == "DESCRIPTOR" and value and value.kind == VALUE_STRING:
            descriptor = dex.string(value.value)
        if not name.startswith("TRANSACTION_"):
            continue
        if field_type != "I" or value is None or value.kind != VALUE_INT:
            raise DexFormatError(f"{name} decoded as {value}; expected an int constant")
        codes[name[len("TRANSACTION_"):]] = value.value
    check_table(codes, descriptor)
    return codes


def check_table(codes: dict[str, int], descriptor: str | None) -> None:
    if descriptor != DESCRIPTOR:
        raise DexFormatError(f"Stub DESCRIPTOR is {descriptor!r}; expected {DESCRIPTOR!r}")
    if sorted(codes.values()) != list(range(1, len(codes) + 1)):
        raise DexFormatError(f"{len(codes)} transaction codes aren't exactly 1..{len(codes)}")


def proxy_signatures(dex: Dex, class_data: int) -> dict[str, list[tuple[str, tuple[str, ...]]]]:
    """Method name → every signature the proxy has for it (overloads included)."""
    _, method_ids = class_members(dex, class_data)
    signatures: dict[str, list[tuple[str, tuple[str, ...]]]] = {}
    for method_id in method_ids:
        name, proto = dex.method(method_id)
        signatures.setdefault(name, []).append(proto)
    return signatures


def checked_codes(codes: dict[str, int], signatures: dict[str, list[tuple[str, tuple[str, ...]]]]) -> dict[str, int]:
    """Wanted methods whose only proxy signature is the expected one."""
    return {name: codes[name] for name, proto in WANTED.items() if name in codes and signatures.get(name) == [proto]}


def find_class(dexes: list[Dex], descriptor: str) -> tuple[Dex, int, int]:
    for dex in dexes:
        found = dex.class_def(descriptor)
        if found and found[0]:
            return dex, found[0], found[1]
    raise DexFormatError(f"{descriptor} not found in {len(dexes)} dex files")


def audio_codes(jar_path: str) -> dict[str, int]:
    """Example: audio_codes("framework.jar") → {"getStreamVolume": 27, "setAppVolume": 293, …}."""
    with zipfile.ZipFile(jar_path) as jar:
        names = sorted(n for n in jar.namelist() if n.startswith("classes") and n.endswith(".dex"))
        dexes = [Dex(jar.read(name)) for name in names]
    stub, stub_data, stub_values = find_class(dexes, STUB)
    proxy, proxy_data, _ = find_class(dexes, PROXY)
    return checked_codes(transaction_codes(stub, stub_data, stub_values), proxy_signatures(proxy, proxy_data))


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"Usage: {argv[0]} framework.jar; got {argv[1:]}", file=sys.stderr)
        return 1
    try:
        codes = audio_codes(argv[1])
    except (OSError, zipfile.BadZipFile, DexFormatError, struct.error, IndexError) as error:
        print(f"Couldn't read audio codes from {argv[1]}: {error}", file=sys.stderr)
        return 2
    if "getStreamVolume" not in codes:
        print(f"{argv[1]} has no checkable getStreamVolume to verify against; found {sorted(codes)}", file=sys.stderr)
        return 2
    for name in sorted(codes):
        print(f"{name}={codes[name]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
