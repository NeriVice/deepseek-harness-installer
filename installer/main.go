package main

import (
	"bufio"
	_ "embed"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

// install-dsh.ps1 se incrusta en el ejecutable final.
//
//go:embed install-dsh.ps1
var installScript []byte

func main() {
	if runtime.GOOS != "windows" {
		fmt.Println("Este instalador solo puede ejecutarse en Windows.")
		fmt.Println("En Linux/macOS instale DeepSeek Harness con:")
		fmt.Println("    npm install -g @deepseek-ai/dsh")
		os.Exit(1)
	}

	fmt.Println("==========================================================")
	fmt.Println("  Instalador de DeepSeek Harness (Windows)")
	fmt.Println("  Instala siempre la ultima version del CLI oficial")
	fmt.Println("==========================================================")
	fmt.Println()

	ps, err := exec.LookPath("powershell.exe")
	if err != nil {
		fmt.Println("ERROR: no se encontro PowerShell (se requiere Windows 10 o superior).")
		pause()
		os.Exit(1)
	}

	dir, err := os.MkdirTemp("", "dsh-installer")
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		pause()
		os.Exit(1)
	}
	defer os.RemoveAll(dir)

	script := filepath.Join(dir, "install-dsh.ps1")

	// Normaliza el BOM UTF-8 para que PowerShell 5.1 lea el script correctamente,
	// independientemente de como se haya guardado el archivo fuente.
	b := installScript
	if len(b) >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF {
		b = b[3:]
	}
	data := append([]byte{0xEF, 0xBB, 0xBF}, b...)

	if err := os.WriteFile(script, data, 0o644); err != nil {
		fmt.Printf("ERROR al preparar el instalador: %v\n", err)
		pause()
		os.Exit(1)
	}

	args := append([]string{"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script}, os.Args[1:]...)
	if len(os.Args) == 1 {
		args = append(args, "-Mode", "Install")
	}

	cmd := exec.Command(ps, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	err = cmd.Run()
	code := 0
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			code = ee.ExitCode()
		} else {
			fmt.Printf("ERROR al ejecutar PowerShell: %v\n", err)
			code = 1
		}
	}

	fmt.Println()
	if code == 0 {
		fmt.Println("El instalador ha terminado correctamente.")
	} else {
		fmt.Printf("El instalador termino con errores (codigo %d).\n", code)
	}
	pause()
	os.Exit(code)
}

func pause() {
	fmt.Print("Presione ENTER para cerrar...")
	_, _ = bufio.NewReader(os.Stdin).ReadString('\n')
}
