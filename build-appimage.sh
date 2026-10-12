#!/usr/bin/env bash
# Reproducible build of an unofficial Muse Code AppImage for x86_64 Linux.
# The Muse Code binary is NOT stored in this repo: it is fetched from Meta's
# official release channel at build time and verified against Meta's sha256 manifest.
set -euo pipefail

CHANNEL_URL="${CHANNEL_URL:-https://api.meta.ai/muse-code/channels/muse-stable}"
ARTIFACT="${ARTIFACT:-x86_linux}"          # manifest key for muse-x86-linux
ARCH=x86_64
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-$HERE/build}"
OUT="${OUT:-$HERE/Muse-Code-${ARCH}.AppImage}"
APPIMAGETOOL_URL="${APPIMAGETOOL_URL:-https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required tool: $1" >&2; exit 1; }; }
for t in curl python3 sha256sum; do need "$t"; done
CURL=(curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --retry 3)

mkdir -p "$WORK"
echo "==> channel: $CHANNEL_URL"
"${CURL[@]}" -o "$WORK/channel.json" "$CHANNEL_URL"
MANIFEST_URL="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["manifest_url"])' "$WORK/channel.json")"
VERSION="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$WORK/channel.json")"
echo "==> version: $VERSION"
"${CURL[@]}" -o "$WORK/manifest.json" "$MANIFEST_URL"

read -r BIN_URL BIN_SHA BIN_SIZE < <(python3 - "$WORK/manifest.json" "$ARTIFACT" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
assert m.get("checksum_algorithm") == "sha256", "unexpected checksum algorithm"
a = m["artifacts"][sys.argv[2]]
print(a["url"], a["checksum"].lower(), a.get("size", 0))
PY
)

BIN="$WORK/muse-x86-linux"
if [[ -f "$BIN" ]] && echo "$BIN_SHA  $BIN" | sha256sum -c --status; then
  echo "==> cached binary verified"
else
  echo "==> downloading muse-x86-linux (${BIN_SIZE} bytes)"
  "${CURL[@]}" -o "$BIN.part" "$BIN_URL"
  mv "$BIN.part" "$BIN"
fi
echo "==> verifying sha256 against Meta manifest"
echo "$BIN_SHA  $BIN" | sha256sum -c - || { echo "CHECKSUM MISMATCH, refusing to package" >&2; rm -f "$BIN"; exit 1; }

echo "==> assembling AppDir"
APPDIR="$WORK/AppDir"
rm -rf "$APPDIR"; mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/512x512/apps"
install -m 0755 "$BIN" "$APPDIR/usr/bin/muse"
install -m 0755 "$HERE/packaging/AppRun" "$APPDIR/AppRun"
install -m 0644 "$HERE/packaging/muse-code.desktop" "$APPDIR/muse-code.desktop"
install -m 0644 "$HERE/packaging/muse-code.desktop" "$APPDIR/usr/share/applications/muse-code.desktop"
install -m 0644 "$HERE/packaging/muse-code.png" "$APPDIR/muse-code.png"
install -m 0644 "$HERE/packaging/muse-code.png" "$APPDIR/usr/share/icons/hicolor/512x512/apps/muse-code.png"
ln -sf muse-code.png "$APPDIR/.DirIcon"

TOOL="${APPIMAGETOOL:-$(command -v appimagetool || true)}"
if [[ -z "$TOOL" ]]; then
  TOOL="$WORK/appimagetool"
  [[ -x "$TOOL" ]] || { "${CURL[@]}" -o "$TOOL" "$APPIMAGETOOL_URL"; chmod +x "$TOOL"; }
fi
echo "==> appimagetool"
ARCH=$ARCH APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" --no-appstream "$APPDIR" "$OUT"
echo "==> built $OUT"
"$OUT" --version
