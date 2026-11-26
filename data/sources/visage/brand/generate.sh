#!/usr/bin/env bash
#
# Regenerate Visage's brand files from the kit — the Command Line Tools are enough.
# The geometry lives in kit/Mark.swift; every file next to this script comes
# from it. Edit the kit, never the files.
#
#   sh generate.sh                      # rewrite the SVG files next to this script
#   sh generate.sh --iconset DIR        # also render the app icon into DIR.iconset
#
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${0}")" && pwd)";
BUILD_DIR="${SRC_DIR}/.build";
ICONSET="";

while [ "$#" -gt 0 ]; do
	case "${1}" in
		--iconset) ICONSET="${2:?--iconset needs a directory}"; shift 2;;
		-h|--help) sed -n '2,9p' "${0}"; exit 0;;
		*) echo "Unknown option: ${1}"; exit 1;;
	esac;
done;

if ! command -v swiftc >/dev/null 2>&1; then
	echo "swiftc not found. Install the Command Line Tools: xcode-select --install";
	exit 1;
fi;

mkdir -p "${BUILD_DIR}";

echo "==> Compiling the kit";
swiftc -O -swift-version 6 -o "${BUILD_DIR}/brandkit" "${SRC_DIR}"/kit/*.swift;

echo "==> Writing the SVG files";
"${BUILD_DIR}/brandkit" svg "${SRC_DIR}";

if [ -n "${ICONSET}" ]; then
	echo "==> Rendering the app icon into ${ICONSET}";
	"${BUILD_DIR}/brandkit" iconset "${ICONSET}";
fi;
