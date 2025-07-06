(
SynthDef(\mbSynth, {
	|out=0, freq=440, amp=0.3, gate=1,
	 vibRate=5, vibDepth=0.005, wowDepth=0.03,
	 cutoff=1200, pan=0|

	var sig, env, vibrato, wow, filt, delay, reverb, detune, cutoffMod;

	// Per-synth randomness (static once per voice)
	detune = Rand(0.996, 1.004);
	cutoffMod = Rand(0.6, 1.4);

	// Vibrato + wow
	vibrato = SinOsc.kr(vibRate, 0, vibDepth).lag(0.05);
	wow = LFNoise1.kr(0.3) * wowDepth;

	// Oscillator blend
	sig = Mix([
		Saw.ar(freq * detune * (1 + vibrato + wow), 0.3),
		Pulse.ar(freq * 0.997, 0.5, 0.3)
	]);

	// Envelope: longer release, soft curve
	env = EnvGen.kr(
		Env.adsr(0.01, 0.1, 0.8, 1.5, curve: -4),
		gate,
		doneAction: 2
	);
	sig = sig * env;

	// Filtering
	filt = RLPF.ar(sig, cutoff * cutoffMod, 0.3);

	// FX
	sig = tanh(filt * 2);
	delay = CombC.ar(sig, 0.3, 0.2 + LFNoise1.kr(0.1).range(-0.05, 0.05), 3);
	reverb = FreeVerb.ar(delay + sig, mix: 0.35, room: 0.7, damp: 0.5);

	// Stereo output with pan
	sig = Pan2.ar(reverb, pan, amp);
	Out.ar(out, sig);
}).add;
)

(
~ccState = (
	\cutoff: 1200,
	\vibRate: 5,
	\vibDepth: 0.01,
	\wowDepth: 0.03,
	\pan: 0
);

~activeSynths = IdentityDictionary.new;

MIDIdef.noteOn(\noteOnHandler, { |vel, note, chan, src|
	var freq = note.midicps;
	var amp = vel / 127;

	var args = [
		\freq, freq,
		\amp, amp
	] ++ ~ccState;

	args.postln;  // Debug

	~activeSynths[note] = Synth(\mbSynth, args);
});

MIDIdef.noteOff(\noteOffHandler, { |vel, note|
	~activeSynths[note].set(\gate, 0);
	~activeSynths.removeAt(note);
});

MIDIdef.cc(\cutoffCtrl, { |val|
	var v = val.linexp(0, 127, 200, 8000);
	~ccState[\cutoff] = v;
	~activeSynths.do { |s| s.set(\cutoff, v) };
}, 1);

MIDIdef.cc(\vibRateCtrl, { |val|
	var v = val.linlin(0, 127, 0.1, 8);
	~ccState[\vibRate] = v;
	~activeSynths.do { |s| s.set(\vibRate, v) };
}, 2);

MIDIdef.cc(\vibDepthCtrl, { |val|
	var v = val.linlin(0, 127, 0, 0.1);
	~ccState[\vibDepth] = v;
	~activeSynths.do { |s| s.set(\vibDepth, v) };
}, 3);

MIDIdef.cc(\wowDepthCtrl, { |val|
	var v = val.linlin(0, 127, 0, 0.9);
	~ccState[\wowDepth] = v;
	~activeSynths.do { |s| s.set(\wowDepth, v) };
}, 5);

MIDIdef.cc(\panCtrl, { |val|
	var v = val.linlin(0, 127, -1, 1);
	~ccState[\pan] = v;
	~activeSynths.do { |s| s.set(\pan, v) };
}, 10);
)
