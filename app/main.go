// Galactic Racer Telemetry: a local app that reads the files of the SWGR Telemetry mod.
// It never connects to the internet: it serves a page only for this PC (127.0.0.1) and shows it
// in its own window.
package main

import (
	"fmt"
	"net"
	"net/http"
	"os"
	"time"
)

// The app and the mod always carry the same version number (both will become 1.0 together)
const appVersion = "0.9.31"

// Version of the mod this app goes with (the app warns when the mod's is a different one)
const expectedModVersion = appVersion

func main() {
	modFolder := findModFolder()
	app := &server{modFolder: modFolder}
	if modFolder != "" {
		migrateOldFiles(modFolder, app.logf)
		sortIntoFolders(modFolder, app.logf)
		app.settings = loadAppSettings(modFolder)
		app.logf("Carpeta del mod: %s", modFolder)
		go func() {
			for {
				maintainTelemetry(modFolder, app.settings, app.logf)
				time.Sleep(2 * time.Minute)
			}
		}()
	} else {
		app.logf("No se encuentra la carpeta del mod SWGRTelemetry")
	}
	// Only reachable from this PC
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		fmt.Println("No se pudo iniciar:", err)
		os.Exit(1)
	}
	url := fmt.Sprintf("http://%s/", listener.Addr().String())
	go http.Serve(listener, app.routes())
	title := "Telemetría Galactic Racer"
	if modFolder != "" && isEnglishPage(loadKeyValues(modFilePath(modFolder, "preferences.txt"))["language"]) {
		title = "Galactic Racer Telemetry"
	}
	openWindow(url, title)
}

// The page is in Spanish (the original) or English; Aurebesh is written over the English page
func isEnglishPage(language string) bool { return language == "en" || language == "aurebesh" }
