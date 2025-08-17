// Boot server and connect audio input
(
s.options.device_("Scarlett 18i8 USB");
//s.options.outDevice = "BlackHole 2ch";
s.options.numInputBusChannels = 8;
s.options.numOutputBusChannels = 10;
s.reboot;
)

{ Out.ar([2, 3], SinOsc.ar(440) * 0.05) }.play;

s.options.sampleRate = 48000

ServerOptions.devices;

(
SynthDef(\ruinerFinalBlend, {
    |in=0, out=2, amp=0.3, gain=5, crushSteps=32, glitchRate=30, dropoutChance=0.5, decayTime=0.03, mix=1.0|

    var input, boosted, clipped, crushed;
    var dropoutGate, smoothedGate;
    var dry, wet, output;

    // Input + distortion
    input = SoundIn.ar(in);
    boosted = input * gain;
    clipped = boosted.clip2(0.9);
    crushed = (clipped * crushSteps).round * (1 / crushSteps);

    // Dropout control
    dropoutGate = LFNoise0.kr(glitchRate).range(0, 1) > dropoutChance;
    smoothedGate = Lag.kr(dropoutGate, decayTime);

    // Dry = always distorted, Wet = distorted + dropouts
    dry = crushed;
    wet = crushed * smoothedGate;

    // Blend between dry and wet
    output = XFade2.ar(dry, wet, (mix * 2) - 1);  // mix: 0 = dry, 1 = wet

    Out.ar(out, output * amp ! 2);
}).add;
)

x = Synth(\ruinerFinalBlend, [\in, 0]);
x.set(\mix, 0.0);  // 100% dry
x.set(\mix, 0.6);  // 50/50 blend
x.set(\mix, 1.0);  // 100% broken (default)
x.set(\dropoutChance, 0.4);
x.set(\decayTime, 0.06);
x.set(\glitchRate, 40);
x.set(\gain, 20);



SynthDef(\ruinerWithFeedback, {
		|in=0, out=3, amp=0.3, gain=5, crushSteps=32,
		glitchRate=30, dropoutChance=0.5, decayTime=0.03,
		mix=1.0, feedback=0|

		var input, boosted, clipped, crushed;
		var dropoutGate, smoothedGate;
		var dry, wet, blended;
		var fbIn, fbSig, finalOut;

		// Feedback input (safe loop)
		fbIn = LocalIn.ar(1);  // mono feedback

		// Input + optional feedback mix
		input = SoundIn.ar(in) + (fbIn * feedback);
		boosted = input * gain;
		clipped = boosted.clip2(0.9);
		crushed = (clipped * crushSteps).round * (1 / crushSteps);

		// Dropout control
		dropoutGate = LFNoise0.kr(glitchRate).range(0, 1) > dropoutChance;
		smoothedGate = Lag.kr(dropoutGate, decayTime);

		// Dry = always distorted, Wet = distorted + dropouts
		dry = crushed;
		wet = crushed * smoothedGate;
		blended = XFade2.ar(dry, wet, (mix * 2) - 1);

		// Send signal into feedback loop
		LocalOut.ar(blended);

		// Final output
		finalOut = blended * amp;
		Out.ar(out, finalOut ! 2);
	}).add;
x = Synth(\ruinerWithFeedback, [\in, 0]);
x.set(\feedback, 0.0);   // no feedback
x.set(\feedback, 0.2);   // subtle resonance
x.set(\feedback, 0.5);   // wild chaos
x.set(\mix, 0.8);        // mostly glitchy
x.set(\dropoutChance, 0.5);
x.set(\glitchRate, 40);
x.set(\decayTime, 0.04);




(
~ruinerGui = Window("Ruiner Pedal", Rect(100, 100, 320, 300));
~ruinerGui.layout = VLayout.new;

~makeSlider = { |label, param, min=0, max=1, init=0.5|
    var row, labelText, slider;

    row = HLayout.new.spacing_(10);

    labelText = StaticText.new
        .string_(label)
        .align_(\left)
        .fixedWidth_(100);  // prevent shrinking

    slider = Slider.new
        .orientation_(\horizontal)
        .value_((init - min) / (max - min)) // normalized
        .action_({
            var actual = slider.value.linlin(0, 1, min, max);
            x.set(param, actual);
        });

    row.add(labelText);
    row.add(slider);
    ~ruinerGui.layout.add(row);
};

~makeSlider.("Gain", \gain, 0, 30, 5);
~makeSlider.("Glitch Mix", \mix, 0, 1, 1.0);
~makeSlider.("Drop Chance", \dropoutChance, 0, 1, 0.4);
~makeSlider.("Glitch Rate", \glitchRate, 1, 60, 30);
~makeSlider.("Decay Time", \decayTime, 0.001, 0.2, 0.03);
~makeSlider.("Feedback", \feedback, 0, 0.7, 0.2);

~ruinerGui.front;
)







~revBuf = Buffer.alloc(s, s.sampleRate * 2, 1);  // 2 seconds mono
(
SynthDef(\revPlayer, {
    |out=0, buf, amp=0.5, rate=(-1), revMix=0.5|

    var playhead, reversed;

    playhead = Phasor.ar(0, rate, 0, BufFrames.kr(buf));
    reversed = BufRd.ar(1, buf, playhead, loop: 1);

    Out.ar(out, reversed * amp * revMix ! 2);
}).add;
)

~play = Synth(\revPlayer, [\buf, ~revBuf, \revMix, 0.4]);


(
SynthDef(\ruinerMerged, {
    |in=0, out=0, buf, amp=1.0, gain=15, crushSteps=32,
     glitchRate=30, dropoutChance=0.5, decayTime=0.03,
     mix=1.0, reverseMix=0.4|

    var input, boosted, clipped, crushed;
    var dropoutGate, smoothedGate, glitchSig, dry, wet, mixed;
    var playhead, reversed, output;

    // --- Input + distortion ---
    input = SoundIn.ar(in);
    boosted = input * gain;
    clipped = boosted.clip2(0.9);
    crushed = (clipped * crushSteps).round * (1 / crushSteps);

    // --- Dropout gate logic ---
    dropoutGate = LFNoise0.kr(glitchRate).range(0, 1) > dropoutChance;
    smoothedGate = Lag.kr(dropoutGate, decayTime);

    dry = crushed;
    wet = crushed * smoothedGate;

    // Blend dry/wet (glitch mix)
    glitchSig = XFade2.ar(dry, wet, (mix * 2) - 1);

    // --- Record glitch signal into buffer ---
    RecordBuf.ar(glitchSig, buf, loop: 1);

    // --- Read buffer in reverse ---
    playhead = Phasor.ar(0, -1, 0, BufFrames.kr(buf));
    reversed = BufRd.ar(1, buf, playhead, loop: 1);

    // --- Final output: glitch + reversed echo ---
    output = glitchSig + (reversed * reverseMix);
    Out.ar(out, output * amp ! 2);
}).add;
)

x = Synth(\ruinerMerged, [\in, 0, \buf, ~revBuf]);
x.set(\mix, 1.0);             // 0 = clean fuzz, 1 = glitch-only
x.set(\reverseMix, 0.7);      // reverse layer loudness
x.set(\glitchRate, 25);       // how fast dropouts happen
x.set(\dropoutChance, 0.5);   // more dropouts = more broken
x.set(\decayTime, 0.03);      // smooth fadeout on cut
x.set(\gain, 20);             // input distortion
x.set(\crushSteps, 16);       // 8 = more crushed



// Route Input 1 (guitar) to Output 3 (channel 2)
(
{
    var input = SoundIn.ar(0); // Input 1 = Analogue 1
    Out.ar(2, input);          // Output 3 = Analogue 3
}.play;
)

{ Out.ar(2, SinOsc.ar(440, 0, 0.1)) }.play;

Server.default.options.device;
s.options.numInputBusChannels;
s.options.numOutputBusChannels; 