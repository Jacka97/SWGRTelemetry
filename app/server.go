package main

import (
	"compress/gzip"
	"embed"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

//go:embed web/index.html web/index_en.html web/fonts/*.woff2
var webFiles embed.FS

// ---------- Local server ----------

type server struct {
	modFolder string
	settings  appSettings
	log       []string
	logLock   sync.Mutex
}

func (app *server) logf(format string, arguments ...any) {
	message := time.Now().Format("15:04:05 ") + fmt.Sprintf(format, arguments...)
	app.logLock.Lock()
	app.log = append(app.log, message)
	if len(app.log) > 200 {
		app.log = app.log[len(app.log)-200:]
	}
	app.logLock.Unlock()
	fmt.Println(message)
}

// A path inside the mod folder, from a relative path sent by the page (never outside the folder)
func (app *server) safePath(relativePath string) (string, bool) {
	clean := filepath.Clean(filepath.FromSlash(relativePath))
	if filepath.IsAbs(clean) || strings.HasPrefix(clean, "..") {
		return "", false
	}
	return filepath.Join(app.modFolder, clean), true
}

func readSmallFile(path string) string {
	content, err := os.ReadFile(path)
	if err != nil || len(content) > 1<<16 {
		return ""
	}
	return strings.TrimSpace(string(content))
}

func writeJSON(writer http.ResponseWriter, value any) {
	writer.Header().Set("Content-Type", "application/json; charset=utf-8")
	writer.Header().Set("Cache-Control", "no-store")
	json.NewEncoder(writer).Encode(value)
}

// Files whose changes make the page reload its data: the summaries (written when a lap or an event
// closes) and the files saved by hand. The telemetry written during the race does not cause reloads.
var watchedFileNames = map[string]bool{
	"event_records.txt": true, "eventos.txt": true, "manual_game_records.txt": true, "records_juego.txt": true,
	"game_records.txt": true, "records_auto.txt": true, "event_names.txt": true, "nombres.txt": true,
	"safe_mode.txt": true, "modo_seguro.txt": true,
}

// Change stamp: the most recent modification time of the watched files of the mod
// The stamp changes when a summary or a watched file is written, and also when a telemetry or route
// file appears, moves or disappears: the app itself moves the loose sessions of a new circuit into
// tracks\<circuit> and compresses long ones (.csv -> .csv.gz), and an open page must then reload
// the data, or it would keep asking for the files where they were.
func (app *server) changeStamp() int64 {
	var latest int64
	var telemetryFiles uint64
	filepath.WalkDir(app.modFolder, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if entry.IsDir() && (entry.Name() == "Scripts" || entry.Name() == "shared" || entry.Name() == "compartir") {
			return filepath.SkipDir
		}
		name := entry.Name()
		if !entry.IsDir() && (strings.HasSuffix(name, ".csv") || strings.HasSuffix(name, ".csv.gz")) {
			pathHash := fnv.New64a()
			pathHash.Write([]byte(path))
			telemetryFiles += pathHash.Sum64() // a sum, so the order of the walk does not matter
		}
		if !entry.IsDir() && (strings.HasSuffix(name, "_summary.txt") || strings.HasSuffix(name, "_resumen.txt") || watchedFileNames[name] || strings.HasSuffix(name, ".swgr")) {
			if info, err := entry.Info(); err == nil && info.ModTime().UnixNano() > latest {
				latest = info.ModTime().UnixNano()
			}
		}
		return nil
	})
	return latest ^ int64(telemetryFiles)
}

func onlyPost(handler http.HandlerFunc) http.HandlerFunc {
	return func(writer http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodPost {
			http.Error(writer, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		handler(writer, request)
	}
}

func (app *server) routes() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/" {
			http.NotFound(writer, request)
			return
		}
		page := "web/index.html"
		if app.modFolder != "" && isEnglishPage(loadKeyValues(modFilePath(app.modFolder, "preferences.txt"))["language"]) {
			page = "web/index_en.html"
		}
		content, _ := webFiles.ReadFile(page)
		writer.Header().Set("Content-Type", "text/html; charset=utf-8")
		writer.Header().Set("Cache-Control", "no-store")
		writer.Write(content)
	})
	// Free fonts (OFL) built into the app for the Galactic Racer theme
	mux.HandleFunc("/app-fonts/", func(writer http.ResponseWriter, request *http.Request) {
		name := filepath.Base(request.URL.Path)
		content, err := webFiles.ReadFile("web/fonts/" + name)
		if err != nil || !strings.HasSuffix(name, ".woff2") {
			http.NotFound(writer, request)
			return
		}
		writer.Header().Set("Content-Type", "font/woff2")
		writer.Header().Set("Cache-Control", "max-age=86400")
		writer.Write(content)
	})
	mux.HandleFunc("/api/data", func(writer http.ResponseWriter, request *http.Request) {
		if app.modFolder == "" {
			writeJSON(writer, map[string]any{"error": "modFolderNotFound"})
			return
		}
		sessions := scanSessions(app.modFolder)
		if sessions == nil {
			sessions = []*Session{} // no races yet: an empty list, not null
		}
		friends := loadFriends(app.modFolder)
		writeRivals(app.modFolder, friends)
		writeFriendGhosts(app.modFolder, friends)
		writeJSON(writer, map[string]any{
			"modFolder":          app.modFolder,
			"version":            appVersion,
			"attemptsToKeep":     app.settings.AttemptsToKeep,
			"sessions":           sessions,
			"eventRecords":       loadKeyValues(modFilePath(app.modFolder, "event_records.txt")),
			"manualGameRecords":  loadKeyValues(modFilePath(app.modFolder, "manual_game_records.txt")),
			"gameRecords":        loadKeyValues(modFilePath(app.modFolder, "game_records.txt")),
			"eventNames":         loadKeyValues(modFilePath(app.modFolder, "event_names.txt")),
			"preferences":        loadKeyValues(modFilePath(app.modFolder, "preferences.txt")),
			"changeStamp":        app.changeStamp(),
			"friends":            friends,
			"modVersion":         modVersion(app.modFolder),
			"expectedModVersion": expectedModVersion,
			"safeMode":           readSmallFile(modFilePath(app.modFolder, "safe_mode.txt")),
		})
	})
	// Fonts the user puts in the mod's fonts folder (they are not built into the app)
	mux.HandleFunc("/fonts/", func(writer http.ResponseWriter, request *http.Request) {
		name := filepath.Base(strings.TrimPrefix(request.URL.Path, "/fonts/"))
		contentTypes := map[string]string{".ttf": "font/ttf", ".otf": "font/otf", ".woff": "font/woff", ".woff2": "font/woff2"}
		contentType, known := contentTypes[strings.ToLower(filepath.Ext(name))]
		if !known || name == "." || name == ".." {
			http.NotFound(writer, request)
			return
		}
		content, err := os.ReadFile(filepath.Join(modFilePath(app.modFolder, "fonts"), name))
		if err != nil {
			http.NotFound(writer, request)
			return
		}
		writer.Header().Set("Content-Type", contentType)
		writer.Header().Set("Cache-Control", "max-age=3600")
		writer.Write(content)
	})
	mux.HandleFunc("/api/change-stamp", func(writer http.ResponseWriter, request *http.Request) {
		writeJSON(writer, map[string]any{"changeStamp": app.changeStamp()})
	})
	mux.HandleFunc("/api/file", func(writer http.ResponseWriter, request *http.Request) {
		path, allowed := app.safePath(request.URL.Query().Get("path"))
		if !allowed {
			http.Error(writer, "invalid path", http.StatusBadRequest)
			return
		}
		file, err := os.Open(path)
		if err != nil {
			http.Error(writer, "not found", http.StatusNotFound)
			return
		}
		defer file.Close()
		var reader io.Reader = file
		if strings.HasSuffix(path, ".gz") {
			decompressor, err := gzip.NewReader(file)
			if err != nil {
				http.Error(writer, "damaged file", http.StatusInternalServerError)
				return
			}
			defer decompressor.Close()
			reader = decompressor
		}
		writer.Header().Set("Content-Type", "text/plain; charset=utf-8")
		writer.Header().Set("Cache-Control", "no-store")
		io.Copy(writer, reader)
	})
	// Saves a game record typed in by hand, an event name or a preference
	mux.HandleFunc("/api/save", onlyPost(func(writer http.ResponseWriter, request *http.Request) {
		var save struct {
			Kind  string `json:"kind"`
			Key   string `json:"key"`
			Value string `json:"value"`
		}
		if err := json.NewDecoder(io.LimitReader(request.Body, 1<<16)).Decode(&save); err != nil || save.Key == "" {
			http.Error(writer, "invalid data", http.StatusBadRequest)
			return
		}
		fileName := map[string]string{"manualGameRecord": "manual_game_records.txt", "eventName": "event_names.txt", "preference": "preferences.txt"}[save.Kind]
		if fileName == "" || strings.ContainsAny(save.Key+save.Value, "\t\n\r") {
			http.Error(writer, "invalid data", http.StatusBadRequest)
			return
		}
		path := modFilePath(app.modFolder, fileName)
		values := loadKeyValues(path)
		if strings.TrimSpace(save.Value) == "" {
			delete(values, save.Key)
		} else {
			values[save.Key] = strings.TrimSpace(save.Value)
		}
		if err := saveKeyValues(path, values); err != nil {
			http.Error(writer, "No se pudo guardar / could not save: "+err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSON(writer, map[string]any{"ok": true})
	}))
	// Pilot files: export yours, add or remove your friends'
	mux.HandleFunc("/api/export-pilot", onlyPost(func(writer http.ResponseWriter, request *http.Request) {
		content, _ := io.ReadAll(io.LimitReader(request.Body, 32<<20))
		header, err := checkPilotFile(content)
		if err != nil {
			http.Error(writer, err.Error(), http.StatusBadRequest)
			return
		}
		content = addRaceGhosts(app.modFolder, content)
		folder := filepath.Join(app.modFolder, "shared")
		os.MkdirAll(folder, 0o755)
		path := filepath.Join(folder, pilotFileName(header.pilotName()))
		if err := os.WriteFile(path, content, 0o644); err != nil {
			http.Error(writer, "No se pudo guardar / could not save: "+err.Error(), http.StatusInternalServerError)
			return
		}
		app.logf("Archivo de piloto exportado: %s", path)
		revealFile(path)
		writeJSON(writer, map[string]any{"ok": true, "path": path})
	}))
	mux.HandleFunc("/api/add-friend", onlyPost(func(writer http.ResponseWriter, request *http.Request) {
		content, _ := io.ReadAll(io.LimitReader(request.Body, 32<<20))
		header, err := checkPilotFile(content)
		if err != nil {
			http.Error(writer, err.Error(), http.StatusBadRequest)
			return
		}
		folder := filepath.Join(app.modFolder, "friends")
		os.MkdirAll(folder, 0o755)
		if err := os.WriteFile(filepath.Join(folder, pilotFileName(header.pilotName())), content, 0o644); err != nil {
			http.Error(writer, "No se pudo guardar / could not save: "+err.Error(), http.StatusInternalServerError)
			return
		}
		writeJSON(writer, map[string]any{"ok": true, "pilot": header.pilotName()})
	}))
	mux.HandleFunc("/api/remove-friend", onlyPost(func(writer http.ResponseWriter, request *http.Request) {
		var remove struct {
			Pilot string `json:"pilot"`
		}
		if json.NewDecoder(io.LimitReader(request.Body, 1<<12)).Decode(&remove) != nil || remove.Pilot == "" {
			http.Error(writer, "invalid data", http.StatusBadRequest)
			return
		}
		os.Remove(filepath.Join(app.modFolder, "friends", pilotFileName(remove.Pilot)))
		writeJSON(writer, map[string]any{"ok": true})
	}))
	// "Try again": deletes safe_mode.txt; the mod tries everything again the next time the game opens
	mux.HandleFunc("/api/retry-safe-mode", onlyPost(func(writer http.ResponseWriter, request *http.Request) {
		for _, path := range []string{modFilePath(app.modFolder, "safe_mode.txt"), filepath.Join(app.modFolder, "safe_mode.txt"), filepath.Join(app.modFolder, "modo_seguro.txt")} {
			if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
				http.Error(writer, err.Error(), http.StatusInternalServerError)
				return
			}
		}
		writeJSON(writer, map[string]any{"ok": true})
	}))
	mux.HandleFunc("/api/quit", func(writer http.ResponseWriter, request *http.Request) {
		writeJSON(writer, map[string]any{"ok": true})
		go func() { time.Sleep(300 * time.Millisecond); os.Exit(0) }()
	})
	return mux
}
