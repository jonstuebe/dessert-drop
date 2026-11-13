#!/usr/bin/env bash
# Record a 1080x1920 gameplay clip with sound for social posts.
#   tools/record_trailer.sh [out.mp4] [seconds] [seed] [shot]
# shot is "auto" or a scripted shot from record_trailer.gd (wedding).
# The drops and merges in the clip are listed in <out>.events.txt (frame, kind, tier).
# An out of "-" is a dry run: nothing is rendered, only the events are printed.
# Needs godot 4.7 and ffmpeg. The player's save file is backed up and restored.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/export/trailer.mp4}"
SECONDS_LEN="${2:-22}"
SEED="${3:-7}"
SHOT="${4:-auto}"
GODOT="${GODOT_BIN:-godot}"
WORK="$(mktemp -d)"
SAVE="$HOME/Library/Application Support/Godot/app_userdata/Dessert Drop/save.cfg"
[[ "$(uname -s)" == "Linux" ]] && SAVE="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Dessert Drop/save.cfg"

BACKUP=""
if [[ -f "$SAVE" ]]; then
	BACKUP="$WORK/save.cfg.bak"
	cp "$SAVE" "$BACKUP"
fi
restore() {
	if [[ -n "$BACKUP" ]]; then cp "$BACKUP" "$SAVE"; else rm -f "$SAVE"; fi
	rm -rf "$WORK"
}
trap restore EXIT

cd "$ROOT"
if [[ "$OUT" == "-" ]]; then
	"$GODOT" --headless --path . --fixed-fps 60 \
		--script res://tools/record_trailer.gd -- - "$SECONDS_LEN" "$SEED" "$SHOT" | grep -E "EVENT|FRAMES"
	exit 0
fi
"$GODOT" --path . --write-movie "$WORK/audio.avi" --fixed-fps 60 \
	--script res://tools/record_trailer.gd -- "$WORK/frames" "$SECONDS_LEN" "$SEED" "$SHOT" | tee "$WORK/log.txt"

WARM=$(sed -n 's/.*WARMUP_FRAMES=\([0-9]*\).*/\1/p' "$WORK/log.txt")
OFFSET=$(awk "BEGIN{print ${WARM:-0}/60}")

mkdir -p "$(dirname "$OUT")"
ffmpeg -y -loglevel error -framerate 60 -i "$WORK/frames/f%05d.jpg" \
	-ss "$OFFSET" -i "$WORK/audio.avi" \
	-map 0:v -map 1:a -c:v libx264 -pix_fmt yuv420p -crf 18 -preset slow \
	-c:a aac -b:a 192k -shortest -movflags +faststart "$OUT"
grep EVENT "$WORK/log.txt" > "${OUT%.*}.events.txt" || true
echo "Wrote $OUT"
