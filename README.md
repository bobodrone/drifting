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

## LFOs

Two very slow **triangle** LFOs continuously sweep the **tilt** (E2) and
**spacing** (E3) around wherever you've parked them, so the drone keeps moving
on its own:

- **Speed** — hold **K2** and turn **E2** (tilt) or **E3** (spacing). Shown in
  the footer as a **period** (e.g. `50s`); `off` = stopped. Also under
  **PARAMS** as *tilt lfo speed* / *spacing lfo speed* (0–0.2 Hz).
- **Depth** — **PARAMS only** (there's no free encoder): *tilt lfo depth*
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
| `Engine_Drifting.sc` | SuperCollider | One persistent synth with all 21 `SinOsc`s. Reads `base`, `spacing`, `dist`, `amp` (all lagged/smoothed) and a `gate`. Exposes `setBase`, `setSpace`, `setDist`, `setAmp`, `setGate`. |
| `drifting.lua` | Lua | UI + logic: encoders/keys, the spectrum readout, and the engine calls. |

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
