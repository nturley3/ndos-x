#!/usr/bin/env python3
"""Generate a DOS COM mouse probe as a C header without an assembler dependency.

The guest registers an INT33 far callback and repeatedly flushes sixteen bytes
containing buttons, position, driver status, accumulated motion counters, and
callback count/event mask. Addresses are relocated for COM origin 0100h.
"""
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


emit("31 c0 cd 33")                  # XOR AX,AX / INT33: reset mouse driver.
address("a3", "driver")             # MOV [driver],AX (FFFFh when present).
emit("b8 01 00 cd 33")               # INT33 function1: show mouse cursor.
emit("0e 07 b8 0c 00 b9 1f 00")     # ES=CS; function0Ch; motion/button event mask.
address("ba", "callback")           # Callback address ES:DX.
emit("cd 33 31 c9")                 # Register handler, then zero create attributes.
address("ba", "name")               # DS:DX -> feedback filename.
emit("b8 00 3c cd 21")              # DOS AH=3Ch: create feedback file.
address("a3", "handle")

labels["loop"] = len(code) + 0x100
emit("b8 03 00 cd 33")              # INT33 function3: buttons BX, position CX/DX.
address("89 1e", "sample")
address("89 0e", "samplex")
address("89 16", "sampley")
emit("b8 0b 00 cd 33")              # INT33 function0Bh: motion counters CX/DX.
address("01 0e", "mickeyx")          # ADD deltas into accumulated signed words.
address("01 16", "mickeyy")
address("8b 1e", "handle")
emit("31 c9 31 d2 b8 00 42 cd 21")  # DOS seek file to offset0 (AH=42h, AL=0).
address("8b 1e", "handle")
emit("b9 10 00")                    # CX=16 bytes.
address("ba", "sample")
emit("b4 40 cd 21")                 # DOS AH=40h: write complete sample.
address("8b 1e", "handle")
emit("b4 68 cd 21 cd 28")           # DOS commit, then idle interrupt.
emit("e9")                          # Near JMP back to polling loop.
displacement = labels["loop"] - (len(code) + 0x100 + 2)
code.extend(struct.pack("<h", displacement))

labels["callback"] = len(code) + 0x100
emit("9c")                          # PUSHF: preserve interrupt callback flags.
address("2e ff 06", "callbackcount") # INC word CS:[callbackcount].
address("2e 09 06", "callbackmask")  # OR CS:[callbackmask],AX (event flags).
emit("9d cb")                       # POPF / RETF to mouse driver.

for label, contents in [
    ("handle", b"\0\0"), ("name", b"MOUSE.DAT\0"),
    ("sample", b"\0\0"), ("samplex", b"\0\0"), ("sampley", b"\0\0"),
    ("driver", b"\0\0"), ("mickeyx", b"\0\0"), ("mickeyy", b"\0\0"),
    ("callbackcount", b"\0\0"), ("callbackmask", b"\0\0"),
]:
    labels[label] = len(code) + 0x100
    code.extend(contents)
for offset, label in relocations:
    code[offset:offset + 2] = struct.pack("<H", labels[label])

Path(sys.argv[1]).write_text(
    "static const unsigned char program[] = {"
    + ",".join(str(byte) for byte in code) + "};\n"
)
