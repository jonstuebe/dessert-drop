#!/usr/bin/env bash
# Build the web export into export/web, ready for `wrangler deploy`.
#
# Works locally (uses an installed `godot` 4.7.2) and in Cloudflare Workers
# Builds (Ubuntu x86_64, no Godot): there it downloads the official Godot
# binary and export templates from GitHub into .cache/ first.
#
# index.wasm is ~38 MiB, over the 25 MiB per-file limit for Workers static
# assets, so it is stored gzipped as index.wasm.gz and src/worker.js serves
# it at /index.wasm with Content-Encoding: gzip.
set -euo pipefail

GODOT_VERSION="4.7.2"
GODOT_TAG="${GODOT_VERSION}-stable"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/export/web"
CACHE="$ROOT/.cache/godot"
RELEASES="https://github.com/godotengine/godot/releases/download/${GODOT_TAG}"

cd "$ROOT"

godot_ok() {
	command -v "$1" >/dev/null 2>&1 && "$1" --version 2>/dev/null | grep -q "^${GODOT_VERSION}\.stable"
}

GODOT=""
if [[ -n "${GODOT_BIN:-}" ]] && godot_ok "$GODOT_BIN"; then
	GODOT="$GODOT_BIN"
elif godot_ok godot; then
	GODOT="godot"
fi

if [[ -z "$GODOT" ]]; then
	if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
		echo "Godot ${GODOT_VERSION} not found. Install it (macOS: brew install --cask godot) or set GODOT_BIN." >&2
		exit 1
	fi
	mkdir -p "$CACHE"
	BIN="$CACHE/Godot_v${GODOT_TAG}_linux.x86_64"
	if [[ ! -x "$BIN" ]]; then
		echo "==> Downloading Godot ${GODOT_TAG} (linux x86_64)"
		curl -fsSL --retry 3 -o "$CACHE/godot.zip" "$RELEASES/Godot_v${GODOT_TAG}_linux.x86_64.zip"
		unzip -oq "$CACHE/godot.zip" -d "$CACHE"
		rm -f "$CACHE/godot.zip"
		chmod +x "$BIN"
	fi
	GODOT="$BIN"

	TPL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${GODOT_VERSION}.stable"
	if [[ ! -f "$TPL_DIR/web_nothreads_release.zip" ]]; then
		echo "==> Downloading export templates (~1.3 GB; only the web template is kept)"
		curl -fsSL --retry 3 -o "$CACHE/templates.tpz" "$RELEASES/Godot_v${GODOT_TAG}_export_templates.tpz"
		mkdir -p "$TPL_DIR"
		unzip -ojq "$CACHE/templates.tpz" templates/web_nothreads_release.zip templates/version.txt -d "$TPL_DIR"
		rm -f "$CACHE/templates.tpz"
	fi
fi

echo "==> Using $("$GODOT" --version)"

rm -rf "$OUT"
mkdir -p "$OUT"
# Keep Godot from importing (and packing) the web build and npm packages.
touch "$ROOT/export/.gdignore"
[[ -d "$ROOT/node_modules" ]] && touch "$ROOT/node_modules/.gdignore"

echo "==> Importing assets"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

echo "==> Exporting Web preset"
"$GODOT" --headless --path . --export-release "Web" "$OUT/index.html"

for f in index.html index.js index.pck index.wasm; do
	[[ -s "$OUT/$f" ]] || { echo "Export is missing $f" >&2; exit 1; }
done

echo "==> Copying static files (link-preview image, etc.)"
find "$ROOT/web/public" -maxdepth 1 -type f ! -name '.gdignore' -exec cp {} "$OUT/" \;

echo "==> Compressing index.wasm"
gzip -9 -n -f "$OUT/index.wasm"   # -> index.wasm.gz

ls -la "$OUT"
echo "==> Web build ready in export/web"
