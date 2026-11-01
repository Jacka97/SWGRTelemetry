package main

import (
	"bufio"
	"os"
	"sort"
	"strconv"
	"strings"
)

// ---------- Key \t value files (preferences, event names, records typed in by hand) ----------

type keyValues map[string]string

func loadKeyValues(path string) keyValues {
	values := keyValues{}
	file, err := os.Open(path)
	if err != nil {
		return values
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		if key, value, found := strings.Cut(scanner.Text(), "\t"); found {
			values[key] = strings.TrimRight(value, "\r")
		}
	}
	return values
}

func saveKeyValues(path string, values keyValues) error {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	var text strings.Builder
	for _, key := range keys {
		text.WriteString(key + "\t" + values[key] + "\n")
	}
	temporaryPath := path + ".tmp"
	if err := os.WriteFile(temporaryPath, []byte(text.String()), 0644); err != nil {
		return err
	}
	os.Remove(path)
	return os.Rename(temporaryPath, path)
}

// ---------- App settings (app.ini) ----------

type appSettings struct {
	AttemptsToKeep int  // attempts kept per event (the best ones are always kept)
	Compress       bool // compress old sessions
}

const appSettingsText = "; Ajustes de la app de telemetría\n" +
	"; attempts_to_keep: cuántos intentos se conservan con telemetría por evento (los de tus mejores tiempos y sectores se guardan siempre)\n" +
	"; compress: true para comprimir las sesiones antiguas y ocupar menos\n"

func loadAppSettings(modFolder string) appSettings {
	settings := appSettings{AttemptsToKeep: 100, Compress: true}
	path := modFilePath(modFolder, "app.ini")
	file, err := os.Open(path)
	if err != nil {
		os.WriteFile(path, []byte(appSettingsText+"attempts_to_keep=100\ncompress=true\n"), 0644)
		return settings
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		key, value, found := strings.Cut(strings.TrimSpace(scanner.Text()), "=")
		if !found {
			continue
		}
		switch strings.TrimSpace(key) {
		case "attempts_to_keep":
			if number, err := strconv.Atoi(strings.TrimSpace(value)); err == nil && number >= 5 && number != 50 {
				settings.AttemptsToKeep = number // 50 was the default before 0.9.29: it becomes 100
			}
		case "compress":
			settings.Compress = strings.TrimSpace(value) != "false"
		}
	}
	return settings
}

// app.ini from version 0.9.17 and earlier had Spanish keys (intentos, comprimir): rewritten with the new ones
func translateAppSettings(modFolder string) {
	path := modFilePath(modFolder, "app.ini")
	content, err := os.ReadFile(path)
	if err != nil || (!strings.Contains(string(content), "intentos=") && !strings.Contains(string(content), "comprimir=")) {
		return
	}
	attempts, compress := "100", "true"
	for _, line := range strings.Split(string(content), "\n") {
		key, value, found := strings.Cut(strings.TrimSpace(line), "=")
		if !found {
			continue
		}
		switch strings.TrimSpace(key) {
		case "intentos", "attempts_to_keep":
			attempts = strings.TrimSpace(value)
			if attempts == "50" {
				attempts = "100"
			}
		case "comprimir", "compress":
			compress = strings.TrimSpace(value)
		}
	}
	os.WriteFile(path, []byte(appSettingsText+"attempts_to_keep="+attempts+"\ncompress="+compress+"\n"), 0644)
}
