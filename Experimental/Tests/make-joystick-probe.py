#!/usr/bin/env python3
"""Generate a DOS COM BIOS joystick probe without an assembler dependency."""
from pathlib import Path
import struct
import sys

code = bytearray()
labels = {}
relocations = []


def emit(hexadecimal):
    code.extend(bytes.fromhex(hexadecimal))


def address(opcode, label):
    emit(opcode)
    relocations.append((len(code), label))
    code.extend(b"\0\0")


emit("31 c9")                      # Create feedback file with normal attributes.
address("ba", "name")
emit("b8 00 3c cd 21")
address("a3", "handle")
labels["loop"] = len(code) + 0x100
emit("b8 00 84 ba 01 00 cd 15")     # BIOS INT15/84, DX=1: joystick axes.
address("a3", "x")
address("89 1e", "y")
emit("b8 00 84 31 d2 cd 15")        # BIOS INT15/84, DX=0: active-low buttons in AL.
address("a3", "buttons")
address("8b 1e", "handle")
emit("31 c9 31 d2 b8 00 42 cd 21")  # Seek feedback file to start.
address("8b 1e", "handle")
emit("b9 08 00")
address("ba", "x")
emit("b4 40 cd 21")                 # Write eight-byte sample.
address("8b 1e", "handle")
emit("b4 68 cd 21 cd 28 e9")        # Commit, idle, loop.
code.extend(struct.pack("<h", labels["loop"] - (len(code) + 0x100 + 2)))
for label, contents in [
    ("handle", b"\0\0"), ("name", b"JOYSTICK.DAT\0"),
    ("x", b"\0\0"), ("y", b"\0\0"), ("buttons", b"\0\0"),
    ("marker", b"JY"),
]:
    labels[label] = len(code) + 0x100
    code.extend(contents)
for offset, label in relocations:
    code[offset:offset+2] = struct.pack("<H", labels[label])
Path(sys.argv[1]).write_text(
    "static const unsigned char program[] = {"
    + ",".join(str(byte) for byte in code) + "};\n"
)
