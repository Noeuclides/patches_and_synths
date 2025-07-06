// Run this first to boot server
(
s.boot;
MIDIClient.init;
MIDIIn.connectAll;
)

(
SynthDef(\braveMonks, {
	|out=0, freq=220, amp=0.2, gate=1,
	 crunch=0.7, revMix=0.3, cutoff=1500, rq=0.3,
	 feedbackAmt=0, shimmerMix=0.4, fuzzAmt=1, fuzzOn=1, shimmerOn=1|

	var tone, noise, mod, env, sig, drive, baseVerb, shimmer, verb, feedback;

	env = EnvGen.kr(Env.asr(0.01, 1, 2), gate, doneAction: 2);

	tone = Saw.ar(freq * [1, 1.005]) * 0.4;
	noise = BPF.ar(WhiteNoise.ar(0.2), freq * 2, 0.3);
	mod = LFNoise2.kr(4).range(0.8, 1.2);
	sig = (tone + noise) * mod * env;

	feedback = LocalIn.ar(2);
	sig = sig + (feedback * feedbackAmt);

	// Fuzz section with optional toggle
	drive = (sig * crunch).tanh + (sig * 4).clip2(0.3);
	drive = drive * fuzzAmt * fuzzOn;
	drive = RLPF.ar(drive, cutoff, rq);
	drive = HPF.ar(drive, 100);

	baseVerb = FreeVerb.ar(drive, mix: revMix, room: 0.95, damp: 0.4);

	// Shimmer with toggle and mix
	shimmer = PitchShift.ar(baseVerb, 0.2, 2.0, 0.01, 0.01);
	verb = baseVerb + (shimmer * shimmerMix * shimmerOn);

	LocalOut.ar(verb);
	Out.ar(out, Limiter.ar(verb * amp, 0.95));
}).add;
)


(

~ccState = IdentityDictionary[
	\cutoff -> 1500,
    \feedbackAmt -> 0,
    \fuzzAmt -> 0
];


// MIDI CC handlers — always update ~ccState with correct param name
MIDIdef.cc(\cutoffCtrl, { |val|
	var v = val.linexp(0, 127, 200, 8000);
    ~ccState[\cutoff] = v;
    ~activeSynths.do { |synth| synth.set(\cutoff, v) };
}, 1);

MIDIdef.cc(\crunchCtrl, { |val|
	var v = val.linlin(0, 127, 0.1, 2);
    ~ccState[\crunch] = v;
    ~activeSynths.do { |synth| synth.set(\crunch, v) };
}, 2);

MIDIdef.cc(\reverbCtrl, { |val|
	var v = val.linlin(0, 127, 0, 1);
    ~ccState[\revMix] = v;
    ~activeSynths.do { |synth| synth.set(\revMix, v) };
}, 3);

MIDIdef.cc(\shimmerMix, { |val|
	var v = val.linlin(0, 127, 0, 1);
    ~ccState[\shimmerMix] = v;
    ~activeSynths.do { |s| s.set(\shimmerMix, v) };
}, 4);

MIDIdef.cc(\feedbackAmt, { |val|
	var v = val.linlin(0, 127, 0, 0.9);
    ~ccState[\feedbackAmt] = v;
    ~activeSynths.do { |s| s.set(\feedbackAmt, v) };
}, 5);

MIDIdef.cc(\fuzzAmt, { |val|
	var v = val.linlin(0, 127, 0, 2);
    ~ccState[\fuzzAmt] = v;
    ~activeSynths.do { |s| s.set(\fuzzAmt, v) };
}, 6);

MIDIdef.cc(\shimmerOn, { |val|
	var v = val > 63;
    ~ccState[\shimmerOn] = v;
    ~activeSynths.do { |s| s.set(\shimmerOn, v) };
}, 8);

MIDIdef.cc(\fuzzOn, { |val|
	var v = val > 63;
    ~ccState[\fuzzOn] = v;
    ~activeSynths.do { |s| s.set(\fuzzOn, v) };
}, 9);

)

(
~paramsFromState = { |stateDict, overrides|
	var result = List.new;
	var finalDict;

	// Provide default for overrides if not given
	if (overrides.isNil) {
		overrides = IdentityDictionary.new;
	};

	finalDict = stateDict.copy.putAll(overrides);

	finalDict.keysValuesDo { |k, v|
		result.add(k);
		result.add(v);
	};

	result.asArray;
};


~activeSynths = IdentityDictionary.new;

MIDIdef.noteOn(\noteOnHandler, { |vel, note, chan, src|
    var freq = note.midicps;
    var amp = vel / 127;

	var params = ~paramsFromState.(~ccState, IdentityDictionary[
		\freq -> freq,
		\amp -> amp
	]);

	var synth = Synth(\braveMonks, params);

	params.postln;

    ~activeSynths[note] = synth;
});


MIDIdef.noteOff(\noteOffHandler, { |vel, note|
    var synth = ~activeSynths[note];
    if (synth.notNil) {
        synth.set(\gate, 0);
        ~activeSynths.removeAt(note);
    };
});

)

