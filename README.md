# Instalador automático de DeepSeek Harness (Windows)

Instalador ejecutable para Windows que instala **DeepSeek Harness (`dsh`)** — el
harness de agentes de IA de [DeepSeek AI](https://deepseek.com/harness) — y
siempre deja la **última versión disponible**.

> DeepSeek Harness es el CLI oficial `@deepseek-ai/dsh` publicado en npm. Se
> ejecuta como interfaz web con `dsh web` (por defecto en
> `http://127.0.0.1:3080`).

## Qué hace el instalador

Al ejecutar el `.exe` (o el script) se realiza, de forma automática:

1. **Comprueba Node.js.** Si no está instalado o es anterior a 22.0, descarga e
   instala silenciosamente la **última versión LTS** desde `nodejs.org`
   (x64 o arm64 según tu equipo).
2. **Instala la última versión de DeepSeek Harness** ejecutando
   `npm install -g @deepseek-ai/dsh@latest`. El tag `@latest` garantiza que
   siempre se obtenga la versión más reciente publicada por DeepSeek.
3. **Crea accesos directos:**
   - `DeepSeek Harness` (menú Inicio y escritorio) → abre `dsh web`.
   - `Actualizar DeepSeek Harness` → vuelve a instalar la última versión.
   - `Desinstalar DeepSeek Harness` → desinstala el CLI.

El instalador se ejecuta con permisos de administrador (UAC), necesarios para
instalar Node.js a nivel de sistema y escribir en el prefijo global de npm.

## Cómo usarlo

### Opción A — Ejecutable ya compilado (recomendado)

Descarga uno de los `.exe` de la carpeta `dist/` y haz doble clic:

| Archivo | Plataforma |
| --- | --- |
| `dist/DeepSeek-Harness-Setup-x64.exe` | Windows 10/11 de 64 bits (la mayoría) |
| `dist/DeepSeek-Harness-Setup-arm64.exe` | Windows 10/11 en ARM64 |

> **Nota de SmartScreen:** al ser un instalador sin firma digital, Windows puede
> mostrar «Protegió su PC». Pulsa **Más información → Ejecutar de todos modos**.

### Opción B — Script PowerShell / .cmd (sin compilar)

Si prefieres inspeccionar el código antes de ejecutarlo:

```bat
install-dsh.cmd
```

o directamente:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File installer\install-dsh.ps1
```

### Después de instalar

Abre **DeepSeek Harness** desde el menú Inicio o el escritorio, o escribe en una
terminal:

```bat
dsh web
```

Se abrirá la interfaz web en `http://127.0.0.1:3080`. La primera vez te pedirá
configurar tu API key de DeepSeek desde la propia interfaz.

### Mantenerlo siempre actualizado

Ejecuta el acceso directo **Actualizar DeepSeek Harness** (o vuelve a ejecutar el
instalador). Ambos repiten `npm install -g @deepseek-ai/dsh@latest`, por lo que
siempre instalan la versión más reciente.

También puedes actualizar manualmente desde una terminal:

```bat
npm install -g @deepseek-ai/dsh@latest
```

## Modos

```powershell
installer\install-dsh.ps1 -Mode Install    # instala / actualiza (por defecto)
installer\install-dsh.ps1 -Mode Update     # solo actualiza a la última versión
installer\install-dsh.ps1 -Mode Uninstall  # desinstala dsh (conserva ~/.dsh)
```

## Requisitos

- Windows 10 o Windows 11 (PowerShell 5.1 incluido).
- Conexión a internet (para `nodejs.org` y `registry.npmjs.org`).
- El instalador gestiona Node.js automáticamente; no necesitas instalarlo antes.

> Si estás detrás de un firewall o en una red que requiere un mirror de npm,
> configura el registro antes de ejecutar, por ejemplo:
> `npm config set registry https://registry.npmmirror.com`

## Registro de instalación

Todo lo que ocurre queda en:

```
%LOCALAPPDATA%\DeepSeekHarness\install.log
```

Si algo falla, abre ese archivo para ver el detalle.

## Recompilar el ejecutable (.exe)

El `.exe` se genera con **Go** (se compila en Linux/macOS/Windows sin
dependencias y produce un binario de Windows autocontenido). Requiere Go ≥ 1.20:

```bash
./build.sh            # genera x64 y arm64 en dist/
./build.sh x64        # solo x64
./build.sh arm64      # solo arm64
```

Estructura:

```
installer/
  main.go          # envoltura .exe: incrusta y ejecuta el script PowerShell
  install-dsh.ps1  # lógica real (Node + npm install @latest + accesos directos)
  go.mod
build.sh           # compila dist/DeepSeek-Harness-Setup-*.exe
install-dsh.cmd    # alternativa .cmd para ejecutar el script sin compilar
dist/              # ejecutables .exe generados
```

## Aviso

Este proyecto es una utilidad de instalación de la comunidad. No está afiliado,
respaldado ni mantenido por DeepSeek. DeepSeek Harness es software de
[DeepSeek AI](https://github.com/deepseek-ai/deepseek-harness) (licencia MIT).
Revisa su [aviso de seguridad](https://github.com/deepseek-ai/deepseek-harness/blob/master/SAFETY.md)
antes de usarlo.
