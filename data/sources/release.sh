#!/usr/bin/env bash
#
# Packs one of the apps for a GitHub release: the universal app (arm64 + x86_64), zipped, with its SHA-256.
# Run it on a clean checkout of the release's tag: with the same Command Line Tools, two runs give the
# same archive, byte for byte, so anyone can rebuild it and compare with the published checksum.
#
#   sh data/sources/release.sh awake     # data/sources/awake/build/dist/Awake-<version>.zip and .sha256
#   sh data/sources/release.sh siphon
#   sh data/sources/release.sh visage
#
set -euo pipefail

ROOT="$(cd "$(dirname "${0}")" && pwd)";
case "${1:-}" in
	awake|siphon|visage) NAME="${1}";;
	-h|--help) sed -n '2,10p' "${0}"; exit 0;;
	*) echo "Usage: sh release.sh awake|siphon|visage"; exit 1;;
esac;

SRC_DIR="${ROOT}/${NAME}";
APPNAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "${SRC_DIR}/Info.plist")";
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${SRC_DIR}/Info.plist")";
DIST="${SRC_DIR}/build/dist";
ARCHIVE="${APPNAME}-${VERSION}.zip";

# Untracked files count too: a stray .swift file next to the sources would be compiled into the app.
if [ -n "$(git -C "${SRC_DIR}" status --porcelain -- .)" ]; then
	echo "Uncommitted changes under data/sources/${NAME}: a release is built from a commit.";
	exit 1;
fi;
# git ignores a personal icon dropped next to the sources, but build.sh would pack it.
if [ -f "${SRC_DIR}/AppIcon.icns" ]; then
	echo "data/sources/${NAME}/AppIcon.icns is a personal icon: move it away to build a release.";
	exit 1;
fi;

echo "==> Building the universal ${APPNAME}";
ZERO_AR_DATE=1 sh "${SRC_DIR}/build.sh" --universal >/dev/null;

rm -rf "${DIST}";
mkdir -p "${DIST}/stage";
ditto --norsrc --noextattr "${SRC_DIR}/build/${APPNAME}.app" "${DIST}/stage/${APPNAME}.app";

# Every file dated at the last commit, archived in a fixed order, with no extended attribute and no extra
# timestamp: the archive depends on the sources only, not on when or where it was made.
STAMP="$(TZ=UTC git -C "${SRC_DIR}" log -1 --format=%cd --date=format-local:%Y%m%d%H%M.%S)";
TZ=UTC find "${DIST}/stage/${APPNAME}.app" -exec touch -h -t "${STAMP}" {} +;
(cd "${DIST}/stage" && find "${APPNAME}.app" | LC_ALL=C sort | TZ=UTC zip -q -X -y -@ "${DIST}/${ARCHIVE}");
rm -rf "${DIST}/stage";

(cd "${DIST}" && shasum -a 256 "${ARCHIVE}" > "${ARCHIVE}.sha256");
cat "${DIST}/${ARCHIVE}.sha256";
echo "==> ${DIST}/${ARCHIVE}";
