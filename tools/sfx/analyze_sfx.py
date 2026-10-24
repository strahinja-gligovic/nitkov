"""Checks the generated sound effects by measurement (nobody has to listen):
duration, sample and true peak, DC offset, K-weighted loudness, RMS per 10 ms,
spectral centroid over time, band balance, clicks, tails, and loop seams.
Draws waveform + spectrogram sheets so the shapes can be looked at.

    uv run --no-project python -I tools/sfx/analyze_sfx.py [names...] [--png=<dir>] [--cols=3]

`names` filter by prefix (fire_ matches every fire sound). Exit code 1 when a
check fails: peak above -1 dBFS, |DC| above 0.002, a click, a one-shot that
doesn't start and end at zero, a loop whose seam jumps or whose level steps.
"""
import cmath
import math
import os
import struct
import sys
import zlib

sys.stdout.reconfigure(encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dsp  # noqa: E402
import build_sfx  # noqa: E402  (the registry: each sound's kind and flags)

REPO = os.path.dirname(os.path.dirname(HERE))
SFX = os.path.join(REPO, "assets", "sfx")
SR = dsp.SR

# --- spectra ------------------------------------------------------------------

_TW = {}


def fft(x):
	"""Iterative radix-2 FFT of a real list whose length is a power of two."""
	n = len(x)
	if n not in _TW:
		bits = n.bit_length() - 1
		rev = [int(format(i, "0%db" % bits)[::-1], 2) for i in range(n)]
		tw = [cmath.exp(-2j * math.pi * k / n) for k in range(n // 2)]
		_TW[n] = (rev, tw)
	rev, tw = _TW[n]
	a = [complex(x[r]) for r in rev]
	size = 2
	while size <= n:
		half = size // 2
		step = n // size
		for start in range(0, n, size):
			k = 0
			for i in range(start, start + half):
				t = tw[k] * a[i + half]
				u = a[i]
				a[i] = u + t
				a[i + half] = u - t
				k += step
		size *= 2
	return a


def frames(x, size, hop):
	"""Hann-windowed magnitude spectra at hop-spaced frame centres."""
	win = [0.5 - 0.5 * math.cos(2.0 * math.pi * i / size) for i in range(size)]
	pad = [0.0] * (size // 2)
	y = pad + x + pad
	out = []
	for start in range(0, len(x), hop):
		seg = y[start:start + size]
		if len(seg) < size:
			seg = seg + [0.0] * (size - len(seg))
		spec = fft([s * w for s, w in zip(seg, win)])
		out.append([abs(c) for c in spec[: size // 2]])
	return out


# --- measurements -------------------------------------------------------------

def clicks(x, loop):
	"""Discontinuities: a sample-to-sample step over 8x the RMS of the steps
	within 0.3 ms around it (its immediate neighbours left out) and over 0.04. A crackle grain is many big steps in a row, so it passes; a cut,
	a jump or a missing fade is one big step among small ones. Loops are
	checked circularly, across the wrap."""
	pre = min(len(x), 2048) if loop else 0
	sig = (x[-pre:] + x) if loop else x
	d = [0.0] + [abs(sig[i] - sig[i - 1]) for i in range(1, len(sig))]
	sq = [v * v for v in d]
	cum = [0.0]
	s = 0.0
	for v in sq:
		s += v
		cum.append(s)
	w = int(0.0003 * SR)
	found = []
	for i, v in enumerate(d):
		if v < 0.04 or i < pre:
			continue
		lo = max(0, i - w)
		hi = min(len(sq), i + w + 1)
		near_lo = max(lo, i - 1)
		near_hi = min(hi, i + 2)
		count = (hi - lo) - (near_hi - near_lo)
		local = (cum[hi] - cum[lo] - (cum[near_hi] - cum[near_lo])) / max(count, 1)
		if v > 8.0 * math.sqrt(max(local, 1e-14)):
			found.append(round((i - pre) / SR, 4))
	return found


def selftest():
	"""The click test must catch steps and pass crackle grains."""
	import random
	rng = random.Random(1)
	sine = [0.5 * math.sin(2 * math.pi * 100 * i / SR) for i in range(4410)]
	stepped = sine[:2000] + [v + 0.12 for v in sine[2000:]]
	assert clicks(stepped, False), "missed a step"
	cut = [0.5 * math.sin(2 * math.pi * 300 * i / SR + 1.2) for i in range(4410)]
	assert clicks([0.0] * 100 + cut, False), "missed a hard start"
	quiet = [0.02 * math.sin(2 * math.pi * 200 * i / SR) for i in range(8820)]
	for t in (1000, 3000, 5000, 7000):
		g = dsp.grain(rng, rng.uniform(0.0002, 0.004), rng.uniform(1500.0, 10000.0), 1.5, 0.9)
		dsp.add_into(quiet, dsp.scale(g, 0.8 / dsp.peak(g)), t)
	assert not clicks(quiet, False), "flagged crackle grains: %s" % clicks(quiet, False)
	print("selftest ok")


BANDS = (63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000)


def analyse(path):
	x, loop = dsp.read_wav(path)
	name = os.path.splitext(os.path.basename(path))[0]
	if loop:
		x = x[: loop[1]]  # drop the wrap-around guard sample
	n = len(x)
	p = dsp.peak(x)
	tp = dsp.true_peak(x)
	dc = sum(x) / n
	mom, integ = dsp.loudness(x + x if loop else x)
	w = int(0.01 * SR)
	rms = []
	for start in range(0, n, w):
		seg = x[start:start + w]
		rms.append(math.sqrt(sum(v * v for v in seg) / len(seg)))
	rms_db = [dsp.db(r) for r in rms]
	top = max(rms_db)
	attack = next((k * 0.01 for k, r in enumerate(rms_db) if r >= top - 3.0), 0.0)
	tail = dsp.db(math.sqrt(sum(v * v for v in x[-int(0.02 * SR):]) / int(0.02 * SR))) - top
	# spectra: centroid over time and band balance
	size = 1024
	hop = max(int(0.0025 * SR), n // 300)
	spec = frames(x, size, hop)
	df = SR / size
	cent = []
	energy = []
	bands = [0.0, 0.0, 0.0, 0.0]
	octaves = [0.0] * len(BANDS)
	for mags in spec:
		tot = sum(mags)
		e = sum(m * m for m in mags)
		energy.append(e)
		cent.append(sum(k * df * m for k, m in enumerate(mags)) / tot if tot > 1e-9 else 0.0)
		for k, m in enumerate(mags):
			f = k * df
			bands[0 if f < 200 else 1 if f < 2000 else 2 if f < 8000 else 3] += m * m
			if f > 44.0:
				octaves[min(len(BANDS) - 1, max(0, int(round(math.log2(f / 63.0)))))] += m * m
	etot = sum(energy) or 1.0
	centroid = sum(c * e for c, e in zip(cent, energy)) / etot
	bsum = sum(bands) or 1.0
	info = dict(name=name, seconds=n / SR, loop=bool(loop), peak_db=dsp.db(p), true_peak_db=dsp.db(tp), dc=dc,
			lufs=integ if loop else mom, lufs_int=integ, rms_max_db=top, attack=attack, tail_db=tail,
			centroid=centroid, bands=[b / bsum for b in bands],
			octaves=[dsp.db(math.sqrt(o / max(octaves))) if o > 0 else -99.0 for o in octaves], clicks=clicks(x, bool(loop)),
			first=x[0], last=x[-1], rms_db=rms_db, cent=cent, spec=spec, hop=hop, size=size)
	if loop:
		deltas = sorted(abs(x[i + 1] - x[i]) for i in range(n - 1))
		typical = deltas[int(0.999 * (len(deltas) - 1))] or 1e-9
		info["seam_jump"] = abs(x[0] - x[-1]) / typical
		k = int(0.05 * SR)
		head = math.sqrt(sum(v * v for v in x[:k]) / k)
		end = math.sqrt(sum(v * v for v in x[-k:]) / k)
		info["seam_step_db"] = dsp.db(end) - dsp.db(head)
	return info


def spec_of(name):
	"""The build registry entry for a file name (fire_hit_2 -> fire_hit)."""
	if name in build_sfx.SOUNDS:
		return build_sfx.SOUNDS[name]
	base = name.rsplit("_", 1)[0]
	return build_sfx.SOUNDS.get(base)


def problems(info):
	out = []
	spec = spec_of(info["name"])
	if spec is None:
		out.append("not in the build registry")
	if info["peak_db"] > -0.99:
		out.append("peak %.2f dBFS" % info["peak_db"])
	if info["true_peak_db"] > -0.8:
		out.append("true peak %.2f dBTP" % info["true_peak_db"])
	if abs(info["dc"]) > 0.002:
		out.append("dc %.4f" % info["dc"])
	if info["clicks"]:
		out.append("clicks at %s" % ", ".join("%.3f" % t for t in info["clicks"][:5]))
	if info["loop"]:
		if info["seam_jump"] > 1.0:
			out.append("seam jump %.2fx" % info["seam_jump"])
		if abs(info["seam_step_db"]) > 3.0:
			out.append("seam level step %.1f dB" % info["seam_step_db"])
	else:
		if info["first"] != 0.0 or info["last"] != 0.0:
			out.append("ends not at zero (%.4f, %.4f)" % (info["first"], info["last"]))
		if info["tail_db"] > -35.0 and not (spec and spec["held"]):
			out.append("tail cut at %.0f dB" % info["tail_db"])
	return out


# --- drawing ------------------------------------------------------------------

FONT = {
	"a": ["01110", "00001", "01111", "10001", "01111"], "b": ["10000", "11110", "10001", "10001", "11110"],
	"c": ["01111", "10000", "10000", "10000", "01111"], "d": ["00001", "01111", "10001", "10001", "01111"],
	"e": ["01110", "10001", "11111", "10000", "01111"], "f": ["00110", "01000", "11100", "01000", "01000"],
	"g": ["01111", "10001", "01111", "00001", "01110"], "h": ["10000", "11110", "10001", "10001", "10001"],
	"i": ["00100", "00000", "01100", "00100", "01110"], "j": ["00010", "00000", "00010", "10010", "01100"],
	"k": ["10000", "10010", "11100", "10010", "10001"], "l": ["01100", "00100", "00100", "00100", "01110"],
	"m": ["11010", "10101", "10101", "10101", "10001"], "n": ["10110", "11001", "10001", "10001", "10001"],
	"o": ["01110", "10001", "10001", "10001", "01110"], "p": ["11110", "10001", "11110", "10000", "10000"],
	"q": ["01111", "10001", "01111", "00001", "00001"], "r": ["10110", "11001", "10000", "10000", "10000"],
	"s": ["01111", "10000", "01110", "00001", "11110"], "t": ["01000", "11100", "01000", "01001", "00110"],
	"u": ["10001", "10001", "10001", "10011", "01101"], "v": ["10001", "10001", "10001", "01010", "00100"],
	"w": ["10001", "10001", "10101", "10101", "01010"], "x": ["10001", "01010", "00100", "01010", "10001"],
	"y": ["10001", "10001", "01111", "00001", "01110"], "z": ["11111", "00010", "00100", "01000", "11111"],
	"0": ["01110", "10011", "10101", "11001", "01110"], "1": ["00100", "01100", "00100", "00100", "01110"],
	"2": ["11110", "00001", "01110", "10000", "11111"], "3": ["11110", "00001", "00110", "00001", "11110"],
	"4": ["10010", "10010", "11111", "00010", "00010"], "5": ["11111", "10000", "11110", "00001", "11110"],
	"6": ["01110", "10000", "11110", "10001", "01110"], "7": ["11111", "00001", "00010", "00100", "00100"],
	"8": ["01110", "10001", "01110", "10001", "01110"], "9": ["01110", "10001", "01111", "00001", "01110"],
	".": ["00000", "00000", "00000", "00000", "00100"], "-": ["00000", "00000", "01110", "00000", "00000"],
	"_": ["00000", "00000", "00000", "00000", "11111"], ":": ["00000", "00100", "00000", "00100", "00000"],
	"%": ["11001", "11010", "00100", "01011", "10011"], "/": ["00001", "00010", "00100", "01000", "10000"],
	"+": ["00000", "00100", "01110", "00100", "00000"], " ": ["00000"] * 5, "!": ["00100", "00100", "00100", "00000", "00100"],
}


class Canvas:
	def __init__(self, w, h, bg=(14, 12, 20)):
		self.w = w
		self.h = h
		self.px = bytearray(bytes(bg) * (w * h))

	def set(self, x, y, c):
		if 0 <= x < self.w and 0 <= y < self.h:
			i = (y * self.w + x) * 3
			self.px[i:i + 3] = bytes(c)

	def rect(self, x0, y0, x1, y1, c):
		for y in range(max(0, y0), min(self.h, y1)):
			i = (y * self.w + max(0, x0)) * 3
			self.px[i:i + 3 * (min(self.w, x1) - max(0, x0))] = bytes(c) * (min(self.w, x1) - max(0, x0))

	def text(self, x, y, s, c=(235, 235, 235), scale=1):
		for ch in s.lower():
			rows = FONT.get(ch, FONT[" "])
			for r, row in enumerate(rows):
				for k, bit in enumerate(row):
					if bit == "1":
						for dy in range(scale):
							for dx in range(scale):
								self.set(x + k * scale + dx, y + r * scale + dy, c)
			x += 6 * scale

	def save(self, path):
		raw = b"".join(b"\0" + bytes(self.px[y * self.w * 3:(y + 1) * self.w * 3]) for y in range(self.h))
		def chunk(tag, data):
			return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
		png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 2, 0, 0, 0))
		png += chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
		with open(path, "wb") as f:
			f.write(png)


def heat(v):
	"""0..1 -> dark purple, red, orange, pale yellow (an inferno-ish ramp)."""
	stops = [(0.0, (10, 8, 22)), (0.3, (70, 18, 100)), (0.55, (190, 40, 70)), (0.78, (250, 140, 30)), (1.0, (255, 250, 200))]
	v = min(max(v, 0.0), 1.0)
	for k in range(1, len(stops)):
		if v <= stops[k][0]:
			t0, c0 = stops[k - 1]
			t1, c1 = stops[k]
			u = (v - t0) / (t1 - t0)
			return tuple(int(c0[i] + (c1[i] - c0[i]) * u) for i in range(3))
	return stops[-1][1]


F_LO, F_HI = 40.0, 20000.0


def draw_panel(cv, ox, oy, pw, info, seconds_full):
	"""Label, waveform with 10 ms RMS, log-frequency spectrogram with centroid."""
	label_h, wave_h, spec_h = 22, 56, 130
	cv.rect(ox, oy, ox + pw, oy + label_h + wave_h + spec_h, (20, 18, 28))
	name = info["name"]
	bad = problems(info)
	cv.text(ox + 4, oy + 3, name, (255, 120, 120) if bad else (240, 240, 240))
	stats = "%.2fs %.1flufs pk%.1f c%dhz" % (info["seconds"], info["lufs"], info["true_peak_db"], info["centroid"])
	cv.text(ox + 4, oy + 12, stats, (170, 170, 190))
	span = pw - 2
	scale_t = info["seconds"] / seconds_full
	used = max(2, int(span * scale_t))
	wy = oy + label_h
	mid = wy + wave_h // 2
	x, _ = dsp.read_wav(os.path.join(SFX, name + ".wav"))
	n = len(x)
	for col in range(used):
		a = int(col * n / used)
		b = max(a + 1, int((col + 1) * n / used))
		seg = x[a:b]
		lo, hi = min(seg), max(seg)
		y0 = mid - int(hi * (wave_h // 2 - 2))
		y1 = mid - int(lo * (wave_h // 2 - 2))
		for y in range(y0, y1 + 1):
			cv.set(ox + 1 + col, y, (110, 200, 255))
	# RMS line (dB: 0 at the top of the panel, -60 at the bottom)
	rms = info["rms_db"]
	for col in range(used):
		k = min(len(rms) - 1, int(col * len(rms) / used))
		y = wy + int(min(1.0, max(0.0, -rms[k] / 60.0)) * (wave_h - 1))
		cv.set(ox + 1 + col, y, (255, 255, 255))
	# 100 ms ticks
	for k in range(int(info["seconds"] * 10) + 1):
		tx = ox + 1 + int(k * 0.1 / seconds_full * span)
		for y in range(wy + wave_h - 4, wy + wave_h):
			cv.set(tx, y, (90, 90, 110))
	sy = wy + wave_h
	spec = info["spec"]
	df = SR / info["size"]
	top = 1e-9
	for mags in spec:
		top = max(top, max(mags))
	ftop = math.log(F_HI / F_LO)
	for col in range(used):
		mags = spec[min(len(spec) - 1, int(col * len(spec) / used))]
		for row in range(spec_h):
			f = F_LO * math.exp(ftop * (1.0 - row / (spec_h - 1)))
			k = min(len(mags) - 1, int(f / df))
			level = dsp.db(mags[k] / top)
			cv.set(ox + 1 + col, sy + row, heat((level + 72.0) / 72.0))
	cent = info["cent"]
	for col in range(used):
		c = cent[min(len(cent) - 1, int(col * len(cent) / used))]
		if c <= F_LO:
			continue
		row = int((1.0 - math.log(c / F_LO) / ftop) * (spec_h - 1))
		cv.set(ox + 1 + col, sy + row, (80, 255, 160))
		cv.set(ox + 1 + col, sy + row + 1, (80, 255, 160))
	# frequency guides at 100 Hz, 1 kHz, 10 kHz
	for f in (100.0, 1000.0, 10000.0):
		row = int((1.0 - math.log(f / F_LO) / ftop) * (spec_h - 1))
		for col in range(0, pw, 4):
			cv.set(ox + col, sy + row, (120, 120, 140))
	return label_h + wave_h + spec_h


def sheet(infos, path, cols=3, pw=420, same_scale=False):
	ph = 22 + 56 + 130
	rows = (len(infos) + cols - 1) // cols
	cv = Canvas(cols * (pw + 6) + 6, rows * (ph + 6) + 6)
	longest = max(i["seconds"] for i in infos)
	for k, info in enumerate(infos):
		r, c = divmod(k, cols)
		draw_panel(cv, 6 + c * (pw + 6), 6 + r * (ph + 6), pw, info, longest if same_scale else info["seconds"])
	cv.save(path)


# --- main ---------------------------------------------------------------------

def main(argv):
	if "--selftest" in argv:
		selftest()
		return 0
	prefixes = [a for a in argv if not a.startswith("--")]
	opts = dict(a[2:].split("=", 1) if "=" in a else (a[2:], "") for a in argv if a.startswith("--"))
	files = sorted(f for f in os.listdir(SFX) if f.endswith(".wav"))
	if prefixes:
		files = [f for f in files if any(f.startswith(p) for p in prefixes)]
	from concurrent.futures import ProcessPoolExecutor
	with ProcessPoolExecutor() as pool:
		infos = list(pool.map(analyse, [os.path.join(SFX, f) for f in files]))
	failed = 0
	print("%-26s %5s %6s %6s %6s %6s %5s %6s  %-35s %s" % ("file", "secs", "pk", "tp", "lufs", "cent", "att", "tail",
			"octaves 63..16k (dB re loudest)", "problems"))
	for info in infos:
		bad = problems(info)
		failed += bool(bad)
		b = info["bands"]
		extra = ""
		if info["loop"]:
			extra = " seam %.2fx %+.1fdB" % (info["seam_jump"], info["seam_step_db"])
		octs = " ".join("%3d" % max(-99, round(o)) for o in info["octaves"])
		print("%-26s %5.2f %6.1f %6.1f %6.1f %6.0f %5.2f %6.1f  %-35s %s%s" % (
				info["name"], info["seconds"], info["peak_db"], info["true_peak_db"], info["lufs"], info["centroid"],
				info["attack"], info["tail_db"], octs, "; ".join(bad) if bad else "ok", extra))
	if "png" in opts:
		out = opts["png"]
		os.makedirs(out, exist_ok=True)
		cols = int(opts.get("cols", "3"))
		groups = {}
		for info in infos:
			groups.setdefault(info["name"].split("_")[0], []).append(info)
		for key, group in groups.items():
			for start in range(0, len(group), cols * 6):
				part = group[start:start + cols * 6]
				name = "%s%s.png" % (key, "" if start == 0 else "_%d" % (start // (cols * 6) + 1))
				sheet(part, os.path.join(out, name), cols, same_scale="same" in opts)
		print("sheets ->", out)
	kinds = {}
	for info in infos:
		spec = spec_of(info["name"])
		if spec:
			kinds.setdefault(spec["kind"], []).append(info["lufs"])
	print("loudness by kind (target, measured min..max):")
	for kind, values in sorted(kinds.items()):
		print("  %-8s %6.1f  %6.1f .. %6.1f  (%d files)" % (kind, build_sfx.TARGET[kind], min(values), max(values), len(values)))
	print("%d files, %d with problems" % (len(infos), failed))
	return 1 if failed else 0


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))
