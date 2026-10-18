#!/bin/sh
# MedStation dev helper (macOS/Linux, needs Docker). Usage: tools/medstation_dev.sh <image|compile|tgui|test|run|stop|logs|status>
set -e
cd "$(dirname "$0")/.."
RUN="docker run --rm --platform linux/amd64 -v $PWD:/tgstation medstation:dev"
case "$1" in
	image)   docker build --platform linux/amd64 -f Dockerfile.dev -t medstation:dev . ;;
	compile) $RUN DreamMaker tgstation.dme ;;
	tgui)    $RUN bash -c "tools/build/build.sh tgui" ;;
	test)    # compiles with the CI defines and runs only the focused MedStation unit tests
	         cp tgstation.dme tgstation.test.dme
	         $RUN DreamMaker -DCBT -DCIBUILDING tgstation.test.dme
	         rm -rf data/logs/ci
	         $RUN DreamDaemon tgstation.test.dmb -close -trusted -verbose -params log-directory=ci || true
	         rm -f tgstation.test.*
	         cat data/logs/ci/clean_run.lk 2>/dev/null || { echo "TEST RUN NOT CLEAN"; tail -40 data/logs/ci/unit_tests.log 2>/dev/null; } ;;
	run)     docker rm -f medstation >/dev/null 2>&1 || true
	         docker run -d --name medstation --platform linux/amd64 -p 1337:1337 -v "$PWD":/tgstation medstation:dev \
	             DreamDaemon tgstation.dmb -port 1337 -trusted -close -verbose ;;
	stop)    docker rm -f medstation ;;
	logs)    docker logs -f medstation ;;
	status)  python3 - <<'PY'
import socket,struct,urllib.parse
q=b"?status"
s=socket.create_connection(("127.0.0.1",1337),timeout=10)
s.sendall(b"\x00\x83"+struct.pack(">H",len(q)+6)+b"\x00\x00\x00\x00\x00"+q+b"\x00")
print(urllib.parse.unquote_plus(s.recv(4096)[5:].decode(errors="ignore")).replace("&","\n"))
PY
	;;
	*) echo "usage: $0 image|compile|tgui|test|run|stop|logs|status"; exit 1 ;;
esac
