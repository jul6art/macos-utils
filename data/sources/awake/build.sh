#!/usr/bin/env bash
#
# Build Awake.app without Xcode — the Command Line Tools are enough.
#
#   sh build.sh                  # build ./build/Awake.app for this Mac
#   sh build.sh --universal      # build a universal (arm64 + x86_64) binary
#   sh build.sh --install        # build, then move the app to /Applications
#
set -euo pipefail

APPNAME="Awake";
BUNDLE_ID="com.devinthehood.awake";
MIN_MACOS="13.0";

SRC_DIR="$(cd "$(dirname "${0}")" && pwd)";
BUILD_DIR="${SRC_DIR}/build";
APP_DIR="${BUILD_DIR}/${APPNAME}.app";
MACOS_DIR="${APP_DIR}/Contents/MacOS";
RESOURCES_DIR="${APP_DIR}/Contents/Resources";

UNIVERSAL=0;
INSTALL=0;

for arg in "$@"; do
	case "${arg}" in
		--universal) UNIVERSAL=1;;
		--install) INSTALL=1;;
		-h|--help) sed -n '2,8p' "${0}"; exit 0;;
		*) echo "Unknown option: ${arg}"; exit 1;;
	esac;
done;

if ! command -v swiftc >/dev/null 2>&1; then
	echo "swiftc not found. Install the Command Line Tools: xcode-select --install";
	exit 1;
fi;

echo "==> Cleaning ${BUILD_DIR}";
rm -rf "${BUILD_DIR}";
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}";

echo "==> Compiling Swift sources";
if [ "${UNIVERSAL}" -eq 1 ]; then
	swiftc -O -target "arm64-apple-macos${MIN_MACOS}"  -o "${BUILD_DIR}/${APPNAME}-arm64"  "${SRC_DIR}"/*.swift;
	swiftc -O -target "x86_64-apple-macos${MIN_MACOS}" -o "${BUILD_DIR}/${APPNAME}-x86_64" "${SRC_DIR}"/*.swift;
	lipo -create -output "${MACOS_DIR}/${APPNAME}" "${BUILD_DIR}/${APPNAME}-arm64" "${BUILD_DIR}/${APPNAME}-x86_64";
	rm -f "${BUILD_DIR}/${APPNAME}-arm64" "${BUILD_DIR}/${APPNAME}-x86_64";
else
	swiftc -O -target "$(uname -m)-apple-macos${MIN_MACOS}" -o "${MACOS_DIR}/${APPNAME}" "${SRC_DIR}"/*.swift;
fi;

chmod +x "${MACOS_DIR}/${APPNAME}";

echo "==> Assembling the bundle";
cp "${SRC_DIR}/Info.plist" "${APP_DIR}/Contents/Info.plist";
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo";

if [ -f "${SRC_DIR}/AppIcon.icns" ]; then
	cp "${SRC_DIR}/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns";
fi;

echo "==> Ad-hoc signing";
codesign --force --deep --sign - --identifier "${BUNDLE_ID}" "${APP_DIR}";
codesign --verify --deep --strict "${APP_DIR}";

if [ "${INSTALL}" -eq 1 ]; then
	# Deleting the bundle of a running app kills that process on the spot and
	# drops its power assertion. Ask it to quit first, and put it back after.
	WAS_RUNNING=0;
	if pgrep -f "/Applications/${APPNAME}.app/Contents/MacOS/${APPNAME}" >/dev/null 2>&1; then
		WAS_RUNNING=1;
		echo "==> Quitting the running ${APPNAME}";
		osascript -e "tell application \"${APPNAME}\" to quit" >/dev/null 2>&1 || true;
		for _ in 1 2 3 4 5 6 7 8 9 10; do
			pgrep -f "/Applications/${APPNAME}.app/Contents/MacOS/${APPNAME}" >/dev/null 2>&1 || break;
			sleep 0.5;
		done;
		pkill -f "/Applications/${APPNAME}.app/Contents/MacOS/${APPNAME}" >/dev/null 2>&1 || true;
	fi;

	echo "==> Installing to /Applications";
	rm -rf "/Applications/${APPNAME}.app";
	mv "${APP_DIR}" "/Applications/${APPNAME}.app";

	if [ "${WAS_RUNNING}" -eq 1 ]; then
		echo "==> Relaunching ${APPNAME}";
		open -a "/Applications/${APPNAME}.app";
	fi;

	echo "/Applications/${APPNAME}.app";
else
	echo "${APP_DIR}";
fi;
