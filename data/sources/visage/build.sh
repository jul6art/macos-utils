#!/usr/bin/env bash
#
# Build Visage without Xcode — the Command Line Tools are enough. Plain swiftc, as for the other
# utilities of macos-utils: each module of Sources/ becomes a static library, then the app links them.
#
#   sh build.sh                  # build ./build/Visage.app for this Mac
#   sh build.sh --universal      # build a universal app (arm64 + x86_64)
#   sh build.sh --install        # build, then move the app to /Applications
#   sh build.sh --tests          # build the modules for testing, then run the tests
#
# Signing: ad hoc, under a fixed identifier; macOS has kept the system audio access across rebuilds.
# VISAGE_SIGN_IDENTITY="<certificate name>" signs with a certificate of yours instead.
#
set -euo pipefail

APPNAME="Visage";
BUNDLE_ID="com.devinthehood.visage";
MIN_MACOS="15.0";
# In dependency order: each module sees those before it.
MODULES="Shared AudioSource VoiceAnalysis FaceAnimation HoloRenderer";

SRC_DIR="$(cd "$(dirname "${0}")" && pwd)";
BUILD_DIR="${SRC_DIR}/build";
TARGET="$(uname -m)-apple-macos${MIN_MACOS}";
DEVELOPER_DIR="$(xcode-select -p)";

UNIVERSAL=0;
INSTALL=0;
TESTS=0;
for arg in "$@"; do
	case "${arg}" in
		--universal) UNIVERSAL=1;;
		--install) INSTALL=1;;
		--tests) TESTS=1;;
		-h|--help) sed -n '2,12p' "${0}"; exit 0;;
		*) echo "Unknown option: ${arg}"; exit 1;;
	esac;
done;

if ! command -v swiftc >/dev/null 2>&1; then
	echo "swiftc not found. Install the Command Line Tools: xcode-select --install";
	exit 1;
fi;

# compile_modules <output directory> <swiftc flags…>: every module, as a static library and its interface.
compile_modules() {
	local out="${1}"; shift;
	mkdir -p "${out}";
	local libraries="";
	for module in ${MODULES}; do
		swiftc "$@" -target "${TARGET}" -parse-as-library -module-name "${module}" \
			-emit-module -emit-module-path "${out}/${module}.swiftmodule" \
			-emit-library -static -o "${out}/lib${module}.a" \
			-I "${out}" "${SRC_DIR}/Sources/${module}"/*.swift;
		libraries="${libraries} -l${module}";
	done;
	LINK_LIBRARIES="${libraries}";
}

if [ "${TESTS}" -eq 1 ]; then
	# Swift Testing ships with the Command Line Tools (XCTest does not): its framework and its macros.
	if [ -d "${DEVELOPER_DIR}/Library/Developer/Frameworks/Testing.framework" ]; then
		FRAMEWORKS="${DEVELOPER_DIR}/Library/Developer/Frameworks";
		INTEROP="${DEVELOPER_DIR}/Library/Developer/usr/lib";
		PLUGINS="${DEVELOPER_DIR}/usr/lib/swift/host/plugins/testing";
	else
		FRAMEWORKS="${DEVELOPER_DIR}/Platforms/MacOSX.platform/Developer/Library/Frameworks";
		INTEROP="${DEVELOPER_DIR}/Platforms/MacOSX.platform/Developer/usr/lib";
		PLUGINS="${DEVELOPER_DIR}/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing";
	fi;
	OUT="${BUILD_DIR}/tests";
	echo "==> Compiling the modules for testing";
	compile_modules "${OUT}" -Onone -enable-testing;
	echo "==> Compiling the tests";
	# shellcheck disable=SC2086
	swiftc -Onone -target "${TARGET}" -parse-as-library -module-name VisageTests \
		-I "${OUT}" -L "${OUT}" ${LINK_LIBRARIES} \
		-F "${FRAMEWORKS}" -framework Testing -plugin-path "${PLUGINS}" \
		-Xlinker -rpath -Xlinker "${FRAMEWORKS}" -Xlinker -rpath -Xlinker "${INTEROP}" \
		-o "${OUT}/VisageTests" "${SRC_DIR}"/Tests/*.swift "${SRC_DIR}"/Tests/*/*.swift;
	echo "==> Running the tests";
	"${OUT}/VisageTests";
	exit $?;
fi;

OUT="${BUILD_DIR}/release";
APP_DIR="${BUILD_DIR}/${APPNAME}.app";
ARCHS="$(uname -m)";
[ "${UNIVERSAL}" -eq 1 ] && ARCHS="arm64 x86_64";
BINARIES="";
# One pass per architecture, the modules included: a static library holds a single one.
for arch in ${ARCHS}; do
	TARGET="${arch}-apple-macos${MIN_MACOS}";
	echo "==> Compiling the modules (${arch})";
	compile_modules "${OUT}/${arch}" -O;
	echo "==> Compiling the app (${arch})";
	# shellcheck disable=SC2086
	swiftc -O -target "${TARGET}" -parse-as-library -module-name VisageApp \
		-I "${OUT}/${arch}" -L "${OUT}/${arch}" ${LINK_LIBRARIES} \
		-o "${OUT}/${arch}/${APPNAME}" "${SRC_DIR}/Sources/VisageApp"/*.swift;
	BINARIES="${BINARIES} ${OUT}/${arch}/${APPNAME}";
done;
if [ "${UNIVERSAL}" -eq 1 ]; then
	# shellcheck disable=SC2086
	lipo -create -output "${OUT}/${APPNAME}" ${BINARIES};
else
	cp "${OUT}/${ARCHS}/${APPNAME}" "${OUT}/${APPNAME}";
fi;

echo "==> Assembling the bundle";
rm -rf "${APP_DIR}";
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources";
cp "${OUT}/${APPNAME}" "${APP_DIR}/Contents/MacOS/${APPNAME}";
cp "${SRC_DIR}/Info.plist" "${APP_DIR}/Contents/Info.plist";
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo";
cp -R "${SRC_DIR}"/Resources/*.lproj "${APP_DIR}/Contents/Resources/";
# The faces, built by tools/faces: one .glb each, and their list.
cp -R "${SRC_DIR}/Resources/Faces" "${APP_DIR}/Contents/Resources/Faces";

echo "==> Icon";
# Drawn by code from the brand's geometry (docs/charte.md, § 2): the repository holds no bitmap.
sh "${SRC_DIR}/brand/generate.sh" --iconset "${BUILD_DIR}/AppIcon.iconset" >/dev/null;
iconutil -c icns "${BUILD_DIR}/AppIcon.iconset" -o "${APP_DIR}/Contents/Resources/AppIcon.icns";
rm -rf "${BUILD_DIR}/AppIcon.iconset";

echo "==> Signing";
codesign --force --sign "${VISAGE_SIGN_IDENTITY:--}" --identifier "${BUNDLE_ID}" "${APP_DIR}";
codesign --verify --strict "${APP_DIR}";

if [ "${INSTALL}" -eq 1 ]; then
	# Quit a running copy first: deleting its bundle would kill it without stopping its tap.
	if pgrep -f "/Applications/${APPNAME}.app/Contents/MacOS/${APPNAME}" >/dev/null 2>&1; then
		osascript -e "tell application id \"${BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true;
		sleep 1;
	fi;
	rm -rf "/Applications/${APPNAME}.app";
	mv "${APP_DIR}" "/Applications/";
	echo "==> Installed in /Applications/${APPNAME}.app";
else
	echo "==> ${APP_DIR}";
fi;
