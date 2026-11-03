# Instalador automático de DeepSeek Harness (Linux)

Instalador para **Linux** que instala [DeepSeek Harness (`dsh`)](https://github.com/deepseek-ai/deepseek-harness)
— el harness de agentes de IA de DeepSeek AI — y siempre deja la **última
versión disponible**.

> DeepSeek Harness es el CLI oficial `@deepseek-ai/dsh` publicado en npm. Se
> ejecuta como interfaz web con `dsh web` (por defecto en
> `http://127.0.0.1:3080`). En Linux el paquete ya incluye **todos los binarios
> nativos precompilados** (node-pty, koffi, sharp, sherpa-onnx…), por lo que no
> hace falta compilador ni `sudo`.

## Qué hace el instalador

Al ejecutar `install-dsh.sh` se realiza, de forma automática:

1. **Comprueba Node.js.** Si no está instalado o es anterior a 18, descarga e
   instala la **última versión LTS** de Node en `~/.local` (sin `sudo`, sirve
   para cualquier distribución y arquitectura x64/arm64).
2. **Instala la última versión de DeepSeek Harness** con
   `npm install -g @deepseek-ai/dsh@latest`. El tag `@latest` garantiza que
   siempre se obtenga la versión más reciente publicada por DeepSeek.
3. **Crea accesos directos y ayudantes:**
   - `deepseek-harness` → lanzador que abre `dsh web`.
   - `dsh-update` → actualiza a la última versión.
   - `dsh-uninstall` → desinstala DeepSeek Harness.
   - Entrada de escritorio `DeepSeek Harness` en el menú de aplicaciones.

## Cómo usarlo

### Opción A — One-liner (recomendado)

Copia y pega una sola línea en la terminal de tu Linux:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/NeriVice/deepseek-harness-installer/main/install-dsh.sh)
```

### Opción B — Descargar el script y ejecutarlo

```bash
curl -fsSL -o install-dsh.sh https://raw.githubusercontent.com/NeriVice/deepseek-harness-installer/main/install-dsh.sh
bash install-dsh.sh
```

Repositorio: <https://github.com/NeriVice/deepseek-harness-installer>

### Después de instalar

Abre una terminal nueva (para que el PATH se recargue) y ejecuta:

```bash
dsh web
```

Luego abre en el navegador **http://127.0.0.1:3080**. La primera vez te pedirá
configurar tu API key de DeepSeek desde la propia interfaz.

También puedes lanzarlo desde el menú de aplicaciones buscando
**DeepSeek Harness**.

### Mantenerlo siempre actualizado

```bash
dsh-update
```

(equivale a `npm install -g @deepseek-ai/dsh@latest`, es decir, siempre la
última versión).

### Desinstalar

```bash
dsh-uninstall
```

> `dsh-uninstall` quita el CLI y los accesos creados, pero **no** elimina
> Node.js (por si lo usas para otras cosas).

## Requisitos

- Linux (x64 o arm64).
- `curl` (o `wget`) y `tar`.
- Conexión a internet (para `nodejs.org` y `registry.npmjs.org`).

Node.js lo gestiona el propio instalador; no necesitas instalarlo antes.

## Nota sobre el aviso de `allow-scripts` (npm 11+)

Con npm 11 o superior es normal ver un aviso como:

```
npm warn allow-scripts 5 packages have install scripts not yet covered by allowScripts:
```

**Es inofensivo en Linux.** Ese aviso se refiere a scripts de instalación de
módulos nativos que, en Linux, no son necesarios porque DeepSeek Harness ya
distribuye los binarios precompilados para `linux-x64` y `linux-arm64`
(verificado: `dsh web` arranca correctamente sin ejecutarlos).

## Estructura del proyecto

```
install-dsh.sh        # ← instalador de Linux (el que necesitas)
README.md
installer/
  install-dsh.ps1     # instalador de Windows (PowerShell)
  main.go             # envoltura .exe de Windows (Go)
  go.mod
build.sh              # recompila los .exe de Windows
install-dsh.cmd       # alternativa .cmd de Windows
dist/                 # artefactos generados (exe + instalador Linux)
```

> Los archivos de Windows (`installer/`, `build.sh`, `install-dsh.cmd`, y los
> `.exe` de `dist/`) se conservan por si en algún momento los necesitas, pero
> **el instalador principal de este proyecto es `install-dsh.sh` (Linux)**.

## Aviso

Este proyecto es una utilidad de instalación de la comunidad. No está afiliado,
respaldado ni mantenido por DeepSeek. DeepSeek Harness es software de
[DeepSeek AI](https://github.com/deepseek-ai/deepseek-harness) (licencia MIT).
Revisa su [aviso de seguridad](https://github.com/deepseek-ai/deepseek-harness/blob/master/SAFETY.md)
antes de usarlo.
