package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
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

// ---------- Panel en carrera: timing_panel.ini del mod (clave=valor, con comentarios «;») ----------

// timingPanelKeys: las claves que la app puede cambiar, en el orden en que se escriben
var timingPanelKeys = []string{"enabled", "style", "x", "y", "scale", "opacity", "last_lap", "best_lap", "ideal_lap", "event_total", "target",
	"previous_sectors", "compare_with", "live_difference", "sector_bars", "speeds", "forecast",
	"color_background", "color_top_bar", "color_title", "color_label", "color_text", "color_dim", "color_best", "color_better", "color_worse", "color_gain", "color_loss"}

var timingPanelValue = regexp.MustCompile(`^[#A-Za-z0-9._-]{0,16}$`)

func readTimingPanel(path string) map[string]string {
	values := map[string]string{}
	data, err := os.ReadFile(path)
	if err != nil {
		return values
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, ";") {
			continue
		}
		if key, value, found := strings.Cut(line, "="); found {
			values[strings.TrimSpace(key)] = strings.TrimSpace(value)
		}
	}
	return values
}

// saveTimingPanel junta los valores nuevos con los del archivo y lo vuelve a escribir con su explicación
func saveTimingPanel(path string, changes map[string]string) error {
	allowed := map[string]bool{}
	for _, key := range timingPanelKeys {
		allowed[key] = true
	}
	values := readTimingPanel(path)
	for key, value := range changes {
		if !allowed[key] || !timingPanelValue.MatchString(value) {
			return fmt.Errorf("valor no válido: %s", key)
		}
		values[key] = value
	}
	var text strings.Builder
	text.WriteString("; Panel de tiempos del mod SWGR Telemetry · timing panel of the SWGR Telemetry mod\n")
	text.WriteString("; Se cambia desde la app (Opciones > Panel en carrera) y se aplica en la siguiente carrera\n")
	text.WriteString("; style: sith o compact · x, y: posición de 0 a 1 (0,0 = arriba a la izquierda) · scale: tamaño · opacity: fondo de 0 a 1\n")
	text.WriteString("; color_*: colores en #RRGGBB (vacío = los del estilo; color_top_bar=none quita la barra de arriba)\n")
	written := map[string]bool{}
	for _, key := range timingPanelKeys {
		if value, found := values[key]; found {
			text.WriteString(key + "=" + value + "\n")
			written[key] = true
		}
	}
	for key, value := range values { // las que no conoce la app se conservan
		if !written[key] {
			text.WriteString(key + "=" + value + "\n")
		}
	}
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(text.String()), 0644)
}
