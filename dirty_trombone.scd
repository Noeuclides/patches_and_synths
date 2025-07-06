(
s.boot;
MIDIIn.connectAll;
)

(
SynthDef(\dirtyTromboneMono, {
    |out=0, freq=220, amp=0.3, gate=1,
     dirt=0.5, maxNasty=0,
     vibRate=5, vibDepth=0.01, wowRate=0.3, wowDepth=0.03,
     tone=8000, fxDepth=0.2, delayMix=0.2,
     glide=0.05,
     pan=0|

    var sig, env, vibrato, wow, pitchMod, buzz, noise, formant;
    var distortion, crackle, mod, delay, glideFreq, nastyLayer;

    env = EnvGen.kr(Env.adsr(0.02, 0.2, 0.8, 0.5), gate, doneAction: 2);
    glideFreq = Lag.kr(freq, glide);

    vibrato = SinOsc.kr(vibRate).range((0 - vibDepth), vibDepth);
    wow = SinOsc.kr(wowRate).range((0 - wowDepth), wowDepth);
    pitchMod = vibrato + wow;

    buzz = Mix.fill(5, { |i| Saw.ar(glideFreq * (1 + (i * 0.01) + pitchMod)) }) * 0.15;
    noise = BPF.ar(WhiteNoise.ar(0.2), glideFreq * 2, 0.3);

    sig = (buzz + noise) * env;
    formant = Formant.ar(glideFreq, glideFreq * 2, glideFreq * 0.5) * 0.1;
    sig = sig + formant;

    sig = LPF.ar(sig, tone + (env * 2000));

    distortion = SelectX.ar(dirt, [
        sig,
        tanh(sig * 3),
        Decimator.ar(sig, 44100 * (1 - dirt), 8 - (dirt * 6))
    ]);

    crackle = Crackle.ar(1.9 + (dirt * 0.1)) * dirt * 0.05;
    sig = (distortion + crackle).tanh;

    // Max Nasty Mode
    nastyLayer = SelectX.ar(maxNasty, [
        sig,
        Fold.ar(sig * 4, -0.6, 0.6).tanh + (LFNoise1.ar(1200) * 0.01)
    ]);

    mod = SinOsc.kr(0.2).range(0.001, 0.02) * fxDepth;
    sig = AllpassN.ar(nastyLayer, 0.02, mod, 0.2) + (1 - fxDepth) * nastyLayer;

    delay = CombC.ar(sig, 0.3, 0.3, 3);
    sig = XFade2.ar(sig, delay, delayMix * 2 - 1);

    Out.ar(out, Pan2.ar(sig * amp, pan));
}).add;
)




(

// CC state for knobs/sliders

~ccState = IdentityDictionary[
    \dirt -> 0.5,
    \maxNasty -> 0,
    \tone -> 8000,
    \fxDepth -> 0.2,
    \delayMix -> 0.2,
    \glide -> 0.1,
    \amp -> 0.4
];

~isMono = {
	if (~voiceLimit == 1) {
		true;
	} {
		false;
	};
};  // true for monophonic, false for polyphonic

~setParam = { |key, val|
    if (~isMono) {
        if (~monoSynth.notNil) {
            ~monoSynth.set(key, val);
        };
    } {
        ~activeSynths.do { |s| s.set(key, val) };
    };
};


MIDIdef.cc(\dirtControl, { |val, num, chan, src|
    var v = val.linlin(0, 127, 0, 1);
    ~ccState[\dirt] = v;
	~setParam.(\dirt, v);
    //"Dirtiness: %".format(dirt).postln;
}, 1);


MIDIdef.cc(\toneCC, { |val, num, chan, src|
    var v = val.linexp(0, 127, 1000, 10000);
    ~ccState[\tone] = v;
	~setParam.(\dirt, v);
}, 2);


MIDIdef.cc(\fxDepthCC, { |val, num, chan, src|
    var v = val.linlin(0, 127, 0, 1);
    ~ccState[\fxDepth] = v;
	~setParam.(\dirt, v);
}, 3);

MIDIdef.cc(\delayMixCC, { |val, num, chan, src|
    var v = val.linlin(0, 127, 0, 1);
    ~ccState[\delayMix] = v;
	~setParam.(\dirt, v);
}, 4);

MIDIdef.cc(\glideCC, { |val, num, chan, src|
    var v = val.linlin(0, 127, 0, 1);
    ~ccState[\glide] = v;
	~setParam.(\dirt, v);
}, 5);


MIDIdef.cc(\maxNastyControl, { |val|
	var v = val.linlin(0, 127, 0, 1);
    ~ccState[\maxNasty] = v;
	~setParam.(\dirt, v);
}, 6);
)
(


//~activeSynths = IdentityDictionary.new;

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
)

(
// CONFIG
~voiceLimit = 2;  // Change this to 1, 2, 3, or 4

// TRACKING
~activeSynths = IdentityDictionary.new;
~voiceQueue = List.new;  // Keeps insertion order
)


(
// START SYNTH
~startVoice = {
    |note, vel|
    var freq = note.midicps;
    var amp = vel / 127;
    var params = ~paramsFromState.(~ccState, IdentityDictionary[
        \freq -> freq,
        \amp -> amp,
        \gate -> 1
    ]);

	var synth = Synth(\dirtyTromboneMono, params);
    // Voice stealing
    if (~voiceQueue.size >= ~voiceLimit) {
		var oldestNote = ~voiceQueue.removeAt(~voiceQueue.size - 1);
		var oldSynth = ~activeSynths.removeAt(oldestNote);
        if (oldSynth.notNil) { oldSynth.set(\gate, 0); };
    };


    ~voiceQueue.addFirst(note);
    ~activeSynths[note] = synth;
};

// NOTE ON
MIDIdef.noteOn(\polyNoteOn, { |vel, note, chan, src|
    ~startVoice.(note, vel);
});

// NOTE OFF
MIDIdef.noteOff(\polyNoteOff, { |vel, note, chan, src|
    var synth = ~activeSynths.removeAt(note);
    if (synth.notNil) {
        synth.set(\gate, 0);
        ~voiceQueue.removeAllSuchThat { |n| n == note };
    };
});

)
