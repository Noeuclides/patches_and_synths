// ==========================================
// PERCUSSIVE ATTACK → GRITTY SUSTAIN SYNTH
// ==========================================
// Attack: triggerable sample with variable length & start position
// Sustain: rich subtractive body with character, grit, movement

(
// ==========================================
// 1. BOOT SERVER & CREATE BUSES FIRST
// ==========================================
s.waitForBoot({
    
    // Create reverb bus BEFORE SynthDefs
    ~reverbBus = Bus.audio(s, 2);
    
    // Load your percussive sample here
    // Replace path with your actual 5-second recording
    ~percBuffer = Buffer.read(s, "/Users/nicolas/Music/Logic/laminado_sampler.wav");

    s.sync;
    
    // ==========================================
    // 2. MAIN SYNTHDEF
    // ==========================================
    SynthDef(\percussiveGrit, {
        |out=0, gate=1, freq=110, amp=0.4, 
        reverbBus=10,           // reverb send bus (will be set at creation)
        
        // Sample attack controls
        attackLen=2,          // how long the sample plays (0.05 to 1.0)
        attackStart=0,          // random start position within sample (0 to 1)
        attackVol=0.8,          // sample loudness
        
        // Sustain body controls
        pressure=0.5,           // opens harmonics, adds grit (0 to 1)
        grit=0.4,               // distortion/saturation amount
        cutoff=0.6,             // filter frequency (0 to 1, musical scale)
        resonance=0.3,          // filter Q
        drift=0.2,              // slow pitch/filter instability
        space=0.3,              // reverb send
        pan=0|
        
        var sampleSig, synthSig, sig;
        var envAttack, envSustain, envTone, envPressure;
        var osc1, osc2, sub, noise, body;
        var filt, sat, shaped;
        var driftFreq, driftFilt;
        var sampleDur, sampleStartFrame;
        var bufnum;
        
        // ==========================================
        // ENVELOPES
        // ==========================================
        
        // Sample attack envelope - quick fade in, hold, quick fade out
        sampleDur = attackLen.clip(0.05, 1.0);
        envAttack = EnvGen.kr(
            Env([0, 1, 1, 0], [0.002, sampleDur - 0.012, 0.01], \sin),
            gate
        );

        // Sustain body envelope - slow attack, infinite sustain, slow release
        envSustain = EnvGen.kr(
            Env.asr(2.5, 1.0, 2.5, \sin),
            gate,
            doneAction: 2
        );
        
        // Tonal evolution - blooms open over time
        envTone = EnvGen.kr(
            Env([0.2, 1.0, 0.7], [1.2, 3.0], [\exp, \sin]),
            gate
        );
        
        // Pressure envelope - maps physical effort to timbre
        envPressure = pressure.lag(0.05) * envTone;
        
        // ==========================================
        // DRIFT & INSTABILITY
        // ==========================================
        // Slow wandering pitch and filter - "breathing"
        driftFreq = LFNoise1.kr(0.3).bipolar(drift * 8); // ±cents
        driftFilt = LFNoise1.kr(0.15).range(0.92, 1.08); // subtle filter wander
        
        // ==========================================
        // SAMPLE ATTACK (handles mono or stereo buffers)
        // ==========================================
        bufnum = \buf.kr(0);
        
        // PlayBuf for stereo buffers (most common for recordings)
        // If your buffer is mono, change numChannels to 1
        sampleSig = PlayBuf.ar(
            2, // CHANGE THIS: 1 for mono samples, 2 for stereo samples
            bufnum,
            BufRateScale.kr(bufnum),
            startPos: attackStart.linlin(0, 1, 0, 
                (BufFrames.kr(bufnum) - (sampleDur * SampleRate.ir)).max(0)),
            loop: 0
        );
        
        // Mix stereo to mono for processing
        sampleSig = (sampleSig[0] + sampleSig[1]) * 0.5;
        
        // Mute if no valid buffer
        sampleSig = sampleSig * (bufnum > 0);
        
        sampleSig = sampleSig * envAttack * attackVol;
        
        // ==========================================
        // SYNTH BODY - Rich subtractive layers
        // ==========================================
        
        // Main oscillator - saw with slight detuning for width
        osc1 = Saw.ar(freq * (1 + driftFreq.midiratio)) 
             + Saw.ar(freq * (1 + driftFreq.midiratio) * 1.004); 
        osc1 = osc1 * 0.35;
        
        // Secondary layer - pulse with pressure-modulated width
        osc2 = Pulse.ar(
            freq * 0.5 * (1 + driftFreq.midiratio), 
            (0.3 + (envPressure * 0.4)).clip(0.05, 0.95)
        );
        osc2 = osc2 * 0.25;
        
        // Sub bass - solid low end
        sub = SinOsc.ar(freq * 0.5) * 0.3;
        
        // Air/noise layer - increases with pressure (bow scrape, breath)
        noise = LPF.ar(
            PinkNoise.ar(envPressure * 0.15),
            freq * 4
        );
        
        // Combine sources
        body = osc1 + osc2 + sub + noise;
        
        // ==========================================
        // FILTER - Musical cutoff with pressure
        // ==========================================
        filt = RLPF.ar(
            body,
            (cutoff.linexp(0, 1, 120, 8000) * 
             (0.5 + (envPressure * 2.5)) * 
             driftFilt).clip(80, 12000),
            (1 - (resonance * 0.7)).clip(0.1, 0.95)
        );
        
        // Secondary resonance pass for character
        filt = BPF.ar(filt, freq * 2, 1.5, 2) + filt;
        
        // ==========================================
        // SATURATION - Asymmetric grit, amp-like
        // ==========================================
        // Dual-stage waveshaping for richness
        shaped = (filt * (1 + (grit * 3))).tanh;
        shaped = (shaped * (1 + (envPressure * grit * 2))).clip(-0.95, 1.0);
        
        // Soft clip final to prevent harshness
        sat = (shaped * 1.4).softclip * 0.7;
        
        // ==========================================
        // MIX SAMPLE + SYNTH
        // ==========================================
        synthSig = sat * envSustain;
        
        // Sample is LOUDER and more present (1.8x instead of 1.2x)
        // Synth body stays quieter during attack phase
        sig = (sampleSig * 1.8) + (synthSig * amp * 0.7);
        
        // ==========================================
        // STEREO & OUTPUT
        // ==========================================
        sig = Pan2.ar(sig, pan);
        
        // Direct output
        Out.ar(out, sig * (1 - space));
        
        // Send to reverb bus
        Out.ar(reverbBus, sig * space);
        
    }).add;
    
    // ==========================================
    // 3. GLOBAL REVERB (Simple but effective)
    // ==========================================
    
    SynthDef(\globalReverb, {
        |in, out=0, size=0.7, damp=0.5, mix=0.4|
        var sig, verb;
        
        sig = In.ar(in, 2);
        
        // FreeVerb - efficient, sounds good for this context
        verb = FreeVerb2.ar(
            sig[0], sig[1],
            mix: 1.0,
            room: size.linlin(0, 1, 0.5, 0.97),
            damp: damp
        );
        
        Out.ar(out, verb * mix);
    }).add;
    
    s.sync;
    
    // Start reverb node
    ~reverbNode = Synth(\globalReverb, [
        \in, ~reverbBus,
        \size, 0.75,
        \mix, 0.35
    ], addAction: \addToTail);
    
    "=== PERCUSSIVE GRIT SYNTH READY ===".postln;
    "~reverbBus: %".format(~reverbBus.index).postln;
    "~percBuffer: % (replace path if needed)".format(~percBuffer.bufnum).postln;
});
)

// ==========================================
// 4. TEST PATTERNS
// ==========================================

// Single note test - adjust parameters live
// Works even without sample loaded (will just be synth body)
(
~testNote = Synth(\percussiveGrit, [
    \freq, 110,
    \amp, 0.5,
    \reverbBus, ~reverbBus,    // pass the bus
    \buf, ~percBuffer.bufnum,  // pass the buffer (or 0 if not loaded)
    \attackLen, 3,           // sample plays for 400ms
    \attackStart, 0.2,         // starts 20% into the sample
    \attackVol, 1.8,
    \pressure, 0.6,            // moderate pressure
    \grit, 0.5,                // medium grit
    \cutoff, 0.5,
    \resonance, 0.4,
    \drift, 0.3,
    \space, 0.4,
    \pan, 0
]);
)

// Release note
~testNote.set(\gate, 0);

// Test without sample (pure synth)
(
~testNote = Synth(\percussiveGrit, [
    \freq, 55,
    \amp, 0.6,
    \reverbBus, ~reverbBus,
    \buf, 0,                   // no sample
    \pressure, 0.8,
    \grit, 0.6,
    \cutoff, 0.4,
    \drift, 0.4,
    \space, 0.5
]);
)

// ==========================================
// Random variations pattern
(
Pbind(
    \instrument, \percussiveGrit,
    \dur, Pwhite(2.0, 5.0),
    \midinote, Prand([38, 41, 45, 50], inf),
    \amp, 0.4,
    
    // Pass buses/buffers
    \reverbBus, ~reverbBus,
    \buf, Pfunc({ if(~percBuffer.notNil, { ~percBuffer.bufnum }, { 0 }) }),
    
    // Randomize attack sample behavior
    \attackLen, Pwhite(1, 3.5),
    \attackStart, Pwhite(0.0, 1),
    \attackVol, Pwhite(1, 1.8),

    // Vary sustain character
    \pressure, Pwhite(0.3, 0.9),
    \grit, Pwhite(0.3, 0.7),
    \cutoff, Pwhite(0.3, 0.7),
    \resonance, Pwhite(0.2, 0.5),
    \drift, Pwhite(0.1, 0.4),
    
    \space, Pwhite(0.2, 0.5),
    \pan, Pwhite(-0.5, 0.5),
    
    \legato, Pwhite(0.8, 1.2)
).play;
)

// ==========================================
// 5. LOAD YOUR SAMPLE (do this after boot)
// ==========================================
/*
// Replace with your actual path:
~percBuffer = Buffer.read(s, "/Users/you/samples/metal_hit.wav");

// Or load multiple samples into an array:
~percSamples = [
    Buffer.read(s, "/path/to/hit1.wav"),
    Buffer.read(s, "/path/to/hit2.wav"),
    Buffer.read(s, "/path/to/scrape.wav")
];

// Then use random sample in pattern:
Pbind(
    ...
    \buf, Prand(~percSamples.collect(_.bufnum), inf),
    ...
)
*/

// ==========================================
// 6. LIVE CONTROL TEMPLATE
// ==========================================
// Map these to your MIDI controller

(
MIDIClient.init;
MIDIIn.connectAll;

// Store notes in dictionary by note number (allows multiple notes)
~activeNotes = IdentityDictionary.new;

// Example MIDI CC mapping (adjust CC numbers to your controller)
MIDIdef.cc(\pressureControl, { |val|
    ~activeNotes.do({ |note|
        note.set(\pressure, val.linlin(0, 127, 0, 1));
    });
}, 1); // CC1 = Mod wheel

MIDIdef.cc(\gritControl, { |val|
    ~activeNotes.do({ |note|
        note.set(\grit, val.linlin(0, 127, 0, 1));
    });
}, 74); // CC74

MIDIdef.cc(\cutoffControl, { |val|
    ~activeNotes.do({ |note|
        note.set(\cutoff, val.linlin(0, 127, 0, 1));
    });
}, 71); // CC71

MIDIdef.cc(\spaceControl, { |val|
    ~activeNotes.do({ |note|
        note.set(\space, val.linlin(0, 127, 0, 0.8));
    });
}, 91); // CC91 = Reverb

MIDIdef.noteOn(\noteOnHandler, { |vel, num|
    // Create new synth for this note
    ~activeNotes[num] = Synth(\percussiveGrit, [
        \freq, num.midicps,
        \amp, vel.linlin(0, 127, 0, 0.8),
        \reverbBus, ~reverbBus,
        \buf, if(~percBuffer.notNil, { ~percBuffer.bufnum }, { 0 }),
        \attackLen, exprand(0.2, 0.6),
        \attackStart, rrand(0.0, 0.5)
    ]);
});

MIDIdef.noteOff(\noteOffHandler, { |vel, num|
    // Release the specific note
    if(~activeNotes[num].notNil, {
        ~activeNotes[num].set(\gate, 0);
        ~activeNotes[num] = nil; // clear from dictionary
    });
});
)