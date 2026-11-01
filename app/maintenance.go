package main

import (
	"bufio"
	"compress/gzip"
	"io"
	"math"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

// ---------- Maintenance: compress, and keep only the latest attempts ----------

var maintenanceLock sync.Mutex

func gzipFile(sourcePath string) error {
	input, err := os.Open(sourcePath)
	if err != nil {
		return err
	}
	defer input.Close()
	temporaryPath := sourcePath + ".gz.tmp"
	output, err := os.Create(temporaryPath)
	if err != nil {
		return err
	}
	compressor := gzip.NewWriter(output)
	if _, err := io.Copy(compressor, input); err != nil {
		compressor.Close()
		output.Close()
		os.Remove(temporaryPath)
		return err
	}
	if err := compressor.Close(); err != nil {
		output.Close()
		os.Remove(temporaryPath)
		return err
	}
	output.Close()
	input.Close()
	if err := os.Rename(temporaryPath, sourcePath+".gz"); err != nil {
		os.Remove(temporaryPath)
		return err
	}
	return os.Remove(sourcePath)
}

func maintainTelemetry(modFolder string, settings appSettings, logf func(string, ...any)) {
	maintenanceLock.Lock()
	defer maintenanceLock.Unlock()
	if moved := moveLooseSessions(modFolder, logf); moved > 0 {
		logf("Sesiones de circuitos nuevos pasadas a su carpeta: %d archivos", moved)
	}
	sessions := scanSessions(modFolder)
	sessionsByEvent := map[string][]*Session{}
	for _, session := range sessions {
		sessionsByEvent[session.Event] = append(sessionsByEvent[session.Event], session)
	}
	// Kept always (0.9.29): the attempts with your best total, best lap, best lap 1 (start) and each best
	// sector (of flying laps and of lap 1), so the ideal laps and the replays of your bests never lose
	// their telemetry. Summaries are never deleted: the times of every attempt stay for the history.
	alwaysKept := map[*Session]bool{}
	for event, eventSessions := range sessionsByEvent {
		arcade := strings.HasPrefix(event, "LDB_ARC")
		if arcade {
			for _, session := range protectedSessions(eventSessions) {
				alwaysKept[session] = true
			}
		}
		limit := settings.AttemptsToKeep
		if !arcade {
			limit = 20 // campaign and older races outside Arcade: only for looking at them
		}
		// the sessions are sorted from newest to oldest
		kept := 0
		for _, session := range eventSessions {
			if session.TelemetryFile == "" {
				continue
			}
			path := filepath.Join(modFolder, filepath.FromSlash(session.TelemetryFile))
			// Quick restarts of older versions (no lap done and no total): not attempts worth keeping
			if len(session.Laps) == 0 && session.Total == 0 && !alwaysKept[session] {
				if info, err := os.Stat(path); err == nil && time.Since(info.ModTime()) > 10*time.Minute {
					if os.Remove(path) == nil {
						for _, suffix := range summaryFileSuffixes {
							os.Remove(filepath.Join(modFolder, filepath.FromSlash(session.Folder), session.ID+suffix))
						}
						logf("Reinicio rápido %s %s eliminado", session.Event, session.ID)
					}
				}
				continue
			}
			kept++
			if kept > limit && !alwaysKept[session] {
				if err := os.Remove(path); err == nil {
					logf("Telemetría de %s %s eliminada (más de %d intentos)", session.Event, session.ID, limit)
				}
			}
		}
	}
	addBoostToGhosts(modFolder, sessions, logf)
	for _, name := range []string{"boost_samples.txt", "PRUEBAS.txt", "ghost_search.txt"} {
		os.Remove(filepath.Join(modFolder, name)) // diagnostics of earlier tests
	}
	if !settings.Compress {
		return
	}
	for _, session := range sessions {
		if session.TelemetryFile == "" || strings.HasSuffix(session.TelemetryFile, ".gz") {
			continue
		}
		path := filepath.Join(modFolder, filepath.FromSlash(session.TelemetryFile))
		info, err := os.Stat(path)
		if err != nil || time.Since(info.ModTime()) < 10*time.Minute {
			continue // the mod may still be writing it
		}
		if err := gzipFile(path); err != nil {
			logf("No se pudo comprimir %s: %v", session.TelemetryFile, err)
		}
	}
}

// protectedSessions are the attempts of an event that hold one of your bests.
func protectedSessions(sessions []*Session) []*Session {
	type best struct {
		time    float64
		session *Session
	}
	bests := map[string]*best{}
	note := func(key string, value float64, session *Session) {
		if value <= 0 {
			return
		}
		if current, found := bests[key]; !found || value < current.time {
			bests[key] = &best{value, session}
		}
	}
	for _, session := range sessions {
		if session.HasBuild || session.TelemetryFile == "" {
			continue
		}
		note("total", session.Total, session)
		for _, lap := range session.Laps {
			kind := "lap"
			if lap.Number == 1 && session.PlannedLaps > 1 {
				kind = "start"
			}
			if lap.Official {
				note(kind, lap.Time, session)
			}
			for index, sector := range lap.Sectors {
				note(kind+"|S"+strconv.Itoa(index+1), sector, session)
				if lap.Valid && !lap.Incident {
					note(kind+"|clean|S"+strconv.Itoa(index+1), sector, session)
				}
			}
		}
	}
	list := []*Session{}
	seen := map[*Session]bool{}
	for _, value := range bests {
		if !seen[value.session] {
			seen[value.session] = true
			list = append(list, value.session)
		}
	}
	return list
}

// addBoostToGhosts completes your race ghosts saved before they carried the boost: the ghost comes
// from one race, and that race's telemetry has the boost of every moment (mod 0.9.26 on). The race is
// found by its total; each ghost point takes the boost of the nearest telemetry sample. Done once per
// ghost (afterwards it has the column).
func addBoostToGhosts(modFolder string, sessions []*Session, logf func(string, ...any)) {
	paths, _ := filepath.Glob(filepath.Join(modFolder, "race_ghosts", "*.txt"))
	for _, path := range paths {
		name := filepath.Base(path)
		if strings.HasSuffix(name, ".friend.txt") || !strings.HasPrefix(name, "LDB_") {
			continue
		}
		content, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		lines := strings.Split(strings.ReplaceAll(string(content), "\r", ""), "\n")
		if len(lines) < 12 || len(strings.Split(lines[1], "\t")) != 7 {
			continue // already with boost, or without rotation (older ghosts)
		}
		total, _ := strconv.ParseFloat(strings.Split(lines[0], "\t")[0], 64)
		event := strings.TrimSuffix(name, ".txt")
		var source *Session
		for _, session := range sessions {
			if session.Event == event && session.TelemetryFile != "" && math.Abs(session.Total-total) < 0.0015 {
				source = session
				break
			}
		}
		if source == nil {
			continue
		}
		samples := readBoostSamples(filepath.Join(modFolder, filepath.FromSlash(source.TelemetryFile)))
		if len(samples) == 0 {
			continue
		}
		cursor, found := 0, 0
		for index := 1; index < len(lines); index++ {
			columns := strings.Split(lines[index], "\t")
			if len(columns) != 7 {
				continue
			}
			x, _ := strconv.ParseFloat(columns[1], 64)
			y, _ := strconv.ParseFloat(columns[2], 64)
			// the nearest sample, searching forward from the last match (the race goes forward)
			best, bestDistance := cursor, math.Inf(1)
			for candidate := cursor; candidate < len(samples) && candidate < cursor+400; candidate++ {
				distance := math.Hypot(samples[candidate].x-x, samples[candidate].y-y)
				if distance < bestDistance {
					best, bestDistance = candidate, distance
				}
			}
			cursor = best
			if bestDistance < 1500 { // within 15 m
				lines[index] += "\t" + samples[best].boost
				found++
			} else {
				lines[index] += "\t"
			}
		}
		if found*2 < len(lines) {
			continue // not that race after all
		}
		if os.WriteFile(path, []byte(strings.Join(lines, "\n")), 0o644) == nil {
			logf("Fantasma de %s completado con el boost de su carrera (%s)", event, source.ID)
		}
	}
}

type boostSample struct {
	x, y  float64
	boost string
}

func readBoostSamples(path string) []boostSample {
	file, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer file.Close()
	var reader io.Reader = file
	if strings.HasSuffix(path, ".gz") {
		decompressor, err := gzip.NewReader(file)
		if err != nil {
			return nil
		}
		defer decompressor.Close()
		reader = decompressor
	}
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 1<<16), 1<<20)
	if !scanner.Scan() {
		return nil
	}
	header := strings.Split(scanner.Text(), ",")
	column := func(name string) int {
		for index, value := range header {
			if value == name {
				return index
			}
		}
		return -1
	}
	xColumn, yColumn, boostColumn := column("x"), column("y"), column("boost")
	if xColumn < 0 || yColumn < 0 || boostColumn < 0 {
		return nil
	}
	samples := []boostSample{}
	for scanner.Scan() {
		columns := strings.Split(scanner.Text(), ",")
		if len(columns) <= boostColumn {
			continue
		}
		x, errX := strconv.ParseFloat(columns[xColumn], 64)
		y, errY := strconv.ParseFloat(columns[yColumn], 64)
		if errX == nil && errY == nil {
			samples = append(samples, boostSample{x, y, columns[boostColumn]})
		}
	}
	return samples
}
