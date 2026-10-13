#!/usr/bin/env python3
"""Write the icons embedded in a Windows exe as PNGs, for a desktop entry.

    extract-icons.py <exe> <out dir> [name]

Writes <out dir>/<W>x<H>/apps/<name>.png for every image in the exe's first
icon group (hicolor layout). PNG images are written as they are; 32-bit DIB
images are converted (stdlib only). Prints what it wrote.
"""
import os, struct, sys, zlib

RT_ICON, RT_GROUP_ICON = 3, 14

def sections(pe):
    off = struct.unpack_from('<I', pe, 0x3C)[0]
    n = struct.unpack_from('<H', pe, off + 6)[0]
    opt = struct.unpack_from('<H', pe, off + 20)[0]
    magic = struct.unpack_from('<H', pe, off + 24)[0]
    dd = off + 24 + (96 if magic == 0x10B else 112)
    rsrc_rva = struct.unpack_from('<I', pe, dd + 2 * 8)[0]
    secs = []
    for i in range(n):
        o = off + 24 + opt + 40 * i
        vsz, va, rsz, raw = struct.unpack_from('<IIII', pe, o + 8)
        secs.append((va, max(vsz, rsz), raw))
    return rsrc_rva, secs

def rva_to_off(secs, rva):
    for va, size, raw in secs:
        if va <= rva < va + size:
            return raw + rva - va
    raise ValueError('rva %x outside the sections' % rva)

def resources(pe):
    rsrc_rva, secs = sections(pe)
    base = rva_to_off(secs, rsrc_rva)
    def entries(dir_off):
        named, ids = struct.unpack_from('<HH', pe, dir_off + 12)
        for i in range(named + ids):
            name, target = struct.unpack_from('<II', pe, dir_off + 16 + 8 * i)
            yield name, target
    out = {}
    for typ, t1 in entries(base):
        if not t1 & 0x80000000:
            continue
        for rid, t2 in entries(base + (t1 & 0x7FFFFFFF)):
            if not t2 & 0x80000000:
                continue
            for _lang, t3 in entries(base + (t2 & 0x7FFFFFFF)):
                data_rva, size = struct.unpack_from('<II', pe, base + t3)
                o = rva_to_off(secs, data_rva)
                out.setdefault(typ, {}).setdefault(rid, pe[o:o + size])
                break
    return out

def png(width, height, rgba):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xFFFFFFFF)
    rows = b''.join(b'\0' + rgba[y * width * 4:(y + 1) * width * 4] for y in range(height))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b''))

def dib_to_png(dib):
    hsize, w, h2, planes, bpp = struct.unpack_from('<IiiHH', dib, 0)
    h = h2 // 2                       # an icon DIB holds the colour rows and the AND mask
    if bpp != 32:
        return None, w, h
    rgba = bytearray(w * h * 4)
    for y in range(h):
        src = hsize + (h - 1 - y) * w * 4     # bottom-up
        for x in range(w):
            b, g, r, a = dib[src + 4 * x: src + 4 * x + 4]
            rgba[(y * w + x) * 4:(y * w + x) * 4 + 4] = bytes((r, g, b, a))
    return png(w, h, bytes(rgba)), w, h

def main():
    exe, out_dir = sys.argv[1], sys.argv[2]
    name = sys.argv[3] if len(sys.argv) > 3 else 'omp-launcher'
    pe = open(exe, 'rb').read()
    res = resources(pe)
    groups = res.get(RT_GROUP_ICON, {})
    if not groups:
        sys.exit('no icon group in %s' % exe)
    group = groups[min(groups)]
    _reserved, _type, count = struct.unpack_from('<HHH', group, 0)
    wrote = 0
    for i in range(count):
        bw, bh, _c, _r, _p, _bpp, _size, icon_id = struct.unpack_from('<BBBBHHIH', group, 6 + 14 * i)
        img = res.get(RT_ICON, {}).get(icon_id)
        if not img:
            continue
        if img[:8] == b'\x89PNG\r\n\x1a\n':
            w, h = struct.unpack_from('>II', img, 16)
            data = img
        else:
            data, w, h = dib_to_png(img)
            if data is None:
                continue
        path = os.path.join(out_dir, '%dx%d' % (w, h), 'apps', name + '.png')
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'wb') as f:
            f.write(data)
        print(path)
        wrote += 1
    if not wrote:
        sys.exit('no usable icon image in %s' % exe)

if __name__ == '__main__':
    main()
