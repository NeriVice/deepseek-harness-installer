#!/usr/bin/env bash
# =============================================================================
#  DeepSeek Harness — Instalador automático para Linux
#  ---------------------------------------------------------------------------
#  Instala SIEMPRE la última versión de DeepSeek Harness (`@deepseek-ai/dsh`),
#  resolviendo el tag `latest` en cada ejecución. Si falta Node.js (o es muy
#  antiguo), descarga e instala la última versión LTS de Node de forma local
#  en ~/.local, sin necesitar sudo.
#
#  Uso:
#      bash install-dsh.sh
#
#  Requisitos: curl (o wget) y tar. Acceso a internet.
# =============================================================================
set -euo pipefail

DSH_PACKAGE="@deepseek-ai/dsh"
NODE_MIN_MAJOR=18
INSTALL_DIR="${DSH_INSTALL_DIR:-$HOME/.local}"   # raíz de la instalación local
BIN_DIR="$INSTALL_DIR/bin"
DESKTOP_DIR="$INSTALL_DIR/share/applications"

# --------------------------- salida con colores -------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""
fi
info() { printf '%s\n' "${C_CYAN}[*]${C_RESET} $*"; }
ok()   { printf '%s\n' "${C_GREEN}[✓]${C_RESET} $*"; }
warn() { printf '%s\n' "${C_YELLOW}[!]${C_RESET} $*"; }
fail() { printf '%s\n' "${C_RED}[✗]${C_RESET} $*" >&2; }

banner() {
  printf '%s\n' "${C_BOLD}=============================================${C_RESET}"
  printf '%s\n' "${C_BOLD}   DeepSeek Harness — Instalador para Linux${C_RESET}"
  printf '%s\n' "${C_BOLD}=============================================${C_RESET}"
}

# --------------------------- utilidades --------------------------------------
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { fail "Falta el comando '$1'. Instálalo e inténtalo de nuevo."; exit 1; }
}

dl() { # dl <url> <salida>
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 25 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --tries=3 --timeout=25 -O "$2" "$1"
  else
    fail "Necesito 'curl' o 'wget' para descargar. Instala uno e inténtalo de nuevo."
    exit 1
  fi
}

arch_node() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "x64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l)        echo "armv7l" ;;
    *) fail "Arquitectura no soportada: $(uname -m)"; exit 1 ;;
  esac
}

# --------------------------- Node.js ----------------------------------------
node_major() {
  local v
  v="$("$1" --version 2>/dev/null | sed 's/^v//' | cut -d. -f1 || true)"
  echo "${v:-0}"
}

node_ok() {
  # 1) Node instalado localmente por este instalador
  if [ -x "$BIN_DIR/node" ] && [ "$(node_major "$BIN_DIR/node")" -ge "$NODE_MIN_MAJOR" ]; then
    return 0
  fi
  # 2) Node del sistema presente en el PATH
  if command -v node >/dev/null 2>&1 && [ "$(node_major "$(command -v node)")" -ge "$NODE_MIN_MAJOR" ]; then
    return 0
  fi
  return 1
}

latest_node_lts() {
  local idx ver
  idx=$(mktemp)
  if ! dl "https://nodejs.org/dist/index.json" "$idx" >/dev/null 2>&1; then
    rm -f "$idx"; return 1
  fi
  ver=$(sed 's/},{/}\n{/g' "$idx" \
      | grep '"lts":"' \
      | head -n1 \
      | grep -o '"version":"v[0-9][0-9.]*"' \
      | head -n1 \
      | cut -d'"' -f4 || true)
  rm -f "$idx"
  echo "$ver"
}

install_node() {
  local arch ver url tarball
  arch=$(arch_node)
  info "Resolviendo la última versión LTS de Node.js..."
  ver=$(latest_node_lts || true)
  if [ -z "$ver" ]; then
    fail "No pude resolver la versión LTS de Node.js (¿sin conexión a nodejs.org?)."
    exit 1
  fi
  url="https://nodejs.org/dist/${ver}/node-${ver}-linux-${arch}.tar.gz"
  tarball="/tmp/node-${ver}-linux-${arch}.tar.gz"
  info "Descargando Node.js ${ver} (${arch})..."
  dl "$url" "$tarball"
  info "Instalando Node.js en ${INSTALL_DIR} ..."
  mkdir -p "$INSTALL_DIR"
  tar -xzf "$tarball" -C "$INSTALL_DIR" --strip-components=1
  rm -f "$tarball"
  ok "Node.js ${ver} instalado en ${BIN_DIR}."
}

# --------------------------- PATH -------------------------------------------
PATH_LINE="export PATH=\"${BIN_DIR}:\$PATH\""

ensure_path() {
  local rc changed=0
  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile"; do
    if [ -f "$rc" ]; then
      if ! grep -qF "$PATH_LINE" "$rc"; then
        printf '\n# DeepSeek Harness\nexport PATH="%s:$PATH"\n' "$BIN_DIR" >> "$rc"
        info "Añadido ${BIN_DIR} al PATH en ${rc}"
        changed=1
      fi
    fi
  done
  if [ "$changed" -eq 0 ]; then
    info "PATH ya configurado (o no hay archivos de perfil que tocar)."
  fi
}

# --------------------------- instalación de DSH -----------------------------
install_dsh() {
  # En Linux, @deepseek-ai/dsh trae TODOS los binarios nativos precompilados
  # (node-pty, koffi, sharp, sherpa-onnx, etc.), por lo que un `npm install -g`
  # simple basta: los scripts de instalación no hacen falta en Linux.
  info "Instalando ${DSH_PACKAGE}@latest (siempre la última versión)..."
  npm_config_prefix="$INSTALL_DIR" npm install -g --no-audit --no-fund "$DSH_PACKAGE@latest"
}

# --------------------------- launchers --------------------------------------
create_launchers() {
  local dsh_bin
  dsh_bin="$(command -v dsh || true)"
  [ -n "$dsh_bin" ] || dsh_bin="$BIN_DIR/dsh"
  mkdir -p "$BIN_DIR" "$DESKTOP_DIR"

  # Lanzador de terminal
  cat > "$BIN_DIR/deepseek-harness" <<EOF
#!/usr/bin/env bash
# Inicia DeepSeek Harness (interfaz web en http://127.0.0.1:3080)
exec "$dsh_bin" web
EOF
  chmod +x "$BIN_DIR/deepseek-harness"

  # Actualizador
  cat > "$BIN_DIR/dsh-update" <<EOF
#!/usr/bin/env bash
set -e
echo "Actualizando DeepSeek Harness a la última versión..."
npm_config_prefix="$INSTALL_DIR" npm install -g --no-audit --no-fund $DSH_PACKAGE@latest
echo "Versión instalada:"
"$dsh_bin" --version || true
EOF
  chmod +x "$BIN_DIR/dsh-update"

  # Desinstalador
  cat > "$BIN_DIR/dsh-uninstall" <<EOF
#!/usr/bin/env bash
set -e
echo "Desinstalando DeepSeek Harness..."
npm_config_prefix="$INSTALL_DIR" npm uninstall -g $DSH_PACKAGE >/dev/null 2>&1 || true
rm -f "$BIN_DIR/deepseek-harness" "$BIN_DIR/dsh-update" "$BIN_DIR/dsh-uninstall"
rm -f "$DESKTOP_DIR/deepseek-harness.desktop"
echo "Listo. Node.js NO se elimina (bórralo manualmente si lo deseas)."
EOF
  chmod +x "$BIN_DIR/dsh-uninstall"

  # Acceso directo del menú / escritorio
  cat > "$DESKTOP_DIR/deepseek-harness.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=DeepSeek Harness
Comment=Agente local de DeepSeek (interfaz web en http://127.0.0.1:3080)
Exec=$BIN_DIR/deepseek-harness
Terminal=true
Categories=Development;Utility;
EOF

  ok "Accesos creados: deepseek-harness, dsh-update, dsh-uninstall y entrada de escritorio."
}

# --------------------------- verificación -----------------------------------
verify() {
  local dsh_bin
  dsh_bin="$(command -v dsh || true)"
  if [ -z "$dsh_bin" ]; then
    fail "No encuentro el comando 'dsh' en el PATH."
    warn "Reinicia la terminal o ejecuta: export PATH=\"${BIN_DIR}:\$PATH\""
    exit 1
  fi
  ok "dsh instalado en: ${dsh_bin}"
  info "Versión: $("$dsh_bin" --version 2>/dev/null || echo 'desconocida (preview)')"
}

summary() {
  printf '\n%s\n' "${C_BOLD}${C_GREEN}¡Instalación completada!${C_RESET}"
  printf '%s\n' "Para arrancar DeepSeek Harness ejecuta:"
  printf '%s\n' "  ${C_BOLD}dsh web${C_RESET}      (o abre \"DeepSeek Harness\" desde el menú de aplicaciones)"
  printf '%s\n' "  y abre en el navegador: ${C_BOLD}http://127.0.0.1:3080${C_RESET}"
  printf '%s\n' ""
  printf '%s\n' "Otros comandos:"
  printf '%s\n' "  ${C_BOLD}dsh-update${C_RESET}      → actualiza a la última versión"
  printf '%s\n' "  ${C_BOLD}dsh-uninstall${C_RESET}   → desinstala DeepSeek Harness"
  printf '%s\n' ""
  info "Nota: con npm 11+ es normal ver un aviso 'allow-scripts'. En Linux no"
  info "afecta: el paquete ya incluye todos los binarios nativos precompilados."
  printf '%s\n' ""
  warn "Si 'dsh' no se reconoce aún, abre una terminal nueva o ejecuta: source ~/.bashrc"
}

# --------------------------- main -------------------------------------------
main() {
  banner
  info "Detectando sistema: $(uname -s) / $(uname -m)"
  need_cmd tar
  need_cmd mktemp

  export PATH="$BIN_DIR:$PATH"
  hash -r 2>/dev/null || true

  if node_ok; then
    ok "Node.js $(node --version 2>/dev/null || echo '?') ya está instalado (npm $(npm --version 2>/dev/null || echo '?'))."
  else
    warn "Node.js no encontrado o demasiado antiguo (se necesita >= ${NODE_MIN_MAJOR})."
    install_node
    export PATH="$BIN_DIR:$PATH"
    hash -r 2>/dev/null || true
  fi

  ensure_path
  install_dsh
  verify
  create_launchers
  summary
}

main "$@"
