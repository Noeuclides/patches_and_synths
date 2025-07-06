MIDIClient.init;
MIDIIn.connectAll;
(
// Synth definition
SynthDef(\learnCCSynth, {
    |freq=440, amp=0.3, gate=1, cutoff=1000|
    var sig, env, filt;

    env = EnvGen.kr(Env.asr(0.01, 1, 0.3), gate, doneAction: 2);
    sig = Saw.ar(freq) * env;
    filt = RLPF.ar(sig, cutoff, 0.2);

    Out.ar(0, filt!2 * amp);
}).add;

// Global state for current CC values
~ccState = IdentityDictionary[
    \cutoff -> 1000,
    \amp -> 0.3
];

MIDIdef.cc(\cutoffCC, { |val, num, chan, src|
    var cutoff = val.linexp(0, 127, 200, 5000);  // Map CC value to frequency
    ~ccState[\cutoff] = cutoff;

    // Live update the parameter on all active synths
    ~activeSynths.do { |synth|
        synth.set(\cutoff, cutoff);
    };

    ("Cutoff updated to: " ++ cutoff).postln;
}, 1);  // CC number 1


// Track active synths by MIDI note
~activeSynths = IdentityDictionary.new;

// MIDI Note On: use latest CC values
MIDIdef.noteOn(\noteOnHandler, { |vel, note, chan, src|
    var freq = note.midicps;
    var amp = vel.linlin(1, 127, 0.1, 0.5);  // scale vel if desired

	var params = [
        \freq, freq,
        \amp, amp,
        \gate, 1,
        \cutoff, ~ccState[\cutoff]
    ];
    var synth = Synth(\learnCCSynth, params);

    ~activeSynths[note] = synth;
}, nil);

MIDIdef.noteOff(\noteOffHandler, { |vel, note|
    ~activeSynths[note].set(\gate, 0);
    ~activeSynths.removeAt(note);
});

)
