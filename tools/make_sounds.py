"""Synthesised UI/hardware sounds, written as 16-bit mono WAV.

Recorded audio is not worth a dependency for what these are: two short, dry
mechanical noises. Synthesising them keeps the repository free of binaries whose
source nobody has, and a parameter change is a re-run rather than a new recording.

Run: python tools/make_sounds.py
"""

import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "audio")


def write(name, samples):
	os.makedirs(OUT, exist_ok=True)
	path = os.path.join(OUT, name)
	peak = max(1e-6, max(abs(s) for s in samples))
	with wave.open(path, "w") as f:
		f.setnchannels(1)
		f.setsampwidth(2)
		f.setframerate(RATE)
		f.writeframes(b"".join(
			struct.pack("<h", int(max(-1.0, min(1.0, s / peak * 0.85)) * 32767))
			for s in samples))
	print(f"{name:20s} {len(samples) / RATE * 1000:5.0f} ms  {os.path.getsize(path) / 1024:5.1f} KB")


def noise_burst(length, decay, low, high, seed):
	"""Filtered noise: the body of any small plastic knock."""
	rng = random.Random(seed)
	out = []
	prev = 0.0
	for i in range(int(RATE * length)):
		white = rng.uniform(-1.0, 1.0)
		# one-pole low pass, sweeping down as the knock dies away
		t = i / (RATE * length)
		cutoff = low + (high - low) * (1.0 - t)
		alpha = min(1.0, cutoff / (RATE * 0.5))
		prev += alpha * (white - prev)
		out.append(prev * math.exp(-decay * t))
	return out


def click(freq, length, decay, seed):
	"""A short pitched tick riding on the noise, which is what makes a latch read
	as a latch rather than as a thud."""
	body = noise_burst(length, decay, 900, 6000, seed)
	for i in range(len(body)):
		t = i / RATE
		body[i] += 0.5 * math.sin(TAU * freq * t) * math.exp(-decay * 2.2 * t / length)
	return body


TAU = math.pi * 2


def main():
	# Going in: the shell bottoming out, then the latch snapping over it.
	seat = noise_burst(0.055, 5.0, 700, 4200, 11)
	latch = click(2100, 0.040, 7.0, 12)
	plug = seat + [0.0] * int(RATE * 0.012)
	for i, v in enumerate(latch):
		at = int(RATE * 0.052) + i
		while at >= len(plug):
			plug.append(0.0)
		plug[at] += v * 0.9
	write("plug_in.wav", plug)

	# Coming out: the latch pressed first, then the shell dragging clear.
	press = click(1500, 0.028, 9.0, 21)
	drag = noise_burst(0.075, 3.4, 400, 2600, 22)
	unplug = press + [0.0] * int(RATE * 0.010)
	for i, v in enumerate(drag):
		at = int(RATE * 0.034) + i
		while at >= len(unplug):
			unplug.append(0.0)
		unplug[at] += v * 0.75
	write("plug_out.wav", unplug)


main()
