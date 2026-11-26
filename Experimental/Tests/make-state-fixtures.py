"""Derive invalid slot archives from the real engine's test save."""
from pathlib import Path
import struct
import sys
import zipfile

source = Path(sys.argv[1])
with zipfile.ZipFile(source) as original:
    metadata = {"DOSBox-X_Version", "Memory_Size", "Machine_Type", "Program_Name",
                "Time_Stamp", "Save_Remark"}
    component = next(entry.filename for entry in original.infolist()
                     if entry.filename not in metadata and entry.file_size > 0)
    for slot, key, replacement in [
        (2, "DOSBox-X_Version", b"old build"), (3, "Memory_Size", b"1"),
        (4, "Machine_Type", b"MCH_PC98"), (5, component, None),
        (6, component, original.read(component)), (7, "Program_Name", b"OTHER.EXE"),
        (8, "CMOS", b""), (9, component, original.read(component)),
    ]:
        target = source.with_name(f"{slot}.sav")
        with zipfile.ZipFile(target, "w") as archive:
            for name in original.namelist():
                if name == key and replacement is None:
                    continue
                archive.writestr(name, replacement if name == key else original.read(name),
                                 compress_type=zipfile.ZIP_STORED if name == component else zipfile.ZIP_DEFLATED)
        if slot == 6:
            # Damage a stored payload without changing either copy of its CRC.
            with zipfile.ZipFile(target) as archive:
                offset = archive.getinfo(component).header_offset
            with target.open("r+b") as handle:
                handle.seek(offset + 26)
                name_len, extra_len = struct.unpack("<HH", handle.read(4))
                handle.seek(name_len + extra_len, 1)
                value = handle.read(1)[0]
                handle.seek(-1, 1)
                handle.write(bytes([value ^ 1]))

        if slot == 9:
            # Both ZIP headers claim one extra output byte. The data CRC is valid.
            with zipfile.ZipFile(target) as archive:
                entry = archive.getinfo(component)
                central = archive.start_dir
            with target.open("r+b") as handle:
                length = struct.pack("<I", entry.file_size + 1)
                handle.seek(entry.header_offset + 22)
                handle.write(length)
                handle.seek(central)
                while True:
                    header = handle.read(46)
                    assert header[:4] == b"PK\x01\x02"
                    name, extra, comment = struct.unpack_from("<HHH", header, 28)
                    if struct.unpack_from("<I", header, 42)[0] == entry.header_offset:
                        handle.seek(-22, 1)
                        handle.write(length)
                        break
                    handle.seek(name + extra + comment, 1)
