(
SynthDef(\click, {
    |out=0, amp=0.3, pitch=1000|
    var env = Env.perc(0.001, 0.05).kr(2); // short percussive envelope
    var sig = SinOsc.ar(pitch, 0, amp) * env;
    Out.ar(out, Pan2.ar(sig));
}).add;
)


(
~bounceParams = (
    decay: 0.85,
    pitch: 1200,
    amp: 0.3,
    bounces: 12
);

// Function to simulate bouncing behavior
~triggerBounce = {
    var n = ~bounceParams[\bounces];

    Routine({
        var interval = 0.05;
        var pitch = ~bounceParams[\pitch];
        var amp   = ~bounceParams[\amp];

        n.do {
            var decay = ~bounceParams[\decay];  // 👈 now read it on each bounce
            Synth(\click, [\pitch, pitch, \amp, amp]);
            interval = interval / decay;
            pitch = pitch * 0.98;
            interval.wait;
        };
    }).play;
};



(
MIDIClient.init;
MIDIIn.connectAll;

MIDIdef.noteOn(\bounceFromNote, { |vel, num|
    ~bounceParams[\amp] = vel.linlin(1, 127, 0.1, 0.5);
    ~triggerBounce.();  // launch bouncing sequence
});
)

(
MIDIdef.cc(\setDecay, { |val, num, chan|
    ~bounceParams[\decay] = val.linlin(0, 127, 0.7, 0.99);
    ("Decay now: " ++ ~bounceParams[\decay]).postln;
}, 7, chan: 11);  // 👈 channel 11 explicitly
)

Synth(\click, [\pitch, 1000, \amp, 0.4]);

~triggerBounce.(); // simulate bouncing

MIDIClient.init;
MIDIIn.connectAll;
MIDIClient.sources.do { |src, i| ("[" ++ i ++ "] " ++ src.device).postln; }


MIDIdef.cc(\debugCC, { |val, num, chan, src|
    ("CC " ++ num ++ ": " ++ val).postln;
});

MIDIIn.connect(0, MIDIClient.sources[0]);
MIDIdef.all.do(_.free);

MIDIClient.init;

// Connect manually using the device you saw printed earlier
MIDIIn.connect(0, MIDIClient.sources[0]);

(
MIDIdef.cc(\debugAllCC, { |val, num, chan, src|
    ("CC received - Num: " ++ num ++ ", Value: " ++ val).postln;
});
)

(
MIDIIn.control = { |src, chan, num, val|
    ("MIDI raw: chan=" ++ chan ++ " CC=" ++ num ++ " val=" ++ val).postln;
};
)


(
MIDIdef.cc(\ccCatchAll, { |val, num, chan, src|
    ("Caught CC #" ++ num ++ " value: " ++ val).postln;
}, nil);  // Listen to ALL CCs
)



