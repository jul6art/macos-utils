#!/usr/bin/env bash
#
# The pilot's measured tests (lot 0, docs/specs.md). Run them at the Mac, sound on: the first run makes
# macOS ask for system audio recording and for the microphone — allow both.
#
#   sh run-tests.sh            # 1 capture by process · 2 crash with a private tap · 3 crash with a public
#                              # tap · 4 capture by bundle ID, and the tap following an app that restarts
#   sh run-tests.sh --claude   # and 5: Claude Desktop in voice mode (talk to it while the test waits)
#
# The microphone is the ear: it measures whether a voice comes out of the speakers. Results (levels and
# the pilot's status, no audio) land in results/.
#
set -euo pipefail

DIR="$(cd "$(dirname "${0}")" && pwd)";
PILOT_APP="${DIR}/build/VisagePilot.app";
PILOT_BIN="${PILOT_APP}/Contents/MacOS/VisagePilot";
STANDIN_APP="${DIR}/build/VoiceStandIn.app";
LOGS="${HOME}/Library/Logs/VisagePilot";
OUT="${DIR}/results";
VOICE="${DIR}/build/voice.aiff";
CLAUDE=0;

for arg in "$@"; do
	case "${arg}" in
		--claude) CLAUDE=1;;
		-h|--help) sed -n '2,12p' "${0}"; exit 0;;
		*) echo "Unknown option: ${arg}"; exit 1;;
	esac;
done;

[ -x "${PILOT_BIN}" ] || { echo "Build the pilot first: sh build.sh"; exit 1; };
if osascript -e 'output muted of (get volume settings)' | grep -q true; then
	echo "The Mac's sound is muted: the microphone would hear nothing. Turn it on, then run again.";
	exit 1;
fi;
mkdir -p "${OUT}";
rm -f "${OUT}"/*.json "${OUT}"/*.txt;
if [ ! -f "${VOICE}" ]; then
	say -v Jacques -o "${VOICE}" "Bonjour. Je suis la voix de test du pilote de Visage. Papa boit un bon bol de lait au miel, puis il part promener le petit chien dans le parc, sous la pluie de mai. Maman m'a bien dit : passe par le bout du pont, prends le bus de midi. Bébé, pomme, bambou, papillon, mimosa, problème, possible, immobile." \
		|| say -o "${VOICE}" "This is the test voice of the Visage pilot.";
fi;

status() { # status <key>: a field of the pilot's status
	python3 -I -c "import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2]))" "${LOGS}/status.json" "${1}" 2>/dev/null || echo "";
}

capturing() { # true when the pilot runs and hears the target
	python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('connected') and d.get('callbacks',0) > 0 and d.get('levelDb',-120) > -60 else 1)" "${LOGS}/status.json" 2>/dev/null;
}

wait_capture() { # wait_capture <seconds>
	for _ in $(seq 1 "${1}"); do capturing && return 0; sleep 1; done;
	return 1;
}

pilot_start() {
	rm -f "${LOGS}/status.json" "${LOGS}/pilot.log";
	open -n "${PILOT_APP}" --args "$@" --connect;
}

pilot_crash() { # SIGKILL: nothing gets cleaned up, as in a real crash
	pkill -9 -f "VisagePilot.app/Contents/MacOS/VisagePilot --target" || true;
}

mic() { # mic <name>: three seconds of microphone, median level printed
	open -W -n "${PILOT_APP}" --args --mic 3 "${OUT}/mic-${1}.json";
	python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('medianDb', d.get('error')))" "${OUT}/mic-${1}.json";
}

save() { cp "${LOGS}/status.json" "${OUT}/${1}.json"; cp "${LOGS}/pilot.log" "${OUT}/${1}-events.txt"; }

cpu() { # cpu <name>: the pilot's CPU, five samples a second apart
	local pid; pid="$(pgrep -f "VisagePilot.app/Contents/MacOS/VisagePilot --target" | head -1)";
	for _ in 1 2 3 4 5; do ps -o %cpu= -p "${pid}"; sleep 1; done > "${OUT}/${1}.txt";
}

echo "==> 1 · capture by process (afplay), private tap";
afplay "${VOICE}" & AFPLAY=$!;
sleep 1;
echo "    voice straight out: $(mic direct) dB";
kill -STOP "${AFPLAY}"; echo "    silence:            $(mic silence) dB"; kill -CONT "${AFPLAY}";
pilot_start --target afplay --mode processes --delay 150 --anticipation 40;
if ! wait_capture 120; then
	echo "    NO CAPTURE: allow VisagePilot in System Settings > Privacy & Security > Screen & System Audio Recording, then run again.";
	pilot_crash; kill "${AFPLAY}" 2>/dev/null || true; exit 1;
fi;
sleep 4; save t1; cpu t1-cpu;
echo "    through the pilot:  $(mic through-pilot) dB   lookahead $(status lookaheadMs) ms, mismatches $(status frameMismatches), overloads $(status overloads)";

echo "==> 2 · crash with a private tap";
pilot_crash; sleep 0.5;
echo "    after the crash:    $(mic after-crash-private) dB";
kill "${AFPLAY}" 2>/dev/null || true; wait "${AFPLAY}" 2>/dev/null || true;

echo "==> 3 · crash with a public tap";
afplay "${VOICE}" & AFPLAY=$!;
pilot_start --target afplay --mode processes --delay 150 --public;
wait_capture 30 || echo "    (no capture)";
pilot_crash; sleep 0.5;
echo "    after the crash:    $(mic after-crash-public) dB";
"${PILOT_BIN}" --list | grep '^taps' | tee "${OUT}/t3-taps.txt";
for uid in $(sed -e 's/^taps: //' -e 's/,//g' "${OUT}/t3-taps.txt"); do "${PILOT_BIN}" --destroy-tap "${uid}"; done;
kill "${AFPLAY}" 2>/dev/null || true; wait "${AFPLAY}" 2>/dev/null || true;

echo "==> 4 · capture by bundle ID, and the app restarting";
open -n "${STANDIN_APP}" --args "${VOICE}"; sleep 2;
pilot_start --target com.devinthehood.visage.standin --mode bundle --exact --delay 150;
if wait_capture 30; then
	save t4-before;
	pkill -TERM -f "VoiceStandIn.app/Contents/MacOS/VoiceStandIn" || true; sleep 2;
	open -n "${STANDIN_APP}" --args "${VOICE}";
	if wait_capture 20; then echo "    restored after the restart: yes"; else echo "    restored after the restart: NO"; fi;
	save t4-after;
	echo "    connections in the log: $(grep -c '"event":"connected"' "${LOGS}/pilot.log")";
else
	echo "    NO CAPTURE by bundle ID";
fi;
pilot_crash; pkill -TERM -f "VoiceStandIn.app/Contents/MacOS/VoiceStandIn" || true;

if [ "${CLAUDE}" -eq 1 ]; then
	echo "==> 5 · Claude Desktop";
	[ -d /Applications/Claude.app ] || { echo "    Claude Desktop is not in /Applications"; exit 1; };
	echo "    Open Claude, start voice mode and talk to it: waiting for it to answer (2 min at most).";
	for _ in $(seq 1 120); do
		"${PILOT_BIN}" --list | grep -i -E 'OUT.*(anthropic|claude)' > "${OUT}/t5-processes.txt" && break;
		sleep 1;
	done;
	cat "${OUT}/t5-processes.txt" || true;
	pilot_start --target com.anthropic.claudefordesktop --mode bundle --delay 150 --anticipation 40;
	if wait_capture 120; then
		save t5;
		echo "    capturing Claude: level $(status levelDb) dB, lookahead $(status lookaheadMs) ms";
		echo "    The pilot stays open: keep talking for a minute, through the speakers, and watch the mouth.";
	else
		echo "    NO CAPTURE of Claude";
		pilot_crash;
	fi;
fi;

echo "==> Results in ${OUT}";
