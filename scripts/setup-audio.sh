#!/bin/bash
# FXSound Audio Setup Script for PipeWire/PulseAudio

echo "🎧 FXSound Audio Setup"
echo "======================"
echo ""

# Check if PipeWire or PulseAudio is running
if pgrep -x pipewire > /dev/null; then
    echo "✓ PipeWire detected"
    AUDIO_SERVER="pipewire"
elif pgrep -x pulseaudio > /dev/null; then
    echo "✓ PulseAudio detected"
    AUDIO_SERVER="pulseaudio"
else
    echo "✗ No audio server detected"
    echo "Please start PipeWire or PulseAudio first"
    exit 1
fi

echo ""
echo "Setting up audio routing for FXSound..."
echo ""

# Keep the real hardware sink as FXSound's physical output.
# The FXSound virtual sink is the capture stage, so we must never create a
# monitor -> virtual loopback or the app will capture its own processed audio.
FXSOUND_SINK="fxsound_virtual"
DEFAULT_SINK=$(pactl get-default-sink)
if [ "$DEFAULT_SINK" = "$FXSOUND_SINK" ]; then
    DEFAULT_SINK=$(pactl list short sinks | awk -v v="$FXSOUND_SINK" '$2 != v {print $2; exit}')
fi
if [ -z "$DEFAULT_SINK" ]; then
    echo "✗ Could not find a physical output sink"
    exit 1
fi
echo "Physical audio output: $DEFAULT_SINK"

# Create the virtual capture sink only when it does not already exist.
FXSOUND_MODULE_ID=$(pactl list short modules | awk -v s="$FXSOUND_SINK" '$2 == "module-null-sink" && $3 ~ ("sink_name=" s) {print $1; exit}')
if [ -z "$FXSOUND_MODULE_ID" ]; then
    echo "Creating FXSound virtual sink..."
    FXSOUND_MODULE_ID=$(pactl load-module module-null-sink sink_name="$FXSOUND_SINK" sink_properties=device.description="FXSound-Virtual")
fi

# New applications send audio to the virtual sink; FXSound captures its monitor
# and sends the processed result to the physical sink above.
echo "Setting FXSound virtual sink as default..."
pactl set-default-sink "$FXSOUND_SINK"

# Move already-running playback streams into the virtual capture stage.
FXSOUND_SINK_ID=$(pactl list short sinks | awk -v s="$FXSOUND_SINK" '$2 == s {print $1; exit}')
while read -r INPUT_ID SINK_ID _; do
    [ -z "$INPUT_ID" ] && continue
    if [ "$SINK_ID" != "$FXSOUND_SINK_ID" ]; then
        pactl move-sink-input "$INPUT_ID" "$FXSOUND_SINK" 2>/dev/null || true
    fi
done < <(pactl list short sink-inputs)

echo ""
echo "✓ Audio routing ready: applications → FXSound → physical output"
echo ""
echo "Now run FXSound app. To restore the physical output:"
echo "  pactl set-default-sink $DEFAULT_SINK"
echo "  # Remove the FXSound virtual sink when no longer needed:"
echo "  pactl unload-module $FXSOUND_MODULE_ID"
