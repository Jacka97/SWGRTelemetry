package main

import (
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// ---------- Finding the mod folder ----------

var defaultModFolders = []string{
	`C:\Program Files (x86)\Steam\steamapps\common\STAR WARS Galactic Racer\Griffin\Binaries\Win64\ue4ss\Mods\SWGRTelemetry`,
	`D:\SteamLibrary\steamapps\common\STAR WARS Galactic Racer\Griffin\Binaries\Win64\ue4ss\Mods\SWGRTelemetry`,
}

func looksLikeModFolder(folder string) bool {
	for _, name := range []string{"tracks", "circuitos", "event_records.txt", "eventos.txt", "best_times.txt", "bests.txt", filepath.Join("Scripts", "main.lua")} {
		if _, err := os.Stat(filepath.Join(folder, name)); err == nil {
			return true
		}
	}
	return false
}

func findModFolder() string {
	if len(os.Args) > 1 && looksLikeModFolder(os.Args[1]) {
		return os.Args[1]
	}
	if executable, err := os.Executable(); err == nil {
		folder := filepath.Dir(executable)
		if looksLikeModFolder(folder) {
			return folder
		}
	}
	if workingFolder, err := os.Getwd(); err == nil && looksLikeModFolder(workingFolder) {
		return workingFolder
	}
	for _, folder := range defaultModFolders {
		if looksLikeModFolder(folder) {
			return folder
		}
	}
	return ""
}

var modVersionPattern = regexp.MustCompile(`local VERSION = '([^']+)'`)

// Version of the installed mod, read from its main.lua ("" if there is none)
func modVersion(modFolder string) string {
	content, err := os.ReadFile(filepath.Join(modFolder, "Scripts", "main.lua"))
	if err != nil {
		return ""
	}
	if match := modVersionPattern.FindSubmatch(content); match != nil {
		return string(match[1])
	}
	return ""
}

// versionAtLeast("0.9.18", "0.9.17") == true; parts are compared as numbers
func versionAtLeast(version, minimum string) bool {
	have, want := strings.Split(version, "."), strings.Split(minimum, ".")
	for index := 0; index < len(want); index++ {
		haveNumber, wantNumber := 0, 0
		if index < len(have) {
			haveNumber, _ = strconv.Atoi(have[index])
		}
		wantNumber, _ = strconv.Atoi(want[index])
		if haveNumber != wantNumber {
			return haveNumber > wantNumber
		}
	}
	return true
}

// ---------- Files and folders renamed in 0.9.18 (their names used to be in Spanish) ----------

// First version whose files have English names
const firstEnglishFilesVersion = "0.9.18"

// Files written by the mod: they are only renamed when the installed mod is a version that uses the
// new names (an older mod would keep writing the old ones). Until then the app reads the old names.
var modFilesOldNames = map[string]string{
	"log.txt":                    "registro.txt",
	"best_times.txt":             "bests.txt",
	"learned_tracks.txt":         "metas.txt",
	"ghosts.txt":                 "fantasmas.txt",
	"event_records.txt":          "eventos.txt",
	"game_records.txt":           "records_auto.txt",
	"safe_mode.txt":              "modo_seguro.txt",
	"operation_in_progress.txt":  "en_curso.txt",
	"diagnostics.txt":            "diag.txt",
	"record_search.txt":          "busqueda_records.txt",
	"record_search_progress.txt": "busqueda_progreso.txt",
}

// Files and folders that only the app writes: always renamed
var appFilesOldNames = map[string]string{
	"manual_game_records.txt": "records_juego.txt",
	"event_names.txt":         "nombres.txt",
	"friends":                 "amigos",
	"shared":                  "compartir",
	"fonts":                   "fuentes",
}

// Preferences: old key -> new key, and the old values of each key
var preferenceOldKeys = map[string]string{"tema": "theme", "holograma": "hologram", "animaciones": "animations", "idioma": "language",
	"piloto": "pilot_name", "color": "color", "novedades": "seen_changes_version"}
var preferenceOldValues = map[string]map[string]string{
	"hologram":   {"no": "off", "suave": "soft", "si": "normal", "fuerte": "strong"},
	"animations": {"si": "on", "no": "off"},
}

// Folders of the mod folder (0.9.29): settings, data the mod and the app keep, logs and diagnostics,
// and the long documents. The main folder keeps only the app, enabled.txt, a short guide and folders.
var fileFolders = map[string]string{
	"preferences.txt": "config", "timing_panel.ini": "config", "hud.ini": "config", "app.ini": "config",
	"best_times.txt": "data", "learned_tracks.txt": "data", "ghosts.txt": "data", "event_records.txt": "data",
	"game_records.txt": "data", "rivals.txt": "data", "event_names.txt": "data", "manual_game_records.txt": "data",
	"log.txt": "logs", "diagnostics.txt": "logs", "safe_mode.txt": "logs", "operation_in_progress.txt": "logs",
	"record_search.txt": "logs", "record_search_progress.txt": "logs", "state_samples.txt": "logs",
	"README.txt": "docs", "PRUEBAS.txt": "docs", "README_EN.txt": "docs", "README_app.txt": "docs", "README_app_EN.txt": "docs",
	"FONT_LICENSE_OFL.txt": "docs", "LICENCIA_FUENTES_OFL.txt": "docs", "TESTING.txt": "docs", "TESTING_EN.txt": "docs",
}

// sortIntoFolders moves the files of the main folder into their folder (once; nothing is overwritten)
func sortIntoFolders(modFolder string, logf func(string, ...any)) {
	moved := 0
	for name, folder := range fileFolders {
		target := filepath.Join(modFolder, folder)
		os.MkdirAll(target, 0o755)
		oldPath, newPath := filepath.Join(modFolder, name), filepath.Join(target, name)
		if !exists(oldPath) {
			continue
		}
		if !exists(newPath) {
			if os.Rename(oldPath, newPath) == nil {
				moved++
			}
		} else if strings.HasPrefix(name, "README") || strings.HasPrefix(name, "TESTING") || name == "FONT_LICENSE_OFL.txt" {
			os.Remove(oldPath) // an older copy of a document
		}
	}
	if moved > 0 {
		logf("Archivos ordenados en carpetas (config, data, logs, docs): %d", moved)
	}
	guide := filepath.Join(modFolder, "LEEME - README.txt")
	if !exists(guide) {
		os.WriteFile(guide, []byte(shortGuide), 0o644)
	}
}

const shortGuide = "SWGR Telemetry\r\n\r\n" +
	"ES  Abre GalacticRacerTelemetry.exe para ver tu telemetría. Las guías completas están en docs\\.\r\n" +
	"    config\\ ajustes · data\\ tus récords y mejores tiempos · logs\\ registro y diagnósticos\r\n" +
	"    tracks\\ telemetría de cada circuito · race_ghosts\\ fantasmas · friends\\ archivos de tus amigos\r\n" +
	"    shared\\ tu archivo para pasar · Scripts\\ el mod. Solo para jugar OFFLINE.\r\n\r\n" +
	"EN  Open GalacticRacerTelemetry.exe to see your telemetry. The full guides are in docs\\.\r\n" +
	"    config\\ settings · data\\ your records and best times · logs\\ log and diagnostics\r\n" +
	"    tracks\\ telemetry of each circuit · race_ghosts\\ ghosts · friends\\ your friends' files\r\n" +
	"    shared\\ your file to pass on · Scripts\\ the mod. For OFFLINE play only.\r\n"

// Path of a file of the mod folder: in its folder (0.9.29), or where older versions left it
func modFilePath(modFolder, name string) string {
	path := filepath.Join(modFolder, name)
	if folder, found := fileFolders[name]; found {
		inFolder := filepath.Join(modFolder, folder, name)
		if exists(inFolder) || !exists(path) {
			path = inFolder
		}
	}
	if _, err := os.Stat(path); err == nil {
		return path
	}
	for _, oldNames := range []map[string]string{modFilesOldNames, appFilesOldNames} {
		if oldName, found := oldNames[name]; found {
			oldPath := filepath.Join(modFolder, oldName)
			if _, err := os.Stat(oldPath); err == nil {
				return oldPath
			}
		}
	}
	return path
}

// Whether two files have exactly the same bytes (false if either cannot be read)
func sameContent(firstPath, secondPath string) bool {
	first, firstError := os.ReadFile(firstPath)
	second, secondError := os.ReadFile(secondPath)
	return firstError == nil && secondError == nil && string(first) == string(second)
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// Renames the files of older versions. It can run many times: what is already renamed is left alone.
func migrateOldFiles(modFolder string, logf func(string, ...any)) {
	renamed := 0
	rename := func(oldPath, newPath string) {
		if exists(oldPath) && !exists(newPath) {
			if err := os.Rename(oldPath, newPath); err == nil {
				renamed++
			} else {
				logf("No se pudo renombrar %s: %v", oldPath, err)
			}
		}
	}
	// Preferences: new file name, keys and values
	if oldPath := filepath.Join(modFolder, "preferencias.txt"); exists(oldPath) {
		newPath := filepath.Join(modFolder, "preferences.txt")
		preferences := loadKeyValues(newPath)
		for oldKey, value := range loadKeyValues(oldPath) {
			newKey := preferenceOldKeys[oldKey]
			if newKey == "" {
				newKey = oldKey
			}
			if newValue, found := preferenceOldValues[newKey][value]; found {
				value = newValue
			}
			if _, alreadySet := preferences[newKey]; !alreadySet {
				preferences[newKey] = value
			}
		}
		if saveKeyValues(newPath, preferences) == nil {
			os.Remove(oldPath)
			renamed++
		}
	}
	// Event names and records typed in by hand: events never identified were "TRAZADO:<track>", now "TRACK:<track>"
	for _, names := range [][2]string{{"nombres.txt", "event_names.txt"}, {"records_juego.txt", "manual_game_records.txt"}} {
		oldPath, newPath := filepath.Join(modFolder, names[0]), filepath.Join(modFolder, names[1])
		if !exists(oldPath) || exists(newPath) {
			continue
		}
		values := keyValues{}
		for key, value := range loadKeyValues(oldPath) {
			values[strings.Replace(key, "TRAZADO:", "TRACK:", 1)] = value
		}
		if saveKeyValues(newPath, values) == nil {
			os.Remove(oldPath)
			renamed++
		}
	}
	for newName, oldName := range appFilesOldNames {
		oldPath, newPath := filepath.Join(modFolder, oldName), filepath.Join(modFolder, newName)
		if info, err := os.Stat(oldPath); err == nil && info.IsDir() && exists(newPath) {
			// The new package already brought the new folder (fonts/, for example): the old one is emptied into it
			entries, _ := os.ReadDir(oldPath)
			for _, entry := range entries {
				oldEntry, newEntry := filepath.Join(oldPath, entry.Name()), filepath.Join(newPath, entry.Name())
				if sameContent(oldEntry, newEntry) {
					os.Remove(oldEntry) // an identical copy is already in the new folder
					continue
				}
				rename(oldEntry, newEntry)
			}
			os.Remove(oldPath) // only if it is empty now
			continue
		}
		rename(oldPath, newPath)
	}
	// Pilot files: piloto_<name>.swgr -> pilot_<name>.swgr (their content is still read as it is)
	for _, folder := range []string{"friends", "shared"} {
		entries, _ := os.ReadDir(filepath.Join(modFolder, folder))
		for _, entry := range entries {
			if strings.HasPrefix(entry.Name(), "piloto_") && strings.HasSuffix(entry.Name(), ".swgr") {
				rename(filepath.Join(modFolder, folder, entry.Name()), filepath.Join(modFolder, folder, "pilot_"+strings.TrimPrefix(entry.Name(), "piloto_")))
			}
		}
	}
	translateAppSettings(modFolder)
	removeReplacedFiles(modFolder)
	if installed := modVersion(modFolder); installed == "" || versionAtLeast(installed, firstEnglishFilesVersion) {
		for newName, oldName := range modFilesOldNames {
			rename(filepath.Join(modFolder, oldName), filepath.Join(modFolder, newName))
		}
		renamed += migrateTrackFolders(modFolder, logf)
	}
	if renamed > 0 {
		logf("Archivos de versiones anteriores pasados a los nombres nuevos: %d", renamed)
	}
}

var (
	oldSummaryName = regexp.MustCompile(`^(\d{8}_\d{6})_resumen\.txt$`)
)

// circuitos/ -> tracks/, and inside each track: ruta.csv -> route.csv, historial.txt -> history.txt,
// <date>_resumen.txt -> <date>_summary.txt. The sessions of the first versions, saved loose in the
// mod folder (telemetria_<date>_<track>.*, ruta_<track>.csv), move into their track's folder.
func migrateTrackFolders(modFolder string, logf func(string, ...any)) int {
	moved := 0
	move := func(oldPath, newPath string) {
		if err := os.Rename(oldPath, newPath); err == nil {
			moved++
		} else {
			logf("No se pudo mover %s: %v", oldPath, err)
		}
	}
	tracksFolder := filepath.Join(modFolder, "tracks")
	oldTracksFolder := filepath.Join(modFolder, "circuitos")
	if exists(oldTracksFolder) {
		if !exists(tracksFolder) {
			move(oldTracksFolder, tracksFolder)
		} else {
			// Both exist: each track folder (or its files) goes into tracks/
			tracks, _ := os.ReadDir(oldTracksFolder)
			for _, track := range tracks {
				oldTrack, newTrack := filepath.Join(oldTracksFolder, track.Name()), filepath.Join(tracksFolder, track.Name())
				if !exists(newTrack) {
					move(oldTrack, newTrack)
					continue
				}
				files, _ := os.ReadDir(oldTrack)
				for _, file := range files {
					if !exists(filepath.Join(newTrack, file.Name())) {
						move(filepath.Join(oldTrack, file.Name()), filepath.Join(newTrack, file.Name()))
					}
				}
				os.Remove(oldTrack) // only if it is empty now
			}
			os.Remove(oldTracksFolder)
		}
	}
	tracks, _ := os.ReadDir(tracksFolder)
	for _, track := range tracks {
		if !track.IsDir() {
			continue
		}
		folder := filepath.Join(tracksFolder, track.Name())
		// The route is written again at every race: the old file is only kept if there is no new one
		if oldRoute := filepath.Join(folder, "ruta.csv"); exists(oldRoute) {
			if exists(filepath.Join(folder, "route.csv")) {
				os.Remove(oldRoute)
			} else {
				move(oldRoute, filepath.Join(folder, "route.csv"))
			}
		}
		// The history only grows: the old lines go before the new ones
		if oldHistory := filepath.Join(folder, "historial.txt"); exists(oldHistory) {
			newHistory := filepath.Join(folder, "history.txt")
			if !exists(newHistory) {
				move(oldHistory, newHistory)
			} else if oldContent, err := os.ReadFile(oldHistory); err == nil {
				newContent, _ := os.ReadFile(newHistory)
				if os.WriteFile(newHistory, append(oldContent, newContent...), 0o644) == nil {
					os.Remove(oldHistory)
					moved++
				}
			}
		}
		files, _ := os.ReadDir(folder)
		for _, file := range files {
			if match := oldSummaryName.FindStringSubmatch(file.Name()); match != nil {
				newPath := filepath.Join(folder, match[1]+"_summary.txt")
				if !exists(newPath) {
					move(filepath.Join(folder, file.Name()), newPath)
				}
			}
		}
	}
	// Loose sessions of the first versions
	moved += moveLooseSessions(modFolder, logf)
	return moved
}

// Documents and the app's executable from older versions, left behind when the new package is copied
// over the old one. They are deleted once their replacement is there.
var replacedFiles = map[string]string{
	"LEEME.txt": "README.txt", "LEEME_app.txt": "README_app.txt", "PRUEBAS.txt": "TESTING.txt", "LEEME_demo.txt": "README_demo.txt",
	"LICENCIA_FUENTES_OFL.txt": "FONT_LICENSE_OFL.txt", "TelemetriaGalacticRacer.exe": "GalacticRacerTelemetry.exe",
}

func removeReplacedFiles(modFolder string) {
	running := ""
	if executable, err := os.Executable(); err == nil {
		running = filepath.Base(executable)
	}
	for oldName, newName := range replacedFiles {
		if oldName != running && exists(filepath.Join(modFolder, newName)) {
			os.Remove(filepath.Join(modFolder, oldName))
		}
	}
}

var (
	looseSessionFile = regexp.MustCompile(`^(?:telemetry|telemetria)_(\d{8}_\d{6})_(.+?)(\.csv|\.csv\.gz|_summary\.txt|_resumen\.txt)$`)
	looseRouteFile   = regexp.MustCompile(`^(?:route|ruta)_(.+)\.csv$`)
)

// How long a loose session must go without changes before it is moved: the mod may still be writing it
const looseSessionQuietTime = 5 * time.Minute

// Sessions saved loose in the mod folder go into their track's folder (tracks/<track>/). The mod writes
// them there the first time a track is raced, because creating a folder from the game would open a
// system window for a moment, and that takes a full-screen game out of full screen. The app creates
// the folder instead; from then on the mod writes into it. The first versions of the mod also saved
// their sessions loose, with Spanish names (telemetria_<date>_<track>.*, ruta_<track>.csv).
func moveLooseSessions(modFolder string, logf func(string, ...any)) int {
	moved := 0
	tracksFolder := filepath.Join(modFolder, "tracks")
	rootFiles, _ := os.ReadDir(modFolder)
	quiet := func(name string) bool {
		info, err := os.Stat(filepath.Join(modFolder, name))
		return err == nil && time.Since(info.ModTime()) >= looseSessionQuietTime
	}
	// A session is moved only when none of its files has changed for a while
	sessionIsQuiet := map[string]bool{}
	for _, file := range rootFiles {
		if match := looseSessionFile.FindStringSubmatch(file.Name()); match != nil {
			stamp := match[1]
			if _, seen := sessionIsQuiet[stamp]; !seen {
				sessionIsQuiet[stamp] = true
			}
			sessionIsQuiet[stamp] = sessionIsQuiet[stamp] && quiet(file.Name())
		}
	}
	move := func(oldPath, newPath string) {
		if err := os.Rename(oldPath, newPath); err == nil {
			moved++
		} else {
			logf("No se pudo mover %s: %v", oldPath, err)
		}
	}
	for _, file := range rootFiles {
		match := looseSessionFile.FindStringSubmatch(file.Name())
		if match == nil || !sessionIsQuiet[match[1]] {
			continue
		}
		stamp, track, kind := match[1], match[2], match[3]
		folder := filepath.Join(tracksFolder, track)
		if os.MkdirAll(folder, 0o755) != nil {
			continue
		}
		newName := stamp + strings.Replace(kind, "_resumen.txt", "_summary.txt", 1)
		if !exists(filepath.Join(folder, newName)) {
			move(filepath.Join(modFolder, file.Name()), filepath.Join(folder, newName))
		}
	}
	for _, file := range rootFiles {
		match := looseRouteFile.FindStringSubmatch(file.Name())
		if match == nil || !quiet(file.Name()) {
			continue
		}
		folder := filepath.Join(tracksFolder, match[1])
		newRoute := filepath.Join(folder, "route.csv")
		if exists(newRoute) {
			os.Remove(filepath.Join(modFolder, file.Name())) // an older copy of the same route: the mod writes it again at every race
		} else if os.MkdirAll(folder, 0o755) == nil {
			move(filepath.Join(modFolder, file.Name()), newRoute)
		}
	}
	return moved
}
