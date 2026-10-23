"""A small DSP kit for the procedural sound effects: Python stdlib only.

Signals are plain lists of floats at 44.1 kHz, nominally within -1..1. Parameters
that can move over time (cutoffs, pitches, amounts) accept a number, a callable
of time in seconds, or a list with one value per sample.

Building blocks, roughly in the order the recipes use them:
  noise        white / pink / brown sources (seeded random.Random)
  filters      TPT state-variable filter (lp/bp/hp, sweepable), one-pole, biquads
  oscillators  sine, polyBLEP square/saw, FM, pitched-down thump
  envelopes    attack + exponential decay, piecewise curves, fades
  events       crackle grains, glassy pings, modal partials
  space        a small Schroeder reverb for big tails
  mastering    K-weighted loudness, lookahead limiter, seamless loops, WAV out
"""
import array
import math
import struct

SR = 44100
TAU = 2.0 * math.pi


def n_of(seconds):
	return max(1, int(round(seconds * SR)))


def zeros(n):
	return [0.0] * n


def _per_sample(p, n):
	"""A number, a callable of t (s), or a list -> a list of n values."""
	if callable(p):
		inv = 1.0 / SR
		return [p(i * inv) for i in range(n)]
	if isinstance(p, (list, tuple)):
		if len(p) >= n:
			return list(p[:n])
		return list(p) + [p[-1]] * (n - len(p))
	return [float(p)] * n


def _at(p, i):
	"""Value of a parameter at sample i (for block-rate updates)."""
	if callable(p):
		return p(i / SR)
	if isinstance(p, (list, tuple)):
		return p[min(i, len(p) - 1)]
	return p


# --- arithmetic ---------------------------------------------------------------

def scale(x, g):
	return [v * g for v in x]


def mul(a, b):
	return [u * v for u, v in zip(a, b)]


def add_into(dst, src, at=0, gain=1.0):
	"""Mixes src into dst starting at sample `at` (clipped to dst's length)."""
	if at < 0:
		src = src[-at:]
		at = 0
	end = min(len(dst), at + len(src))
	for i in range(at, end):
		dst[i] += src[i - at] * gain
	return dst


def mix(n, *layers):
	"""mix(n, (signal, gain[, offset_seconds]), ...) -> new list of length n."""
	out = zeros(n)
	for layer in layers:
		sig, gain = layer[0], layer[1]
		offset = n_of(layer[2]) if len(layer) > 2 and layer[2] > 0 else 0
		add_into(out, sig, offset, gain)
	return out


def peak(x):
	return max((abs(v) for v in x), default=0.0)


def db(v):
	return 20.0 * math.log10(max(v, 1e-12))


def undb(d):
	return 10.0 ** (d / 20.0)


# --- noise --------------------------------------------------------------------

def white(n, rng):
	u = rng.random
	return [2.0 * u() - 1.0 for _ in range(n)]


def pink(n, rng):
	"""Paul Kellet's refined pink filter over white noise (about unit peak)."""
	u = rng.random
	b0 = b1 = b2 = b3 = b4 = b5 = b6 = 0.0
	out = [0.0] * n
	for i in range(n):
		w = 2.0 * u() - 1.0
		b0 = 0.99886 * b0 + w * 0.0555179
		b1 = 0.99332 * b1 + w * 0.0750759
		b2 = 0.96900 * b2 + w * 0.1538520
		b3 = 0.86650 * b3 + w * 0.3104856
		b4 = 0.55000 * b4 + w * 0.5329522
		b5 = -0.7616 * b5 - w * 0.0168980
		out[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.2
		b6 = w * 0.115926
	return out


def brown(n, rng, corner=20.0):
	"""Leaky-integrated white noise (red/brown), normalised to unit peak."""
	u = rng.random
	a = math.exp(-TAU * corner / SR)
	y = 0.0
	out = [0.0] * n
	for i in range(n):
		y = a * y + (1.0 - a) * (2.0 * u() - 1.0)
		out[i] = y
	p = peak(out)
	return scale(out, 1.0 / p) if p > 0 else out


def smooth_noise(n, rng, rate, lo=-1.0, hi=1.0):
	"""Slow random wobble: random points every 1/rate s, cosine-interpolated."""
	step = max(1, int(SR / max(rate, 0.01)))
	points = [rng.uniform(lo, hi) for _ in range(n // step + 3)]
	out = [0.0] * n
	for i in range(n):
		k, r = divmod(i, step)
		t = r / step
		w = 0.5 - 0.5 * math.cos(math.pi * t)
		out[i] = points[k] * (1.0 - w) + points[k + 1] * w
	return out


# --- filters ------------------------------------------------------------------

def svf(x, fc, q=0.707, mode="lp", block=16):
	"""Topology-preserving state-variable filter (Zavalishin), stable under fast
	sweeps. `fc` and `q` may move. mode: lp, bp (unity peak), bpq (peak = q), hp,
	notch."""
	n = len(x)
	out = [0.0] * n
	ic1 = ic2 = 0.0
	nyq = SR * 0.45
	for start in range(0, n, block):
		f = min(max(_at(fc, start), 8.0), nyq)
		qq = max(_at(q, start), 0.05)
		k = 1.0 / qq
		g = math.tan(math.pi * f / SR)
		a1 = 1.0 / (1.0 + g * (g + k))
		a2 = g * a1
		a3 = g * a2
		end = min(n, start + block)
		if mode == "lp":
			for i in range(start, end):
				v3 = x[i] - ic2
				v1 = a1 * ic1 + a2 * v3
				v2 = ic2 + a2 * ic1 + a3 * v3
				ic1 = 2.0 * v1 - ic1
				ic2 = 2.0 * v2 - ic2
				out[i] = v2
		elif mode == "bp" or mode == "bpq":
			gain = k if mode == "bp" else 1.0
			for i in range(start, end):
				v3 = x[i] - ic2
				v1 = a1 * ic1 + a2 * v3
				v2 = ic2 + a2 * ic1 + a3 * v3
				ic1 = 2.0 * v1 - ic1
				ic2 = 2.0 * v2 - ic2
				out[i] = v1 * gain
		elif mode == "hp":
			for i in range(start, end):
				v0 = x[i]
				v3 = v0 - ic2
				v1 = a1 * ic1 + a2 * v3
				v2 = ic2 + a2 * ic1 + a3 * v3
				ic1 = 2.0 * v1 - ic1
				ic2 = 2.0 * v2 - ic2
				out[i] = v0 - k * v1 - v2
		elif mode == "notch":
			for i in range(start, end):
				v0 = x[i]
				v3 = v0 - ic2
				v1 = a1 * ic1 + a2 * v3
				v2 = ic2 + a2 * ic1 + a3 * v3
				ic1 = 2.0 * v1 - ic1
				ic2 = 2.0 * v2 - ic2
				out[i] = v0 - k * v1
		else:
			raise ValueError(mode)
	return out


def lp(x, fc, q=0.707):
	return svf(x, fc, q, "lp")


def hp(x, fc, q=0.707):
	return svf(x, fc, q, "hp")


def bp(x, fc, q=1.0):
	return svf(x, fc, q, "bp")


def lp4(x, fc):
	"""24 dB/oct low-pass (two cascaded Butterworth-ish sections)."""
	return svf(svf(x, fc, 0.54, "lp"), fc, 1.31, "lp")


def hp4(x, fc):
	return svf(svf(x, fc, 0.54, "hp"), fc, 1.31, "hp")


def onepole_lp(x, fc):
	a = 1.0 - math.exp(-TAU * fc / SR)
	y = 0.0
	out = [0.0] * len(x)
	for i, v in enumerate(x):
		y += a * (v - y)
		out[i] = y
	return out


def biquad(x, b0, b1, b2, a1, a2):
	x1 = x2 = y1 = y2 = 0.0
	out = [0.0] * len(x)
	for i, v in enumerate(x):
		y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = v
		y2 = y1
		y1 = y
		out[i] = y
	return out


def peaking(x, f, q, gain_db):
	"""RBJ peaking EQ."""
	a = 10.0 ** (gain_db / 40.0)
	w = TAU * f / SR
	alpha = math.sin(w) / (2.0 * q)
	cw = math.cos(w)
	a0 = 1.0 + alpha / a
	return biquad(x, (1.0 + alpha * a) / a0, -2.0 * cw / a0, (1.0 - alpha * a) / a0,
			-2.0 * cw / a0, (1.0 - alpha / a) / a0)


def shelf(x, f, gain_db, high=True, s=1.0):
	"""RBJ shelving EQ (high or low)."""
	a = 10.0 ** (gain_db / 40.0)
	w = TAU * f / SR
	cw = math.cos(w)
	alpha = math.sin(w) / 2.0 * math.sqrt((a + 1.0 / a) * (1.0 / s - 1.0) + 2.0)
	sa = 2.0 * math.sqrt(a) * alpha
	if high:
		b0 = a * ((a + 1) + (a - 1) * cw + sa)
		b1 = -2 * a * ((a - 1) + (a + 1) * cw)
		b2 = a * ((a + 1) + (a - 1) * cw - sa)
		a0 = (a + 1) - (a - 1) * cw + sa
		a1 = 2 * ((a - 1) - (a + 1) * cw)
		a2 = (a + 1) - (a - 1) * cw - sa
	else:
		b0 = a * ((a + 1) - (a - 1) * cw + sa)
		b1 = 2 * a * ((a - 1) - (a + 1) * cw)
		b2 = a * ((a + 1) - (a - 1) * cw - sa)
		a0 = (a + 1) + (a - 1) * cw + sa
		a1 = -2 * ((a - 1) + (a + 1) * cw)
		a2 = (a + 1) + (a - 1) * cw - sa
	return biquad(x, b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)


def dc_block(x, fc=22.0):
	"""Second-order high-pass well below hearing: kills DC and sub rumble."""
	return svf(svf(x, fc, 0.6, "hp"), fc, 0.6, "hp")


def resonate(x, f, tau):
	"""Two-pole resonator ringing at f with decay time tau, unity-ish gain."""
	r = math.exp(-1.0 / (tau * SR))
	w = TAU * f / SR
	c1 = 2.0 * r * math.cos(w)
	c2 = -r * r
	g = (1.0 - r * r) * 0.5
	y1 = y2 = 0.0
	out = [0.0] * len(x)
	for i, v in enumerate(x):
		y = g * v + c1 * y1 + c2 * y2
		y2 = y1
		y1 = y
		out[i] = y
	return out


# --- oscillators --------------------------------------------------------------

def phases(freq, n, phase=0.0):
	"""Running phase in cycles for a (possibly moving) frequency."""
	fs = _per_sample(freq, n)
	out = [0.0] * n
	p = phase
	inv = 1.0 / SR
	for i in range(n):
		out[i] = p
		p += fs[i] * inv
	return out


def sine(freq, n, phase=0.0):
	sin = math.sin
	return [sin(TAU * p) for p in phases(freq, n, phase)]


def _blep(t, dt):
	if t < dt:
		t /= dt
		return t + t - t * t - 1.0
	if t > 1.0 - dt:
		t = (t - 1.0) / dt
		return t * t + t + t + 1.0
	return 0.0


def saw(freq, n, phase=0.0):
	"""Band-limited (polyBLEP) sawtooth."""
	fs = _per_sample(freq, n)
	out = [0.0] * n
	p = phase % 1.0
	for i in range(n):
		dt = fs[i] / SR
		out[i] = 2.0 * p - 1.0 - _blep(p, dt)
		p += dt
		if p >= 1.0:
			p -= 1.0
	return out


def square(freq, n, pw=0.5, phase=0.0):
	"""Band-limited (polyBLEP) pulse wave with pulse width pw."""
	fs = _per_sample(freq, n)
	out = [0.0] * n
	p = phase % 1.0
	for i in range(n):
		dt = fs[i] / SR
		v = 1.0 if p < pw else -1.0
		v += _blep(p, dt)
		q = (p - pw) % 1.0
		v -= _blep(q, dt)
		out[i] = v
		p += dt
		if p >= 1.0:
			p -= 1.0
	return out


def fm(carrier, modulator, index, n, phase=0.0):
	"""Phase modulation: sin(carrier + index * sin(modulator)); all may move."""
	pc = phases(carrier, n, phase)
	pm = phases(modulator, n)
	ix = _per_sample(index, n)
	sin = math.sin
	return [sin(TAU * pc[i] + ix[i] * sin(TAU * pm[i])) for i in range(n)]


def thump(seconds, f_start, f_end, sweep_tau, decay_tau, attack=0.0015, drive=1.0):
	"""A pitched-down sine kick: the body of booms, punches and impacts."""
	n = n_of(seconds)
	freq = lambda t: f_end + (f_start - f_end) * math.exp(-t / sweep_tau)
	tone = sine(freq, n)
	env = env_exp(n, attack, decay_tau)
	out = mul(tone, env)
	if drive != 1.0:
		out = saturate(out, drive)
	return out


# --- envelopes ----------------------------------------------------------------

def env_exp(n, attack, tau, delay=0.0, hold=0.0):
	"""0 before `delay`, a raised-cosine attack, a hold, then exp(-t/tau)."""
	out = [0.0] * n
	d = int(delay * SR)
	a = max(1, int(attack * SR))
	h = int(hold * SR)
	k = math.exp(-1.0 / (max(tau, 1e-4) * SR))
	v = 1.0
	cos = math.cos
	for i in range(d, n):
		j = i - d
		if j < a:
			out[i] = 0.5 - 0.5 * cos(math.pi * j / a)
		elif j < a + h:
			out[i] = 1.0
		else:
			out[i] = v
			v *= k
	return out


def env_points(n, points, curve="lin"):
	"""Piecewise envelope through (seconds, value) pairs. curve 'lin' or 'cos'
	(smooth), or 'exp' (straight lines in dB; values must be > 0)."""
	out = [0.0] * n
	pts = sorted(points)
	for i in range(n):
		t = i / SR
		if t <= pts[0][0]:
			out[i] = pts[0][1]
			continue
		if t >= pts[-1][0]:
			out[i] = pts[-1][1]
			continue
		for k in range(1, len(pts)):
			if t <= pts[k][0]:
				t0, v0 = pts[k - 1]
				t1, v1 = pts[k]
				u = (t - t0) / max(t1 - t0, 1e-9)
				if curve == "cos":
					u = 0.5 - 0.5 * math.cos(math.pi * u)
					out[i] = v0 + (v1 - v0) * u
				elif curve == "exp":
					out[i] = math.exp(math.log(v0) + (math.log(v1) - math.log(v0)) * u)
				else:
					out[i] = v0 + (v1 - v0) * u
				break
	return out


def riser(n, start_db=-30.0, power=2.0):
	"""0 dB at the end, `start_db` at the start, curving up like a charge."""
	out = [0.0] * n
	for i in range(n):
		u = i / max(n - 1, 1)
		out[i] = undb(start_db * (1.0 - u) ** power)
	return out


def fade(x, fade_in=0.003, fade_out=0.01):
	"""Raised-cosine fades at both ends (in place, returns x)."""
	n = len(x)
	a = min(n, max(1, int(fade_in * SR)))
	b = min(n, max(1, int(fade_out * SR)))
	for i in range(a):
		x[i] *= 0.5 - 0.5 * math.cos(math.pi * i / a)
	for i in range(b):
		x[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / b)
	x[0] = 0.0
	x[-1] = 0.0
	return x


def saturate(x, drive=2.0):
	"""tanh soft clip normalised so that full scale stays full scale."""
	norm = 1.0 / math.tanh(drive)
	th = math.tanh
	return [th(drive * v) * norm for v in x]


# --- events -------------------------------------------------------------------

def poisson_times(seconds, rate, rng, start=0.0):
	"""Event times (s) of a Poisson process; `rate` (events/s) is a number or a
	callable of time (sampled by thinning against its maximum)."""
	fn = rate if callable(rate) else (lambda _t: rate)
	grid = [max(fn(start + (seconds - start) * k / 256.0), 0.0) for k in range(257)]
	rmax = max(grid) * 1.05
	times = []
	if rmax <= 0.0:
		return times
	t = start
	while True:
		t += rng.expovariate(rmax)
		if t >= seconds:
			return times
		if rng.random() * rmax <= max(fn(t), 0.0):
			times.append(t)


def grain(rng, length, f, q, bright=0.0):
	"""One crackle: a decaying noise tick rung through a band-pass at f, with
	`bright` of the raw tick mixed back in. A 0.2 ms rise and a 9 kHz
	low-pass keep it crisp without a raw step or top-octave fizz."""
	n = max(18, int(length * SR))
	src = [(2.0 * rng.random() - 1.0) * math.exp(-3.0 * i / n) for i in range(n)]
	for i in range(9):
		src[i] *= 0.5 - 0.5 * math.cos(math.pi * (i + 0.5) / 9.0)
	out = svf(src, f, q, "bp", block=n)
	if bright > 0:
		out = [o + bright * s for o, s in zip(out, src)]
	return svf(out + [0.0] * 8, 9000.0, 0.6, "lp", block=n + 8)


def crackle(seconds, rng, rate, f_lo=1500.0, f_hi=6000.0, length=(0.0006, 0.004),
		q=1.5, amp_power=2.5, bright=0.3, amp=None):
	"""Sparse random pops (fire crackle, sparks, grit). amp_power > 1 makes most
	pops small and a few loud. `amp` optionally scales pops by time (callable)."""
	n = n_of(seconds)
	out = zeros(n)
	for t in poisson_times(seconds, rate, rng):
		a = rng.random() ** amp_power
		if amp is not None:
			a *= amp(t)
		f = math.exp(rng.uniform(math.log(f_lo), math.log(f_hi)))
		# at least 1.5 cycles of its own pitch: a "tik", never a bare step
		g = grain(rng, max(rng.uniform(*length), 1.5 / f), f, q, bright)
		sign = 1.0 if rng.random() < 0.5 else -1.0
		add_into(out, g, int(t * SR), a * sign)
	return out


def ping(seconds, f, tau, rng=None, attack=0.0004, partials=((1.0, 1.0, 1.0),), detune=0.0):
	"""A glassy ping: decaying sines. partials = (ratio, amp, tau_scale) triples."""
	n = n_of(seconds)
	out = zeros(n)
	sin = math.sin
	for ratio, amp, tscale in partials:
		fr = f * ratio * (1.0 + (rng.uniform(-detune, detune) if rng else 0.0))
		if fr >= SR * 0.45:
			continue
		k = math.exp(-1.0 / (max(tau * tscale, 1e-4) * SR))
		w = TAU * fr / SR
		ph = rng.random() * TAU if rng else 0.0
		v = amp
		a = max(1, int(attack * SR))
		for i in range(n):
			e = v * (i / a if i < a else 1.0)
			if e < 1e-5 and i > a:
				break
			out[i] += e * sin(w * i + ph)
			v *= k
	return out


# Mode ratios for struck objects (free-free bar, glass, metal plate-ish).
BAR = (1.0, 2.756, 5.404, 8.933)
GLASS = (1.0, 2.32, 4.25, 6.63, 9.38)
PLATE = (1.0, 1.59, 2.14, 2.30, 2.65, 2.92, 3.16, 3.50)


def modal(seconds, f, ratios, amps, taus, rng=None, detune=0.0, attack=0.0005):
	return ping(seconds, f, 1.0, rng, attack,
			tuple((r, a, t) for r, a, t in zip(ratios, amps, taus)), detune)


# --- space --------------------------------------------------------------------

def reverb(x, room=0.75, damp=0.35, wet=0.3, tail=1.0, predelay=0.012):
	"""A compact mono Schroeder/Freeverb: 6 damped combs into 3 allpasses.
	Returns dry + wet, extended by `tail` seconds. The dry input is faded over
	its last 30 ms first, so the hand-over to the tail is never a step."""
	x = fade(list(x), 0.0, 0.03)
	n = len(x) + n_of(tail)
	src = x + zeros(n - len(x))
	pd = int(predelay * SR)
	if pd:
		src = zeros(pd) + src[: n - pd]
	combs = [1116, 1188, 1277, 1356, 1422, 1491]
	acc = zeros(n)
	fb = 0.70 + 0.28 * room
	for length in combs:
		buf = [0.0] * length
		idx = 0
		store = 0.0
		for i in range(n):
			o = buf[idx]
			store = o * (1.0 - damp) + store * damp
			buf[idx] = src[i] + store * fb
			acc[i] += o
			idx += 1
			if idx == length:
				idx = 0
	for length in (556, 441, 341):
		buf = [0.0] * length
		idx = 0
		for i in range(n):
			b = buf[idx]
			v = acc[i]
			buf[idx] = v + b * 0.5
			acc[i] = b - v
			idx += 1
			if idx == length:
				idx = 0
	g = wet / len(combs)
	out = x + zeros(n - len(x))
	for i in range(n):
		out[i] += acc[i] * g
	return out


# --- mastering ----------------------------------------------------------------

def _k_weight(x):
	"""ITU-R BS.1770 K-weighting (pre-filter shelf + RLB high-pass) at SR."""
	# stage 1: high shelf
	G, Q, fc = 3.99984385397, 0.7071752369554193, 1681.9744509555319
	K = math.tan(math.pi * fc / SR)
	Vh = 10.0 ** (G / 20.0)
	Vb = Vh ** 0.499666774155
	a0 = 1.0 + K / Q + K * K
	y = biquad(x, (Vh + Vb * K / Q + K * K) / a0, 2.0 * (K * K - Vh) / a0,
			(Vh - Vb * K / Q + K * K) / a0, 2.0 * (K * K - 1.0) / a0, (1.0 - K / Q + K * K) / a0)
	# stage 2: high-pass
	Q, fc = 0.5003270373253953, 38.13547087613982
	K = math.tan(math.pi * fc / SR)
	a0 = 1.0 + K / Q + K * K
	return biquad(y, 1.0, -2.0, 1.0, 2.0 * (K * K - 1.0) / a0, (1.0 - K / Q + K * K) / a0)


def loudness(x, window=0.4, hop=0.1):
	"""(max momentary LUFS over 400 ms windows, integrated LUFS) of a mono
	signal. Short sounds are measured as if padded with silence."""
	y = _k_weight(x)
	sq = [v * v for v in y]
	w = n_of(window)
	h = n_of(hop)
	if len(sq) < w:
		sq = sq + [0.0] * (w - len(sq))
	# running sums
	cum = [0.0]
	s = 0.0
	for v in sq:
		s += v
		cum.append(s)
	blocks = []
	for start in range(0, len(sq) - w + 1, h):
		blocks.append((cum[start + w] - cum[start]) / w)
	if not blocks:
		blocks = [cum[-1] / max(len(sq), 1)]
	lufs = lambda ms: -0.691 + 10.0 * math.log10(max(ms, 1e-12))
	momentary = max(lufs(b) for b in blocks)
	# integrated with the -70 LUFS absolute and -10 LU relative gates
	gated = [b for b in blocks if lufs(b) > -70.0]
	if not gated:
		return momentary, -99.0
	rel = lufs(sum(gated) / len(gated)) - 10.0
	gated = [b for b in gated if lufs(b) > rel] or gated
	return momentary, lufs(sum(gated) / len(gated))


def _sinc_phases(taps=6):
	out = []
	for ph in (0.25, 0.5, 0.75):
		ks = []
		for k in range(-taps + 1, taps + 1):
			d = k - ph
			s = math.sin(math.pi * d) / (math.pi * d)
			ks.append((k, s * (0.5 + 0.5 * math.cos(math.pi * d / taps))))
		out.append(ks)
	return out


_PHASES = _sinc_phases()


def inter_peaks(x, floor):
	"""Per-sample peak including the 4x-oversampled points up to the next
	sample (a true-peak estimate). Only samples near `floor` or above are
	interpolated; quieter stretches can't overshoot it."""
	n = len(x)
	out = [abs(v) for v in x]
	for i in range(n - 1):
		if out[i] < floor * 0.5 and abs(x[i + 1]) < floor * 0.5:
			continue
		for ks in _PHASES:
			acc = 0.0
			for k, c in ks:
				j = i + k
				if 0 <= j < n:
					acc += x[j] * c
			acc = abs(acc)
			if acc > out[i]:
				out[i] = acc
	return out


def true_peak(x):
	p = peak(x)
	return max(inter_peaks(x, p * 0.7)) if p > 0 else 0.0


def limiter(x, ceiling_db=-1.0, lookahead=0.0015, release=0.06, circular=False):
	"""Lookahead true-peak limiter: neither samples nor the points between them
	(4x oversampled) pass the ceiling; the gain ramps down over `lookahead`
	before a peak and recovers over `release`. With circular=True the signal is
	treated as a loop (no seam in the gain)."""
	n = len(x)
	if circular:
		y = limiter(x + x + x, ceiling_db, lookahead, release)
		return y[n:2 * n]
	ceil = undb(ceiling_db)
	peaks = inter_peaks(x, ceil)
	need = [min(1.0, ceil / p) if p > 0.0 else 1.0 for p in peaks]
	for i in range(n - 1, 0, -1):
		# the overshoot between i-1 and i is fixed by gain at both neighbours
		if need[i - 1] < need[i]:
			need[i] = need[i - 1]
	if min(need) >= 1.0:
		return list(x)
	L = max(1, int(lookahead * SR))
	# forward-looking sliding minimum over [i, i + L]
	from collections import deque
	fwd = [1.0] * n
	dq = deque()
	for i in range(n - 1, -1, -1):
		while dq and need[dq[-1]] >= need[i]:
			dq.pop()
		dq.append(i)
		while dq[0] > i + L:
			dq.popleft()
		fwd[i] = need[dq[0]]
	# backward box average over [i - L + 1, i] -> smooth attack, still <= need at peaks
	box = [0.0] * n
	s = 0.0
	for i in range(n):
		s += fwd[i]
		if i >= L:
			s -= fwd[i - L]
		box[i] = s / min(i + 1, L)
	# release: recover gently, never above the box curve
	k = 1.0 - math.exp(-1.0 / (release * SR))
	g = 1.0
	out = [0.0] * n
	for i in range(n):
		b = box[i]
		if b < g:
			g = b
		else:
			g += (b - g) * k
		v = x[i] * g
		out[i] = max(-ceil, min(ceil, v))
	return out


def master(x, target_lufs, ceiling_db=-1.0, loop=False, measure="momentary"):
	"""Gain to the target loudness, then peak-limit to the ceiling (repeats a
	couple of times since limiting lowers loudness). Returns (signal, info)."""
	y = list(x)
	reduction = 0.0
	for _ in range(8):
		m, integ = loudness(y + y if loop else y)
		cur = integ if (loop or measure == "integrated") else m
		gain = undb(target_lufs - cur)
		y = scale(y, gain)
		before = peak(y)
		y = limiter(y, ceiling_db, circular=loop)
		after = peak(y)
		reduction = max(0.0, db(before) - db(after)) if before > 0 else 0.0
		m, integ = loudness(y + y if loop else y)
		cur = integ if (loop or measure == "integrated") else m
		if abs(cur - target_lufs) < 0.3:
			break
	return y, {"lufs": cur, "peak_db": db(peak(y)), "tp_db": db(true_peak(y)), "limited_db": reduction}


def active_rms(x, window=0.03):
	"""RMS of the loudest `window`-long stretch: how loud a layer is when it
	speaks, regardless of how long it lasts."""
	w = n_of(window)
	if len(x) <= w:
		return math.sqrt(sum(v * v for v in x) / max(len(x), 1))
	cum = [0.0]
	s = 0.0
	for v in x:
		s += v * v
		cum.append(s)
	best = 0.0
	for start in range(0, len(x) - w + 1, max(1, w // 4)):
		best = max(best, cum[start + w] - cum[start])
	return math.sqrt(best / w)


def stack(n, *layers):
	"""stack(n, (signal, gain_db[, offset_s]), ...): sets each layer's loudest
	30 ms to `gain_db` RMS before summing, so the gains read as how loud each
	layer is against the others (a sine and a noise burst at the same peak are
	~10 dB apart in loudness)."""
	out = zeros(n)
	for layer in layers:
		sig, gain_db = layer[0], layer[1]
		offset = n_of(layer[2]) if len(layer) > 2 and layer[2] > 0 else 0
		r = active_rms(sig)
		if r > 0.0:
			add_into(out, sig, offset, undb(gain_db) / r)
	return out


def make_loop(x, loop_seconds, xfade_seconds):
	"""Turns len >= loop + xfade samples into a seamless loop of `loop` samples:
	the run-on past the end is equal-power crossfaded into the head, so the
	wrap from the last sample to the first is continuous."""
	L = n_of(loop_seconds)
	X = n_of(xfade_seconds)
	assert len(x) >= L + X, "loop source too short"
	out = list(x[:L])
	for i in range(X):
		u = i / X
		fi = math.sin(0.5 * math.pi * u)
		fo = math.cos(0.5 * math.pi * u)
		out[i] = x[i] * fi + x[L + i] * fo
	return out


def write_wav(path, x, loop=False):
	"""16-bit mono PCM. A loop gets a `smpl` chunk (forward loop over the whole
	file) that Godot's importer reads, plus one wrap-around guard sample so the
	resampler's lookahead at the seam reads the loop's first sample."""
	ints = array.array("h", (int(round(max(-1.0, min(1.0, v)) * 32767.0)) for v in x))
	frames = len(ints)
	if loop:
		ints.append(ints[0])
	data = ints.tobytes()
	fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
	chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
	chunks += b"data" + struct.pack("<I", len(data)) + data
	if len(data) % 2:
		chunks += b"\0"
	if loop:
		smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
		smpl += struct.pack("<6I", 0, 0, 0, frames, 0, 0)
		chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
	with open(path, "wb") as f:
		f.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)


def read_wav(path):
	"""Reads a 16-bit mono WAV -> (samples as floats, loop (begin, end) or None)."""
	with open(path, "rb") as f:
		raw = f.read()
	assert raw[:4] == b"RIFF" and raw[8:12] == b"WAVE", path
	pos = 12
	samples = None
	loop = None
	while pos + 8 <= len(raw):
		cid = raw[pos:pos + 4]
		size = struct.unpack("<I", raw[pos + 4:pos + 8])[0]
		body = raw[pos + 8:pos + 8 + size]
		if cid == b"fmt ":
			fmt, ch, sr, _, _, bits = struct.unpack("<HHIIHH", body[:16])
			assert fmt == 1 and ch == 1 and bits == 16 and sr == SR, (path, fmt, ch, sr, bits)
		elif cid == b"data":
			a = array.array("h")
			a.frombytes(body)
			samples = [v / 32767.0 for v in a]
		elif cid == b"smpl":
			vals = struct.unpack("<15I", body[:60])
			if vals[7] >= 1:
				loop = (vals[11], vals[12])
		pos += 8 + size + (size & 1)
	return samples, loop
