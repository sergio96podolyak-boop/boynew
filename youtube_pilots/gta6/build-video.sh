#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
ASSET_DIR="$BASE_DIR/assets"
OUTPUT="$BASE_DIR/gta6-no-disc-short-en.mp4"
FONT="/System/Library/Fonts/Supplemental/Arial Bold.ttf"

python3 "$BASE_DIR/render-overlays.py"

ffmpeg -y \
  -loop 1 -t 5.10 -i "$ASSET_DIR/scene-01-empty-case.png" \
  -loop 1 -t 5.10 -i "$ASSET_DIR/scene-02-code-card.png" \
  -loop 1 -t 5.10 -i "$ASSET_DIR/scene-03-neon-city.png" \
  -loop 1 -t 5.10 -i "$ASSET_DIR/scene-04-countdown.png" \
  -loop 1 -t 19.50 -i "$BASE_DIR/overlays/overlay-01.png" \
  -loop 1 -t 19.50 -i "$BASE_DIR/overlays/overlay-02.png" \
  -loop 1 -t 19.50 -i "$BASE_DIR/overlays/overlay-03.png" \
  -loop 1 -t 19.50 -i "$BASE_DIR/overlays/overlay-04.png" \
  -loop 1 -t 19.50 -i "$BASE_DIR/overlays/overlay-05.png" \
  -loop 1 -t 19.50 -i "$BASE_DIR/overlays/overlay-06.png" \
  -loop 1 -t 19.50 -i "$BASE_DIR/overlays/overlay-07.png" \
  -i "$BASE_DIR/narration.aiff" \
  -f lavfi -t 19.50 -i "sine=frequency=55:sample_rate=48000" \
  -f lavfi -t 19.50 -i "sine=frequency=110:sample_rate=48000" \
  -filter_complex "
    [0:v]scale=1200:2134:force_original_aspect_ratio=increase,crop=1200:2134,
      zoompan=z='min(zoom+0.00055,1.08)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':
      d=153:s=1080x1920:fps=30,setsar=1[v0];
    [1:v]scale=1200:2134:force_original_aspect_ratio=increase,crop=1200:2134,
      zoompan=z='min(zoom+0.00045,1.07)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':
      d=153:s=1080x1920:fps=30,setsar=1[v1];
    [2:v]scale=1200:2134:force_original_aspect_ratio=increase,crop=1200:2134,
      zoompan=z='min(zoom+0.00035,1.06)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':
      d=153:s=1080x1920:fps=30,setsar=1[v2];
    [3:v]scale=1200:2134:force_original_aspect_ratio=increase,crop=1200:2134,
      zoompan=z='min(zoom+0.00050,1.08)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':
      d=153:s=1080x1920:fps=30,setsar=1[v3];
    [v0][v1]xfade=transition=fade:duration=0.30:offset=4.80[x1];
    [x1][v2]xfade=transition=wipeleft:duration=0.30:offset=9.60[x2];
    [x2][v3]xfade=transition=fadeblack:duration=0.30:offset=14.40[x3];
    [x3]eq=saturation=1.08:contrast=1.04,
      drawbox=x=0:y=1886:w='1080*t/19.50':h=34:color=0xFF2FA7@1:t=fill[base];
    [base][4:v]overlay=0:0:enable='between(t,0,2.2)'[o1];
    [o1][5:v]overlay=0:0:enable='between(t,2.2,4.2)'[o2];
    [o2][6:v]overlay=0:0:enable='between(t,4.2,7.2)'[o3];
    [o3][7:v]overlay=0:0:enable='between(t,7.2,9.5)'[o4];
    [o4][8:v]overlay=0:0:enable='between(t,9.5,14.4)'[o5];
    [o5][9:v]overlay=0:0:enable='between(t,14.4,16.7)'[o6];
    [o6][10:v]overlay=0:0:enable='between(t,16.7,19.5)',format=yuv420p[vout];
    [11:a]aresample=48000,highpass=f=70,acompressor=threshold=-18dB:ratio=2.5:
      attack=8:release=80,volume=1.25[voice];
    [12:a]volume=0.024,tremolo=f=2:d=0.75,lowpass=f=180[bass];
    [13:a]volume=0.010,tremolo=f=4:d=0.60,lowpass=f=500[synth];
    [voice][bass][synth]amix=inputs=3:duration=longest:dropout_transition=1:normalize=0,
      alimiter=limit=0.92,afade=t=out:st=18.90:d=0.60[aout]
  " \
  -map "[vout]" -map "[aout]" \
  -t 19.50 \
  -c:v libx264 -preset medium -crf 18 -profile:v high -level 4.1 \
  -c:a aac -b:a 192k -ar 48000 \
  -movflags +faststart \
  "$OUTPUT"

ffprobe -v error \
  -show_entries format=duration,size:stream=codec_name,width,height,r_frame_rate \
  -of default=noprint_wrappers=1 \
  "$OUTPUT"
