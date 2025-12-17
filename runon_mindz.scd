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
    ~spaceBus = Bus.control(s, 1).set(0.3);
    ~grainDensityBus = Bus.control(s, 1).set(10);

    "✓ Global buses created".postln;

    s.sync;

    // ─────────────────────────────────────────────────────────────────────
    // 3. SYNTHDEFS — PHYSICAL MODELING CORE
    // ─────────────────────────────────────────────────────────────────────

    SynthDef(\physicalBody, {
        |out=0, gate=1, freq=110, amp=0.3,
        // Exciter params
        malletVol=0.5, noiseVol=0.5, stiffness=0.5, noiseColor=0.5, exciterColor=0.35,
        // Resonator params
        resFreq=440, resDecay=2.0, resBright=0.4, resOpening=0.0, resRatio=0.5,
        // Movement
        lfo1rate=0.5, lfo1amt=0.5, lfo2rate=0.3, lfo2amt=0.96,
        // Output
        pressure=0.5, pan=0, reverbSend=0.3, delaySend=0.1,air=0.3, hollow=0.5|

        var exciter, mallet, noise, resonated, sig;
        var envAmp, envExcite, lfo1, lfo2;
        var resMod, brightMod;
        var base, freqs1, freqs2;

        // ═══ ENVELOPES ═══
        envAmp = EnvGen.kr(Env.asr(0.005, 1, 1.2), gate, doneAction:2);
        // Sharp attack for exciter, dies down
        envExcite = EnvGen.kr(Env.perc(0.001, 0.08 * stiffness.linexp(0,1,0.5,3.0)), gate);

        // ═══ MODULATION ═══
        lfo1 = SinOsc.kr(lfo1rate).bipolar(lfo1amt);
        lfo2 = LFNoise1.kr(lfo2rate).bipolar(lfo2amt * 0.15);

        // ═══ EXCITER SOURCES ═══

        // Mallet: percussive harmonic burst
        mallet = Pulse.ar(
            freq * (1 + (exciterColor * 2)),
            0.2 + (stiffness * 0.6)
        ) * envExcite * malletVol;

        // Noise: bow scrape / breath attack
        noise = BPF.ar(
            WhiteNoise.ar(),
            noiseColor.linexp(0, 1, 800, 12000),
            0.6
        ) * envExcite * noiseVol * (0.4 + (air * 0.8));

        // Blend mallet -> noise by hollow (0=solid, 1=hollow/air)
        exciter = XFade2.ar(mallet, noise, (hollow * 2) - 1);

        // ═══ RESONATOR (dual Klank for body) ═══

        resMod = resFreq;// * (1 + lfo1 + lfo2);
        brightMod = resBright + (lfo1 * 0.0);

        base = resFreq.max(60); // allow low notes to track, but avoid 0/denormals
        freqs1 = ([1, 2.01, 3.98, 5.03, 7.1] * base).clip(60, 12000);
        freqs2 = ([1, 2.03, 4.02, 5.01, 7.2] * base).clip(60, 12000);

        brightMod = resBright.clip(0.1, 1);

        // Two parallel resonator banks for stereo depth
        resonated = Klank.ar(
            `[
                freqs1,
                [1, 0.7, 0.5, 0.3, 0.2] * brightMod,
                [1, 0.8, 0.6, 0.4, 0.3] * resDecay
            ],
            exciter,
            decayscale: resRatio.linlin(0, 1, 0.5, 2.0)
        );

        resonated = resonated + Klank.ar(
            `[
                freqs2,
                [1, 0.65, 0.48, 0.28, 0.18] * brightMod,
                [1, 0.85, 0.65, 0.42, 0.32] * resDecay
            ],
            exciter * 0.9,
            decayscale: resRatio.linlin(0, 1, 0.5, 2.0)
        );

        // cleanup + keep it clear
        resonated = LeakDC.ar(resonated);
        resonated = HPF.ar(resonated, 30);

        // keep “pressure” as tone opening, but avoid hard distortion
        resonated = resonated * (1 + (pressure * 1.2));
        resonated = Limiter.ar(resonated, 0.9, 0.01);

        resonated = BRF.ar(resonated, hollow.linexp(0, 1, 250, 900), 0.5); // scoops “box”
        resonated = resonated + (HPF.ar(resonated, 4000) * (hollow * 0.15)); // air sheen
        // ═══ PRESSURE / OPENING (tone evolution) ═══

        // As pressure rises: more harmonics, more dirt
        //resonated = RLPF.ar(
          //  resonated,
            //resOpening.linexp(0, 1, 300, 12000) * (1 + (pressure * 3)),
            //0.3 + (pressure * 0.4)
        //);

        // Subtle saturation that grows with pressure
        //resonated = (resonated * (1 + (pressure * 2))).tanh * 0.7;

        // ═══ OUTPUT ═══

        sig = resonated * envAmp * amp;
        sig = Pan2.ar(sig, pan + (lfo2 * 0.3));

        // Send to global FX
        Out.ar(~reverbBus, sig * reverbSend);
        Out.ar(~delayBus, sig * delaySend);
        Out.ar(out, sig);
    }).add;


    SynthDef(\bowedDrone, {
        |out=0, gate=1, freq=110, amp=0.2,
        pressure=0.5, air=0.3, space=0.3, pan=0|

        var src, body, noise, filt, sat, envAmp, envTone, sig;
        var breathMod, pressureMod;

        // Long evolving envelope
        envAmp = EnvGen.kr(Env.asr(0.8, 1, 2.5), gate, doneAction:2);
        envTone = EnvGen.kr(Env([0.2, 1, 0.6], [1.2, 4.0], [\lin, \exp]), gate);

        // Breathing modulation
        breathMod = LFNoise1.kr(0.3 + (air * 2)).bipolar(0.05);
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
            freq * (2 + (air * 6))
        ) * air * 0.15;

        src = src + body + noise;

        // Resonant filter opens with pressure & time
        filt = RLPF.ar(
            src,
            (freq * (1.5 + (pressureMod * 4)) * envTone).clip(80, 12000),
            0.25 + (pressure * 0.3)
        );

        // Saturation that intensifies with pressure (amp breathing)
        sat = (filt * (1 + (pressure * 5))).tanh * 0.6;

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
    // 5. LOAD SAMPLE BUFFERS
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
        "⚠ Sample folder not found at: ".post; samplePath.postln;
        "  Creating placeholder buffers...".postln;
        // Create silence buffers as placeholders
        ~buffers[\metal1] = Buffer.alloc(s, s.sampleRate * 0.5, 1);
        ~buffers[\breath1] = Buffer.alloc(s, s.sampleRate * 0.3, 1);
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
    // 7. PERFORMANCE HELPERS
    // ─────────────────────────────────────────────────────────────────────

    // Voice pool for polyphony
    ~voices = Dictionary.new;

    // Play physical modeling voice
    ~playPhysical = { |freq=440, vel=100, pressure=0.5|
        var amp = vel.linlin(0, 127, 0.1, 0.6);
        Synth(\physicalBody, [
            \freq, freq,
            \amp, amp,
            \pressure, pressure,
            \malletVol, 0.5,
            \noiseVol, 0.5,
            \stiffness, 0.46,
            \noiseColor, 0.52,
            \exciterColor, 0.35,
            \resFreq, freq,
            \resDecay, 2.2,
            \resBright, 0.43,
            \resOpening, 0.0,
            \resRatio, 0.49,
            \lfo1rate, 0.5,
            \lfo1amt, 0.5,
            \lfo2rate, 0.3,
            \lfo2amt, 0.96,
            \reverbSend, 0.3,
            \delaySend, 0.1
        ]);
    };

    // Play sustained drone
    ~playDrone = { |freq=110, pressure=0.5, air=0.3|
        Synth(\bowedDrone, [
            \out, ~droneBus,
            \freq, freq,
            \amp, 0.25,
            \pressure, pressure,
            \air, air,
            \space, 0.5
        ]);
    };

    ~triggerMetal = { |bufKey=\metal1, rate=1.0, pressure=0.3|
        Synth(\metalHitPlayer, [
            \rate, rate,
            \pressure, pressure,
            \cutoff, 8000,
            \resonance, 0.3,
            \reverbSend, 0.6,
            \delaySend, 0.3
        ]);
    };

    ~triggerGrain = { |bufKey=\metal1, rate=1.0, pressure=0.3|
        Synth(\grainTexture, [
            \rate, rate,
            \pressure, pressure,
            \cutoff, 8000,
            \resonance, 0.3,
            \reverbSend, 0.6,
            \delaySend, 0.3
        ]);
    };

    "✓ Performance helpers ready".postln;

    // ─────────────────────────────────────────────────────────────────────
    // 8. MIDI SETUP (basic - expand in separate file)
    // ─────────────────────────────────────────────────────────────────────

    MIDIClient.init;
    MIDIIn.connectAll;

    // Note On
    MIDIdef.noteOn(\noteHandler, { |vel, nn, chan, src|
        var freq = nn.midicps;
        var pressure = ~pressureBus.getSynchronous;
        ~playPhysical.(freq, vel, pressure);
    });

    // CC 1 (mod wheel) -> pressure
    MIDIdef.cc(\ccPressure, { |val|
        ~pressureBus.set(val.linlin(0, 127, 0, 1));
    }, 1);

    // CC 74 -> air/breath
    MIDIdef.cc(\ccAir, { |val|
        ~airBus.set(val.linlin(0, 127, 0, 1));
    }, 2);

    // CC 91 -> reverb send
    MIDIdef.cc(\ccSpace, { |val|
        ~reverbNode.set(\mix, val.linlin(0, 127, 0, 0.7));
    }, 3);

    "✓ MIDI connected (basic mappings active)".postln;

    // ─────────────────────────────────────────────────────────────────────
    // 9. STATUS REPORT
    // ─────────────────────────────────────────────────────────────────────

    "\n═══════════════════════════════════════════════════════════════".postln;
    "    INSTRUMENT READY".postln;
    "═══════════════════════════════════════════════════════════════".postln;
    ("    Buffers loaded: " ++ ~buffers.size).postln;
    ("    CPU idle: " ++ s.avgCPU.round(0.1) ++ "%").postln;
    ("    Peak CPU: " ++ s.peakCPU.round(0.1) ++ "%").postln;
    "───────────────────────────────────────────────────────────────".postln;
    "    Test commands:".postln;
    "    ~playPhysical.(440, 80)".postln;
    "    ~playDrone.(110, 0.6, 0.4)".postln;
    "    ~triggerMetal.(\\metal1, 1.0, 0.5)".postln;
    "═══════════════════════════════════════════════════════════════".postln;
});
)
