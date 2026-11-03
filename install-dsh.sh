#!/usr/bin/env bash
# =============================================================================
#  DeepSeek Harness — Instalador automático para Linux
#  ---------------------------------------------------------------------------
#  Instala SIEMPRE la última versión de DeepSeek Harness (`@deepseek-ai/dsh`)
#  y se asegura de que haya un Node.js compatible.
#
#  IMPORTANTE: DeepSeek Harness necesita Node.js >= 22.19. Con Node 18 o 20
#  (los que traen Ubuntu/Mint por defecto) npm deja instalar el paquete, pero
#  después `dsh` no arranca: salen avisos EBADENGINE ("Unsupported engine") y
#  errores de sintaxis. Este instalador comprueba la versión de Node y, si no
#  sirve, descarga la última LTS en ~/.local (sin sudo). Además todos los
#  lanzadores usan la ruta absoluta de ese Node, para que el orden del PATH
#  (nvm, apt, etc.) no vuelva a romper la instalación.
#
#  Uso:
#      bash install-dsh.sh
#
#  Requisitos: curl (o wget) y tar. Acceso a internet.
# =============================================================================
set -euo pipefail

DSH_PACKAGE="@deepseek-ai/dsh"
NODE_MIN_VERSION="22.19.0"
INSTALL_DIR="${DSH_INSTALL_DIR:-$HOME/.local}"   # raíz de la instalación local
BIN_DIR="$INSTALL_DIR/bin"
DESKTOP_DIR="$INSTALL_DIR/share/applications"

# Rutas que se resuelven durante la ejecución
NODE_BIN=""
NPM_BIN=""
DSH_JS=""
TMP_DIR=""

cleanup() { [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# --------------------------- salida con colores -------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""
fi
info() { printf '%s\n' "${C_CYAN}[*]${C_RESET} $*"; }
ok()   { printf '%s\n' "${C_GREEN}[✓]${C_RESET} $*"; }
warn() { printf '%s\n' "${C_YELLOW}[!]${C_RESET} $*" >&2; }
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

# version_ge A B  ->  cierto si A >= B (versiones tipo 22.19.0)
version_ge() {
  local -a a b
  local i x y
  IFS=. read -r -a a <<< "${1:-0}"
  IFS=. read -r -a b <<< "${2:-0}"
  for i in 0 1 2; do
    x="${a[$i]:-0}"; y="${b[$i]:-0}"
    # Sólo comparamos la parte numérica inicial (por si llega algo como 22.19.0-rc1)
    x="${x%%[!0-9]*}"; y="${y%%[!0-9]*}"
    x="${x:-0}"; y="${y:-0}"
    if [ "$((10#$x))" -gt "$((10#$y))" ]; then return 0; fi
    if [ "$((10#$x))" -lt "$((10#$y))" ]; then return 1; fi
  done
  return 0
}

# --------------------------- Node.js ----------------------------------------
node_version() { # node_version <ruta-node>  ->  "24.11.0" (vacío si no sirve)
  [ -x "$1" ] || return 0
  "$1" --version 2>/dev/null | sed -n 's/^v\([0-9][0-9.]*\).*/\1/p' | head -n1
}

# select_node: deja en NODE_BIN/NPM_BIN un Node >= mínimo; falla si no hay.
select_node() {
  local cand dir path_npm
  NODE_BIN=""; NPM_BIN=""
  for cand in "$BIN_DIR/node" "$(command -v node 2>/dev/null || true)"; do
    [ -n "$cand" ] || continue
    [ -x "$cand" ] || continue
    version_ge "$(node_version "$cand")" "$NODE_MIN_VERSION" || continue
    dir="$(dirname "$cand")"
    if [ -x "$dir/npm" ]; then
      NODE_BIN="$cand"; NPM_BIN="$dir/npm"; return 0
    fi
    path_npm="$(command -v npm 2>/dev/null || true)"
    if [ -n "$path_npm" ]; then
      NODE_BIN="$cand"; NPM_BIN="$path_npm"; return 0
    fi
  done
  return 1
}

# Convierte index.json de nodejs.org en líneas "version<TAB>es_lts"
index_versions() {
  tr -d '\r\n' < "$1" \
    | sed 's/},{/}\n{/g' \
    | awk '{
        if (match($0, /"version": *"v[0-9]+\.[0-9]+\.[0-9]+"/)) {
          v = substr($0, RSTART, RLENGTH)
          sub(/.*"version": *"v/, "", v)
          sub(/".*/, "", v)
          lts = ($0 ~ /"lts": *"[A-Za-z]/) ? "1" : "0"
          print v "\t" lts
        }
      }'
}

# Devuelve la última versión LTS (o, si la LTS fuese más antigua que el mínimo,
# la última versión estable) que cumpla NODE_MIN_VERSION.
resolve_node_version() {
  local idx="$TMP_DIR/node-index.json" v l lts_v="" any_v=""
  if ! dl "https://nodejs.org/dist/index.json" "$idx" >/dev/null 2>&1; then
    return 1
  fi
  # index.json viene de más nueva a más antigua. Leemos todas las líneas (sin
  # break) para no cortar la tubería y evitar el aviso "Broken pipe" de awk.
  while IFS=$'\t' read -r v l; do
    [ -n "$v" ] || continue
    version_ge "$v" "$NODE_MIN_VERSION" || continue
    [ -n "$any_v" ] || any_v="$v"
    if [ -z "$lts_v" ] && [ "$l" = "1" ]; then lts_v="$v"; fi
  done < <(index_versions "$idx")

  if [ -n "$lts_v" ]; then
    printf '%s\n' "$lts_v"
  elif [ -n "$any_v" ]; then
    warn "La última LTS es anterior a ${NODE_MIN_VERSION}; usaré Node v${any_v}."
    printf '%s\n' "$any_v"
  else
    return 1
  fi
}

install_node() {
  local arch ver tarball url
  arch=$(arch_node)
  info "Resolviendo la última versión LTS de Node.js..."
  ver=$(resolve_node_version) || {
    fail "No pude resolver una versión de Node.js >= ${NODE_MIN_VERSION} (¿sin conexión a nodejs.org?)."
    exit 1
  }
  url="https://nodejs.org/dist/v${ver}/node-v${ver}-linux-${arch}.tar.gz"
  tarball="$TMP_DIR/node.tar.gz"
  info "Descargando Node.js v${ver} (linux-${arch})..."
  if ! dl "$url" "$tarball"; then
    rm -f "$tarball"
    fail "No pude descargar Node.js desde ${url}"
    if [ "$arch" = "armv7l" ]; then
      fail "Node.js moderno ya no publica binarios para armv7l. Instálalo a mano y vuelve a ejecutar este script."
    fi
    exit 1
  fi
  info "Instalando Node.js en ${INSTALL_DIR} ..."
  mkdir -p "$INSTALL_DIR"
  tar -xzf "$tarball" -C "$INSTALL_DIR" --strip-components=1
  rm -f "$tarball"
  if [ ! -x "$BIN_DIR/node" ]; then
    fail "La instalación de Node.js no dejó ${BIN_DIR}/node. Revisa los permisos de ${INSTALL_DIR}."
    exit 1
  fi
  ok "Node.js v${ver} instalado en ${BIN_DIR}."
}

# --------------------------- PATH -------------------------------------------
ensure_path() {
  local rc changed=0
  for rc in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    if grep -qF "$BIN_DIR" "$rc" 2>/dev/null; then
      continue
    fi
    printf '\n# DeepSeek Harness\nexport PATH="%s:$PATH"\n' "$BIN_DIR" >> "$rc"
    info "Añadido ${BIN_DIR} al PATH en ${rc}"
    changed=1
  done

  # Fish shell (si se usa)
  local fish="$HOME/.config/fish/config.fish"
  if [ -f "$fish" ] && ! grep -qF "$BIN_DIR" "$fish" 2>/dev/null; then
    printf '\n# DeepSeek Harness\nfish_add_path %s\n' "$BIN_DIR" >> "$fish"
    info "Añadido ${BIN_DIR} al PATH en ${fish}"
    changed=1
  fi

  # Si no había ningún archivo de perfil, creamos ~/.profile
  if [ ! -f "$HOME/.profile" ] && [ ! -f "$HOME/.bashrc" ] && [ ! -f "$HOME/.bash_profile" ] && [ ! -f "$HOME/.zshrc" ]; then
    printf 'export PATH="%s:$PATH"\n' "$BIN_DIR" > "$HOME/.profile"
    info "Creado ${HOME}/.profile con ${BIN_DIR} en el PATH"
    changed=1
  fi

  if [ "$changed" -eq 0 ]; then
    info "PATH ya configurado."
  fi
}

# --------------------------- instalación de DSH -----------------------------
install_dsh() {
  # En Linux, @deepseek-ai/dsh trae TODOS los binarios nativos precompilados
  # (node-pty, koffi, sharp, sherpa-onnx, etc.), por lo que un `npm install -g`
  # simple basta: no hacen falta compilador ni scripts de instalación.
  info "Instalando ${DSH_PACKAGE}@latest (siempre la última versión)..."
  mkdir -p "$BIN_DIR"
  # PATH con el Node elegido delante: así los scripts de npm usan el Node bueno.
  PATH="$(dirname "$NODE_BIN"):$BIN_DIR:$PATH" \
    "$NPM_BIN" install -g --prefix "$INSTALL_DIR" --no-audit --no-fund "$DSH_PACKAGE@latest"
}

# Devuelve la ruta real del bin.js de dsh instalado.
dsh_entry() {
  local p="$INSTALL_DIR/lib/node_modules/@deepseek-ai/dsh/lib/bin.js" root
  if [ -f "$p" ]; then printf '%s\n' "$p"; return 0; fi
  root=$("$NPM_BIN" root -g --prefix "$INSTALL_DIR" 2>/dev/null | tail -n1 || true)
  if [ -n "$root" ] && [ -f "$root/@deepseek-ai/dsh/lib/bin.js" ]; then
    printf '%s\n' "$root/@deepseek-ai/dsh/lib/bin.js"
    return 0
  fi
  return 1
}

# --------------------------- launchers --------------------------------------
create_launchers() {
  mkdir -p "$BIN_DIR" "$DESKTOP_DIR"

  # Lanzador de terminal: usa la ruta absoluta del Node validado.
  cat > "$BIN_DIR/deepseek-harness" <<EOF
#!/usr/bin/env bash
# Inicia DeepSeek Harness (interfaz web en http://127.0.0.1:3080)
set -e
NODE_BIN="$NODE_BIN"
DSH_JS="$DSH_JS"
if [ ! -x "\$NODE_BIN" ]; then
  NODE_BIN="\$(command -v node || true)"
fi
if [ -z "\$NODE_BIN" ] || [ ! -x "\$NODE_BIN" ]; then
  echo "No encuentro Node.js. Vuelve a ejecutar el instalador de DeepSeek Harness." >&2
  exit 1
fi
if [ ! -f "\$DSH_JS" ]; then
  echo "No encuentro DeepSeek Harness en \$DSH_JS. Vuelve a ejecutar el instalador." >&2
  exit 1
fi
exec "\$NODE_BIN" "\$DSH_JS" web "\$@"
EOF
  chmod +x "$BIN_DIR/deepseek-harness"

  # Actualizador
  cat > "$BIN_DIR/dsh-update" <<EOF
#!/usr/bin/env bash
set -e
NODE_BIN="$NODE_BIN"
NPM_BIN="$NPM_BIN"
INSTALL_DIR="$INSTALL_DIR"
DSH_JS="$DSH_JS"
echo "Actualizando DeepSeek Harness a la última versión..."
if [ ! -x "\$NPM_BIN" ]; then
  echo "No encuentro npm en \$NPM_BIN. Vuelve a ejecutar el instalador." >&2
  exit 1
fi
PATH="\$(dirname "\$NODE_BIN"):\$PATH" "\$NPM_BIN" install -g --prefix "\$INSTALL_DIR" --no-audit --no-fund $DSH_PACKAGE@latest
echo -n "Versión instalada: "
"\$NODE_BIN" "\$DSH_JS" --version
EOF
  chmod +x "$BIN_DIR/dsh-update"

  # Desinstalador
  cat > "$BIN_DIR/dsh-uninstall" <<EOF
#!/usr/bin/env bash
set -e
NODE_BIN="$NODE_BIN"
NPM_BIN="$NPM_BIN"
INSTALL_DIR="$INSTALL_DIR"
BIN_DIR="$BIN_DIR"
echo "Desinstalando DeepSeek Harness..."
if [ -x "\$NPM_BIN" ]; then
  PATH="\$(dirname "\$NODE_BIN"):\$PATH" "\$NPM_BIN" uninstall -g --prefix "\$INSTALL_DIR" $DSH_PACKAGE >/dev/null 2>&1 || true
fi
rm -f "\$BIN_DIR/deepseek-harness" "\$BIN_DIR/dsh-update" "\$BIN_DIR/dsh-uninstall"
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
  if [ ! -e "$BIN_DIR/dsh" ]; then
    fail "npm no creó el comando '${BIN_DIR}/dsh'."
    exit 1
  fi
  if ! DSH_JS="$(dsh_entry)"; then
    fail "No encuentro el paquete instalado de DeepSeek Harness."
    exit 1
  fi

  # Comprobación real: si dsh no arranca con este Node, no damos la instalación
  # por buena (esto es lo que fallaba con Node 18: EBADENGINE + crash).
  local out
  if ! out="$("$NODE_BIN" "$DSH_JS" --version 2>&1)"; then
    fail "DeepSeek Harness se instaló pero no arranca con Node $(node_version "$NODE_BIN")."
    printf '%s\n' "$out" | sed 's/^/    /' | head -n 20 >&2
    fail "Vuelve a ejecutar este instalador para reparar la instalación."
    exit 1
  fi
  ok "dsh instalado en: ${BIN_DIR}/dsh"
  ok "Versión: ${out:-desconocida}"

  local resolved
  resolved="$(command -v dsh 2>/dev/null || true)"
  if [ -n "$resolved" ] && [ "$resolved" != "$BIN_DIR/dsh" ]; then
    warn "Tu PATH resuelve 'dsh' a ${resolved} (otra instalación)."
    warn "Usa ${BIN_DIR}/dsh o abre una terminal nueva para que gane esta."
  fi
}

summary() {
  printf '\n%s\n' "${C_BOLD}${C_GREEN}¡Instalación completada!${C_RESET}"
  printf '%s\n' "Node.js usado: ${NODE_BIN} ($(node_version "$NODE_BIN"))"
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

  TMP_DIR="$(mktemp -d)" || { fail "No pude crear un directorio temporal."; exit 1; }

  export PATH="$BIN_DIR:$PATH"
  hash -r 2>/dev/null || true

  if select_node; then
    ok "Node.js v$(node_version "$NODE_BIN") detectado en ${NODE_BIN}"
  else
    warn "Node.js no encontrado o demasiado antiguo (se necesita >= ${NODE_MIN_VERSION})."
    if command -v node >/dev/null 2>&1; then
      warn "Versión en el PATH: v$(node_version "$(command -v node)") — se ignorará."
    fi
    install_node
    export PATH="$BIN_DIR:$PATH"
    hash -r 2>/dev/null || true
    select_node || { fail "No pude preparar un Node.js >= ${NODE_MIN_VERSION}."; exit 1; }
    ok "Node.js v$(node_version "$NODE_BIN") listo en ${NODE_BIN}"
  fi

  ensure_path
  install_dsh
  verify
  create_launchers
  summary
}

main "$@"
