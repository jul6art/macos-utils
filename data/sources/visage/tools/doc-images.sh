#!/usr/bin/env bash
#
# Remakes the pictures of data/doc/VISAGE.md from the app itself, offline: --snapshot renders the
# screens, --render films a face speaking a file. Nothing is played aloud and no permission is asked.
# Needs a built app (sh build.sh), ffmpeg and the WebP tools: brew install ffmpeg webp.
#
#   sh tools/doc-images.sh
#
set -euo pipefail

DIR="$(cd "$(dirname "${0}")/.." && pwd)";
APP="${DIR}/build/Visage.app/Contents/MacOS/Visage";
OUT="$(cd "${DIR}/../../doc" && pwd)/images/visage";
VOICE="${VOICE:-Samantha}";

for tool in ffmpeg cwebp img2webp; do
	command -v "${tool}" >/dev/null 2>&1 || { echo "${tool} not found: brew install ffmpeg webp"; exit 1; };
done;
[ -x "${APP}" ] || { echo "Build the app first: sh build.sh"; exit 1; };

WORK="$(mktemp -d)";
trap 'rm -rf "${WORK}"' EXIT;
mkdir -p "${OUT}";

# English, and the settings of a first launch. Given on the command line, they win over the saved ones
# for this run only: nothing is written to the preferences.
visage() {
	"${APP}" "$@" -AppleLanguages '(en)' -AppleLocale en_US -face lea -realism 0 -faceScale 1 \
		-windowMode floating -holoColour braise -halo 1 -scanlines 1 -projector YES -glitches YES \
		-camera NO -microphone NO;
}

echo "==> Screens";
visage --snapshot "${WORK}/shots" >/dev/null;
# <snapshot> <picture>: lossless, text stays sharp. Screens are rendered at twice their size, for Retina.
for pair in welcome:welcome connect-idle:connect connect-permission:permission connect-connected:connected \
	settings:settings settings-hologram:settings-hologram settings-conversation:settings-conversation \
	settings-camera:settings-camera settings-window:settings-window settings-sync:settings-sync; do
	cwebp -quiet -lossless -z 9 "${WORK}/shots/${pair%%:*}.png" -o "${OUT}/${pair##*:}.webp";
done;
# The faces are photographs: lossy, at the size they show.
for sheet in faces faces-real; do
	cwebp -quiet -q 82 -resize 1440 0 "${WORK}/shots/${sheet}.png" -o "${OUT}/${sheet}.webp";
done;

echo "==> A face speaking";
say -v "${VOICE}" -o "${WORK}/voice.aiff" \
	"Hello. I am the voice you already talk to. Now, I have a face, and it moves before I speak.";
# The gauge slides from the hologram to the real face across the clip.
visage --render "${WORK}/voice.aiff" "${WORK}/speaking.mov" --face lea --realism 0-100 --mute >/dev/null;
mkdir "${WORK}/frames";
ffmpeg -loglevel error -i "${WORK}/speaking.mov" -vf "fps=15,scale=360:-1:flags=lanczos" \
	"${WORK}/frames/%04d.png";
# shellcheck disable=SC2046
img2webp -loop 0 -lossy -q 70 -m 6 -d 67 $(find "${WORK}/frames" -name '*.png' | sort) \
	-o "${OUT}/speaking.webp" >/dev/null;

du -h "${OUT}"/*.webp;
