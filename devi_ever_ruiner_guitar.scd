// Initialize MIDI
(
MIDIClient.init;
MIDIIn.connectAll;
)

// Sound setup
(
s.options.device_("Scarlett 18i8 USB");
s.options.numInputBusChannels = 8;
s.options.numOutputBusChannels = 10;
s.reboot;
)

(
SynthDef(\ruinerWithFeedback, {
    |in=0, out=3, amp=0.5, glitchRate=10,
     dropoutChance=0.3, decayTime=0.08, mix=1, feedback=0.0|
    var input;
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

    // More musical dropout with smoother transitions
    dropoutGate = LFNoise1.kr(glitchRate).range(0, 1) > dropoutChance;
    smoothedGate = Lag.kr(dropoutGate, decayTime);

	dry = LeakDC.ar(input);
    wet = LeakDC.ar(input * smoothedGate);

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

// Enhanced GUI with MIDI control and bypass
(
~ruinerGui = Window("Ruiner Pedal", Rect(100, 100, 400, 450));
~ruinerGui.layout = VLayout.new;

// Store slider references for MIDI control
~sliders = IdentityDictionary.new;

// Store bypass state and last mix value
~bypassState = false;
~lastMixValue = 0.5;

// Parameter configurations: [label, param, min, max, init]
~params = [
    ["Drop Chance", \dropoutChance, 0, 1, 0.3],
    ["Glitch Rate", \glitchRate, 0.1, 30, 22],
    ["Decay Time", \decayTime, 0.01, 0.5, 0.18],
    ["Feedback", \feedback, 0, 2, 0.0]
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

            // Store mix value when changed
            if (param == \mix) {
                ~lastMixValue = actual;
            };
        });

    valueText = StaticText.new
        .string_(init.round(0.001).asString)
        .align_(\right)
        .fixedWidth_(60);

    // Store slider reference with param as key
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

// Add spacer
~ruinerGui.layout.add(nil);

// Bypass button
~bypassButton = Button.new
    .states_([["BYPASS", Color.red, Color.white], ["ACTIVE", Color.green, Color.white]])
    .value_(1) // start active
    .action_({ |button|
        ~bypassState = button.value == 0;
        if (~bypassState) {
            x.set(\mix, 0); // full dry signal
            ~statusText.string_("STATUS: BYPASSED (Press 'V' to toggle)");
            ~statusText.background_(Color.red(0.2));
        } {
            // restore last mix setting
            x.set(\mix, ~lastMixValue);
            ~statusText.string_("STATUS: ACTIVE (Press 'V' to toggle)");
            ~statusText.background_(Color.green(0.2));
        };
    });
~ruinerGui.layout.add(~bypassButton);

~statusText = StaticText.new
    .string_("STATUS: ACTIVE (Press 'V' to toggle)")
    .align_(\center)
    .background_(Color.green(0.2));
~ruinerGui.layout.add(~statusText);

// Add spacer
~ruinerGui.layout.add(nil);

~midiStatus = StaticText.new
    .string_("MIDI: Waiting for controller...")
    .align_(\center);
~ruinerGui.layout.add(~midiStatus);

~ruinerGui.front;

// Keyboard control for bypass (V key)
~ruinerGui.view.keyDownAction_({ |view, char, modifiers, unicode, keycode|
    if (char == $v or: { char == $V }) {
        ~bypassState = ~bypassState.not;
        ~bypassButton.value_(~bypassState.not.asInteger);

        if (~bypassState) {
            x.set(\mix, 0); // bypass - full dry
            ~statusText.string_("STATUS: BYPASSED (Press 'V' to toggle)");
            ~statusText.background_(Color.red(0.2));
        } {
            x.set(\mix, ~lastMixValue); // restore effect
            ~statusText.string_("STATUS: ACTIVE (Press 'V' to toggle)");
            ~statusText.background_(Color.green(0.2));
        };
    };
});

// Make sure window can receive key events
~ruinerGui.view.focus;

// MIDI Control Setup
~ccMap = IdentityDictionary[
    70 -> \dropoutChance,
    71 -> \glitchRate,
    72 -> \decayTime,
    73 -> \feedback
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
                if (~midiStatus.notNil) {
                    ~midiStatus.string_("MIDI: CC" ++ cc ++ " -> " ++ param ++ " = " ++ actualVal.round(0.01));
                };
            }.defer;

            // Update synth
            x.set(param, actualVal);

            // Store mix value when changed via MIDI
            if (param == \mix) {
                ~lastMixValue = actualVal;
            };
        };
    };
});

// Cleanup function
~cleanup = {
    if (~midiCC.notNil) { ~midiCC.free };
    if (~ruinerGui.notNil) { ~ruinerGui.close };
    if (x.notNil) { x.free };
};

~ruinerGui.onClose_({
    ~cleanup.();
});

"Ruiner Pedal with MIDI control and V-key bypass ready!".postln;
"CC Mapping:".postln;
~ccMap.keysValuesDo({ |cc, param|
    ("CC" ++ cc ++ " -> " ++ param).postln;
});
"Press 'V' key (with GUI focused) to bypass/activate".postln;
)