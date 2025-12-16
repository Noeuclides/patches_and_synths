// ═══════════════════════════════════════════════════════════════════════════
// LIVE INSTRUMENT — MAIN BOOT FILE
// Physical modeling synth for unstable / ritual / pressure music
// ═══════════════════════════════════════════════════════════════════════════

(
// ─────────────────────────────────────────────────────────────────────────
// 1. SERVER SETUP
// ─────────────────────────────────────────────────────────────────────────

s.options.memSize = 8192 * 16;  // 128 MB for samples
s.options.numBuffers = 1024 * 4;
s.options.numOutputBusChannels = 2;
s.options.numInputBusChannels = 0;
s.options.maxNodes = 1024 * 4;
s.options.blockSize = 128; // balance latency vs CPU

s.waitForBoot({
    var samplePath;

    "═══════════════════════════════════════════════════════════════".postln;
    "    LIVE INSTRUMENT BOOT SEQUENCE".postln;
    "═══════════════════════════════════════════════════════════════".postln;

    // ─────────────────────────────────────────────────────────────────────
    // 2. GLOBAL BUSES
    // ─────────────────────────────────────────────────────────────────────

    ~reverbBus = Bus.audio(s, 2);
    ~delayBus = Bus.audio(s, 2);
    ~droneBus = Bus.audio(s, 2);

    // Control buses for MIDI mapping
    ~pressureBus = Bus.control(s, 1).set(0.5);
    ~airBus = Bus.control(s, 1).set(0.3);
    ~hollowBus = Bus.control(s, 1).set(0.5);  // hollow (0) to stiff (1)
    ~spaceBus = Bus.control(s, 1).set(0.3);
    ~grainDensityBus = Bus.control(s, 1).set(10);

    "✓ Global buses created".postln;

    s.sync;

    // ─────────────────────────────────────────────────────────────────────
    // 3. SYNTHDEFS — PHYSICAL MODELING CORE
    // ─────────────────────────────────────────────────────────────────────

    // ═══════════════════════════════════════════════════════════════════════
    // KLANK EXPLANATION:
    //
    // Klank.ar is a resonator bank - like plucking/hitting a physical object
    // and hearing its natural resonances ring out.
    //
    // The `[...] syntax creates a "specification" with 3 arrays:
    //   [frequencies, amplitudes, decay_times]
    //
    // [1, 2.01, 3.98, 5.03, 7.1] * resMod
    //   → These are the resonant frequencies (partials/harmonics)
    //   → "1" is the fundamental, "2.01" is ~2x that (octave up), etc.
    //   → Slightly detuned (2.01 instead of 2.0) for organic beating
    //   → resMod is the base frequency - so if resMod=440Hz:
    //       440, 884, 1751, 2213, 3124 Hz
    //   → .clip(80, 8000) prevents subsonic rumble or ultrasonic noise
    //
    // [1, 0.7, 0.5, 0.3, 0.2] * brightMod
    //   → Amplitude of each partial
    //   → Higher partials are quieter (0.2 vs 1.0)
    //   → brightMod scales this - low bright = dark tone, high = bright
    //
    // [1, 0.8, 0.6, 0.4, 0.3] * resDecay
    //   → How long each partial rings (in seconds)
    //   → Higher partials die faster (0.3s vs 1.0s × resDecay)
    //   → This mimics real materials: low frequencies sustain longer
    //
    // exciter = the input signal that "hits" the resonator
    // decayscale = resRatio stretches/compresses all decay times
    //
    // Result: Turns a sharp impulse into a complex, ringing body tone
    // ═══════════════════════════════════════════════════════════════════════

    SynthDef(\physicalBody, {
        |out=0, gate=1, freq=110, amp=0.3,
        // Exciter params
        malletVol=0.5, noiseVol=0.5, stiffness=0.5, noiseColor=0.5, exciterColor=0.35,
        // Resonator params
        resFreq=440, resDecay=2.0, resBright=0.4, resOpening=0.0, resRatio=0.5,
        // Movement
        lfo1rate=0.5, lfo1amt=0.5, lfo2rate=0.3, lfo2amt=0.96,
        hollow=0.5,
        // Output
        pressure=0.5, pan=0, reverbSend=0.3, delaySend=0.1|

        var exciter, mallet, noise, resonated, sig;
        var envAmp, envExcite, lfo1, lfo2;
        var resMod, brightMod;
        var hollowNoise, airLayer;

        // FIX: Ensure resFreq tracks freq if not explicitly set
        resFreq = freq;

        // ═══ ENVELOPES ═══
        envAmp = EnvGen.kr(Env.asr(0.005, 1, 1.2), gate, doneAction:2);
        // Sharp attack for exciter, dies down
        envExcite = EnvGen.kr(Env.perc(0.001, 0.08 * stiffness.linexp(0,1,0.5,3.0)), gate);

        // ═══ MODULATION ═══
        lfo1 = SinOsc.kr(lfo1rate).bipolar(lfo1amt * 0.02);  // reduced for stability
        lfo2 = LFNoise1.kr(lfo2rate).bipolar(lfo2amt * 0.03);

        // ═══ EXCITER SOURCES ═══

        // Mallet: percussive harmonic burst (more present for stiff)
        mallet = Pulse.ar(
            freq * (1 + (exciterColor * 2)),
            0.2 + (stiffness * 0.6)
        ) * envExcite * malletVol * (0.5 + (hollow * 0.5));

        // Noise: bow scrape / breath attack
        noise = LPF.ar(
            WhiteNoise.ar(),
            noiseColor.linexp(0, 1, 400, 8000)
        ) * envExcite * noiseVol * 0.7;

        exciter = mallet + noise;

        // ═══ AIR / HOLLOW LAYER ═══
        // Continuous breathy/airy component (more prominent when hollow)
        hollowNoise = BPF.ar(
            PinkNoise.ar(),
            freq * (1 + lfo1),
            1.0 + (hollow * 1.5)  // wider Q when stiff, tighter when hollow
        ) * (1 - hollow).linexp(0, 1, 0.1, 0.6);  // much louder when hollow

        airLayer = LPF.ar(
            WhiteNoise.ar(),
            (freq * 4).clip(300, 8000)
        ) * (1 - hollow).linexp(0, 1, 0.2, 0.05) * envAmp;  // airy breath layer

        exciter = exciter + (hollowNoise * 1.5) + (airLayer * 2.0);

        // ═══ RESONATOR (dual Klank for body) ═══

        resMod = resFreq * (1 + lfo1 + lfo2);
        brightMod = resBright + (lfo1 * 0.2);

        // FIX: Better low-end handling - reduce sub-bass rumble
        // When hollow: fewer, cleaner partials. When stiff: more complex.
        resonated = Klank.ar(
            `[
                [1, 2.01, 3.98, 5.03, 7.1] * resMod.clip(100, 8000),  // raised floor to 100Hz
                [1, 0.7, 0.5, 0.3, 0.2] * brightMod.clip(0.1, 1) * (0.7 + (hollow * 0.3)),
                [1, 0.8, 0.6, 0.4, 0.3] * resDecay
            ],
            exciter,
            freqscale: 1,
            freqoffset: 0,
            decayscale: resRatio.linlin(0, 1, 0.5, 2.0)
        );

        resonated = resonated + Klank.ar(
            `[
                [1, 2.03, 4.02, 5.01, 7.2] * resMod.clip(100, 8000),
                [1, 0.65, 0.48, 0.28, 0.18] * brightMod.clip(0.1, 1) * (0.7 + (hollow * 0.3)),
                [1, 0.85, 0.65, 0.42, 0.32] * resDecay
            ],
            exciter * 0.9,
            freqscale: 1,
            freqoffset: 0,
            decayscale: resRatio.linlin(0, 1, 0.5, 2.0)
        );

        // ═══ PRESSURE / OPENING (tone evolution) ═══

        resonated = RLPF.ar(
            resonated,
            (freq * (3 + (resOpening * 8))).clip(150, 12000) * (1 + (pressure * 2)),
            0.3 + (pressure * 0.4)
        );

        resonated = (resonated * (1 + (pressure * hollow * 1.2))).tanh * 0.5;

        // High-pass to clean up subsonic mud
        resonated = HPF.ar(resonated, 40);

        // ═══ OUTPUT ═══

        sig = resonated * envAmp * amp;
        sig = Pan2.ar(sig, pan + (lfo2 * 0.2));

        // Send to global FX
        Out.ar(~reverbBus, sig * reverbSend);
        Out.ar(~delayBus, sig * delaySend);
        Out.ar(out, sig);
    }).add;


    SynthDef(\bowedDrone, {
        |out=0, gate=1, freq=110, amp=0.2,
        pressure=0.5, air=0.3, space=0.3, hollow=0.5, pan=0|

        var src, body, noise, filt, sat, envAmp, envTone, sig;
        var breathMod, pressureMod;
        var airLayer, hollowRes;

        // Long evolving envelope
        envAmp = EnvGen.kr(Env.asr(0.8, 1, 2.5), gate, doneAction:2);
        envTone = EnvGen.kr(Env([0.2, 1, 0.6], [1.2, 4.0], [\lin, \exp]), gate);

        // Breathing modulation
        breathMod = LFNoise1.kr(0.3 + (air * 2)).bipolar(0.02);
        pressureMod = pressure.linlin(0, 1, 0.5, 1.5);

        // Core oscillators: detuned saws for beating
        src = Mix.ar([
            Saw.ar(freq * (1 + breathMod)),
            Saw.ar(freq * (1.003 + (breathMod * 0.7))),
            Saw.ar(freq * (0.997 - (breathMod * 0.5)))
        ]) * 0.4;

        // Subharmonic support
        body = Pulse.ar(freq / 2, 0.3 + (pressure * 0.3)) * 0.3;

        // Air/breath layer
        noise = LPF.ar(
            PinkNoise.ar(),
            freq * (2 + (air * 8))
        ) * air * 0.5;  // increased from 0.35

        // Hollow resonance - airy body
        hollowRes = BPF.ar(
            WhiteNoise.ar(),
            freq * (1 + (LFNoise1.kr(0.5).bipolar(0.02))),
            1.0 + (hollow * 1.5)  // wider when stiff
        ) * (1 - hollow).linexp(0, 1, 0.1, 0.7) * envAmp;  // much more prominent when hollow

        src = src + body + noise + hollowRes;

        // Resonant filter opens with pressure & time
        filt = RLPF.ar(
            src,
            (freq * (1.5 + (pressureMod * 4)) * envTone).clip(100, 12000),
            0.25 + (pressure * 0.3)
        );

        // High-pass for clarity
        filt = HPF.ar(filt, 40);

        // Saturation that intensifies with pressure (only when stiff)
        sat = (filt * (1 + (pressure * hollow * 3))).tanh * 0.5;

        sig = sat * envAmp * amp;
        sig = Pan2.ar(sig, pan + (LFNoise1.kr(0.2).bipolar(0.2)));

        // Heavy space send for drones
        Out.ar(~reverbBus, sig * space);
        Out.ar(~delayBus, sig * (space * 0.5));
        Out.ar(out, sig);
    }).add;


    SynthDef(\metalHitPlayer, {
        |out=0, buf=(-1), gate=1, amp=0.5,
        rate=1.0, start=0, pressure=0.3,
        cutoff=8000, resonance=0.3,
        pan=0, reverbSend=0.5, delaySend=0.2|

        var sig, filt, envAmp, envTone;
        var sampleSig, synthSig, noise, body, useSample;

        envAmp = EnvGen.kr(Env.asr(0.001, 1, 0.8), gate, doneAction:2);
        envTone = EnvGen.kr(Env.perc(0.01, 1.5), gate);

        // Generate both signals, then select
        sampleSig = PlayBuf.ar(1, buf.max(0), rate * BufRateScale.kr(buf.max(0)), gate, start * BufFrames.kr(buf.max(0)), loop:0);

        noise = WhiteNoise.ar() * EnvGen.kr(Env.perc(0.001, 0.05));
        body = Klank.ar(
            `[
                [1, 2.4, 3.7, 5.2, 7.8, 11.3] * (200 * rate),  // metallic ratios
                [1, 0.6, 0.4, 0.3, 0.2, 0.15],
                [0.8, 0.6, 0.5, 0.4, 0.3, 0.2]
            ],
            noise
        ) * 0.7;
        synthSig = body;

        // Select which to use (buf < 0 means use synth)
        useSample = (buf >= 0);
        sig = Select.ar(useSample, [synthSig, sampleSig]);

        // Tonal evolution: filter opens with envelope
        filt = RLPF.ar(
            sig,
            cutoff.linexp(0.1, 1, 300, 12000) * (0.5 + (envTone * 1.5)),
            resonance.linlin(0, 1, 0.9, 0.1)
        );

        // High-pass for clarity
        filt = HPF.ar(filt, 60);

        // Pressure adds grit
        filt = (filt * (1 + (pressure * 3))).tanh;

        sig = filt * envAmp * amp;
        sig = Pan2.ar(sig, pan);

        Out.ar(~reverbBus, sig * reverbSend);
        Out.ar(~delayBus, sig * delaySend);
        Out.ar(out, sig);
    }).add;


    SynthDef(\grainTexture, {
        |out=0, gate=1, buf=(-1), amp=0.3,
        density=10, speed=1.0, pitch=1.0,
        spray=0.1, pressure=0.5, pan=0,
        cutoff=4000, space=0.4|

        var sig, filt, envAmp;
        var sampleSig, synthSig, useSample;
        var trate, dur, clk, pos;
        var grains;

        envAmp = EnvGen.kr(Env.asr(0.3, 1, 1.5), gate, doneAction:2);

        // Sample-based granular
        trate = density.linexp(0.01, 1, 2, 80) * (1 + (pressure * 2));
        dur = 0.08 / (density.linexp(0.01, 1, 0.1, 20) + 1);
        clk = Impulse.kr(trate);
        pos = Phasor.kr(clk, speed * BufRateScale.kr(buf.max(0)), 0, BufFrames.kr(buf.max(0)));
        pos = pos + LFNoise1.kr(2).bipolar(spray * BufFrames.kr(buf.max(0)) * 0.3);

        sampleSig = GrainBuf.ar(
            2,
            clk,
            dur,
            buf.max(0),
            pitch,
            pos / BufFrames.kr(buf.max(0)),
            2,
            pan + LFNoise1.kr(0.5).bipolar(0.4)
        );

        // Synthesized granular texture
        grains = Mix.fill(8, { |i|
            var env, osc;
            env = EnvGen.ar(
                Env.sine(dur),
                Dust.ar(trate + (i * 3))
            );
            osc = SinOsc.ar(
                TRand.ar(200, 3000, env) * pitch,
                Rand(0, 2pi)
            );
            Pan2.ar(osc * env, TRand.ar(-0.8, 0.8, env));
        }) * 0.15;
        synthSig = grains;

        // Select which to use
        useSample = (buf >= 0);
        sig = Select.ar(useSample, [synthSig, sampleSig]);

        // Filter softens harsh grains
        filt = BLowPass4.ar(sig, cutoff * (1 + (pressure * 2)).clip(100, 18000), 0.5);

        sig = filt * envAmp * amp * 0.7;

        Out.ar(~reverbBus, sig * space);
        Out.ar(out, sig);
    }).add;


    // ─────────────────────────────────────────────────────────────────────
    // 4. GLOBAL FX
    // ─────────────────────────────────────────────────────────────────────

    SynthDef(\globalReverb, {
        |in=0, out=0, mix=0.4, room=0.8, damp=0.6|
        var sig = In.ar(in, 2);
        var verb;

        verb = FreeVerb2.ar(sig[0], sig[1], mix, room, damp);

        // Subtle HP to prevent mud
        verb = HPF.ar(verb, 80);

        Out.ar(out, verb);
    }).add;


    SynthDef(\globalDelay, {
        |in=0, out=0, time=0.375, feedback=0.4, mix=0.3|
        var sig = In.ar(in, 2);
        var del;

        // Stereo ping-pong delay
        del = sig + LocalIn.ar(2);
        del = DelayC.ar(del, 2.0, [time, time * 1.03]);
        del = LPF.ar(del, 6000); // darken repeats
        del = del * feedback.clip(0, 0.75); // safety limit
        LocalOut.ar(del);

        Out.ar(out, sig + (del * mix));
    }).add;


    SynthDef(\droneGate, {
        |in=0, out=0, amp=0.5|
        var sig = In.ar(in, 2);
        Out.ar(out, sig * amp);
    }).add;


    "✓ SynthDefs compiled".postln;

    s.sync;

    // ─────────────────────────────────────────────────────────────────────
    // 5. LOAD SAMPLE BUFFERS (OPTIONAL)
    // ─────────────────────────────────────────────────────────────────────

    ~buffers = Dictionary.new;

    // Example paths — adjust to your sample library
    samplePath = PathName(thisProcess.nowExecutingPath).parentPath +/+ "samples/";

    if(PathName(samplePath).isFolder, {
        // Load all samples in folder
        PathName(samplePath).entries.do({ |path|
            if(path.extension.asSymbol == 'wav' or: { path.extension.asSymbol == 'aif' }, {
                ~buffers[path.fileNameWithoutExtension.asSymbol] = Buffer.read(s, path.fullPath);
                ("  Loading: " ++ path.fileName).postln;
            });
        });
        ("✓ Loaded " ++ ~buffers.size ++ " samples").postln;
    }, {
        "⚠ Sample folder not found - synths will use synthesis mode".postln;
    });

    s.sync;

    // ─────────────────────────────────────────────────────────────────────
    // 6. SPAWN GLOBAL FX
    // ─────────────────────────────────────────────────────────────────────

    ~reverbNode = Synth(\globalReverb, [
        \in, ~reverbBus,
        \out, 0,
        \mix, 0.4,
        \room, 0.85,
        \damp, 0.6
    ], addAction:\addToTail);

    ~delayNode = Synth(\globalDelay, [
        \in, ~delayBus,
        \out, 0,
        \time, 0.375,
        \feedback, 0.35,
        \mix, 0.25
    ], addAction:\addToTail);

    ~droneGate = Synth(\droneGate, [
        \in, ~droneBus,
        \out, 0,
        \amp, 0.6
    ], addAction:\addToTail);

    "✓ Global FX running".postln;

    s.sync;

    // ─────────────────────────────────────────────────────────────────────
    // 7. POLYPHONIC VOICE MANAGER
    // ─────────────────────────────────────────────────────────────────────

    ~voices = Dictionary.new;  // track active notes
    ~currentSynth = \physicalBody;  // which synth to play

    // Unified note-on handler (works with any synth)
    ~noteOn = { |nn, vel=100|
        var freq = nn.midicps;
        var amp = vel.linlin(0, 127, 0.1, 0.6);
        var pressure = ~pressureBus.getSynchronous;
        var air = ~airBus.getSynchronous;
        var hollow = ~hollowBus.getSynchronous;
        var space = ~spaceBus.getSynchronous;
        var voice;

        // Free old voice if note is retriggered
        if(~voices[nn].notNil, {
            ~voices[nn].release;
        });

        // Spawn new voice based on current synth
        voice = Synth(~currentSynth, [
            \freq, freq,
            \amp, amp,
            \pressure, pressure,
            \air, air,
            \hollow, hollow,
            \space, space,
            // Physical body specific
            \malletVol, 0.5,
            \noiseVol, 0.5,
            \stiffness, 0.46,
            \resDecay, 2.2,
            \reverbSend, 0.3,
            \delaySend, 0.1,
            // If using drone bus
            \out, if(~currentSynth == \bowedDrone, ~droneBus, 0)
        ]);

        ~voices[nn] = voice;
    };

    // Note-off handler
    ~noteOff = { |nn|
        if(~voices[nn].notNil, {
            ~voices[nn].release;
            ~voices[nn] = nil;
        });
    };

    // Switch active synth
    ~setSynth = { |synthName|
        ~currentSynth = synthName;
        ("► Active synth: " ++ synthName).postln;
    };

    "✓ Voice manager ready".postln;

    // ─────────────────────────────────────────────────────────────────────
    // 8. PERFORMANCE HELPERS
    // ─────────────────────────────────────────────────────────────────────

    // Quick play functions (legacy support)
    ~playPhysical = { |freq=440, vel=100|
        ~setSynth.(\physicalBody);
        ~noteOn.(freq.cpsmidi.round, vel);
    };

    ~playDrone = { |freq=110|
        ~setSynth.(\bowedDrone);
        ~noteOn.(freq.cpsmidi.round, 80);
    };

    // Trigger metal sample OR synthesis
    ~triggerMetal = { |bufKey=nil, rate=1.0, pressure=0.5|
        var buf = if(bufKey.notNil and: { ~buffers[bufKey].notNil }, {
            ~buffers[bufKey].bufnum;
        }, {
            -1;  // use synthesis mode
        });

        Synth(\metalHitPlayer, [
            \buf, buf,
            \rate, rate,
            \pressure, pressure,
            \cutoff, 8000,
            \resonance, 0.3,
            \reverbSend, 0.6,
            \delaySend, 0.3,
            \amp, 0.5
        ]);
    };

    // Trigger grain texture OR synthesis
    ~triggerGrain = { |bufKey=nil, density=0.5, pressure=0.5|
        var buf = if(bufKey.notNil and: { ~buffers[bufKey].notNil }, {
            ~buffers[bufKey].bufnum;
        }, {
            -1;  // use synthesis mode
        });

        Synth(\grainTexture, [
            \buf, buf,
            \density, density,
            \pressure, pressure,
            \cutoff, 4000,
            \space, 0.4,
            \amp, 0.4
        ]);
    };

    "✓ Performance helpers ready".postln;

    // ─────────────────────────────────────────────────────────────────────
    // 9. MIDI SETUP
    // ─────────────────────────────────────────────────────────────────────

    MIDIClient.init;
    MIDIIn.connectAll;

    // Note On - uses active synth
    MIDIdef.noteOn(\noteHandler, { |vel, nn, chan, src|
        ~noteOn.(nn, vel);
    });

    // Note Off
    MIDIdef.noteOff(\noteOffHandler, { |vel, nn, chan, src|
        ~noteOff.(nn);
    });

    // CC 1 (mod wheel) -> pressure
    MIDIdef.cc(\ccPressure, { |val|
        ~pressureBus.set(val.linlin(0, 127, 0, 1));
    }, 1);

    // CC 74 -> air/breath
    MIDIdef.cc(\ccAir, { |val|
        ~airBus.set(val.linlin(0, 127, 0, 1));
    }, 2);

    // CC 71 -> hollow (0) to stiff (1)
    MIDIdef.cc(\ccHollow, { |val|
        ~hollowBus.set(val.linlin(0, 127, 0, 1));
    }, 3);

    // CC 91 -> reverb send
    MIDIdef.cc(\ccSpace, { |val|
        ~reverbNode.set(\mix, val.linlin(0, 127, 0, 0.7));
    }, 4);

    // CC 93 -> delay feedback
    MIDIdef.cc(\ccDelayFB, { |val|
        ~delayNode.set(\feedback, val.linlin(0, 127, 0, 0.65));
    }, 5);

    "✓ MIDI connected".postln;

    // ─────────────────────────────────────────────────────────────────────
    // 10. STATUS REPORT
    // ─────────────────────────────────────────────────────────────────────

    "\n═══════════════════════════════════════════════════════════════".postln;
    "    INSTRUMENT READY".postln;
    "═══════════════════════════════════════════════════════════════".postln;
    ("    Buffers loaded: " ++ ~buffers.size).postln;
    ("    CPU idle: " ++ s.avgCPU.round(0.1) ++ "%").postln;
    ("    Peak CPU: " ++ s.peakCPU.round(0.1) ++ "%").postln;
    "───────────────────────────────────────────────────────────────".postln;
    "    Synth modes (use ~setSynth):".postln;
    "      ~setSynth.(\\physicalBody)  // default mallet/noise".postln;
    "      ~setSynth.(\\bowedDrone)    // sustained pressure".postln;
    "───────────────────────────────────────────────────────────────".postln;
    "    Quick test commands:".postln;
    "      ~noteOn.(60, 100)           // play middle C".postln;
    "      ~triggerMetal.(rate: 1.2)   // synth metal hit".postln;
    "      ~triggerGrain.(density: 0.7) // synth grain cloud".postln;
    "───────────────────────────────────────────────────────────────".postln;
    "    MIDI CCs mapped:".postln;
    "      CC1  → Pressure  |  CC71 → Hollow/Stiff".postln;
    "      CC74 → Air       |  CC91 → Reverb".postln;
    "      CC93 → Delay Feedback".postln;
    "═══════════════════════════════════════════════════════════════".postln;
});
)