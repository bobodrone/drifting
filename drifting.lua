-- drifting
-- v1.0.0 @bobodrone
-- llllllll.co/t/22222
--
-- 21 sine waves at once:
-- osc 1 is the fundamental,
-- the rest are its harmonics.
--
-- E1 : base pitch (0.05-1000 Hz)
-- E2 : amplitude tilt
--      (low <- equal -> high)
-- E3 : harmonic spacing (0-4)
--      1.0 = natural overtones
--      0.0 = all on the fundamental
-- K1+E3 : master level
-- K2+E2 : tilt LFO speed
-- K2+E3 : spacing LFO speed
-- K3 : drone on / off
-- K2 (tap) : reset E1/E2/E3
--
-- two slow triangle LFOs sweep the
-- tilt and spacing on their own.
-- their DEPTH is set in PARAMS.

-- must match Engine_Drifting in Engine_Drifting.sc
engine.name = "Drifting"

local controlspec = require "controlspec"
local util = require "util"

-- ----------------------------------------------------------------------
-- configuration / state
-- ----------------------------------------------------------------------

local N = 21          -- number of oscillators (fixed, matches the engine)
local K_MAX = 8       -- tilt steepness; must match kMax in the engine

local base_hz  = 110.0   -- E1: fundamental frequency
local dist     = 0.0     -- E2: amplitude tilt, -1 (low) .. 0 .. +1 (high)
local spacing  = 1.0     -- E3: harmonic spacing, 0 .. 4
local master   = 0.3     -- master level (also a PARAM)
local drift    = 0.3     -- per-osc frequency wander, 0 = still (a PARAM)
local droning  = false   -- is the drone gated on?
local k1_held  = false   -- K1 shift: E3 -> master level
local k2_held  = false   -- K2 shift: E2/E3 -> LFO speeds
local k2_twisted = false -- did an encoder move while K2 was held?

-- the two slow triangle LFOs. rate + depth are PARAMS; these mirror them.
local tilt_rate  = 0.02  -- Hz
local tilt_depth = 0.4   -- +/- swing added to tilt (dist spans -1..1)
local space_rate = 0.02  -- Hz
local space_depth = 0.5  -- +/- swing added to spacing (spans 0..4)

-- the tilt/spacing actually sent to the engine each frame (base + LFO).
-- also what the spectrum bars draw, so screen and sound stay in sync.
local mod_dist  = dist
local mod_space = spacing

local lfo_metro          -- drives the LFOs + redraw

-- encoder feel
local PITCH_RATIO = 1.04  -- E1 is exponential: each detent is a fixed ratio
local DIST_STEP   = 0.02  -- E2 per detent
local SPACE_STEP  = 0.02  -- E3 per detent

-- defaults K2 (tap) restores
local BASE_DEFAULT, DIST_DEFAULT, SPACE_DEFAULT = 110.0, 0.0, 1.0

-- ----------------------------------------------------------------------
-- helpers
-- ----------------------------------------------------------------------

-- compute the frequency + normalised amplitude of every partial, mirroring
-- the engine math so the screen shows what you actually hear.
local function partials()
  local slope = mod_dist * K_MAX
  local freqs, weights = {}, {}
  local wsum = 0
  for i = 0, N - 1 do
    local f = base_hz * (1 + i * mod_space)
    local w = math.exp(slope * (i / (N - 1)))
    if f >= 20000 then w = 0 end        -- muted above Nyquist, like the engine
    freqs[i + 1] = f
    weights[i + 1] = w
    wsum = wsum + w
  end
  if wsum <= 0 then wsum = 1 end
  for i = 1, N do weights[i] = weights[i] / wsum end
  return freqs, weights
end

-- readable Hz across a huge range (0.05 Hz .. 1000 Hz).
local function fmt_hz(f)
  if f < 1 then return string.format("%.3f Hz", f)
  elseif f < 10 then return string.format("%.2f Hz", f)
  elseif f < 100 then return string.format("%.1f Hz", f)
  else return string.format("%.0f Hz", f) end
end

-- an LFO rate shown as its period, since these are meant to be very slow.
local function fmt_period(rate)
  if rate <= 0 then return "off" end
  return string.format("%.0fs", 1 / rate)
end

-- unipolar phase (cycles) -> triangle in -1..1.
local function tri(phase)
  local f = phase - math.floor(phase)
  return (4 * math.abs(f - 0.5)) - 1
end

-- the LFO/redraw frame: sweep tilt + spacing with their triangle LFOs,
-- push the modulated values to the engine, and repaint. running this in
-- Lua (not the engine) keeps the on-screen bars locked to what you hear.
local function tick()
  local t = util.time()
  mod_dist  = util.clamp(dist    + tri(t * tilt_rate)  * tilt_depth,  -1, 1)
  mod_space = util.clamp(spacing + tri(t * space_rate) * space_depth,  0, 4)
  engine.setDist(mod_dist)
  engine.setSpace(mod_space)
  redraw()
end

-- ----------------------------------------------------------------------
-- norns lifecycle
-- ----------------------------------------------------------------------

function init()
  -- master level lives in PARAMS (all three encoders are taken).
  params:add_control("master", "master level",
    controlspec.new(0, 1, "lin", 0.01, master, ""))
  params:set_action("master", function(v)
    master = v
    engine.setAmp(v)
    redraw()
  end)

  -- drift: how much each oscillator wanders in frequency. 0 = exact,
  -- phase-locked (the "motorboat"); higher = evolving shimmer.
  params:add_control("drift", "drift",
    controlspec.new(0, 1, "lin", 0.01, drift, ""))
  params:set_action("drift", function(v)
    drift = v
    engine.setDrift(v)
    redraw()
  end)

  -- the two slow triangle LFOs on tilt and spacing.
  -- speed is also live on K2+E2 / K2+E3; depth is only here (no free encoder).
  params:add_separator("tilt LFO")
  params:add_control("tilt_lfo_rate", "tilt lfo speed",
    controlspec.new(0, 0.2, "lin", 0.005, tilt_rate, "Hz"))
  params:set_action("tilt_lfo_rate", function(v) tilt_rate = v; redraw() end)
  params:add_control("tilt_lfo_depth", "tilt lfo depth",
    controlspec.new(0, 1, "lin", 0.01, tilt_depth, ""))
  params:set_action("tilt_lfo_depth", function(v) tilt_depth = v end)

  params:add_separator("spacing LFO")
  params:add_control("space_lfo_rate", "spacing lfo speed",
    controlspec.new(0, 0.2, "lin", 0.005, space_rate, "Hz"))
  params:set_action("space_lfo_rate", function(v) space_rate = v; redraw() end)
  params:add_control("space_lfo_depth", "spacing lfo depth",
    controlspec.new(0, 4, "lin", 0.05, space_depth, ""))
  params:set_action("space_lfo_depth", function(v) space_depth = v end)

  -- push the starting state to the engine.
  engine.setBase(base_hz)
  engine.setDrift(drift)
  engine.setAmp(master)
  -- (dist/spacing are pushed every frame by the LFO tick below.)

  -- run the LFOs + redraw at ~30 fps.
  lfo_metro = metro.init()
  lfo_metro.event = tick
  lfo_metro.time = 1 / 30
  lfo_metro:start()

  redraw()
end

function cleanup()
  if lfo_metro then lfo_metro:stop() end
end

function enc(n, d)
  -- any turn while K2 is held means it's a shift gesture, not a tap-to-reset.
  if k2_held then k2_twisted = true end

  if n == 1 then
    -- E1: base pitch, exponential so every detent is a musical ratio.
    base_hz = util.clamp(base_hz * (PITCH_RATIO ^ d), 0.05, 1000)
    engine.setBase(base_hz)
  elseif n == 2 then
    if k2_held then
      -- K2 + E2: tilt LFO speed (via the PARAM so it saves + stays in sync).
      params:delta("tilt_lfo_rate", d)
    else
      -- E2: amplitude tilt centre (the LFO sweeps around it).
      dist = util.clamp(dist + d * DIST_STEP, -1, 1)
    end
  elseif n == 3 then
    if k2_held then
      -- K2 + E3: spacing LFO speed.
      params:delta("space_lfo_rate", d)
    elseif k1_held then
      -- K1 + E3: master level.
      params:delta("master", d)
    else
      -- E3: harmonic spacing centre.
      spacing = util.clamp(spacing + d * SPACE_STEP, 0, 4)
    end
  end
  redraw()
end

function key(n, z)
  -- K1: shift modifier for E3 -> master level.
  if n == 1 then
    k1_held = (z == 1)
    redraw()
    return
  end

  -- K2: hold as a shift for the LFO speeds; a plain tap (no twist) resets.
  if n == 2 then
    if z == 1 then
      k2_held, k2_twisted = true, false
    else
      k2_held = false
      if not k2_twisted then
        base_hz, dist, spacing = BASE_DEFAULT, DIST_DEFAULT, SPACE_DEFAULT
        engine.setBase(base_hz)
      end
    end
    redraw()
    return
  end

  -- K3: toggle the whole drone on/off (the engine env does the fade).
  if n == 3 and z == 1 then
    droning = not droning
    engine.setGate(droning and 1 or 0)
  end
  redraw()
end

function redraw()
  screen.clear()

  local freqs, weights = partials()

  -- header
  screen.level(15)
  screen.move(0, 8)
  screen.text("drifting")
  screen.level(droning and 15 or 3)
  screen.move(128, 8)
  screen.text_right(droning and "playing" or "muted")

  -- readouts
  screen.level(6)
  screen.move(0, 18)
  screen.text("pitch " .. fmt_hz(base_hz))
  screen.move(0, 28)
  screen.text(string.format("tilt %+.2f", dist))
  screen.move(70, 28)
  screen.text(string.format("space %.2f", spacing))

  -- partial spectrum: one bar per oscillator, height = its amplitude.
  local maxw = 0
  for i = 1, N do if weights[i] > maxw then maxw = weights[i] end end
  if maxw <= 0 then maxw = 1 end
  local base_y = 54
  for i = 1, N do
    local x = 6 + (i - 1) * 5
    local h = (weights[i] / maxw) * 20
    screen.level(freqs[i] < 20000 and 15 or 2)   -- dim the muted (>20kHz) ones
    screen.rect(x, base_y - h, 3, h)
    screen.fill()
  end

  -- footer: reflects whichever shift is held.
  screen.level(3)
  screen.move(0, 62)
  if k2_held then
    screen.text(string.format("lfo  tilt %s  space %s",
      fmt_period(tilt_rate), fmt_period(space_rate)))
  elseif k1_held then
    screen.text(string.format("K1+E3 master %.2f", master))
  else
    screen.text("E1 pitch  E2 tilt  E3 space")
  end

  screen.update()
end
