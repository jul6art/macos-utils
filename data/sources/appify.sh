#!/usr/bin/env bash
#
# appify — wrap a shell script into a minimal macOS .app bundle.
#
# Vendored from Thomas Aylott's original appify (gist 674099) so this repo
# stays self-contained. Public domain / MIT-compatible, credit to the author.
#
#   sh appify.sh PATH/TO/script.sh "Your App Name"
#
# Prints the path of the generated bundle.
set -euo pipefail

APPNAME=${2:-$(basename "${1}" '.sh')};
DIR="${APPNAME}.app/Contents/MacOS";

if [ -a "${APPNAME}.app" ]; then
	echo "${PWD}/${APPNAME}.app already exists :(";
	exit 1;
fi;

mkdir -p "${DIR}";
cp "${1}" "${DIR}/${APPNAME}";
chmod +x "${DIR}/${APPNAME}";

echo "${PWD}/$APPNAME.app";
