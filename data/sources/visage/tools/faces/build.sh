#!/usr/bin/env bash
#
# Builds Visage's ten faces into Resources/Faces (spec, § 8.1). Needs Blender, its MPFB extension, and
# MakeHuman's CC0 packs (system assets, faceunits01) — only to rebuild the faces: the app never needs them.
#
#   sh tools/faces/build.sh            # the ten faces
#   sh tools/faces/build.sh lea hugo   # only these
#
set -euo pipefail

DIR="$(cd "$(dirname "${0}")" && pwd)";
OUT="${DIR}/../../Resources/Faces";
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}";

if [ ! -x "${BLENDER}" ]; then
	echo "Blender not found: brew install --cask blender (or set BLENDER)";
	exit 1;
fi;

mkdir -p "${OUT}";
"${BLENDER}" -b --factory-startup --python "${DIR}/build_faces.py" -- "${DIR}/presets.json" "${OUT}" "$@" 2>&1 \
	| grep -E "^FACE|^SEEN|^TIDY|Error|Traceback";
cp "${DIR}/presets.json" "${OUT}/faces.json";
