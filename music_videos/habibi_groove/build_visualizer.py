#!/usr/bin/env python3
"""Render the full 3:03 Habibi Groove official visualizer with FFmpeg."""

from __future__ import annotations

import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "sergio-habibi-groove-official-visualizer.mp4"
FPS = 30


SCENES = [
    ("scene-01-portal.png", 34, 0.00013, ""),
    ("scene-02-corridor.png", 32, 0.00015, ""),
    ("scene-03-drop.png", 31, 0.00017, "eq=saturation=1.10:contrast=1.04,"),
    ("scene-02-corridor.png", 18, 0.00012, "hue=h=8:s=1.06,"),
    ("scene-01-portal.png", 40, 0.00011, "hue=h=-7:s=1.04,"),
    ("scene-03-drop.png", 27, 0.00018, "eq=saturation=1.20:contrast=1.08,"),
    ("scene-04-finale.png", 7, 0.00008, "eq=saturation=0.90:brightness=-0.02,"),
]


def scene_filter(index: int, duration: int, zoom_step: float, look: str) -> str:
    drift_x = 8 + index * 2
    drift_y = 5 + index
    return (
        f"[{index}:v]"
        "scale=2304:1296:force_original_aspect_ratio=increase,"
        "crop=2304:1296,"
        f"{look}"
        f"zoompan=z='min(zoom+{zoom_step:.5f},1.095)':"
        f"x='iw/2-(iw/zoom/2)+{drift_x}*sin(on/{68 + index * 7})':"
        f"y='ih/2-(ih/zoom/2)+{drift_y}*cos(on/{83 + index * 5})':"
        f"d=1:s=1920x1080:fps={FPS},"
        f"trim=duration={duration},setpts=PTS-STARTPTS,"
        "vignette=PI/5,format=yuv420p"
        f"[v{index}]"
    )


def build_command() -> list[str]:
    command = ["ffmpeg", "-y", "-hide_banner"]
    for filename, duration, _, _ in SCENES:
        command.extend(
            [
                "-loop",
                "1",
                "-framerate",
                str(FPS),
                "-t",
                str(duration),
                "-i",
                str(ROOT / filename),
            ]
        )
    command.extend(["-i", str(ROOT / "habibi-groove.mp3")])
    command.extend(
        [
            "-loop",
            "1",
            "-framerate",
            str(FPS),
            "-t",
            "8",
            "-i",
            str(ROOT / "title-card.png"),
        ]
    )
    command.extend(
        [
            "-loop",
            "1",
            "-framerate",
            str(FPS),
            "-t",
            "7",
            "-i",
            str(ROOT / "outro-card.png"),
        ]
    )
    command.extend(
        [
            "-loop",
            "1",
            "-framerate",
            str(FPS),
            "-t",
            "183",
            "-i",
            str(ROOT / "corner-bug.png"),
        ]
    )

    filters = [
        scene_filter(index, duration, zoom, look)
        for index, (_, duration, zoom, look) in enumerate(SCENES)
    ]
    filters.extend(
        [
            "[v0][v1]xfade=transition=fade:duration=1:offset=33[x1]",
            "[x1][v2]xfade=transition=fade:duration=1:offset=64[x2]",
            "[x2][v3]xfade=transition=fade:duration=1:offset=94[x3]",
            "[x3][v4]xfade=transition=fade:duration=1:offset=111[x4]",
            "[x4][v5]xfade=transition=fade:duration=1:offset=150[x5]",
            "[x5][v6]xfade=transition=fade:duration=1:offset=176[base]",
            "[7:a]asplit=2[master][react]",
            "[master]volume=-1.5dB,aresample=48000,atrim=duration=183[aout]",
            "[react]showwaves=s=1720x120:mode=cline:rate=30:"
            "colors=0x4C8CFF|0xA05CFF,"
            "format=rgba,colorkey=0x000000:0.10:0.08[wave]",
            "[base][wave]overlay=x=(W-w)/2:y=H-h-34:"
            "eof_action=pass:shortest=0[withwave]",
            "[10:v]format=rgba,colorchannelmixer=aa=0.72[bug]",
            "[withwave][bug]overlay=x=50:y=30:eof_action=pass[withbug]",
            "[8:v]format=rgba,"
            "fade=t=in:st=0:d=1:alpha=1,"
            "fade=t=out:st=6.5:d=1.5:alpha=1[title]",
            "[withbug][title]overlay=0:0:eof_action=pass:"
            "enable='between(t,0,8)'[withtitle]",
            "[9:v]format=rgba,"
            "fade=t=in:st=0:d=1:alpha=1,"
            "fade=t=out:st=5.8:d=1.2:alpha=1,"
            "setpts=PTS-STARTPTS+176/TB[outro]",
            "[withtitle][outro]overlay=0:0:eof_action=pass:"
            "enable='between(t,176,183)'[withoutro]",
            "[withoutro]drawbox=x=0:y=1076:w='iw*t/183':h=4:"
            "color=0xD9A650@0.90:t=fill,format=yuv420p[vout]",
        ]
    )
    command.extend(
        [
            "-filter_complex",
            ";".join(filters),
            "-map",
            "[vout]",
            "-map",
            "[aout]",
            "-t",
            "183",
            "-r",
            str(FPS),
            "-c:v",
            "libx264",
            "-preset",
            "fast",
            "-crf",
            "18",
            "-profile:v",
            "high",
            "-level",
            "4.2",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-b:a",
            "320k",
            "-ar",
            "48000",
            "-movflags",
            "+faststart",
            str(OUTPUT),
        ]
    )
    return command


def main() -> None:
    command = build_command()
    print("Rendering:", OUTPUT)
    subprocess.run(command, check=True)
    print("Finished:", OUTPUT)


if __name__ == "__main__":
    main()
