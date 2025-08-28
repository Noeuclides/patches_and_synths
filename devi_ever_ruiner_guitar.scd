// Initialize MIDI
MIDIClient.init;
MIDIIn.connectAll;

// Sound setup
(
s.options.device_("Scarlett 18i8 USB");
s.options.numInputBusChannels = 8;
s.options.numOutputBusChannels = 10;
s.reboot;
)
(
SynthDef(\ruinerWithFeedback, {
    |in=0, out=3, amp=0.5, gain=2, crushSteps=8, glitchRate=10,
     dropoutChance=0.3, decayTime=0.08, mix=0.5, feedback=0.0,
     tone=0.7, saturation=0.3|
    var input, preamp, saturated, filtered, crushed;
    var dropoutGate, smoothedGate;
    var dry, wet, blended;
    var fbIn, finalOut;
    var inputLevel, compressedInput;

    // Feedback input (safe loop)
    fbIn = LocalIn.ar(1);

    // Input processing with dynamics preservation
    input = SoundIn.ar(in) + (fbIn * feedback);

    // Gentle input level detection for dynamics
    inputLevel = Amplitude.kr(input, 0.01, 0.1);

    // Soft compression to preserve some dynamics
    compressedInput = Compander.ar(input, input,
        thresh: 0.3,
        slopeBelow: 1.0,
        slopeAbove: 0.4,
        clampTime: 0.002,
        relaxTime: 0.05
    );

    // Analog-style preamp with softer saturation
    preamp = compressedInput * gain;
    saturated = (preamp * (1 + saturation)).tanh / (1 + saturation);

    // Tone control (low-pass filtering)
    filtered = LPF.ar(saturated, tone.linexp(0, 1, 800, 12000));

    // Gentler bit crushing with variable steps
    crushed = (filtered * crushSteps).round / crushSteps;

    // More musical dropout with smoother transitions
    dropoutGate = LFNoise1.kr(glitchRate).range(0, 1) > dropoutChance;
    smoothedGate = Lag.kr(dropoutGate, decayTime);

    // Preserve original dynamics in dry signal
    dry = LeakDC.ar(filtered * (0.3 + (inputLevel * 0.7)));
    wet = LeakDC.ar(crushed * smoothedGate);

    // Crossfade with softer curve
    blended = (dry * (1 - mix)) + (wet * mix);

    // Send to feedback with limiting
    LocalOut.ar(blended.tanh * 0.8);

    // Final output with gentle limiting
    finalOut = blended * amp;
    finalOut = finalOut.tanh; // soft limiting

    Out.ar(out, finalOut ! 2);
}).add;
)

x = Synth(\ruinerWithFeedback, [\in, 0]);

// Enhanced GUI with MIDI control
(
~ruinerGui = Window("Ruiner Pedal", Rect(100, 100, 400, 350));
~ruinerGui.layout = VLayout.new;

// Store slider references for MIDI control
~sliders = IdentityDictionary.new;

// Parameter configurations: [label, param, min, max, init]
~params = [
    ["Gain", \gain, 0, 30, 5],
    ["Glitch Mix", \mix, 0, 1, 1.0],
    ["Drop Chance", \dropoutChance, 0, 1, 0.4],
    ["Glitch Rate", \glitchRate, 1, 60, 30],
    ["Decay Time", \decayTime, 0.001, 0.2, 0.03],
    ["Feedback", \feedback, 0, 0.7, 0.2]
];

~makeSlider = { |label, param, min=0, max=1, init=0.5|
    var row, labelText, slider, valueText;

    row = HLayout.new.spacing_(10);

    labelText = StaticText.new
        .string_(label)
        .align_(\left)
        .fixedWidth_(80);

    slider = Slider.new
        .orientation_(\horizontal)
        .value_((init - min) / (max - min)) // normalized
        .action_({
            var actual = slider.value.linlin(0, 1, min, max);
            x.set(param, actual);
            valueText.string_(actual.round(0.001).asString);
        });

    valueText = StaticText.new
        .string_(init.round(0.001).asString)
        .align_(\right)
        .fixedWidth_(60);

    // Store slider reference with CC number as key
    ~sliders[param] = [slider, min, max, valueText];

    row.add(labelText);
    row.add(slider);
    row.add(valueText);
    ~ruinerGui.layout.add(row);
};

// Create sliders
~params.do({ |paramConfig|
    ~makeSlider.(paramConfig[0], paramConfig[1], paramConfig[2], paramConfig[3], paramConfig[4]);
});

// Add MIDI status display
~ruinerGui.layout.add(nil); // spacer
~midiStatus = StaticText.new
    .string_("MIDI: Waiting for LPD8...")
    .align_(\center);
~ruinerGui.layout.add(~midiStatus);

~ruinerGui.front;

// MIDI Control Setup
~ccMap = IdentityDictionary[
    70 -> \gain,
    71 -> \mix,
    72 -> \dropoutChance,
    73 -> \glitchRate,
    74 -> \decayTime,
    75 -> \feedback
];

// MIDI CC responder
~midiCC = MIDIFunc.cc({ |val, cc, chan, src|
    var param, sliderData, slider, min, max, valueText;
    var normalizedVal, actualVal;

    if (~ccMap[cc].notNil) {
        param = ~ccMap[cc];
        sliderData = ~sliders[param];

        if (sliderData.notNil) {
            #slider, min, max, valueText = sliderData;

            // Convert MIDI value (0-127) to normalized slider value (0-1)
            normalizedVal = val / 127.0;

            // Convert to actual parameter value
            actualVal = normalizedVal.linlin(0, 1, min, max);

            // Update GUI
            {
                slider.value_(normalizedVal);
                valueText.string_(actualVal.round(0.001).asString);
                ~midiStatus.string_("MIDI: CC" ++ cc ++ " -> " ++ param ++ " = " ++ actualVal.round(0.01));
            }.defer;

            // Update synth
            x.set(param, actualVal);
        };
    };
});

// Cleanup function
~cleanup = {
    ~midiCC.free;
    ~ruinerGui.close;
    x.free;
};

~ruinerGui.onClose_({
    ~cleanup.();
});

"Ruiner Pedal with MIDI control ready!".postln;
"CC Mapping:".postln;
~ccMap.keysValuesDo({ |cc, param|
    ("CC" ++ cc ++ " -> " ++ param).postln;
});
)

