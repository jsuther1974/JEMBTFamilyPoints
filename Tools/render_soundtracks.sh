#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUDIO_DIR="$ROOT/JEMBT Family Points Tracker/Audio"

cd "$ROOT"
xcrun swift Tools/render_soundtracks.swift

for wav in "$AUDIO_DIR"/*.wav; do
    m4a="${wav%.wav}.m4a"
    afconvert "$wav" "$m4a" -f m4af -d aac -b 112000
    rm "$wav"
done

echo "Rendered app soundtracks in $AUDIO_DIR"
