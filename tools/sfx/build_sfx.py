"""Synthesises every sound effect into assets/sfx/*.wav (44.1 kHz, 16-bit mono).

Original procedural sounds only, Python stdlib only. Every sound is seeded, so a
re-run rewrites byte-identical files. Each one is DC-blocked, faded at both ends
(one-shots) or crossfaded into a seamless loop (loops: a `smpl` chunk tells
Godot's importer to loop it), then gained to its kind's loudness target (K-weighted
LUFS) and true-peak limited to -1 dBFS.

Recipes stack layers by loudness (dsp.stack): each layer's gain is how loud its
loudest 30 ms is, in dB against the others.

Frequently repeated sounds come in variants (<name>_1.wav, _2, _3); SpellSfx and
CombatSfx pick one at random and jitter the pitch.

    uv run --no-project python -I tools/sfx/build_sfx.py            # everything
    uv run --no-project python -I tools/sfx/build_sfx.py fire_hit   # some names
    uv run --no-project python -I tools/sfx/build_sfx.py --list

Check the results with tools/sfx/analyze_sfx.py (levels, clicks, loop seams,
waveform and spectrogram sheets).
"""
import math
import os
import random
import sys
import time
import zlib

sys.stdout.reconfigure(encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dsp  # noqa: E402
from dsp import (n_of, mul, svf, env_exp, pink, white, brown, crackle, stack,  # noqa: E402
		thump, saturate, smooth_noise, sine, square, fm, ping, GLASS, PLATE, BAR, SR)

REPO = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(REPO, "assets", "sfx")

# Loudness target per kind: max momentary LUFS for one-shots, integrated for
# loops. Big moments sit loudest; loops and charges sit under the one-shots.
TARGET = {
	"charge": -20.0, "release": -17.0, "hit": -16.0, "surface": -16.5, "fizzle": -22.0,
	"loop": -22.0, "wall": -22.5, "shock": -21.0, "warning": -17.0, "big": -13.0,
	"swing": -19.0, "melee": -15.5, "clang": -15.5, "parry": -14.5, "break": -13.5,
	"move": -21.0, "land": -18.5, "death": -15.0,
}
# Fade in / out (s) per kind; impacts keep their snap with the 3 ms minimum.
FADES = {"charge": (0.006, 0.012), "fizzle": (0.006, 0.04), "warning": (0.006, 0.01)}

SOUNDS = {}


def sound(name, kind, variants=1, loop=None, held=False):
	"""Registers a recipe fn(rng, v) -> samples. loop = (seconds, crossfade).
	held: the sound ends at full level on purpose (the game cuts it)."""
	def deco(fn):
		SOUNDS[name] = dict(fn=fn, kind=kind, variants=variants, loop=loop, held=held)
		return fn
	return deco


# --- shared gestures ----------------------------------------------------------

def norm(x, level=1.0):
	p = dsp.peak(x)
	return dsp.scale(x, level / p) if p > 0 else x


def sweep(f0, f1, dur, delay=0.0):
	"""Exponential glide f0 -> f1 over dur (after delay), then holds f1."""
	ratio = f1 / f0
	return lambda t: f0 * ratio ** min(max(t - delay, 0.0) / dur, 1.0)


def arc(f0, f_peak, f1, t_peak, t_end):
	"""Up to f_peak at t_peak, then down to f1 at t_end (exponential legs)."""
	def f(t):
		if t < t_peak:
			return f0 * (f_peak / f0) ** (t / t_peak)
		return f_peak * (f1 / f_peak) ** min((t - t_peak) / max(t_end - t_peak, 1e-3), 1.0)
	return f


def noise(color, n, rng):
	return {"white": white, "pink": pink, "brown": brown}[color](n, rng)


def band(rng, seconds, f, q=1.0, color="pink"):
	return svf(noise(color, n_of(seconds), rng), f, q, "bp")


def hiss(n, rng, lo=3000.0, hi=10000.0):
	"""Band-limited white noise: air and sizzle without the 15 kHz+ fizz."""
	return svf(svf(white(n, rng), lo, 0.707, "hp"), hi, 0.707, "lp")


def burst(rng, seconds, attack, tau, color="white", lp=None, hp=None, bp=None, q=0.8, hold=0.0, delay=0.0):
	"""Filtered noise with a fast attack and exponential decay (peak 1)."""
	n = n_of(seconds)
	x = noise(color, n, rng)
	if bp is not None:
		x = svf(x, bp, q, "bp")
	if lp is not None:
		x = svf(x, lp, 0.707, "lp")
	if hp is not None:
		x = svf(x, hp, 0.707, "hp")
	return norm(mul(x, env_exp(n, attack, tau, delay=delay, hold=hold)))


def whump(rng, seconds, fc, attack, tau, delay=0.0):
	"""A low-mid noise thud (60 Hz .. fc): organic weight a pure sine lacks."""
	n = n_of(seconds)
	x = svf(svf(pink(n, rng), fc, 0.8, "lp"), 60.0, 0.7, "hp")
	return mul(x, env_exp(n, attack, tau, delay=delay))


def charge_env(n, build, start_db=-30.0, power=2.0, tail_tau=0.018):
	"""Rises to 0 dB at `build`, then falls away fast (the release takes over)."""
	b = n_of(build)
	out = [0.0] * n
	for i in range(n):
		if i <= b:
			u = i / max(b, 1)
			out[i] = dsp.undb(start_db * (1.0 - u) ** power)
		else:
			out[i] = math.exp(-(i - b) / (tail_tau * SR))
	return out


def curve(n, fn):
	inv = 1.0 / SR
	return [fn(i * inv) for i in range(n)]


def pings(rng, seconds, times, f_lo, f_hi, tau_lo, tau_hi, amp=lambda t: 1.0, partials=None, detune=0.004):
	"""Glassy shards: one decaying multi-partial ping per onset time."""
	n = n_of(seconds)
	out = dsp.zeros(n)
	parts = partials or ((1.0, 1.0, 1.0), (GLASS[1], 0.45, 0.6), (GLASS[2], 0.25, 0.4))
	for t in times:
		f = math.exp(rng.uniform(math.log(f_lo), math.log(f_hi)))
		tau = rng.uniform(tau_lo, tau_hi)
		length = min(seconds - t, tau * 7.0)
		if length <= 0.002:
			continue
		p = ping(length, f, tau, rng, 0.0003, parts, detune)
		dsp.add_into(out, p, int(t * SR), amp(t) * (0.35 + 0.65 * rng.random()))
	return out


def onset_cloud(rng, count, mean, start=0.0, cap=None):
	"""`count` onsets after `start`, exponentially spread with this mean."""
	times = [start + rng.expovariate(1.0 / mean) for _ in range(count)]
	if cap is not None:
		times = [min(t, cap) for t in times]
	return sorted(times)


def flicker(n, rng, rate, depth, floor=0.0):
	"""1 +- depth random amplitude flutter at about `rate` Hz (never below floor)."""
	w = smooth_noise(n, rng, rate)
	return [max(floor, 1.0 + depth * v) for v in w]


def gate(n, rng, rate, bias=0.5, gain=1.6):
	"""Random on/off sputter (0..1) at about `rate` Hz: arcs catching and dying."""
	return [max(0.0, min(1.0, bias + gain * w)) for w in smooth_noise(n, rng, rate)]


def ring_mod(x, f):
	return mul(x, sine(f, len(x)))


def delayed(x, seconds):
	return [0.0] * n_of(seconds) + x


def jitter(v, amount=0.06):
	"""Per-variant multiplier: 1 - a, 1, 1 + a for v = 0, 1, 2."""
	return 1.0 + amount * (v - 1)


# ============================================================================
# FIRE: roar, flutter and crackle; booms with a low "whoomph".
# ============================================================================

def _fire_charge(rng, build, deep):
	tail = 0.08
	T = build + tail
	n = n_of(T)
	up = lambda t: min(t / build, 1.0)
	f0, f1 = (160.0, 1300.0) if deep else (380.0, 2300.0)
	breath = band(rng, T, lambda t: f0 * (f1 / f0) ** up(t), 1.3)
	roar = svf(svf(pink(n, rng), lambda t: 150.0 + (1400.0 if deep else 900.0) * up(t) ** 2, 0.9, "lp"), 60.0, 0.7, "hp")
	crk = crackle(T, rng, lambda t: 8.0 + (220.0 if deep else 150.0) * up(t) ** 2.5, 1200.0, 6000.0)
	layers = [(breath, 0.0), (roar, -3.0 if deep else -5.0), (crk, -12.0)]
	if deep:
		swell = band(rng, T, lambda t: 90.0 + 260.0 * up(t), 2.0)
		layers.append((mul(swell, flicker(n, rng, 9.0, 0.35)), -4.0))
	x = stack(n, *layers)
	return mul(x, charge_env(n, build, -32.0 if deep else -26.0, 2.2))


@sound("fire_charge", "charge")
def fire_charge(rng, v):
	return _fire_charge(rng, 0.24, False)


@sound("fire_charge_sig", "charge")
def fire_charge_sig(rng, v):
	return _fire_charge(rng, 0.5, True)


@sound("fire_release", "release", variants=3)
def fire_release(rng, v):
	j = jitter(v, 0.08)
	T = 0.55
	n = n_of(T)
	blast = burst(rng, T, 0.002, 0.075, "pink", lp=sweep(8000.0 * j, 700.0, 0.14))
	body = whump(rng, T, 320.0 * j, 0.003, 0.06)
	kick = thump(T, 170.0 * j, 70.0 * j, 0.025, 0.055, drive=1.5)
	whoosh = mul(band(rng, T, sweep(1900.0 * j, 480.0, 0.26), 1.2), env_exp(n, 0.012, 0.12))
	crk = crackle(T, rng, lambda t: 260.0 * math.exp(-t / 0.11) + 6.0, 1200.0, 5500.0, amp=lambda t: math.exp(-t / 0.2))
	x = stack(n, (blast, 0.0), (body, -3.0), (kick, -9.0), (whoosh, -6.0), (crk, -13.0))
	return saturate(norm(x), 1.7)


@sound("fire_loop", "loop", loop=(1.0, 0.22))
def fire_loop(rng, v):
	T = 1.25
	n = n_of(T)
	roar = mul(svf(pink(n, rng), 780.0, 0.8, "lp"), flicker(n, rng, 13.0, 0.45, 0.15))
	jet = svf(white(n, rng), [650.0 + 140.0 * w for w in smooth_noise(n, rng, 3.0)], 1.7, "bp")
	jet = mul(jet, flicker(n, rng, 17.0, 0.5, 0.1))
	low = svf(svf(brown(n, rng, 40.0), 170.0, 0.7, "lp"), 45.0, 0.7, "hp")
	crk = crackle(T, rng, 38.0, 1500.0, 7000.0)
	air = mul(hiss(n, rng, 3500.0, 9000.0), flicker(n, rng, 28.0, 0.6, 0.0))
	return stack(n, (roar, 0.0), (jet, -4.0), (low, -6.0), (crk, -13.0), (air, -20.0))


@sound("fire_hit", "hit", variants=3)
def fire_hit(rng, v):
	j = jitter(v, 0.07)
	T = 0.7
	n = n_of(T)
	blast = burst(rng, T, 0.0015, 0.065, "pink", lp=sweep(6000.0 * j, 500.0, 0.1))
	body = whump(rng, T, 280.0 * j, 0.002, 0.055)
	kick = thump(T, 150.0 * j, 65.0 * j, 0.022, 0.05, drive=1.8)
	splat = burst(rng, T, 0.0008, 0.022, "white", bp=1100.0 * j, q=1.0)
	sizzle = mul(mul(hiss(n, rng, 3500.0, 9000.0), env_exp(n, 0.025, 0.22, delay=0.01)), flicker(n, rng, 40.0, 0.5, 0.1))
	crk = crackle(T, rng, lambda t: 190.0 * math.exp(-t / 0.15) + 8.0, 1300.0, 6500.0, amp=lambda t: math.exp(-t / 0.25))
	x = stack(n, (blast, 0.0), (body, -2.0), (kick, -8.0), (splat, -6.0), (crk, -12.0), (sizzle, -16.0))
	return saturate(norm(x), 1.8)


@sound("fire_surface", "surface", variants=3)
def fire_surface(rng, v):
	j = jitter(v, 0.07)
	T = 0.95
	n = n_of(T)
	blast = burst(rng, T, 0.001, 0.08, "white", lp=sweep(9500.0 * j, 800.0, 0.12))
	body = whump(rng, T, 300.0 * j, 0.002, 0.09)
	kick = thump(T, 135.0 * j, 55.0 * j, 0.03, 0.08, drive=2.0)
	roar = burst(rng, T, 0.006, 0.22, "pink", bp=430.0 * j, q=0.7)
	debris = crackle(T, rng, lambda t: 420.0 * math.exp(-t / 0.09) + 32.0 * math.exp(-t / 0.4), 1400.0, 7000.0,
			amp=lambda t: math.exp(-t / 0.3))
	smoke = mul(svf(pink(n, rng), 1200.0, 0.7, "lp"), env_exp(n, 0.03, 0.34, delay=0.02))
	x = stack(n, (blast, 0.0), (body, -2.0), (kick, -8.0), (roar, -5.0), (debris, -10.0), (smoke, -13.0))
	return saturate(norm(x), 1.7)


@sound("fire_fizzle", "fizzle", variants=2)
def fire_fizzle(rng, v):
	j = jitter(v * 2, 0.05)
	T = 0.55
	n = n_of(T)
	puff = mul(band(rng, T, sweep(950.0 * j, 330.0, 0.32), 1.0), env_exp(n, 0.012, 0.12))
	smoke = whump(rng, T, 500.0, 0.015, 0.1)
	air = mul(hiss(n, rng, 2800.0, 7000.0), env_exp(n, 0.02, 0.15))
	crk = crackle(T, rng, lambda t: 45.0 * math.exp(-t / 0.15), 1200.0, 5000.0)
	return stack(n, (puff, 0.0), (smoke, -5.0), (air, -14.0), (crk, -14.0))


@sound("fire_release_sig", "release")
def fire_release_sig(rng, v):
	# Flame Wall leaving the hand: a heavy fwoosh flung at the ground
	T = 0.7
	n = n_of(T)
	roar = burst(rng, T, 0.004, 0.18, "pink", lp=sweep(6000.0, 700.0, 0.25))
	whoosh = mul(band(rng, T, sweep(2400.0, 320.0, 0.35), 1.1), env_exp(n, 0.01, 0.16))
	body = whump(rng, T, 300.0, 0.003, 0.08)
	kick = thump(T, 140.0, 55.0, 0.03, 0.07, drive=1.6)
	crk = crackle(T, rng, lambda t: 200.0 * math.exp(-t / 0.18) + 10.0, 1200.0, 6000.0)
	x = stack(n, (roar, 0.0), (whoosh, -3.0), (body, -4.0), (kick, -10.0), (crk, -12.0))
	return saturate(norm(x), 1.5)


@sound("flame_wall_ignite", "big")
def flame_wall_ignite(rng, v):
	T = 1.7
	n = n_of(T)
	go = 0.07  # the gas catches after a short in-rush
	u = n_of(go)
	inrush = [((i / u) ** 2 if i < u else math.exp(-(i - u) / (0.03 * SR))) for i in range(n)]
	pre = mul(band(rng, T, sweep(260.0, 1500.0, go), 1.6), inrush)
	roar = delayed(burst(rng, T - go, 0.008, 0.36, "pink", lp=sweep(6500.0, 850.0, 0.42)), go)
	fwoom = delayed(mul(band(rng, T - go, sweep(1700.0, 260.0, 0.7), 1.0), env_exp(n_of(T - go), 0.012, 0.3)), go)
	body = whump(rng, T, 260.0, 0.004, 0.18, delay=go)
	kick = delayed(thump(T - go, 112.0, 40.0, 0.05, 0.2, drive=2.2), go)
	crk = crackle(T, rng, lambda t: 0.0 if t < go else 360.0 * math.exp(-(t - go) / 0.25) + 40.0, 1200.0, 7000.0)
	sustain = mul(svf(svf(brown(n, rng, 40.0), 520.0, 0.8, "lp"), 45.0, 0.7, "hp"), env_exp(n, 0.05, 0.6, delay=go))
	x = stack(n, (pre, -8.0), (roar, 0.0), (fwoom, -3.0), (body, -2.0), (kick, -7.0), (crk, -11.0), (sustain, -6.0))
	x = saturate(norm(x), 1.4)
	return dsp.reverb(x, room=0.6, damp=0.45, wet=0.14, tail=0.25)


@sound("flame_wall_loop", "wall", loop=(2.0, 0.35))
def flame_wall_loop(rng, v):
	T = 2.4
	n = n_of(T)
	roar = mul(svf(pink(n, rng), 700.0, 0.8, "lp"), flicker(n, rng, 9.0, 0.35, 0.2))
	flames = svf(white(n, rng), [1100.0 + 320.0 * w for w in smooth_noise(n, rng, 1.5)], 0.7, "bp")
	flames = mul(flames, flicker(n, rng, 14.0, 0.45, 0.1))
	low = svf(svf(brown(n, rng, 30.0), 140.0, 0.7, "lp"), 40.0, 0.7, "hp")
	crk = crackle(T, rng, 48.0, 1500.0, 7000.0, amp_power=3.0)
	pops = crackle(T, rng, 3.2, 700.0, 2500.0, length=(0.005, 0.012), q=1.0, amp_power=1.5)
	air = hiss(n, rng, 4500.0, 10000.0)
	return stack(n, (roar, 0.0), (flames, -4.0), (low, -6.0), (crk, -13.0), (pops, -11.0), (air, -22.0))


# ============================================================================
# FROST: glassy inharmonic partials, crunch, sparkle and cold air.
# ============================================================================

def ice_crunch(rng, T, tau, rate=950.0, f_lo=1500.0, f_hi=4600.0):
	return crackle(T, rng, lambda t: rate * math.exp(-t / tau), f_lo, f_hi, length=(0.0004, 0.0016), q=1.2, amp_power=1.5)


def _frost_charge(rng, build, deep):
	tail = 0.08
	T = build + tail
	n = n_of(T)
	up = lambda t: min(t / build, 1.0)
	shimmer = dsp.zeros(n)
	for _ in range(7):
		f = math.exp(rng.uniform(math.log(2800.0), math.log(7600.0)))
		rate = rng.uniform(7.0, 19.0)
		ph = rng.random() * dsp.TAU
		tone = sine(lambda t, f=f: f * (1.0 + 0.12 * up(t)), n, rng.random())
		trem = curve(n, lambda t, r=rate, p=ph: 0.55 + 0.45 * math.sin(dsp.TAU * r * t + p))
		dsp.add_into(shimmer, mul(tone, trem), 0, rng.uniform(0.4, 1.0))
	air = hiss(n, rng, 4500.0, 11000.0)
	tinks = pings(rng, T, dsp.poisson_times(build, lambda t: 10.0 + 90.0 * up(t) ** 2, rng), 3500.0, 8500.0, 0.015, 0.05)
	f0, f1 = (500.0, 2200.0) if deep else (800.0, 2600.0)
	breath = band(rng, T, lambda t: f0 * (f1 / f0) ** up(t), 1.5)
	layers = [(shimmer, -6.0), (air, -14.0), (tinks, -5.0), (breath, 0.0)]
	if deep:
		layers.append((crackle(T, rng, lambda t: 20.0 + 500.0 * up(t) ** 2, 1500.0, 4500.0,
				length=(0.0003, 0.0015), amp_power=1.5), -9.0))
		layers.append((band(rng, T, lambda t: 300.0 + 700.0 * up(t), 2.5), -3.0))
	x = stack(n, *layers)
	return mul(x, charge_env(n, build, -30.0 if deep else -24.0, 2.0))


@sound("frost_charge", "charge")
def frost_charge(rng, v):
	return _frost_charge(rng, 0.24, False)


@sound("frost_charge_sig", "charge")
def frost_charge_sig(rng, v):
	return _frost_charge(rng, 0.45, True)


@sound("frost_release", "release", variants=3)
def frost_release(rng, v):
	j = jitter(v, 0.07)
	T = 0.5
	n = n_of(T)
	crack = burst(rng, T, 0.0004, 0.006, "white", hp=2600.0, lp=13000.0)
	ring = dsp.modal(T, 2100.0 * j, GLASS, (1.0, 0.6, 0.45, 0.3, 0.2), (0.26, 0.14, 0.09, 0.06, 0.04), rng, 0.003)
	ring2 = dsp.modal(T, 2100.0 * j * 1.498, GLASS, (0.7, 0.4, 0.25), (0.2, 0.1, 0.06), rng, 0.003)
	glint = mul(sine(sweep(3200.0 * j, 6400.0 * j, 0.06), n), env_exp(n, 0.002, 0.05))
	air = mul(band(rng, T, sweep(5600.0 * j, 2100.0, 0.15), 1.2, "white"), env_exp(n, 0.002, 0.07))
	grains = ice_crunch(rng, T, 0.02, 1200.0, 2000.0, 6000.0)
	thud = thump(T, 230.0 * j, 95.0, 0.014, 0.03)
	x = stack(n, (air, 0.0), (ring, 0.0), (ring2, -5.0), (glint, -8.0), (crack, -9.0), (grains, -8.0), (thud, -11.0))
	return saturate(norm(x), 1.2)


@sound("frost_loop", "loop", loop=(0.8, 0.18))
def frost_loop(rng, v):
	T = 1.0
	n = n_of(T)
	w1 = svf(white(n, rng), [3200.0 * (1.0 + 0.025 * w) for w in smooth_noise(n, rng, 4.0)], 9.0, "bp")
	w2 = svf(white(n, rng), [4700.0 * (1.0 + 0.02 * w) for w in smooth_noise(n, rng, 5.0)], 11.0, "bp")
	body = mul(svf(pink(n, rng), 950.0, 0.9, "bp"), flicker(n, rng, 6.0, 0.3, 0.3))
	glints = pings(rng, T, dsp.poisson_times(T, 20.0, rng), 5000.0, 9500.0, 0.012, 0.04)
	air = hiss(n, rng, 6000.0, 12000.0)
	return stack(n, (w1, 0.0), (w2, -3.0), (body, -9.0), (glints, -6.0), (air, -16.0))


@sound("frost_hit", "hit", variants=3)
def frost_hit(rng, v):
	j = jitter(v, 0.07)
	T = 0.6
	n = n_of(T)
	crunch = ice_crunch(rng, T, 0.035)
	crush = burst(rng, T, 0.0005, 0.035, "white", bp=2600.0 * j, q=0.9)
	crack = burst(rng, T, 0.0004, 0.005, "white", hp=1900.0, lp=13000.0)
	shards = pings(rng, T, onset_cloud(rng, 11, 0.05), 2500.0 * j, 7500.0, 0.04, 0.12)
	puff = mul(hiss(n, rng, 2500.0, 9000.0), env_exp(n, 0.001, 0.06))
	thud = thump(T, 195.0 * j, 80.0 * j, 0.02, 0.045, drive=1.5)
	body = whump(rng, T, 350.0, 0.002, 0.04)
	x = stack(n, (crunch, 0.0), (crush, -2.0), (crack, -9.0), (shards, -2.0), (puff, -8.0), (thud, -10.0), (body, -7.0))
	return saturate(norm(x), 1.3)


@sound("frost_surface", "surface", variants=3)
def frost_surface(rng, v):
	j = jitter(v, 0.07)
	T = 0.85
	n = n_of(T)
	crunch = ice_crunch(rng, T, 0.06, 900.0, 1300.0, 4200.0)
	crush = burst(rng, T, 0.0005, 0.05, "white", bp=2300.0 * j, q=0.9)
	crack = burst(rng, T, 0.0004, 0.006, "white", hp=1700.0, lp=13000.0)
	times = onset_cloud(rng, 18, 0.11, 0.004) + [rng.uniform(0.25, 0.5) for _ in range(3)]
	debris = pings(rng, T, sorted(times), 2000.0, 8200.0, 0.025, 0.08, amp=lambda t: math.exp(-t / 0.35))
	dust = mul(hiss(n, rng, 3200.0, 10000.0), env_exp(n, 0.002, 0.12))
	thud = thump(T, 155.0 * j, 65.0, 0.022, 0.05, drive=1.5)
	body = whump(rng, T, 320.0, 0.002, 0.05)
	x = stack(n, (crunch, 0.0), (crush, -2.0), (crack, -8.0), (debris, -4.0), (dust, -13.0), (thud, -11.0), (body, -8.0))
	return saturate(norm(x), 1.3)


@sound("frost_fizzle", "fizzle", variants=2)
def frost_fizzle(rng, v):
	T = 0.6
	n = n_of(T)
	mist = mul(hiss(n, rng, 3000.0, 9000.0), env_exp(n, 0.02, 0.16))
	puff = mul(band(rng, T, sweep(3000.0, 1100.0, 0.3), 1.0), env_exp(n, 0.01, 0.1))
	tinkles = pings(rng, T, sorted(rng.uniform(0.0, 0.32) for _ in range(6)), 4000.0, 8500.0, 0.02, 0.05)
	return stack(n, (puff, 0.0), (mist, -2.0), (tinkles, -8.0))


@sound("frost_nova", "big")
def frost_nova(rng, v):
	T = 1.9
	n = n_of(T)
	blast = burst(rng, T, 0.002, 0.12, "pink", lp=sweep(10000.0, 1500.0, 0.25))
	kick = thump(T, 98.0, 38.0, 0.05, 0.2, drive=2.0)
	body = whump(rng, T, 260.0, 0.003, 0.15)
	whoosh = mul(band(rng, T, sweep(3300.0, 480.0, 0.6), 1.3), env_exp(n, 0.006, 0.28))
	freeze = crackle(T, rng, lambda t: 650.0 * math.exp(-t / 0.25) + 20.0 * math.exp(-t / 0.8), 1500.0, 5000.0,
			length=(0.0003, 0.002), amp_power=1.6)
	ring = dsp.zeros(n)
	for base, gain in ((880.0, 1.0), (1318.5, 0.7), (1760.0, 0.4)):
		for det in (-0.003, 0.003):
			r = dsp.modal(T, base * (1.0 + det), GLASS, (1.0, 0.5, 0.3, 0.2, 0.1), (0.9, 0.55, 0.4, 0.25, 0.15), rng, 0.002, 0.002)
			dsp.add_into(ring, r, n_of(0.004), gain)
	shimmer = pings(rng, T, onset_cloud(rng, 32, 0.3, 0.01, 1.4), 5000.0, 9500.0, 0.02, 0.07,
			amp=lambda t: math.exp(-t / 0.6))
	x = stack(n, (blast, 0.0), (kick, -6.0), (body, -4.0), (whoosh, -3.0), (freeze, -8.0), (ring, -7.0), (shimmer, -10.0))
	x = saturate(norm(x), 1.3)
	return dsp.reverb(x, room=0.7, damp=0.3, wet=0.18, tail=0.3)


@sound("shatter", "big", variants=2)
def shatter(rng, v):
	T = 1.9
	n = n_of(T)
	go = 0.006  # a hair after the snap
	crack = burst(rng, T, 0.0003, 0.004, "white", hp=3000.0, lp=14000.0)
	smash = burst(rng, T, 0.0005, 0.013, "white", lp=12000.0, delay=go)
	crunch = crackle(T, rng, lambda t: 1600.0 * math.exp(-t / 0.05) + 60.0 * math.exp(-t / 0.3), 1200.0, 5200.0,
			length=(0.0003, 0.002), amp_power=1.4)
	glass = pings(rng, T, onset_cloud(rng, 58, 0.08, go, 0.95), 1600.0, 9800.0, 0.02, 0.15,
			amp=lambda t: math.exp(-t / 0.3))
	chunks = pings(rng, T, sorted(rng.uniform(0.01, 0.3) for _ in range(6)), 600.0, 1450.0, 0.25, 0.45,
			partials=((1.0, 1.0, 1.0), (2.32, 0.5, 0.5), (4.25, 0.25, 0.3)))
	kick = thump(T, 135.0 * jitter(v, 0.08), 45.0, 0.03, 0.15, drive=2.2)
	body = whump(rng, T, 300.0, 0.002, 0.1, delay=go)
	spray = mul(hiss(n, rng, 3600.0, 12000.0), env_exp(n, 0.001, 0.2, delay=go))
	x = stack(n, (glass, 0.0), (crunch, -1.0), (smash, -4.0), (crack, -10.0), (chunks, -6.0), (kick, -8.0),
			(body, -5.0), (spray, -12.0))
	x = saturate(norm(x), 1.3)
	return dsp.reverb(x, room=0.75, damp=0.25, wet=0.22, tail=0.35)


# ============================================================================
# LIGHTNING: square-wave buzz, FM and ring modulation, cracks and crackle.
# ============================================================================

def zap_crack(rng, T, hp_f=1500.0, length=0.012):
	n = n_of(T)
	a = burst(rng, T, 0.0003, 0.004, "white", lp=15000.0)
	b = burst(rng, T, 0.0003, length, "white", hp=hp_f, lp=14000.0)
	return dsp.mix(n, (a, 1.0), (b, 0.8))


def sparks(rng, T, rate, f_lo=2500.0, f_hi=10500.0):
	return crackle(T, rng, rate, f_lo, f_hi, length=(0.0004, 0.0012), q=0.9, amp_power=1.8, bright=0.9)


def buzz_zz(n, f, pw, ring_f, centre, q=0.8):
	"""A square buzz, ring-modulated for clangorous sidebands, band-passed."""
	sq = square(f, n, pw)
	return svf(mul(sq, [0.5 + 0.5 * s for s in sine(ring_f, n)]), centre, q, "bp")


def _lightning_charge(rng, build, deep):
	tail = 0.08
	T = build + tail
	n = n_of(T)
	up = lambda t: min(t / build, 1.0)
	c0, c1 = (250.0, 1500.0) if deep else (350.0, 1400.0)
	carrier = lambda t: c0 * (c1 / c0) ** up(t)
	whine = fm(carrier, lambda t: carrier(t) * 0.5 + 29.0, lambda t: 0.6 + 3.2 * up(t), n)
	b0, b1 = (55.0, 150.0) if deep else (70.0, 150.0)
	buzz = square(lambda t: b0 * (b1 / b0) ** up(t), n, 0.3)
	buzz = svf(buzz, lambda t: 900.0 + 1600.0 * up(t), 0.9, "bp")
	crk = sparks(rng, T, lambda t: 5.0 + (220.0 if deep else 160.0) * up(t) ** 2)
	layers = [(whine, -6.0), (buzz, 0.0), (crk, -9.0)]
	if deep:
		layers.append((sine(lambda t: 55.0 * (1.0 + up(t)), n), -8.0))
	x = stack(n, *layers)
	return mul(x, charge_env(n, build, -30.0 if deep else -24.0, 2.0))


@sound("lightning_charge", "charge")
def lightning_charge(rng, v):
	return _lightning_charge(rng, 0.24, False)


@sound("lightning_charge_sig", "charge")
def lightning_charge_sig(rng, v):
	return _lightning_charge(rng, 0.5, True)


@sound("lightning_release", "release", variants=3)
def lightning_release(rng, v):
	j = jitter(v, 0.07)
	T = 0.42
	n = n_of(T)
	crack = zap_crack(rng, T)
	cf = sweep(2600.0 * j, 380.0, 0.12)
	zap = mul(fm(cf, lambda t: cf(t) * 0.5, 3.2, n), env_exp(n, 0.001, 0.07))
	buzz = mul(buzz_zz(n, 110.0 * j, 0.35, 830.0 * j, 2000.0), env_exp(n, 0.002, 0.11))
	crk = sparks(rng, T, lambda t: 520.0 * math.exp(-t / 0.06))
	thud = thump(T, 185.0, 85.0, 0.01, 0.025)
	x = stack(n, (zap, 0.0), (buzz, -3.0), (crack, -7.0), (crk, -10.0), (thud, -12.0))
	return saturate(norm(x), 1.5)


@sound("lightning_loop", "loop", loop=(0.5, 0.12))
def lightning_loop(rng, v):
	T = 0.65
	n = n_of(T)
	f = [97.0 + 5.0 * w for w in smooth_noise(n, rng, 7.0)]
	sq = dsp.mix(n, (square(f, n, 0.25), 1.0), (square([x * 1.48 for x in f], n, 0.4), 0.6))
	zz = svf(mul(sq, [0.5 + 0.5 * s for s in sine(1270.0, n)]), 2200.0, 0.7, "bp")
	body = svf(sq, 900.0, 0.7, "lp")
	sizzle = mul(hiss(n, rng, 4000.0, 11000.0), gate(n, rng, 45.0))
	crk = sparks(rng, T, 75.0)
	return stack(n, (zz, 0.0), (body, -9.0), (sizzle, -12.0), (crk, -10.0))


@sound("lightning_hit", "hit", variants=3)
def lightning_hit(rng, v):
	j = jitter(v, 0.07)
	T = 0.5
	n = n_of(T)
	crack = zap_crack(rng, T, 1500.0, 0.01)
	zap = mul(fm(1700.0 * j, 71.0 * j, 6.0, n), env_exp(n, 0.001, 0.09))
	zz = mul(buzz_zz(n, 120.0 * j, 0.3, 910.0, 2300.0), env_exp(n, 0.002, 0.08))
	sizzle = mul(mul(hiss(n, rng, 3600.0, 10000.0), gate(n, rng, 50.0)), env_exp(n, 0.005, 0.2))
	crk = sparks(rng, T, lambda t: 320.0 * math.exp(-t / 0.1))
	thud = thump(T, 165.0 * j, 70.0, 0.015, 0.04, drive=1.5)
	x = stack(n, (zap, 0.0), (zz, -4.0), (crack, -7.0), (sizzle, -9.0), (crk, -13.0), (thud, -10.0))
	return saturate(norm(x), 1.5)


@sound("lightning_surface", "surface", variants=3)
def lightning_surface(rng, v):
	j = jitter(v, 0.07)
	T = 0.65
	n = n_of(T)
	crack = zap_crack(rng, T, 1200.0, 0.016)
	spark_rain = crackle(T, rng, lambda t: 620.0 * math.exp(-t / 0.12) + 15.0, 2500.0, 10500.0, length=(0.0004, 0.0012),
			q=0.9, amp_power=1.8, bright=0.9, amp=lambda t: math.exp(-t / 0.18))
	tinks = pings(rng, T, onset_cloud(rng, 8, 0.12), 4000.0, 9000.0, 0.006, 0.02)
	zap = mul(fm(1300.0 * j, 93.0, 5.0, n), env_exp(n, 0.001, 0.06))
	thud = thump(T, 150.0 * j, 60.0, 0.016, 0.04, drive=1.5)
	x = stack(n, (zap, -3.0), (spark_rain, -4.0), (crack, -6.0), (tinks, -12.0), (thud, -10.0))
	return saturate(norm(x), 1.5)


@sound("lightning_fizzle", "fizzle", variants=2)
def lightning_fizzle(rng, v):
	T = 0.5
	n = n_of(T)
	buzz = square(sweep(130.0 * jitter(v * 2, 0.05), 68.0, 0.36), n, 0.3)
	buzz = mul(svf(buzz, sweep(2300.0, 600.0, 0.35), 1.0, "bp"), env_exp(n, 0.005, 0.12))
	crk = sparks(rng, T, lambda t: 60.0 * math.exp(-t / 0.12))
	return stack(n, (buzz, 0.0), (crk, -10.0))


@sound("lightning_release_sig", "release")
def lightning_release_sig(rng, v):
	# Lightning Strike leaving the raised hand: a zap that rips upward
	T = 0.65
	n = n_of(T)
	crack = zap_crack(rng, T, 1500.0, 0.014)
	cf = sweep(380.0, 3300.0, 0.22)
	zap = mul(fm(cf, lambda t: cf(t) * 0.5 + 31.0, 3.5, n), env_exp(n, 0.003, 0.14))
	rise = mul(band(rng, T, sweep(700.0, 4500.0, 0.3), 1.4, "white"), env_exp(n, 0.01, 0.15))
	buzz = mul(svf(square(sweep(70.0, 140.0, 0.3), n, 0.3), 1800.0, 0.9, "bp"), env_exp(n, 0.004, 0.16))
	crk = sparks(rng, T, lambda t: 400.0 * math.exp(-t / 0.12))
	x = stack(n, (zap, 0.0), (buzz, -3.0), (rise, -4.0), (crack, -7.0), (crk, -9.0))
	return saturate(norm(x), 1.4)


@sound("strike_warning", "warning", held=True)
def strike_warning(rng, v):
	# 0.9 s countdown to the bolt (SpellSfx aligns its end with the strike),
	# then a held top in case the strike comes late; cut when the bolt lands.
	build = 0.9
	T = build + 0.35
	n = n_of(T)
	up = lambda t: min(t / build, 1.0)
	f_buzz = lambda t: 55.0 * 3.0 ** up(t)
	body = svf(square(f_buzz, n, 0.3), lambda t: 700.0 * (3800.0 / 700.0) ** up(t), 1.1, "bp")
	carrier = lambda t: 420.0 * 5.0 ** up(t)
	whine = fm(carrier, lambda t: carrier(t) * 0.5 + 23.0, lambda t: 1.5 + 2.8 * up(t), n)
	# pulses that speed up like a countdown: 5 Hz -> 30 Hz
	pulse_phase = dsp.phases(lambda t: 5.0 + 25.0 * up(t) ** 2, n)
	pulse = [0.45 + 0.55 * (0.5 + 0.5 * math.cos(dsp.TAU * p)) ** 1.5 for p in pulse_phase]
	crk = sparks(rng, T, lambda t: 8.0 + 170.0 * up(t) ** 2)
	sub = sine(f_buzz, n)
	x = stack(n, (mul(body, pulse), 0.0), (mul(whine, pulse), -6.0), (crk, -10.0), (sub, -12.0))
	env = [dsp.undb(-20.0 * (1.0 - up(i / SR)) ** 1.6) for i in range(n)]
	return saturate(mul(norm(x), env), 1.3)


@sound("strike_thunder", "big", variants=2)
def strike_thunder(rng, v):
	T = 3.4
	n = n_of(T)
	tick = burst(rng, T, 0.0002, 0.0015, "white", lp=15000.0)
	crack = dsp.mix(n, (burst(rng, T, 0.0003, 0.008, "white", lp=15000.0), 1.0),
			(burst(rng, T, 0.0005, 0.03, "white", hp=2000.0, lp=13000.0), 0.8))
	tear = crackle(T, rng, lambda t: 2600.0 * math.exp(-t / 0.04), 1500.0, 9000.0,
			length=(0.0002, 0.001), q=0.9, amp_power=1.3, bright=1.0)
	boom = thump(T, 88.0 * jitter(v, 0.06), 34.0, 0.06, 0.35, drive=2.5)
	boom_noise = mul(svf(svf(brown(n, rng, 30.0), 260.0, 0.7, "lp"), 30.0, 0.7, "hp"), env_exp(n, 0.003, 0.3))
	rumble = dsp.zeros(n)
	t0 = 0.12
	for k in range(6):
		onset = t0 + rng.uniform(0.0, 0.25)
		t0 = onset + rng.uniform(0.12, 0.3)
		amp = 0.85 ** k
		roll = svf(svf(brown(n, rng, 25.0), rng.uniform(150.0, 260.0), 0.7, "lp"), 30.0, 0.7, "hp")
		roll = mul(roll, env_exp(n, rng.uniform(0.06, 0.12), rng.uniform(0.25, 0.6), delay=onset))
		mid = mul(svf(pink(n, rng), rng.uniform(380.0, 520.0), 0.7, "bp"), env_exp(n, 0.08, 0.3, delay=onset))
		dsp.add_into(rumble, norm(roll), 0, amp)
		dsp.add_into(rumble, norm(mid), 0, amp * 0.25)
	sizzle = mul(mul(hiss(n, rng, 4000.0, 11000.0), gate(n, rng, 40.0)), env_exp(n, 0.005, 0.25))
	x = stack(n, (crack, -5.0), (tear, -6.0), (tick, -12.0), (boom, -4.0), (boom_noise, -3.0), (rumble, -5.0),
			(sizzle, -14.0))
	x = saturate(norm(x), 1.6)
	return dsp.reverb(x, room=0.8, damp=0.4, wet=0.25, tail=0.6)


@sound("shock_loop", "shock", loop=(0.6, 0.1))
def shock_loop(rng, v):
	T = 0.75
	n = n_of(T)
	g = gate(n, rng, 30.0, 0.45, 2.2)
	zz = mul(buzz_zz(n, 120.0, 0.3, 860.0, 2400.0), g)
	tone = mul(fm(600.0, 60.0, 5.0, n), g)
	crk = sparks(rng, T, 95.0)
	body = svf(square(120.0, n, 0.3), 600.0, 0.7, "lp")
	return stack(n, (zz, 0.0), (tone, -9.0), (crk, -8.0), (body, -10.0))


# ============================================================================
# WIND: noise through resonant band-pass sweeps; whistles, gusts, booms.
# ============================================================================

def _wind_charge(rng, build, deep):
	tail = 0.08
	T = build + tail
	n = n_of(T)
	up = lambda t: min(t / build, 1.0)
	if deep:
		spin = dsp.phases(lambda t: 3.0 + 11.0 * up(t), n)
		centre = [(300.0 * (1400.0 / 300.0) ** up(i / SR)) * (1.0 + 0.25 * math.sin(dsp.TAU * spin[i])) for i in range(n)]
		vortex = svf(pink(n, rng), centre, 5.0, "bp")
		vortex2 = svf(pink(n, rng), [c * 1.6 for c in centre], 4.0, "bp")
		roar = svf(pink(n, rng), lambda t: 200.0 + 700.0 * up(t), 0.8, "lp")
		whistle = svf(white(n, rng), lambda t: 700.0 * (2200.0 / 700.0) ** up(t), 16.0, "bp")
		x = stack(n, (vortex, 0.0), (vortex2, -4.0), (roar, -4.0), (whistle, -9.0))
		return mul(x, charge_env(n, build, -30.0, 2.2))
	res = svf(pink(n, rng), lambda t: 380.0 * (1900.0 / 380.0) ** up(t), 4.0, "bp")
	broad = svf(pink(n, rng), lambda t: 300.0 * (1200.0 / 300.0) ** up(t), 0.9, "bp")
	whistle = svf(white(n, rng), lambda t: 900.0 * (2600.0 / 900.0) ** up(t), 14.0, "bp")
	x = stack(n, (res, 0.0), (broad, -2.0), (whistle, -8.0))
	return mul(x, charge_env(n, build, -24.0, 2.0))


@sound("wind_charge", "charge")
def wind_charge(rng, v):
	return _wind_charge(rng, 0.24, False)


@sound("wind_charge_sig", "charge")
def wind_charge_sig(rng, v):
	return _wind_charge(rng, 0.55, True)


@sound("wind_release", "release", variants=3)
def wind_release(rng, v):
	j = jitter(v, 0.08)
	T = 0.5
	n = n_of(T)
	main = mul(band(rng, T, sweep(2700.0 * j, 650.0, 0.16), 2.8), env_exp(n, 0.006, 0.09))
	second = mul(band(rng, T, sweep(1800.0 * j, 450.0, 0.2), 4.5), env_exp(n, 0.012, 0.11))
	broad = mul(band(rng, T, sweep(3000.0 * j, 900.0, 0.15), 0.9), env_exp(n, 0.004, 0.06))
	whistle = mul(band(rng, T, sweep(2000.0 * j, 900.0, 0.18), 12.0, "white"), env_exp(n, 0.008, 0.1))
	thup = thump(T, 130.0, 75.0, 0.015, 0.03)
	return stack(n, (main, 0.0), (second, -3.0), (broad, -6.0), (whistle, -6.0), (thup, -12.0))


@sound("wind_loop", "loop", loop=(0.8, 0.16))
def wind_loop(rng, v):
	# the crescent whirls: 7.5 Hz "whuh-whuh" (6 turns per loop)
	T = 0.96
	n = n_of(T)
	turn = lambda t: 0.5 + 0.5 * math.cos(dsp.TAU * 7.5 * t)
	am = curve(n, lambda t: 0.25 + 0.75 * turn(t) ** 1.5)
	whir = svf(pink(n, rng), lambda t: 950.0 + 160.0 * math.sin(dsp.TAU * 7.5 * t), 2.2, "bp")
	whistle = svf(white(n, rng), lambda t: 1650.0 * (1.0 + 0.03 * math.sin(dsp.TAU * 7.5 * t + 1.0)), 14.0, "bp")
	air = hiss(n, rng, 3000.0, 9000.0)
	return stack(n, (mul(whir, am), 0.0), (mul(whistle, [0.6 + 0.4 * a for a in am]), -5.0), (mul(air, am), -15.0))


@sound("wind_spear_loop", "loop", loop=(1.0, 0.2))
def wind_spear_loop(rng, v):
	T = 1.2
	n = n_of(T)
	howl = svf(white(n, rng), lambda t: 720.0 * (1.0 + 0.03 * math.sin(dsp.TAU * 5.0 * t)), 16.0, "bp")
	howl2 = svf(white(n, rng), lambda t: 1090.0 * (1.0 + 0.025 * math.sin(dsp.TAU * 4.0 * t + 1.0)), 18.0, "bp")
	roar = mul(svf(pink(n, rng), 420.0, 1.2, "bp"), flicker(n, rng, 8.0, 0.3, 0.3))
	low = svf(svf(brown(n, rng, 30.0), 180.0, 0.7, "lp"), 45.0, 0.7, "hp")
	whistle = svf(white(n, rng), 2300.0, 25.0, "bp")
	return stack(n, (roar, -2.0), (howl, 0.0), (howl2, -4.0), (low, -6.0), (whistle, -11.0))


@sound("wind_hit", "hit", variants=3)
def wind_hit(rng, v):
	j = jitter(v, 0.07)
	T = 0.55
	n = n_of(T)
	gust = mul(band(rng, T, sweep(1600.0 * j, 380.0, 0.25), 2.6), env_exp(n, 0.004, 0.12))
	slap = burst(rng, T, 0.0008, 0.02, "white", bp=700.0 * j, q=1.0)
	punch = thump(T, 140.0 * j, 65.0, 0.018, 0.05, drive=1.6)
	body = whump(rng, T, 330.0, 0.002, 0.05)
	flap = mul(band(rng, T, 1200.0, 1.5), curve(n, lambda t: (0.5 + 0.5 * math.sin(dsp.TAU * 28.0 * t)) * math.exp(-t / 0.08)))
	return stack(n, (gust, 0.0), (slap, -5.0), (body, -6.0), (punch, -9.0), (flap, -10.0))


@sound("wind_surface", "surface", variants=3)
def wind_surface(rng, v):
	j = jitter(v, 0.07)
	T = 0.65
	n = n_of(T)
	gust = mul(band(rng, T, sweep(2000.0 * j, 500.0, 0.3), 2.4), env_exp(n, 0.003, 0.13))
	slap = burst(rng, T, 0.0006, 0.016, "white", bp=1100.0 * j, q=0.9)
	grit = crackle(T, rng, lambda t: 260.0 * math.exp(-t / 0.15), 2500.0, 8000.0, length=(0.0002, 0.0006), amp_power=1.2)
	air = mul(hiss(n, rng, 2500.0, 9000.0), env_exp(n, 0.005, 0.18))
	thud = thump(T, 120.0, 62.0, 0.02, 0.035)
	return stack(n, (gust, 0.0), (slap, -4.0), (grit, -12.0), (air, -13.0), (thud, -11.0))


@sound("wind_fizzle", "fizzle", variants=2)
def wind_fizzle(rng, v):
	T = 0.65
	n = n_of(T)
	fade_out = mul(band(rng, T, sweep(1300.0 * jitter(v * 2, 0.05), 320.0, 0.45), 2.6), env_exp(n, 0.02, 0.17))
	whistle = mul(band(rng, T, sweep(1500.0, 600.0, 0.4), 10.0, "white"), env_exp(n, 0.03, 0.12))
	return stack(n, (fade_out, 0.0), (whistle, -9.0))


@sound("wind_release_sig", "release")
def wind_release_sig(rng, v):
	# Wind Spear leaving the hand: a launch gust with a howl
	T = 0.8
	n = n_of(T)
	whoosh = mul(band(rng, T, sweep(3200.0, 420.0, 0.35), 2.4), env_exp(n, 0.008, 0.16))
	howl = mul(band(rng, T, sweep(1400.0, 700.0, 0.35), 12.0, "white"), env_exp(n, 0.01, 0.2))
	body = whump(rng, T, 380.0, 0.002, 0.07)
	kick = thump(T, 125.0, 55.0, 0.03, 0.08, drive=1.8)
	return stack(n, (whoosh, 0.0), (howl, -4.0), (body, -6.0), (kick, -10.0))


@sound("wind_burst", "big", variants=2)
def wind_burst(rng, v):
	j = jitter(v, 0.06)
	T = 1.9
	n = n_of(T)
	blast = mul(band(rng, T, sweep(2600.0 * j, 260.0, 0.9), 2.0), env_exp(n, 0.012, 0.38))
	pop = burst(rng, T, 0.0004, 0.006, "white", hp=1000.0, lp=12000.0)
	boom = thump(T, 92.0 * j, 36.0, 0.045, 0.2, drive=2.2)
	pressure = whump(rng, T, 380.0, 0.002, 0.14)
	spin = lambda t: (700.0 + 500.0 * math.sin(dsp.TAU * 4.5 * t)) * math.exp(-t / 1.5)
	spiral = mul(band(rng, T, spin, 6.0), env_exp(n, 0.02, 0.45))
	second = mul(band(rng, T, sweep(1800.0, 300.0, 0.8, 0.06), 1.6), env_exp(n, 0.02, 0.3, delay=0.06))
	debris = crackle(T, rng, lambda t: 300.0 * math.exp(-t / 0.2), 2500.0, 8000.0, length=(0.0002, 0.0007), amp_power=1.3)
	x = stack(n, (blast, 0.0), (pressure, -3.0), (boom, -5.0), (second, -4.0), (spiral, -6.0), (pop, -10.0),
			(debris, -13.0))
	x = saturate(norm(x), 1.4)
	return dsp.reverb(x, room=0.65, damp=0.4, wet=0.16, tail=0.3)


# ============================================================================
# COMBAT: swings, flesh, steel, footwork.
# ============================================================================

def swing_env(n, peak_at, tau):
	return curve(n, lambda t: (math.sin(math.pi * min(t / peak_at, 1.0) * 0.5) ** 2) * math.exp(-max(t - peak_at, 0.0) / tau))


@sound("sword_swing", "swing", variants=3)
def sword_swing(rng, v):
	j = jitter(v, 0.08)
	T = 0.38
	n = n_of(T)
	path = arc(520.0 * j, 2600.0 * j, 900.0, 0.08, 0.3)
	env = swing_env(n, 0.075, 0.07)
	air = mul(band(rng, T, path, 1.8), env)
	whistle = mul(band(rng, T, lambda t: path(t) * 1.5, 10.0, "white"), env)
	shing = mul(hiss(n, rng, 6000.0, 12000.0), env)
	return stack(n, (air, 0.0), (whistle, -9.0), (shing, -18.0))


@sound("sword_swing_heavy", "swing", variants=2)
def sword_swing_heavy(rng, v):
	j = jitter(v * 2, 0.05)
	T = 0.6
	n = n_of(T)
	path = arc(300.0 * j, 1500.0 * j, 480.0, 0.14, 0.5)
	env = swing_env(n, 0.13, 0.1)
	air = mul(band(rng, T, path, 1.5), env)
	low = mul(band(rng, T, lambda t: path(t) * 0.5, 2.0), env)
	whistle = mul(band(rng, T, lambda t: path(t) * 1.4, 9.0, "white"), env)
	return stack(n, (air, 0.0), (low, -4.0), (whistle, -9.0))


@sound("flesh_hit", "melee", variants=3)
def flesh_hit(rng, v):
	j = jitter(v, 0.07)
	T = 0.42
	n = n_of(T)
	smack = burst(rng, T, 0.0006, 0.018, "white", bp=900.0 * j, q=0.9)
	kick = thump(T, 125.0 * j, 60.0, 0.02, 0.06, drive=2.2)
	crunch = crackle(T, rng, lambda t: 2200.0 * math.exp(-t / 0.012), 800.0, 3200.0, length=(0.0004, 0.002), amp_power=1.2)
	body = whump(rng, T, 320.0, 0.001, 0.05)
	x = stack(n, (smack, 0.0), (body, -3.0), (kick, -4.0), (crunch, -9.0))
	return saturate(norm(x), 1.8)


@sound("block_clang", "clang", variants=3)
def block_clang(rng, v):
	j = jitter(v, 0.07)
	T = 0.95
	n = n_of(T)
	metal = dsp.modal(T, 600.0 * j, PLATE, (1.0, 0.8, 0.7, 0.6, 0.45, 0.4, 0.3, 0.25),
			(0.38, 0.3, 0.22, 0.2, 0.16, 0.13, 0.11, 0.09), rng, 0.004)
	hit = burst(rng, T, 0.0004, 0.006, "white", hp=2000.0, lp=13000.0)
	thud = thump(T, 165.0, 85.0, 0.01, 0.03)
	scrape = burst(rng, T, 0.001, 0.03, "white", bp=3200.0, q=1.2)
	x = stack(n, (metal, 0.0), (hit, -9.0), (thud, -11.0), (scrape, -10.0))
	return saturate(norm(x), 1.3)


@sound("parry_ring", "parry", variants=2)
def parry_ring(rng, v):
	j = jitter(v * 2, 0.04)
	T = 1.9
	n = n_of(T)
	f0 = 1320.0 * j
	ring = dsp.modal(T, f0, BAR, (1.0, 0.55, 0.3, 0.18), (0.9, 0.5, 0.3, 0.2), rng, 0.001)
	ring2 = dsp.modal(T, f0 * 1.0035, BAR, (0.8, 0.4, 0.2, 0.1), (0.85, 0.45, 0.28, 0.18), rng, 0.001)
	hit = burst(rng, T, 0.0003, 0.005, "white", hp=2500.0, lp=13000.0)
	sparkle = dsp.zeros(n)
	for k, ratio in enumerate((2.0, 2.52, 3.0, 4.0)):
		p = ping(0.4, f0 * ratio, 0.07, rng, 0.0005)
		dsp.add_into(sparkle, p, n_of(0.02 + 0.04 * k), 0.5 ** (k * 0.5))
	return stack(n, (ring, 0.0), (ring2, -3.0), (hit, -10.0), (sparkle, -7.0))


@sound("guard_break", "break")
def guard_break(rng, v):
	T = 1.05
	n = n_of(T)
	crash = burst(rng, T, 0.001, 0.08, "pink", lp=3200.0)
	kick = thump(T, 115.0, 45.0, 0.04, 0.14, drive=2.5)
	clang = dsp.modal(T, 330.0, PLATE, (1.0, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.3), (0.3, 0.25, 0.2, 0.18, 0.15, 0.12, 0.1, 0.08), rng, 0.006)
	crunch = crackle(T, rng, lambda t: 1500.0 * math.exp(-t / 0.04), 900.0, 4000.0, length=(0.0004, 0.002), amp_power=1.3)
	x = stack(n, (crash, 0.0), (clang, -2.0), (kick, -5.0), (crunch, -7.0))
	return saturate(norm(x), 1.8)


@sound("dash", "move", variants=2)
def dash(rng, v):
	j = jitter(v * 2, 0.05)
	T = 0.4
	n = n_of(T)
	path = arc(600.0 * j, 1600.0 * j, 700.0, 0.07, 0.3)
	air = mul(band(rng, T, path, 1.3), swing_env(n, 0.05, 0.08))
	scuff = crackle(T, rng, lambda t: 900.0 * math.exp(-t / 0.03), 1800.0, 5000.0, length=(0.0003, 0.001), amp_power=1.2)
	return stack(n, (air, 0.0), (scuff, -11.0))


@sound("land", "land", variants=2)
def land(rng, v):
	j = jitter(v * 2, 0.05)
	T = 0.5
	n = n_of(T)
	dust = burst(rng, T, 0.002, 0.07, "pink", lp=900.0)
	kick = thump(T, 95.0 * j, 50.0, 0.03, 0.07, drive=1.8)
	grit = crackle(T, rng, lambda t: 650.0 * math.exp(-t / 0.04), 1500.0, 5000.0, length=(0.0003, 0.0012), amp_power=1.3)
	return saturate(norm(stack(n, (dust, 0.0), (kick, -3.0), (grit, -10.0))), 1.4)


@sound("death", "death")
def death(rng, v):
	T = 1.5
	n = n_of(T)
	fall = thump(T, 100.0, 48.0, 0.03, 0.1, drive=2.0)
	bounce = delayed(thump(T - 0.18, 90.0, 50.0, 0.025, 0.06, drive=1.6), 0.18)
	dust = burst(rng, T, 0.002, 0.09, "pink", lp=1000.0)
	whomp = mul(band(rng, T, sweep(420.0, 110.0, 0.6), 1.2), env_exp(n, 0.03, 0.4))
	drone = mul(sine(55.0, n), env_exp(n, 0.05, 0.45))
	x = stack(n, (whomp, 0.0), (fall, -2.0), (dust, -3.0), (bounce, -8.0), (drone, -10.0))
	x = saturate(norm(x), 1.5)
	return dsp.reverb(x, room=0.6, damp=0.5, wet=0.15, tail=0.2)


# --- build --------------------------------------------------------------------

def render(name, v):
	spec = SOUNDS[name]
	kind = spec["kind"]
	rng = random.Random(zlib.crc32(("%s:%d" % (name, v)).encode()))
	x = spec["fn"](rng, v)
	x = dsp.dc_block(x)
	if spec["loop"]:
		x = dsp.make_loop(x, *spec["loop"])
		x, info = dsp.master(x, TARGET[kind], loop=True)
	else:
		fin, fout = FADES.get(kind, (0.003, 0.02))
		if not spec["held"]:
			fout = max(fout, 0.12 * len(x) / SR)
		dsp.fade(x, fin, fout)
		x, info = dsp.master(x, TARGET[kind])
	file_name = "%s_%d.wav" % (name, v + 1) if spec["variants"] > 1 else "%s.wav" % name
	dsp.write_wav(os.path.join(OUT, file_name), x, loop=bool(spec["loop"]))
	return file_name, kind, len(x) / SR, info


def main(argv):
	if "--list" in argv:
		for name, spec in SOUNDS.items():
			print("%-24s %-8s x%d%s" % (name, spec["kind"], spec["variants"], "  loop" if spec["loop"] else ""))
		return
	names = [a for a in argv if not a.startswith("--")] or list(SOUNDS)
	unknown = [a for a in names if a not in SOUNDS]
	if unknown:
		sys.exit("unknown sound(s): %s" % ", ".join(unknown))
	os.makedirs(OUT, exist_ok=True)
	jobs = [(name, v) for name in names for v in range(SOUNDS[name]["variants"])]
	start = time.time()
	if "--serial" in argv:
		results = [render(*job) for job in jobs]
	else:
		from concurrent.futures import ProcessPoolExecutor
		with ProcessPoolExecutor() as pool:
			results = list(pool.map(render, *zip(*jobs)))
	for file_name, kind, seconds, info in results:
		print("%-28s %-8s %5.2fs  %6.1f LUFS  peak %5.1f dBFS  true peak %5.1f dBTP  limited %4.1f dB" % (
				file_name, kind, seconds, info["lufs"], info["peak_db"], info["tp_db"], info["limited_db"]))
	print("%d files in %.1fs -> %s" % (len(results), time.time() - start, os.path.relpath(OUT, REPO)))


if __name__ == "__main__":
	main(sys.argv[1:])
