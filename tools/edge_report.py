"""Score high-frequency contrast in a screenshot region.

The rack fronts alternate bright carrier / dark well every 25 mm. Seen down an aisle
that pitch projects to one or two pixels, and the result is a torn, crawling pattern
no amount of MSAA fixes — the fix is to lower the contrast that is being aliased, or
to swap in a flat LOD before it gets that small. Either way the change has to be
measurable, because "looks a bit better" is how four wrong guesses survived.

	python tools/edge_report.py <png> [label] [x0 y0 x1 y1 as fractions]

Reports mean absolute difference between neighbouring pixels (the aliasing energy)
inside the region, and the share of pixel pairs that jump hard.
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
	if len(sys.argv) < 2:
		print(__doc__)
		return 1
	path = sys.argv[1]
	label = sys.argv[2] if len(sys.argv) > 2 else os.path.basename(path)
	box = [float(v) for v in sys.argv[3:7]] if len(sys.argv) >= 7 else [0.60, 0.10, 0.99, 0.60]

	width, height, channels, rows = read_png(path)
	x0, y0 = int(width * box[0]), int(height * box[1])
	x1, y1 = int(width * box[2]), int(height * box[3])

	total = pairs = hard = 0
	for y in range(y0, y1):
		row = rows[y]
		for x in range(x0, x1 - 1):
			o = x * channels
			a = row[o] + row[o + 1] + row[o + 2]
			b = row[o + channels] + row[o + channels + 1] + row[o + channels + 2]
			d = abs(a - b)
			total += d
			pairs += 1
			if d > 90:
				hard += 1

	print(f"{label:22s} edge energy {total / max(pairs, 1):6.2f}   "
	      f"hard steps {100.0 * hard / max(pairs, 1):5.2f}%   region {box}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
