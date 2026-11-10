//go:build windows

package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"unicode/utf16"
	"unsafe"

	webview2 "github.com/jchv/go-webview2"
)

const informationIcon = 0x40

func messageBox(title, text string) {
	user32 := syscall.NewLazyDLL("user32.dll")
	showMessageBox := user32.NewProc("MessageBoxW")
	titleText, _ := syscall.UTF16PtrFromString(title)
	messageText, _ := syscall.UTF16PtrFromString(text)
	showMessageBox.Call(0, uintptr(unsafe.Pointer(messageText)), uintptr(unsafe.Pointer(titleText)), informationIcon)
}

// Opens the app in its own window (WebView2, the same engine as Edge).
// If it is not available, it opens in the browser; it still does not use the internet.
func openWindow(url, title string) {
	removeGarbledDataFolder()
	dataPath := ""
	if localData := os.Getenv("LOCALAPPDATA"); localData != "" {
		dataPath = filepath.Join(localData, "GalacticRacerTelemetry") // WebView2's cache, outside the mod folder
	}
	window := webview2.NewWithOptions(webview2.WebViewOptions{
		AutoFocus: true,
		DataPath:  dataPath,
		WindowOptions: webview2.WindowOptions{
			Title:  title,
			Width:  1440,
			Height: 920,
			IconId: 1, // the app's own icon (rsrc_windows_amd64.syso, made from icon/app.ico)
			Center: true,
		},
	})
	if window == nil {
		exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
		messageBox(title, "La app se ha abierto en tu navegador. Sigue funcionando solo en este PC, sin internet.\nThe app has opened in your browser. It still runs only on this PC, offline.\n\nPulsa Aceptar para cerrarla / Click OK to close it.")
		os.Exit(0)
	}
	defer window.Destroy()
	window.SetSize(1440, 920, webview2.HintNone)
	// La página pide el color de la barra de título al aplicar el tema (el de acento, con texto que se lea)
	window.Bind("setTitleBarColor", func(caption, text string) { setTitleBarColor(uintptr(window.Window()), caption, text) })
	window.Navigate(url)
	window.Run()
}

// Barra de título del color del tema (Windows 11: DWMWA_CAPTION_COLOR y DWMWA_TEXT_COLOR).
// En Windows 10 no existe y se queda la barra normal. dwmapi.dll se carga de System32 a propósito:
// en la carpeta del juego hay otro dwmapi.dll, el de UE4SS.
func setTitleBarColor(window uintptr, caption, text string) {
	dwmapi := syscall.NewLazyDLL(filepath.Join(os.Getenv("SystemRoot"), "System32", "dwmapi.dll"))
	setAttribute := dwmapi.NewProc("DwmSetWindowAttribute")
	if window == 0 || setAttribute.Find() != nil {
		return
	}
	for _, pair := range []struct {
		attribute uintptr
		color     string
	}{{35, caption}, {36, text}} {
		if value, ok := colorReference(pair.color); ok {
			setAttribute.Call(window, pair.attribute, uintptr(unsafe.Pointer(&value)), 4)
		}
	}
}

// colorReference turns "#rrggbb" into the COLORREF of Windows (0x00bbggrr).
func colorReference(hex string) (uint32, bool) {
	hex = strings.TrimPrefix(strings.TrimSpace(hex), "#")
	if len(hex) != 6 {
		return 0, false
	}
	value, err := strconv.ParseUint(hex, 16, 32)
	if err != nil {
		return 0, false
	}
	red, green, blue := uint32(value>>16)&0xff, uint32(value>>8)&0xff, uint32(value)&0xff
	return red | green<<8 | blue<<16, true
}

// Opens the File Explorer with the file selected
func revealFile(path string) { exec.Command("explorer", "/select,", path).Start() }

// WebView2 used to leave its cache (EBWebView) in a folder whose name is the mod folder's path read
// as UTF-16 (Chinese-looking characters) inside the mod folder. It is removed if it is there.
func removeGarbledDataFolder() {
	executable, err := os.Executable()
	if err != nil {
		return
	}
	folder := filepath.Dir(executable)
	raw := []byte(folder)
	if len(raw)%2 == 1 {
		raw = raw[:len(raw)-1]
	}
	units := make([]uint16, len(raw)/2)
	for index := range units {
		units[index] = uint16(raw[2*index]) | uint16(raw[2*index+1])<<8
	}
	garbled := filepath.Join(folder, string(utf16.Decode(units)))
	if info, err := os.Stat(filepath.Join(garbled, "EBWebView")); err == nil && info.IsDir() {
		os.RemoveAll(garbled)
	}
}
