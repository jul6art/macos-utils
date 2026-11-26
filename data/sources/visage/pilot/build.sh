#!/usr/bin/env bash
#
# Build VisagePilot.app without Xcode — the Command Line Tools are enough.
# The pilot of Visage (lot 0, docs/specs.md): it taps an app's sound, plays it
# back with a delay, and moves a sketched mouth with it.
#
#   sh build.sh                  # build ./build/VisagePilot.app for this Mac
#   sh build.sh --open           # build, then open it
#   build/VisagePilot.app/Contents/MacOS/VisagePilot --list
#                                # list the audio processes and the taps
#
set -euo pipefail

APPNAME="VisagePilot";
BUNDLE_ID="com.devinthehood.visage.pilot";
MIN_MACOS="26.0";

SRC_DIR="$(cd "$(dirname "${0}")" && pwd)";
BUILD_DIR="${SRC_DIR}/build";
APP_DIR="${BUILD_DIR}/${APPNAME}.app";
MACOS_DIR="${APP_DIR}/Contents/MacOS";

OPEN=0;

for arg in "$@"; do
	case "${arg}" in
		--open) OPEN=1;;
		-h|--help) sed -n '2,11p' "${0}"; exit 0;;
		*) echo "Unknown option: ${arg}"; exit 1;;
	esac;
done;

if ! command -v swiftc >/dev/null 2>&1; then
	echo "swiftc not found. Install the Command Line Tools: xcode-select --install";
	exit 1;
fi;

echo "==> Cleaning ${BUILD_DIR}";
rm -rf "${BUILD_DIR}";
mkdir -p "${MACOS_DIR}";

echo "==> Compiling Swift sources";
swiftc -O -swift-version 6 -target "$(uname -m)-apple-macos${MIN_MACOS}" -o "${MACOS_DIR}/${APPNAME}" "${SRC_DIR}"/*.swift;

echo "==> Assembling the bundle";
cp "${SRC_DIR}/Info.plist" "${APP_DIR}/Contents/Info.plist";
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo";

echo "==> Ad-hoc signing";
codesign --force --deep --sign - --identifier "${BUNDLE_ID}" "${APP_DIR}";
codesign --verify --deep --strict "${APP_DIR}";

echo "==> The stand-in voice (a real bundle ID to tap)";
STANDIN_DIR="${BUILD_DIR}/VoiceStandIn.app";
mkdir -p "${STANDIN_DIR}/Contents/MacOS";
swiftc -O -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macos${MIN_MACOS}" -o "${STANDIN_DIR}/Contents/MacOS/VoiceStandIn" "${SRC_DIR}"/standin/*.swift;
cp "${SRC_DIR}/standin/Info.plist" "${STANDIN_DIR}/Contents/Info.plist";
codesign --force --sign - --identifier "com.devinthehood.visage.standin" "${STANDIN_DIR}";

echo "==> ${APP_DIR}";

if [ "${OPEN}" -eq 1 ]; then
	open "${APP_DIR}";
fi;
