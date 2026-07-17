// Engine_Drifting.sc
//
// The SuperCollider side of the "drifting" norns script.
// One persistent synth holds all 21 sine oscillators. Three control
// values shape it live:
//   base    - the fundamental frequency of oscillator 1 (Hz)
//   spacing - how far apart the partials are (0 = all on the fundamental,
//             1 = the natural harmonic series, up to 4 = quadruple spacing)
//   dist    - amplitude tilt across the 21 partials (-1 favours the low /
//             fundamental end, 0 = equal, +1 favours the highest partial)
//   amp     - overall master level
// A single gate fades the whole drone in and out (K3 on the norns).

Engine_Drifting : CroneEngine {

	// keep a reference to the one drone synth so commands can .set it live.
	var <synth;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {

		SynthDef("drifting", {
			arg base = 110, spacing = 1.0, dist = 0.0, amp = 0.3,
			    drift = 0.3, gate = 0, out = 0;

			var n = 21;           // number of oscillators
			var kMax = 8;         // steepness of the amplitude tilt at the extremes
			var maxDrift = 0.02;  // max frequency wander at drift = 1 (±2%)
			var lagBase, lagSpace, slope, driftDepth;
			var freqs, gates, weights, wsum, amps, sig, env;

			// smooth encoder moves so changes don't zipper / click.
			lagBase  = Lag.kr(base, 0.1);
			lagSpace = Lag.kr(spacing, 0.1);
			slope    = Lag.kr(dist, 0.1) * kMax;
			driftDepth = Lag.kr(drift, 0.1) * maxDrift;

			// oscillator i (0..20) is harmonic (i+1):
			//   freq = base * (1 + i * spacing)
			// i=0 is always the fundamental; spacing scales the gaps.
			// each osc also gets its own slow, independent frequency wander
			// (LFNoise1 at a random rate) so the 21 partials never phase-lock
			// into a single periodic pulse — that's what turns the "motorboat"
			// into an evolving shimmer. drift = 0 -> dead still / exact freqs.
			freqs = Array.fill(n, { |i|
				var f = lagBase * (1 + (i * lagSpace));
				f * (1 + (LFNoise1.kr(Rand(0.02, 0.2)) * driftDepth));
			});

			// mute any partial above ~20 kHz so high settings stay clean
			// instead of aliasing.
			gates = freqs.collect { |f| f < 20000 };

			// exponential amplitude tilt across the partials. muted partials
			// get zero weight so they don't steal level from the audible ones.
			weights = Array.fill(n, { |i| (slope * (i / (n - 1))).exp }) * gates;

			// normalise so the weights sum to 1 -> total loudness stays roughly
			// constant wherever the tilt sits (and the master stays sane).
			wsum = weights.sum.max(0.0001);
			amps = weights / wsum;

			// sum all 21 sines at their normalised amplitudes. each gets a
			// random start phase (Rand) so they don't all spike together.
			sig = Mix.fill(n, { |i| SinOsc.ar(freqs[i], Rand(0, 2pi)) * amps[i] });

			// whole-drone fade. gate 1 = fade in, gate 0 = fade out.
			// no doneAction: the synth lives for the engine's lifetime and
			// just rests at silence when gated off, so E1/E2/E3 keep working.
			env = EnvGen.kr(
				Env.asr(attackTime: 1.5, releaseTime: 2.0, curve: \sin),
				gate
			);

			sig = sig * Lag.kr(amp, 0.1) * env;

			Out.ar(out, [sig, sig]);
		}).add;

		// register the SynthDef before we instantiate it.
		context.server.sync;

		// create the one drone synth, silent (gate 0) until K3.
		synth = Synth.new(
			"drifting",
			[\gate, 0, \out, context.out_b.index],
			context.xg
		);

		// live control commands. each just sets one arg on the running synth.
		this.addCommand("setBase",  "f", { arg msg; synth.set(\base,    msg[1]); });
		this.addCommand("setSpace", "f", { arg msg; synth.set(\spacing, msg[1]); });
		this.addCommand("setDist",  "f", { arg msg; synth.set(\dist,    msg[1]); });
		this.addCommand("setDrift", "f", { arg msg; synth.set(\drift,   msg[1]); });
		this.addCommand("setAmp",   "f", { arg msg; synth.set(\amp,     msg[1]); });
		this.addCommand("setGate",  "f", { arg msg; synth.set(\gate,    msg[1]); });
	}

	free {
		synth.free;
	}
}
