#!/usr/bin/env python3
"""Write a framework.jar fixture holding a minimal IAudioService Stub/Proxy
dex for audio-codes.py. Only the tables audio-codes.py reads are filled in.

Usage: make-audio-dex.py OUT.jar [samsung|plain|shifted|gap|overload]
  samsung  the Tab S11's codes (getStreamVolume=27, setAppVolume=293, …)
  plain    no Samsung app-volume methods, like a Pixel
  shifted  a boolean and a null static before the codes (decoder regression)
  gap      codes that aren't exactly 1..N
  overload setAppVolume has two proxy signatures
"""
import struct
import sys
import zipfile

STRING = "Ljava/lang/String;"
SAMSUNG = {27: "getStreamVolume", 25: "isMasterMute", 26: "setMasterMute", 293: "setAppVolume", 294: "getAppVolume", 295: "setAppMute", 296: "isAppMute"}
SIGNATURES = {
    "getStreamVolume": ("I", ["I"]),
    "getAppVolume": ("I", ["I"]),
    "setAppVolume": ("V", ["I", "I", STRING]),
    "isAppMute": ("Z", ["I"]),
    "setAppMute": ("V", ["I", "Z", STRING]),
    "isMasterMute": ("Z", []),
    "setMasterMute": ("V", ["Z", "I", STRING, "I", STRING]),
}
SHORTY = {"I": "I", "Z": "Z", "V": "V", STRING: "L"}


def uleb(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


class DexBuilder:
    def __init__(self) -> None:
        self.strings: list[str] = []
        self.types: list[int] = []
        self.protos: list[tuple[int, int, tuple[int, ...]]] = []
        self.fields: list[tuple[int, int, int]] = []
        self.methods: list[tuple[int, int, int]] = []
        self.classes: list[tuple[int, list[int], list[tuple[str, object]], list[int]]] = []

    def string(self, text: str) -> int:
        if text not in self.strings:
            self.strings.append(text)
        return self.strings.index(text)

    def type(self, descriptor: str) -> int:
        index = self.string(descriptor)
        if index not in self.types:
            self.types.append(index)
        return self.types.index(index)

    def proto(self, ret: str, params: list[str]) -> int:
        shorty = SHORTY[ret] + "".join(SHORTY[p] for p in params)
        self.protos.append((self.string(shorty), self.type(ret), tuple(self.type(p) for p in params)))
        return len(self.protos) - 1

    def add_class(self, descriptor: str, statics: list[tuple[str, str, tuple[str, object]]], methods: list[tuple[str, str, list[str]]]) -> None:
        cls = self.type(descriptor)
        field_ids, values = [], []
        for field_type, name, value in statics:
            self.fields.append((cls, self.type(field_type), self.string(name)))
            field_ids.append(len(self.fields) - 1)
            values.append(value)
        method_ids = []
        for name, ret, params in methods:
            self.methods.append((cls, self.proto(ret, params), self.string(name)))
            method_ids.append(len(self.methods) - 1)
        self.classes.append((cls, field_ids, values, method_ids))

    def encoded(self, value: tuple[str, object]) -> bytes:
        kind, payload = value
        if kind == "int":
            return bytes([(3 << 5) | 0x04]) + struct.pack("<i", payload)
        if kind == "string":
            return bytes([(3 << 5) | 0x17]) + struct.pack("<I", self.string(payload))
        if kind == "bool":
            return bytes([(int(payload) << 5) | 0x1F])
        return bytes([0x1E])

    def build(self) -> bytes:
        # Encoded values may add strings, so encode before laying out tables.
        arrays = [uleb(len(values)) + b"".join(self.encoded(v) for v in values) for _, _, values, _ in self.classes]
        sizes = [len(self.strings) * 4, len(self.types) * 4, len(self.protos) * 12, len(self.fields) * 8, len(self.methods) * 8, len(self.classes) * 32]
        offsets, at = [], 0x70
        for size in sizes:
            offsets.append(at)
            at += size
        data = bytearray()
        base = at

        def place(blob: bytes, align: int = 1) -> int:
            while (base + len(data)) % align:
                data.append(0)
            offset = base + len(data)
            data.extend(blob)
            return offset

        string_offsets = [place(uleb(len(s)) + s.encode() + b"\0") for s in self.strings]
        param_offsets = [place(struct.pack("<I", len(p)) + b"".join(struct.pack("<H", t) for t in p), 4) if p else 0 for _, _, p in self.protos]
        class_rows = []
        for (cls, field_ids, _, method_ids), array in zip(self.classes, arrays):
            body = uleb(len(field_ids)) + uleb(0) + uleb(0) + uleb(len(method_ids))
            body += b"".join(uleb(f - (field_ids[k - 1] if k else 0)) + uleb(0x19) for k, f in enumerate(field_ids))
            body += b"".join(uleb(m - (method_ids[k - 1] if k else 0)) + uleb(1) + uleb(0) for k, m in enumerate(method_ids))
            class_rows.append((cls, place(body), place(array) if field_ids else 0))
        header = bytearray(b"dex\n035\0" + bytes(0x70 - 8))
        for k, (size, offset) in enumerate(zip(sizes, offsets)):
            count = size // (4, 4, 12, 8, 8, 32)[k]
            struct.pack_into("<II", header, 0x38 + 8 * k, count, offset)
        tables = b"".join(struct.pack("<I", o) for o in string_offsets)
        tables += b"".join(struct.pack("<I", t) for t in self.types)
        tables += b"".join(struct.pack("<III", s, r, param_offsets[k]) for k, (s, r, _) in enumerate(self.protos))
        tables += b"".join(struct.pack("<HHI", *f) for f in self.fields)
        tables += b"".join(struct.pack("<HHI", *m) for m in self.methods)
        tables += b"".join(struct.pack("<8I", cls, 1, 0, 0, 0, 0, data_off, values_off) for cls, data_off, values_off in class_rows)
        return bytes(header) + tables + bytes(data)


def fixture(variant: str) -> bytes:
    named = dict(SAMSUNG)
    if variant == "plain":
        named = {k: v for k, v in named.items() if "App" not in v}
    count = 300
    statics = [("Ljava/lang/String;", "DESCRIPTOR", ("string", "android.media.IAudioService"))]
    if variant == "shifted":
        statics += [("Z", "DEBUG", ("bool", True)), ("Ljava/lang/Object;", "sDefault", ("null", None))]
    for code in range(1, count + 1):
        value = code + 1 if variant == "gap" and code == count else code
        statics.append(("I", "TRANSACTION_" + named.get(code, f"method{code}"), ("int", value)))
    methods = [(name, *SIGNATURES[name]) for name in named.values()]
    if variant == "overload":
        methods.append(("setAppVolume", "V", ["I", "I"]))
    builder = DexBuilder()
    builder.add_class("Landroid/media/IAudioService$Stub;", statics, [])
    builder.add_class("Landroid/media/IAudioService$Stub$Proxy;", [], methods)
    return builder.build()


def main(argv: list[str]) -> int:
    variant = argv[2] if len(argv) > 2 else "samsung"
    with zipfile.ZipFile(argv[1], "w") as jar:
        jar.writestr("classes.dex", fixture(variant))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
