#!/usr/bin/env bash
# Turn a screen/gameplay recording into the two files the README, itch.io page and
# forum posts need: an optimised looping GIF and a compressed MP4.
#
#   tools/media/make-demo.sh capture.mp4 --start 00:00:04 --duration 15 --speed 3
#
# Writes docs/media/demo.gif and docs/media/demo.mp4 (override with --out).
#
# The GIF is built with a two-pass palette (palettegen/paletteuse). A one-pass GIF
# is limited to a generic 256-colour palette and bands badly on gradients like the
# sky and road; generating a palette from the clip itself is the difference between
# "looks like a GIF" and "looks like the game".
set -euo pipefail

IN=""
START=""
DURATION=""
SPEED=1
WIDTH=640          # GIF width. GIF is a poor codec — small and short beats big.
MP4_WIDTH=1280
FPS=15
OUT="docs/media/demo"
KEEP_AUDIO=0

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'USAGE'

Options:
  --start <ts>      Start time into the recording (e.g. 00:00:04). Default: start.
  --duration <sec>  Seconds to take. Default: all of it.
  --speed <n>       Speed-up factor, e.g. 3 for editor build footage. Default: 1.
  --width <px>      GIF width. Default: 640.
  --mp4-width <px>  MP4 width. Default: 1280.
  --fps <n>         GIF frame rate. Default: 15.
  --out <path>      Output path without extension. Default: docs/media/demo.
  --audio           Keep audio in the MP4 (dropped by default).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --start)     START="$2"; shift 2 ;;
    --duration)  DURATION="$2"; shift 2 ;;
    --speed)     SPEED="$2"; shift 2 ;;
    --width)     WIDTH="$2"; shift 2 ;;
    --mp4-width) MP4_WIDTH="$2"; shift 2 ;;
    --fps)       FPS="$2"; shift 2 ;;
    --out)       OUT="$2"; shift 2 ;;
    --audio)     KEEP_AUDIO=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    -*)          echo "Unknown option: $1" >&2; usage; exit 1 ;;
    *)           IN="$1"; shift ;;
  esac
done

if [[ -z "$IN" ]]; then usage; exit 1; fi
if [[ ! -f "$IN" ]]; then echo "No such recording: $IN" >&2; exit 1; fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is not on PATH. Install it with:  winget install Gyan.FFmpeg" >&2
  echo "(then open a new shell so PATH is picked up)" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

# -ss before -i seeks fast (keyframe-accurate); -t caps the length.
TRIM=()
[[ -n "$START" ]]    && TRIM+=(-ss "$START")
[[ -n "$DURATION" ]] && TRIM+=(-t "$DURATION")

# setpts must come before fps, so frames are dropped AFTER the speed change.
SPEED_F=""
if [[ "$SPEED" != "1" ]]; then SPEED_F="setpts=PTS/${SPEED},"; fi

PALETTE="$(mktemp -t palette.XXXXXX).png"
cleanup() { rm -f "$PALETTE"; }
trap cleanup EXIT

echo "==> [1/3] Sampling a colour palette from the clip"
ffmpeg -hide_banner -loglevel error -y "${TRIM[@]}" -i "$IN" \
  -vf "${SPEED_F}fps=${FPS},scale=${WIDTH}:-1:flags=lanczos,palettegen=stats_mode=diff" \
  "$PALETTE"

echo "==> [2/3] Building ${OUT}.gif  (${WIDTH}px, ${FPS}fps)"
ffmpeg -hide_banner -loglevel error -y "${TRIM[@]}" -i "$IN" -i "$PALETTE" \
  -lavfi "${SPEED_F}fps=${FPS},scale=${WIDTH}:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" \
  "${OUT}.gif"

echo "==> [3/3] Building ${OUT}.mp4  (${MP4_WIDTH}px)"
AUDIO=(-an)
[[ "$KEEP_AUDIO" == "1" ]] && AUDIO=(-c:a aac -b:a 128k)
# -2 (not -1) on the height: H.264 needs even dimensions or the encode fails.
ffmpeg -hide_banner -loglevel error -y "${TRIM[@]}" -i "$IN" \
  -vf "${SPEED_F}scale=${MP4_WIDTH}:-2:flags=lanczos" \
  -c:v libx264 -preset slow -crf 23 -pix_fmt yuv420p -movflags +faststart \
  "${AUDIO[@]}" "${OUT}.mp4"

size_of() { du -k "$1" 2>/dev/null | cut -f1; }
GIF_KB=$(size_of "${OUT}.gif")
MP4_KB=$(size_of "${OUT}.mp4")

echo
printf '  %-24s %6s KB\n' "$(basename "${OUT}.gif")" "$GIF_KB"
printf '  %-24s %6s KB\n' "$(basename "${OUT}.mp4")" "$MP4_KB"
echo

if (( GIF_KB > 5120 )); then
  echo "!! The GIF is over 5 MB — GitHub and forums will load it slowly."
  echo "   Shorten it (--duration 12), or try --width 480 or --fps 12."
fi
