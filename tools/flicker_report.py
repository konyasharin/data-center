"""Measure temporal flicker: how much a still frame changes when nothing moves.

An artefact that "shimmers while standing still" is temporal, and eyeballing single
screenshots cannot tell TAA from dithered LOD from alpha coverage. The showroom's
--flicker mode saves consecutive frames from a locked camera; this scores them.

	python tools/flicker_report.py <dir> [label]

Prints the fraction of pixels whose brightness moves between frames, which drops to
near zero once the real cause is switched off.
"""

import os
import struct
import sys
import zlib


def read_png(path):
	data = open(path, "rb").read()
	pos, idat, width, height, depth, colour = 8, b"", None, None, None, None
	while pos < len(data):
		length = struct.unpack(">I", data[pos:pos + 4])[0]
		tag = data[pos + 4:pos + 8]
		body = data[pos + 8:pos + 8 + length]
		if tag == b"IHDR":
			width, height, depth, colour = struct.unpack(">IIBB", body[:10])
		elif tag == b"IDAT":
			idat += body
		pos += 12 + length

	channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour]
	bpp = channels * (depth // 8)
	stride = width * bpp
	raw = zlib.decompress(idat)
	rows, prev, pos = [], bytearray(stride), 0
	for _ in range(height):
		filt = raw[pos]
		pos += 1
		line = bytearray(raw[pos:pos + stride])
		pos += stride
		if filt:
			for x in range(stride):
				a = line[x - bpp] if x >= bpp else 0
				b = prev[x]
				c = prev[x - bpp] if x >= bpp else 0
				if filt == 1:
					line[x] = (line[x] + a) & 255
				elif filt == 2:
					line[x] = (line[x] + b) & 255
				elif filt == 3:
					line[x] = (line[x] + (a + b) // 2) & 255
				else:
					p = a + b - c
					pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
					pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
					line[x] = (line[x] + pred) & 255
		rows.append(bytes(line))
		prev = line
	return width, height, channels, rows


def main():
	directory = sys.argv[1] if len(sys.argv) > 1 else "."
	label = sys.argv[2] if len(sys.argv) > 2 else os.path.basename(directory)

	files = sorted(f for f in os.listdir(directory) if f.endswith(".png"))
	if len(files) < 2:
		print(f"{label}: need at least two frames")
		return 1

	frames = []
	for name in files:
		width, height, channels, rows = read_png(os.path.join(directory, name))
		frames.append(rows)

	step = 3
	total = moving = strong = 0
	peak = 0
	for y in range(0, height, step):
		for x in range(0, width, step):
			o = x * channels
			vals = [f[y][o] + f[y][o + 1] + f[y][o + 2] for f in frames]
			spread = max(vals) - min(vals)
			total += 1
			peak = max(peak, spread)
			if spread > 12:
				moving += 1
			if spread > 60:
				strong += 1

	print(f"{label:16s} moving {100.0 * moving / total:5.2f}%   "
	      f"strong {100.0 * strong / total:5.2f}%   peak {peak}/765   "
	      f"({len(frames)} frames)")
	return 0


if __name__ == "__main__":
	sys.exit(main())
