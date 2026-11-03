#!/usr/bin/env bash
#
# Compila el instalador de DeepSeek Harness a .exe de Windows usando Go.
#
# Uso:
#   ./build.sh          -> genera dist/DeepSeek-Harness-Setup-x64.exe y -arm64.exe
#   ./build.sh x64      -> solo x64
#   ./build.sh arm64    -> solo arm64
#
# Requiere Go (cualquier Go >= 1.20 sirve). Si no esta en el PATH, se usa
# /usr/local/go/bin/go.
#
set -euo pipefail

cd "$(dirname "$0")"

GO="go"
if ! command -v go >/dev/null 2>&1; then
    if [ -x /usr/local/go/bin/go ]; then
        GO=/usr/local/go/bin/go
    else
        echo "No se encontro Go. Instalalo (https://go.dev/dl) y vuelve a intentarlo." >&2
        exit 1
    fi
fi

mkdir -p dist

build_one() {
    local arch="$1" suffix="$2"
    echo "==> Compilando windows/${arch} -> dist/DeepSeek-Harness-Setup-${suffix}.exe"
    ( cd installer && \
      GOOS=windows GOARCH="${arch}" CGO_ENABLED=0 \
      "${GO}" build -trimpath -ldflags "-s -w" \
      -o "../dist/DeepSeek-Harness-Setup-${suffix}.exe" . )
}

case "${1:-}" in
    x64)   build_one amd64 x64 ;;
    arm64) build_one arm64 arm64 ;;
    "")    build_one amd64 x64
           build_one arm64 arm64 ;;
    *)     echo "Uso: $0 [x64|arm64]" >&2; exit 2 ;;
esac

echo ""
echo "Listo. Salida en dist/:"
ls -lh dist/*.exe
