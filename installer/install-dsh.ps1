#Requires -Version 5.1
<#
.SYNOPSIS
  Instalador automatico de DeepSeek Harness (dsh) para Windows.
  Instala SIEMPRE la ultima version disponible del CLI oficial @deepseek-ai/dsh.

.DESCRIPTION
  - Instala Node.js LTS si no existe o es demasiado antiguo.
  - Ejecuta "npm install -g @deepseek-ai/dsh@latest" (siempre la ultima version).
  - Crea accesos directos para abrir la interfaz web, actualizar y desinstalar.

.PARAMETER Mode
  Install (por defecto), Update o Uninstall.

.PARAMETER NodeMinVersion
  Version minima de Node.js requerida (por defecto 22.19.0).

.PARAMETER SkipNode
  No comprobar ni instalar Node.js.
#>

[CmdletBinding()]
param(
    [ValidateSet('Install', 'Update', 'Uninstall')]
    [string]$Mode = 'Install',

    [string]$NodeMinVersion = '22.19.0',

    [switch]$SkipNode
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# TLS 1.2 para descargas desde nodejs.org / registry.npmjs.org
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$ProductName = 'DeepSeek Harness'
$NpmPackage  = '@deepseek-ai/dsh'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'DeepSeekHarness'
$LogFile     = Join-Path $InstallRoot 'install.log'

function Write-Log {
    param([string]$Message, [ConsoleColor]$Color = 'White')
    $line = ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
    try {
        Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
    } catch { }
    Write-Host $Message -ForegroundColor $Color
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-NodeArch {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { return 'arm64' }
    return 'x64'
}

function Refresh-PathFromRegistry {
    # Une la PATH de maquina y de usuario desde el registro en la sesion actual.
    $paths = @()
    try {
        $m = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name Path -ErrorAction SilentlyContinue).Path
        if ($m) { $paths += $m }
    } catch { }
    try {
        $u = (Get-ItemProperty 'HKCU:\Environment' -Name Path -ErrorAction SilentlyContinue).Path
        if ($u) { $paths += $u }
    } catch { }
    if ($paths.Count -gt 0) {
        $env:Path = ($paths -join ';')
    }
}

function Get-InstalledNodeVersion {
    try {
        $v = & node --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) {
            $s = ($v -join '').Trim().TrimStart('v')
            $ver = $null
            if ([version]::TryParse($s, [ref]$ver)) { return $ver }
        }
    } catch { }
    return $null
}

function Install-NodeLts {
    Write-Log 'Buscando la ultima version LTS de Node.js...'
    $index = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -UseBasicParsing
    $lts = $index |
        Where-Object { $_.lts } |
        Sort-Object { [version]($_.version -replace '^v', '') } -Descending |
        Select-Object -First 1
    if (-not $lts) { throw 'No se pudo determinar la ultima version LTS de Node.js.' }

    $ver  = $lts.version
    $arch = Get-NodeArch
    $msi  = "node-$ver-$arch.msi"
    $url  = "https://nodejs.org/dist/$ver/$msi"
    $dest = Join-Path $env:TEMP $msi

    Write-Log ("Descargando {0} ..." -f $msi)
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($url, $dest)
    } catch {
        throw ("Error al descargar Node.js: {0}" -f $_.Exception.Message)
    }

    Write-Log 'Instalando Node.js (esto puede tardar un poco)...'
    $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', ("`"{0}`"" -f $dest), '/qn', '/norestart') -Wait -PassThru
    Remove-Item $dest -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0) {
        throw ("La instalacion de Node.js fallo (codigo {0})." -f $p.ExitCode)
    }
    Refresh-PathFromRegistry
    Write-Log ("Node.js {0} instalado." -f $ver)
}

function Invoke-NpmInstallLatest {
    Write-Log ("Instalando {0} (ultima version)... " -f $NpmPackage)
    $env:NO_UPDATE_NOTIFIER = '1'

    # npm 11+ bloquea por defecto los scripts de instalacion de los paquetes.
    # @deepseek-ai/dsh depende de modulos nativos (node-pty, koffi, etc.) cuyos
    # scripts hay que permitir explicitamente para que queden bien instalados.
    $allowScripts = '@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs'
    $npmMajor = 0
    $npmVer = & npm --version 2>$null | Select-Object -First 1
    if ($npmVer -and ($npmVer -match '^(\d+)')) { $npmMajor = [int]$Matches[1] }

    if ($npmMajor -ge 11) {
        & npm install -g ("--allow-scripts={0}" -f $allowScripts) ("{0}@latest" -f $NpmPackage) 2>&1 | Tee-Object -FilePath $LogFile -Append
        $code = $LASTEXITCODE
        if ($code -ne 0) {
            # Por si una version futura de npm cambia la opcion, se reintenta sin ella.
            Write-Log 'Reintentando sin --allow-scripts...'
            & npm install -g ("{0}@latest" -f $NpmPackage) 2>&1 | Tee-Object -FilePath $LogFile -Append
            $code = $LASTEXITCODE
        }
    } else {
        & npm install -g ("{0}@latest" -f $NpmPackage) 2>&1 | Tee-Object -FilePath $LogFile -Append
        $code = $LASTEXITCODE
    }

    if ($code -ne 0) {
        throw ("npm no pudo instalar {0} (codigo {1})." -f $NpmPackage, $code)
    }
}

function Get-DshVersion {
    # 1) Mediante el shim "dsh" en la PATH.
    try {
        $v = & dsh --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) {
            return (($v | ForEach-Object { [string]$_ }) -join ' ').Trim()
        }
    } catch { }
    # 2) Mediante node + la ruta del paquete instalado.
    try {
        $root = & npm root -g 2>$null | Select-Object -First 1
        if ($root) {
            $bin = Join-Path $root.Trim() ('@deepseek-ai\dsh\lib\bin.js')
            if (Test-Path $bin) {
                $v = & node $bin --version 2>$null
                if ($LASTEXITCODE -eq 0 -and $v) {
                    return (($v | ForEach-Object { [string]$_ }) -join ' ').Trim()
                }
            }
        }
    } catch { }
    return $null
}

function New-Shortcut {
    param(
        [string]$Path,
        [string]$TargetPath,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [string]$Description
    )
    $ws = New-Object -ComObject WScript.Shell
    $s = $ws.CreateShortcut($Path)
    $s.TargetPath = $TargetPath
    if ($Arguments)      { $s.Arguments = $Arguments }
    if ($WorkingDirectory) { $s.WorkingDirectory = $WorkingDirectory }
    if ($Description)    { $s.Description = $Description }
    $s.Save()
}

function Write-Launchers {
    # Persiste este mismo script para poder Actualizar/Desinstalar despues.
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
        $dest = Join-Path $InstallRoot 'install-dsh.ps1'
        $srcResolved  = (Resolve-Path $PSCommandPath).Path
        $destResolved = $null
        if (Test-Path $dest) { $destResolved = (Resolve-Path $dest).Path }
        if ($srcResolved -ne $destResolved) {
            Copy-Item $PSCommandPath $dest -Force
        }
    }

    $web = Join-Path $InstallRoot 'dsh-web.cmd'
    @'
@echo off
where dsh >nul 2>nul
if errorlevel 1 (
    echo DeepSeek Harness no esta en el PATH. Vuelva a ejecutar el instalador.
    pause
    exit /b 1
)
call dsh web %*
'@ | Set-Content -Path $web -Encoding ASCII

    return $web
}

function Write-Shortcuts {
    $web = Write-Launchers
    $startMenu = [Environment]::GetFolderPath('StartMenu')
    $desktop   = [Environment]::GetFolderPath('DesktopDirectory')
    $ps     = 'powershell.exe'
    $script = Join-Path $InstallRoot 'install-dsh.ps1'
    $updArgs = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode Update' -f $script)
    $uniArgs = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode Uninstall' -f $script)

    New-Shortcut -Path (Join-Path $startMenu 'DeepSeek Harness.lnk') -TargetPath $web -Description 'Abrir DeepSeek Harness (interfaz web)'
    New-Shortcut -Path (Join-Path $startMenu 'Actualizar DeepSeek Harness.lnk') -TargetPath $ps -Arguments $updArgs -Description 'Instalar la ultima version de DeepSeek Harness'
    New-Shortcut -Path (Join-Path $startMenu 'Desinstalar DeepSeek Harness.lnk') -TargetPath $ps -Arguments $uniArgs -Description 'Desinstalar DeepSeek Harness'

    try {
        New-Shortcut -Path (Join-Path $desktop 'DeepSeek Harness.lnk') -TargetPath $web -Description 'Abrir DeepSeek Harness (interfaz web)'
    } catch { }
}

function Invoke-Uninstall {
    Write-Log 'Desinstalando DeepSeek Harness...'
    & npm uninstall -g $NpmPackage 2>&1 | Tee-Object -FilePath $LogFile -Append
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Write-Log ("Aviso: npm uninstall termino con codigo {0}." -f $code) -Color Yellow
    } else {
        Write-Log 'DeepSeek Harness desinstalado.'
    }

    $targets = @(
        (Join-Path ([Environment]::GetFolderPath('StartMenu')) 'DeepSeek Harness.lnk'),
        (Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Actualizar DeepSeek Harness.lnk'),
        (Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Desinstalar DeepSeek Harness.lnk'),
        (Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'DeepSeek Harness.lnk')
    )
    foreach ($p in $targets) {
        Remove-Item $p -Force -ErrorAction SilentlyContinue
    }
    Write-Log 'Accesos directos eliminados. El perfil de usuario (~/.dsh) se conserva.'
}

# ---------------------------------------------------------------------------
# Flujo principal
# ---------------------------------------------------------------------------
try {
    if (-not (Test-Path $InstallRoot)) {
        New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
    }

    if ($Mode -eq 'Uninstall') {
        if (-not (Test-Admin)) {
            $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ("`"{0}`"" -f $PSCommandPath))
            foreach ($k in $PSBoundParameters.Keys) {
                $v = $PSBoundParameters[$k]
                if ($v -is [switch]) {
                    if ($v) { $argList += "-$k" }
                } else {
                    $argList += "-$k"; $argList += [string]$v
                }
            }
            $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList -PassThru
            $p.WaitForExit()
            exit $p.ExitCode
        }
        Invoke-Uninstall
        Write-Log 'Listo.'
        exit 0
    }

    # Auto-elevacion (UAC) para instalar Node.js a nivel de sistema y escribir
    # en el prefijo global de npm sin problemas de permisos.
    if (-not (Test-Admin)) {
        Write-Log 'Se requieren permisos de administrador. Solicitando elevacion (UAC)...'
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ("`"{0}`"" -f $PSCommandPath))
        foreach ($k in $PSBoundParameters.Keys) {
            $v = $PSBoundParameters[$k]
            if ($v -is [switch]) {
                if ($v) { $argList += "-$k" }
            } else {
                $argList += "-$k"; $argList += [string]$v
            }
        }
        $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList -PassThru
        $p.WaitForExit()
        exit $p.ExitCode
    }

    Write-Log ("{0} - modo {1}" -f $ProductName, $Mode)

    if (-not $SkipNode) {
        $nodeVer = Get-InstalledNodeVersion
        $min = [version]$NodeMinVersion
        if (-not $nodeVer -or ($nodeVer -lt $min)) {
            if ($nodeVer) {
                Write-Log ("Node.js {0} es demasiado antiguo (se necesita {1} o superior). Instalando la ultima LTS..." -f $nodeVer, $min)
            } else {
                Write-Log 'Node.js no esta instalado. Instalando la ultima LTS...'
            }
            Install-NodeLts
        } else {
            Write-Log ("Node.js {0} detectado." -f $nodeVer)
        }
    }

    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'No se encontro node. La instalacion no puede continuar.' }
    if (-not (Get-Command npm  -ErrorAction SilentlyContinue)) { throw 'No se encontro npm. La instalacion no puede continuar.' }

    Invoke-NpmInstallLatest

    $dshVer = Get-DshVersion
    if ($dshVer) {
        Write-Log ("DeepSeek Harness instalado: {0}" -f $dshVer) -Color Green
    } else {
        Write-Log 'DeepSeek Harness instalado (no se pudo leer la version).' -Color Green
    }

    Write-Shortcuts

    Write-Log ''
    Write-Log 'Instalacion completada.' -Color Green
    Write-Log 'Para empezar, abra "DeepSeek Harness" desde el menu Inicio o el escritorio,'
    Write-Log 'o ejecute en una terminal:  dsh web'
    Write-Log 'La interfaz web se abre en http://127.0.0.1:3080'
    Write-Log ("Registro de instalacion: {0}" -f $LogFile)
    exit 0
}
catch {
    Write-Log ("ERROR: {0}" -f $_.Exception.Message) -Color Red
    Write-Log ("Revise el registro en: {0}" -f $LogFile)
    exit 1
}
