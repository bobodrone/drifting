-- drifting
-- v1.0.0 @bobodrone
-- llllllll.co/t/22222
--
-- 21 sine waves at once:
-- osc 1 is the fundamental,
-- the rest are its harmonics.
-- (PARAMS > waveform turns them
-- into saws or pulses.)
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
-- MIDI note in : sets the base pitch (E1).
--      drone mode = latched (holds last
--      note, K3 gates); keys mode = notes
--      gate the drone. mode / device /
--      channel are in PARAMS.
--
-- two slow triangle LFOs sweep the
-- tilt and spacing on their own.
-- their DEPTH is set in PARAMS.
--
-- grid (16x8, optional):
-- row 1 : master level
-- row 2 : drift
-- row 3 : tilt (col 8 = equal)
-- row 4 : tilt LFO speed | depth
-- row 5 : spacing
-- row 6 : spacing LFO speed | depth
-- row 7 : pitch octave (A's),
--         col 16 waveform
--         (dim sine, mid saw,
--          bright pulse)
-- row 8 : pitch semitone a..g#,
--         col 14 midi keys mode,
--         col 15 reset,
--         col 16 drone on/off
-- rows 3 + 5 : the bright led is
--         the LFO, live.

-- must match Engine_Drifting in Engine_Drifting.sc
engine.name = "Drifting"

local controlspec = require "controlspec"
local util = require "util"
local musicutil = require "musicutil"

-- ----------------------------------------------------------------------
-- configuration / state
-- ----------------------------------------------------------------------

local N = 21          -- number of oscillators (fixed, matches the engine)
local K_MAX = 8       -- tilt steepness; must match kMax in the engine

-- the oscillator waveforms the "waveform" param can choose between.
-- the index (1-based here) maps to the engine's `wave` arg as index-1.
local WAVES = {"sine", "saw", "pulse"}

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
local midi_in            -- MIDI device: note-in sets the base pitch
local g                  -- the connected grid

-- encoder feel
local PITCH_RATIO = 1.04  -- E1 is exponential: each detent is a fixed ratio
local DIST_STEP   = 0.02  -- E2 per detent
local SPACE_STEP  = 0.02  -- E3 per detent

-- defaults K2 (tap) restores
local BASE_DEFAULT, DIST_DEFAULT, SPACE_DEFAULT = 110.0, 0.0, 1.0

-- grid: the value each cell of a stepped fader stands for, left to right.
-- the encoders and PARAMS still reach the values in between.
local SPACE_STEPS = {0, 0.05, 0.1, 0.25, 0.5, 0.75, 1, 1.25,
                     1.5, 1.75, 2, 2.25, 2.5, 3, 3.5, 4}
local RATE_STEPS        = {0, 0.005, 0.01, 0.02, 0.035, 0.05, 0.1, 0.2}  -- Hz
local TILT_DEPTH_STEPS  = {0, 0.1, 0.2, 0.3, 0.4, 0.6, 0.8, 1}
local SPACE_DEPTH_STEPS = {0, 0.1, 0.25, 0.5, 1, 2, 3, 4}

-- grid: how many cells the linear faders have. tilt gets an odd count so
-- its middle cell is exactly 0 (equal).
local LEVEL_CELLS = 16
local TILT_CELLS  = 15

-- grid: pitch is an octave row of A's plus a semitone row. octave cell
-- A_CELL is A_HZ; 15 cells span 0.054 Hz .. 880 Hz.
local A_HZ, A_CELL, OCTAVE_CELLS = 110, 12, 15
-- semitone cells a..g#: true = a sharp, shown darker (like black keys)
local SHARPS = {false, true, false, false, true, false,
                true, false, false, true, false, true}

-- grid: led brightness (0-15). MID is a fader's set value on the rows
-- where ON is busy showing the live, LFO-swept value.
local LED_SHARP = 1
local LED_DIM   = 3
local LED_MID   = 7
local LED_ON    = 15
-- the waveform key's brightness for sine / saw / pulse
local WAVE_LEDS = {LED_DIM, LED_MID, LED_ON}

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

-- MIDI notes currently held, oldest first (only tracked in "keys" mode).
local held_notes = {}

-- move the base pitch, clamped to the same range as E1.
local function set_base(hz)
  base_hz = util.clamp(hz, 0.05, 1000)
  engine.setBase(base_hz)
end

local function set_base_from_note(note)
  set_base(musicutil.note_num_to_freq(note))
end

-- toggle the whole drone on/off (the engine env does the fade).
local function toggle_drone()
  droning = not droning
  engine.setGate(droning and 1 or 0)
end

-- put pitch / tilt / spacing back to their defaults.
local function reset()
  dist, spacing = DIST_DEFAULT, SPACE_DEFAULT
  set_base(BASE_DEFAULT)
end

-- MIDI note-in. two modes (the "midi mode" PARAM):
--   drone -> a note just sets the base pitch and latches; the drone holds the
--            last note and K3 still gates the sound. (channel 0 = omni.)
--   keys  -> notes gate the drone: sound while held, silence on release. last-
--            note priority means releasing the top note falls back to the most
--            recent note you're still holding.
local function midi_event(data)
  local msg = midi.to_msg(data)
  local ch = params:get("midi_channel")
  if ch > 0 and msg.ch ~= ch then return end

  local keys_mode = params:get("midi_mode") == 2
  -- many controllers send note-on with velocity 0 to mean note-off.
  local is_on  = msg.type == "note_on" and msg.vel > 0
  local is_off = msg.type == "note_off" or (msg.type == "note_on" and msg.vel == 0)

  if is_on then
    set_base_from_note(msg.note)
    if keys_mode then
      table.insert(held_notes, msg.note)
      if not droning then
        droning = true
        engine.setGate(1)
      end
    end
    redraw()

  elseif is_off and keys_mode then
    -- drop the released note from the held stack.
    for i = #held_notes, 1, -1 do
      if held_notes[i] == msg.note then table.remove(held_notes, i); break end
    end
    if #held_notes > 0 then
      set_base_from_note(held_notes[#held_notes])   -- fall back to newest held
    else
      droning = false
      engine.setGate(0)
    end
    redraw()
  end
end

-- ----------------------------------------------------------------------
-- grid: scaling helpers
-- ----------------------------------------------------------------------

-- linear fader: cell i of n (1-based) -> a value in [lo, hi], and back.
local function cell_to_value(i, n, lo, hi)
  return util.linlin(1, n, lo, hi, i)
end

local function value_to_cell(v, n, lo, hi)
  return util.round(util.linlin(lo, hi, 1, n, v))
end

-- stepped fader: going back from a value picks the highest step that is
-- <= v, so in-between values (set with an encoder or in the PARAMS menu)
-- show as the step below. the epsilon forgives float rounding in params.
local function value_to_step(steps, v)
  local cell = 1
  for i, step in ipairs(steps) do
    if v >= step - 1e-6 then cell = i end
  end
  return cell
end

-- the base pitch as (octave cell, semitone cell), to the nearest semitone.
local function pitch_cells()
  local st = math.floor(12 * math.log(base_hz / A_HZ, 2) + 0.5)
  return util.clamp(st // 12 + A_CELL, 1, OCTAVE_CELLS), st % 12 + 1
end

local function set_pitch_cells(octave, semi)
  set_base(A_HZ * 2 ^ ((octave - A_CELL) + (semi - 1) / 12))
end

-- ----------------------------------------------------------------------
-- grid: led helpers
-- ----------------------------------------------------------------------

-- a "line" is n cells starting at (x, y) and running to the right.
-- which cell of the line (1-based) sits at grid position (px, py)? nil = none.
local function line_cell(line, px, py)
  if py == line.y and px >= line.x and px < line.x + line.n then
    return px - line.x + 1
  end
end

-- set every cell of a line; level_for(i) gives the brightness of cell i.
local function led_line(line, level_for)
  for i = 1, line.n do
    g:led(line.x + i - 1, line.y, level_for(i))
  end
end

-- fader look: cells 1..lit bright, the rest of the track dim.
local function led_bar(line, lit)
  led_line(line, function(i) return i <= lit and LED_ON or LED_DIM end)
end

-- LFO fader look: the set value is a mid-bright fill running from cell
-- `from` to cell `set`, and the single bright cell is where the LFO has
-- swept the value to right now. with the LFO off it sits on the fill's tip.
local function led_live(line, from, set, live)
  local lo, hi = math.min(from, set), math.max(from, set)
  led_line(line, function(i)
    if i == live then return LED_ON end
    return (i >= lo and i <= hi) and LED_MID or LED_DIM
  end)
end

-- ----------------------------------------------------------------------
-- grid: layout
-- ----------------------------------------------------------------------

-- every control is a line of cells plus:
--   press(i) : cell i of the line was pressed
--   draw()   : light the line's leds from the current state
--   held     : is one of its cells down right now?
local controls = {}

local function add_control(x, y, n, press, draw)
  local c = {x = x, y = y, n = n, press = press, held = false}
  c.draw = function() draw(c) end
  controls[#controls + 1] = c
end

-- a linear bar fader over a 0..1 control param.
local function add_level_fader(y, id)
  add_control(1, y, LEVEL_CELLS,
    function(i) params:set(id, cell_to_value(i, LEVEL_CELLS, 0, 1)) end,
    function(c) led_bar(c, value_to_cell(params:get(id), LEVEL_CELLS, 0, 1)) end)
end

-- a bar fader over a control param, one cell per entry in `steps`.
local function add_step_fader(x, y, steps, id)
  add_control(x, y, #steps,
    function(i) params:set(id, steps[i]) end,
    function(c) led_bar(c, value_to_step(steps, params:get(id))) end)
end

local function build_controls()
  -- rows 1-2: master level and drift, 0.0 (left) to 1.0 (right)
  add_level_fader(1, "master")
  add_level_fader(2, "drift")

  -- row 3: tilt, -1 (left) .. 0 (col 8) .. +1 (col 15), filled from the
  -- centre. the bright led is the tilt after its LFO.
  local centre = (TILT_CELLS + 1) / 2
  add_control(1, 3, TILT_CELLS,
    function(i) dist = cell_to_value(i, TILT_CELLS, -1, 1) end,
    function(c)
      led_live(c, centre,
        value_to_cell(dist, TILT_CELLS, -1, 1),
        value_to_cell(mod_dist, TILT_CELLS, -1, 1))
    end)

  -- row 4: tilt LFO speed (cols 1-8) and depth (cols 9-16)
  add_step_fader(1, 4, RATE_STEPS, "tilt_lfo_rate")
  add_step_fader(9, 4, TILT_DEPTH_STEPS, "tilt_lfo_depth")

  -- row 5: spacing. the bright led is the spacing after its LFO.
  add_control(1, 5, #SPACE_STEPS,
    function(i) spacing = SPACE_STEPS[i] end,
    function(c)
      led_live(c, 1,
        value_to_step(SPACE_STEPS, spacing),
        value_to_step(SPACE_STEPS, mod_space))
    end)

  -- row 6: spacing LFO speed (cols 1-8) and depth (cols 9-16)
  add_step_fader(1, 6, RATE_STEPS, "space_lfo_rate")
  add_step_fader(9, 6, SPACE_DEPTH_STEPS, "space_lfo_depth")

  -- row 7: pitch octave. keeps the semitone, drops any fine tuning.
  add_control(1, 7, OCTAVE_CELLS,
    function(i)
      local _, semi = pitch_cells()
      set_pitch_cells(i, semi)
    end,
    function(c) led_bar(c, (pitch_cells())) end)

  -- row 7, col 16: waveform. each press steps sine -> saw -> pulse -> sine;
  -- the led gets brighter with the waveform's harmonics.
  add_control(16, 7, 1,
    function() params:set("waveform", params:get("waveform") % #WAVES + 1) end,
    function(c) led_line(c, function() return WAVE_LEDS[params:get("waveform")] end) end)

  -- row 8, cols 1-12: pitch semitone a..g# within that octave.
  add_control(1, 8, #SHARPS,
    function(i) set_pitch_cells((pitch_cells()), i) end,
    function(c)
      local _, semi = pitch_cells()
      led_line(c, function(i)
        if i == semi then return LED_ON end
        return SHARPS[i] and LED_SHARP or LED_DIM
      end)
    end)

  -- row 8, col 14: midi mode. dim = drone, bright = keys
  add_control(14, 8, 1,
    function() params:set("midi_mode", 3 - params:get("midi_mode")) end,
    function(c)
      local keys = params:get("midi_mode") == 2
      led_line(c, function() return keys and LED_ON or LED_DIM end)
    end)

  -- row 8, col 15: reset pitch / tilt / spacing (same as a K2 tap).
  -- lights while held.
  add_control(15, 8, 1,
    function() reset() end,
    function(c) led_line(c, function() return c.held and LED_ON or LED_DIM end) end)

  -- row 8, col 16: drone on/off (same as K3). bright = playing
  add_control(16, 8, 1,
    function() toggle_drone() end,
    function(c) led_line(c, function() return droning and LED_ON or LED_DIM end) end)
end

-- repaint every led from the current state. called from the LFO tick, so
-- encoder, PARAMS and MIDI changes all show up within a frame.
local function grid_redraw()
  g:all(0)
  for _, c in ipairs(controls) do c.draw() end
  g:refresh()
end

-- grid keys: z = 1 pressed / 0 released. find the control under the key.
local function grid_key(x, y, z)
  for _, c in ipairs(controls) do
    local i = line_cell(c, x, y)
    if i then
      c.held = (z == 1)
      if z == 1 then
        c.press(i)
        redraw()
      end
      return
    end
  end
end

-- the LFO/redraw frame: sweep tilt + spacing with their triangle LFOs,
-- push the modulated values to the engine, and repaint the screen and the
-- grid. running this in Lua (not the engine) keeps the on-screen bars and
-- the grid leds locked to what you hear.
local function tick()
  local t = util.time()
  mod_dist  = util.clamp(dist    + tri(t * tilt_rate)  * tilt_depth,  -1, 1)
  mod_space = util.clamp(spacing + tri(t * space_rate) * space_depth,  0, 4)
  engine.setDist(mod_dist)
  engine.setSpace(mod_space)
  redraw()
  grid_redraw()
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

  -- oscillator waveform (shared by all 21 partials).
  params:add_option("waveform", "waveform", WAVES, 1)
  params:set_action("waveform", function(v)
    engine.setWave(v - 1)   -- param is 1-based; engine wants 0-based
    redraw()
  end)

  -- the two slow triangle LFOs on tilt and spacing.
  -- speed is also live on K2+E2 / K2+E3; depth is here and on the grid.
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

  -- MIDI note-in -> base pitch. pick the device and (optionally) a channel.
  params:add_separator("MIDI")
  params:add{
    type = "option", id = "midi_mode", name = "midi mode",
    options = {"drone", "keys"}, default = 1,
    action = function()
      -- switching mode clears any stuck held-note state.
      held_notes = {}
      redraw()
    end
  }
  params:add{
    type = "number", id = "midi_device", name = "midi device",
    min = 1, max = 16, default = 1,
    action = function(v)
      if midi_in then midi_in.event = nil end
      midi_in = midi.connect(v)
      midi_in.event = midi_event
    end
  }
  params:add{
    type = "number", id = "midi_channel", name = "midi channel (0 = omni)",
    min = 0, max = 16, default = 0
  }

  -- connect the default device now (the action only fires on later changes).
  midi_in = midi.connect(params:get("midi_device"))
  midi_in.event = midi_event

  -- grid: connect and lay out the controls. the leds are repainted by
  -- the LFO tick below.
  g = grid.connect()
  g.key = grid_key
  build_controls()

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
  if midi_in then midi_in.event = nil end
  -- leave the grid dark.
  g:all(0)
  g:refresh()
end

function enc(n, d)
  -- any turn while K2 is held means it's a shift gesture, not a tap-to-reset.
  if k2_held then k2_twisted = true end

  if n == 1 then
    -- E1: base pitch, exponential so every detent is a musical ratio.
    set_base(base_hz * (PITCH_RATIO ^ d))
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
      if not k2_twisted then reset() end
    end
    redraw()
    return
  end

  -- K3: toggle the whole drone on/off.
  if n == 3 and z == 1 then toggle_drone() end
  redraw()
end

function redraw()
  screen.clear()

  local freqs, weights = partials()

  -- header
  screen.level(15)
  screen.move(0, 8)
  screen.text("drifting")
  -- the waveform, when it isn't the default sine.
  if params:get("waveform") > 1 then
    screen.level(6)
    screen.move(44, 8)
    screen.text(WAVES[params:get("waveform")])
  end
  screen.level(droning and 15 or 3)
  screen.move(128, 8)
  screen.text_right(droning and "playing" or "muted")

  -- readouts
  screen.level(6)
  screen.move(0, 18)
  screen.text("pitch " .. fmt_hz(base_hz))
  -- show "keys" at the right of the pitch line when in MIDI keys mode.
  if params:get("midi_mode") == 2 then
    screen.level(#held_notes > 0 and 15 or 3)
    screen.move(128, 18)
    screen.text_right("keys")
  end
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
