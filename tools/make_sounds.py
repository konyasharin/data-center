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
		body[i] = body[i] * 0.55 + 0.45 * math.sin(TAU * freq * t) * math.exp(-decay * 2.2 * t / length)
	return body


TAU = math.pi * 2


def main():
	# Going in: the shell bottoming out, then the latch snapping over it. Kept low and
	# short — a bright click repeated forty times a rack is what makes a sound tiring.
	seat = noise_burst(0.045, 7.0, 380, 1700, 11)
	latch = click(880, 0.030, 9.0, 12)
	plug = seat + [0.0] * int(RATE * 0.012)
	for i, v in enumerate(latch):
		at = int(RATE * 0.052) + i
		while at >= len(plug):
			plug.append(0.0)
		plug[at] += v * 0.9
	write("plug_in.wav", plug)

	# Coming out: the latch pressed first, then the shell dragging clear.
	press = click(620, 0.024, 11.0, 21)
	drag = noise_burst(0.065, 5.0, 220, 1200, 22)
	unplug = press + [0.0] * int(RATE * 0.010)
	for i, v in enumerate(drag):
		at = int(RATE * 0.034) + i
		while at >= len(unplug):
			unplug.append(0.0)
		unplug[at] += v * 0.75
	write("plug_out.wav", unplug)

	# Putting a cabinet together, one part at a time. Four different noises rather than
	# one repeated four times: the same sample four times reads as a stutter, and the
	# parts are not alike — a frame lands, rails clatter, panels click home, a door
	# swings and latches.

	# the empty frame set down on the floor: heavy, long, no ring
	frame = noise_burst(0.36, 3.0, 70, 520, 41)
	for i in range(len(frame)):
		t = i / RATE
		frame[i] += 0.32 * math.sin(TAU * 41 * t) * math.exp(-5.0 * t)
	write("rack_frame.wav", frame)

	# rails and strips going in: several small metallic knocks in quick succession
	rail = noise_burst(0.22, 5.0, 300, 2600, 51)
	for n, (delay, pitch) in enumerate(((0.000, 1640), (0.045, 1980), (0.092, 1450))):
		for i, v in enumerate(click(pitch, 0.045, 10.0, 52 + n)):
			at = int(RATE * delay) + i
			while at >= len(rail):
				rail.append(0.0)
			rail[at] += v * 0.5
	write("rack_rail.wav", rail)

	# a flat panel pushed home against the rails: a short body and one bright click
	panel = noise_burst(0.13, 6.0, 200, 1500, 61)
	for i, v in enumerate(click(2150, 0.035, 12.0, 62)):
		at = int(RATE * 0.055) + i
		while at >= len(panel):
			panel.append(0.0)
		panel[at] += v * 0.45
	write("rack_panel.wav", panel)

	# the door: a slow sweep of air, then the catch
	door = noise_burst(0.30, 2.2, 160, 900, 71)
	for i in range(len(door)):
		door[i] *= 0.55
	for i, v in enumerate(click(760, 0.05, 9.0, 72)):
		at = int(RATE * 0.24) + i
		while at >= len(door):
			door.append(0.0)
		door[at] += v * 0.9
	write("rack_door.wav", door)


main()
