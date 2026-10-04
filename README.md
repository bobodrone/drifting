# drifting

A norns additive **drone**: 21 sine oscillators sounding at once. Oscillator 1
is the **fundamental**; the other 20 are its **harmonics**. Three encoders
reshape the whole spectrum live.

## Controls

- **E1** — **base pitch** of the fundamental, `0.05–1000 Hz`. Mapped
  *exponentially*, so each detent is a fixed musical ratio (~1.04×) — you can
  crawl at 0.05 Hz or leap to 1 kHz with the same knob.
- **E2** — **amplitude tilt** across the 21 partials: full left favours the
  **fundamental** (you mostly hear osc 1), centre is **equal**, full right
  favours the **highest** partial (you mostly hear osc 21).
- **E3** — **harmonic spacing**, `0.0–4.0`.
- **K1 + E3** — **master level** (hold K1 as a shift; also in **PARAMS**,
  default **0.30** — 21 sines add up).
- **K2 + E2** — **tilt LFO speed**; **K2 + E3** — **spacing LFO speed**
  (hold K2 as a shift; see *LFOs* below).
- **K3** — drone **on / off** (fades in/out).
- **K2** (plain **tap**, no twist) — reset E1/E2/E3 to defaults
  (110 Hz, equal tilt, natural spacing).
- **drift** (in **PARAMS**, default **0.30**) — see below.
- **waveform** (in **PARAMS**, default **sine**) — turns all 21 oscillators
  into **saw** or **pulse** waves; see *Waveform* below.
- **MIDI note in** — play a note to set the **base pitch** (same as E1), clamped
  to `0.05–1000 Hz`. Two **modes** (in **PARAMS → midi mode**):
  - **drone** *(default)* — notes are **latched**: the drone holds the last note
    (no silence on note-off) and **K3** still gates the sound. Just a remote way
    to set the pitch.
  - **keys** — notes **gate** the drone: sound while a key is **held**, silence
    on release, with **last-note priority** (release the top note and it falls
    back to the most recent one you're still holding). A `keys` indicator shows
    top-right, bright while notes are down. K3 isn't needed here.

  Pick the **midi device** and **midi channel** (`0 = omni`) in **PARAMS**.
  Works with any norns (shield included) — MIDI comes in over USB the usual way.

## Grid

A 16×8 varibright grid is optional. Every control is on one page and is lit
from the current value, so changes made with the encoders, in the PARAMS menu
or over MIDI show up too.

| Cells | Control |
|-------|---------|
| row 1, cols 1–16 | master level, 0.0 (left) to 1.0 (right) |
| row 2, cols 1–16 | drift, 0.0 to 1.0 |
| row 3, cols 1–15 | tilt, −1 (left) · equal (col 8) · +1 (right) |
| row 4, cols 1–8 | tilt LFO speed: `off 200s 100s 50s 29s 20s 10s 5s` |
| row 4, cols 9–16 | tilt LFO depth: `0 .1 .2 .3 .4 .6 .8 1` |
| row 5, cols 1–16 | spacing: `0 .05 .1 .25 .5 .75 1 1.25 1.5 1.75 2 2.25 2.5 3 3.5 4` |
| row 6, cols 1–8 | spacing LFO speed (same steps as the tilt LFO) |
| row 6, cols 9–16 | spacing LFO depth: `0 .1 .25 .5 1 2 3 4` |
| row 7, cols 1–15 | pitch octave: the A's from 0.054 Hz to 880 Hz (col 12 = 110 Hz) |
| row 7, col 16 | waveform, each press steps on: dim = sine, half = saw, bright = pulse |
| row 8, cols 1–12 | pitch semitone within that octave: `a a# b c c# d d# e f f# g g#` |
| row 8, col 14 | MIDI mode: dim = drone, bright = keys |
| row 8, col 15 | reset pitch / tilt / spacing (same as a K2 tap) |
| row 8, col 16 | drone on/off (same as K3), bright = playing |

Faders light as a bar from the left up to the current value. A value between
two steps, such as a spacing of 0.9 set with E3, shows as the step below.

**Tilt and spacing show the LFOs live.** On rows 3 and 5 the value you set is
a half-bright fill (tilt fills outwards from the centre, spacing from the
left) and the single **bright** LED is where the LFO has swept the value to
right now — the same value the screen's bars and the engine are using. With
an LFO's depth or speed at 0 the bright LED just sits on the tip of the fill.

The pitch rows set whole semitones: the octave row keeps the current semitone
and the semitone row keeps the current octave, and either one drops any fine
tuning dialled in with E1. On the semitone row the sharps are darker, like
black keys. Pitch tops out at 1000 Hz, so the top octave only reaches `b`.

The MIDI device and channel stay in PARAMS — they are set-up, not
performance, controls.

The step tables and LED levels are constants at the top of `drifting.lua`
(`SPACE_STEPS`, `RATE_STEPS`, `TILT_DEPTH_STEPS`, `SPACE_DEPTH_STEPS`,
`LED_DIM`, `LED_MID`, `LED_ON`).

## LFOs

Two very slow **triangle** LFOs continuously sweep the **tilt** (E2) and
**spacing** (E3) around wherever you've parked them, so the drone keeps moving
on its own:

- **Speed** — hold **K2** and turn **E2** (tilt) or **E3** (spacing). Shown in
  the footer as a **period** (e.g. `50s`); `off` = stopped. Also under
  **PARAMS** as *tilt lfo speed* / *spacing lfo speed* (0–0.2 Hz).
- **Depth** — **PARAMS or grid** (there's no free encoder): *tilt lfo depth*
  (0–1, default 0.4) and *spacing lfo depth* (0–4, default 0.5). This is the
  ± swing added on top of the E2/E3 centre.

The LFOs are computed in Lua and drive the engine every frame, so the moving
**spectrum bars on screen stay exactly in sync with what you hear**. Set a
depth to **0** to freeze that LFO. E2/E3 still set the **centre** the LFO
sweeps around.

## The math

Oscillator *i* (`i = 0…20`, so osc 1 = i 0) plays:

```
freq(i) = base * (1 + i * spacing)
```

- `spacing = 1.0` → 110, 220, 330, 440 … — the **natural harmonic series**.
- `spacing = 2.0` → 110, 330, 550 … — **double** the gap between partials.
- `spacing = 0.0` → every oscillator collapses onto the **fundamental**.
- osc 1 (`i = 0`) is **always** the fundamental, at any spacing.

Amplitudes use an exponential tilt `weight(i) = exp(k · i/20)` where **E2** sweeps
`k` from `-8` (fundamental dominates) through `0` (equal) to `+8` (top partial
dominates). The 21 weights are then **normalised to sum to 1**, so overall
loudness stays roughly constant wherever you set the tilt — which is also why
the master can stay low and clean.

> At the extremes E2 doesn't hard-mute the others, it just buries them
> (~3000:1). Bump `kMax` in the engine and `K_MAX` in the Lua if you want it
> more absolute.

### Drift — why it isn't a motorboat

21 sine waves that are **equally spaced and phase-locked** don't sound like 21
things — they realign periodically and fuse into a single buzzy pulse train
whose repetition rate is the *spacing frequency* (`base × spacing`). At
`base 110, spacing 0.10` that's **11 Hz** → a putt-putt "motorboat". This is
correct additive summing (`Mix` = sum); the fusion is unavoidable while the
partials stay locked together.

**drift** breaks the lock. Each oscillator gets a random start phase plus its
own slow, independent frequency wander (up to ±2% at drift 1), so the 21
partials beat against each other and never re-lock into a pulse — you hear an
evolving shimmer instead. Turn **drift** down to **0** for the exact,
phase-locked frequencies (110, 121, 132 …) and the original motorboat; turn it
up for a more liquid, alive drone. Default is **0.30**.

### Waveform

**waveform** swaps every one of the 21 sines for a **saw** or a **pulse**
(square). Each "partial" then brings its own overtones, so the spectrum gets
far denser and brighter: tilt and spacing still place the 21 fundamentals,
but the bars on screen only show those, not the overtones on top.

The engine builds all three waveforms and crossfades to the chosen one over
~0.2 s, so switching doesn't click. Saw and pulse are band-limited (no
aliasing) but noticeably louder and buzzier than sine — pull **master** down
first. The screen shows `saw` / `pulse` next to the title when it isn't sine.

### Above Nyquist

At high settings a partial can exceed the audible/representable range
(e.g. `1000 Hz × spacing 4` → osc 21 at 81 kHz). Any partial above **~20 kHz**
is **muted** rather than allowed to alias, so extreme settings stay clean. On
the screen those partials show as **dim** bars.

## Screen

The bar graph shows all 21 partials — bar height is each oscillator's amplitude
(so E2 tilts the graph, E3 spreads it), and dim bars are muted (>20 kHz).

## The two files

| File | Language | Role |
|------|----------|------|
| `Engine_Drifting.sc` | SuperCollider | One persistent synth with all 21 oscillators (`SinOsc` / `Saw` / `Pulse`). Reads `base`, `spacing`, `dist`, `drift`, `amp`, `wave` (all lagged/smoothed) and a `gate`. Exposes `setBase`, `setSpace`, `setDist`, `setDrift`, `setAmp`, `setWave`, `setGate`. |
| `drifting.lua` | Lua | UI + logic: encoders/keys/grid, MIDI note-in, the spectrum readout, and the engine calls. |

Linked by the matching names `engine.name = "Drifting"` (Lua) and
`Engine_Drifting : CroneEngine` (SC).

The drone synth is created **once** when the engine loads and lives for the
whole session — gating it off just fades it to silence, so E1/E2/E3 keep
shaping it even while muted, and turning it back on is instant.

## Install

Copy this whole `drifting` folder into your norns at:

```
~/dust/code/drifting/
```

Then on the norns: **SELECT > drifting**, press **K3** to start, and turn the
encoders. If you edit `Engine_Drifting.sc` you must reload the script (or
restart audio) for SuperCollider to pick up the change.

## Things to try

- Sub-audio `base` (E1 down near 0.05 Hz) with a wide `spacing` turns the whole
  thing into slowly beating rhythmic pulses instead of a pitched drone.
- Sweep **E3** slowly from 1.0 → 0.0 to hear 21 harmonics fold into a single
  fat unison.
- Park **E2** hard left/right and use **E3** to move which single partial you're
  hearing.
