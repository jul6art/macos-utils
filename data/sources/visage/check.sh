#!/usr/bin/env bash
#
# Visage's gate, before every commit — everything comes with the Command Line Tools, nothing to install.
#
#   sh check.sh            # build the app, run the tests, check the format
#   sh check.sh --fix      # format the sources first, then the gate
#
set -euo pipefail

cd "$(dirname "${0}")";

if [ "${1:-}" = "--fix" ]; then
	swift format format --in-place --recursive Sources Tests;
fi;

echo "==> Build";
sh build.sh;

echo "==> Tests";
mkdir -p build;
sh build.sh --tests 2>&1 | tee build/test-output.txt;
# Read the count: the exit code alone has fooled CI before.
grep -E "Test run with [0-9]+ tests? (in [0-9]+ suites? )?passed" build/test-output.txt \
	|| { echo "The tests did not all pass."; exit 1; };

echo "==> Format";
swift format lint --strict --recursive Sources Tests;

echo "==> Gate green.";
