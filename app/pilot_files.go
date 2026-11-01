package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// ---------- Pilot files (to compare yourself with friends, without internet) ----------

// Only the fields the app checks. Version 2 (0.9.18) has English keys; version 1 had Spanish ones
// ("formato": "swgr-piloto", "piloto") and is still accepted.
type pilotFileHeader struct {
	Format    string `json:"format"`
	Pilot     string `json:"pilot"`
	OldFormat string `json:"formato"`
	OldPilot  string `json:"piloto"`
}

func (header pilotFileHeader) pilotName() string {
	if header.Format == "swgr-pilot" {
		return header.Pilot
	}
	return header.OldPilot
}

var characterNotAllowedInFileName = regexp.MustCompile(`[^\pL\pN _.-]`)

func pilotFileName(pilotName string) string {
	name := strings.TrimSpace(characterNotAllowedInFileName.ReplaceAllString(pilotName, "_"))
	if len([]rune(name)) > 40 {
		name = string([]rune(name)[:40])
	}
	if name == "" || name == "." || name == ".." {
		name = "pilot"
	}
	return "pilot_" + name + ".swgr"
}

func checkPilotFile(content []byte) (pilotFileHeader, error) {
	var header pilotFileHeader
	if err := json.Unmarshal(content, &header); err != nil {
		return header, fmt.Errorf("no es un archivo de piloto válido / not a valid pilot file")
	}
	validNew := header.Format == "swgr-pilot"
	validOld := header.OldFormat == "swgr-piloto"
	if (!validNew && !validOld) || strings.TrimSpace(header.pilotName()) == "" {
		return header, fmt.Errorf("no es un archivo de piloto de esta app / not a pilot file from this app")
	}
	return header, nil
}

func loadFriends(modFolder string) []json.RawMessage {
	friends := []json.RawMessage{}
	folder := modFilePath(modFolder, "friends")
	entries, _ := os.ReadDir(folder)
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(strings.ToLower(entry.Name()), ".swgr") {
			continue
		}
		content, err := os.ReadFile(filepath.Join(folder, entry.Name()))
		if err != nil || len(content) > 32<<20 {
			continue
		}
		if _, err := checkPilotFile(content); err == nil {
			friends = append(friends, json.RawMessage(content))
		}
	}
	return friends
}

// rivals.txt: for the timing panel in the game, your friends' best total of each event (id \t time \t pilot).
// Written when the data is read; the mod reads it at the start of each race. Friends with your own pilot
// name are left out (as the app does).
func writeRivals(modFolder string, friends []json.RawMessage) {
	myName := strings.ToLower(strings.TrimSpace(loadKeyValues(modFilePath(modFolder, "preferences.txt"))["pilot_name"]))
	type result struct {
		Total float64 `json:"total"`
	}
	best := map[string]struct {
		time  float64
		pilot string
	}{}
	for _, raw := range friends {
		var file struct {
			Pilot  string            `json:"pilot"`
			Events map[string]result `json:"events"`
		}
		if json.Unmarshal(raw, &file) != nil || file.Pilot == "" || strings.ToLower(strings.TrimSpace(file.Pilot)) == myName {
			continue
		}
		for id, event := range file.Events {
			if event.Total > 0 && (best[id].time == 0 || event.Total < best[id].time) {
				best[id] = struct {
					time  float64
					pilot string
				}{event.Total, strings.NewReplacer("\t", " ", "\n", " ", "\r", " ").Replace(file.Pilot)}
			}
		}
	}
	ids := make([]string, 0, len(best))
	for id := range best {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	var text strings.Builder
	for _, id := range ids {
		fmt.Fprintf(&text, "%s\t%.3f\t%s\n", id, best[id].time, best[id].pilot)
	}
	path := modFilePath(modFolder, "rivals.txt")
	if previous, err := os.ReadFile(path); err == nil && string(previous) == text.String() {
		return
	}
	if text.Len() == 0 {
		os.Remove(path)
		return
	}
	os.WriteFile(path, []byte(text.String()), 0o644)
}

// writeFriendGhosts leaves, per event, the whole best race of your fastest friend in
// race_ghosts\<event>.friend.txt so the mod can show it as a ghost in the race (0.9.29).
// First line: total and pilot; then one point every 0.1 s: time since the start, x, y.
func writeFriendGhosts(modFolder string, friends []json.RawMessage) {
	myName := strings.ToLower(strings.TrimSpace(loadKeyValues(modFilePath(modFolder, "preferences.txt"))["pilot_name"]))
	type lap struct {
		Time         float64     `json:"time"`
		OfficialTime float64     `json:"officialTime"`
		Trace        [][]float64 `json:"trace"`
	}
	type event struct {
		Race *struct {
			Total float64 `json:"total"`
			Laps  []lap   `json:"laps"`
		} `json:"bestRaceTelemetry"`
		RaceGhost string `json:"raceGhost"`
	}
	type choice struct {
		total float64
		pilot string
		laps  []lap
		ghost string // the in-game ghost as the mod saved it (0.9.29), better than rebuilding it from laps
	}
	best := map[string]choice{}
	for _, raw := range friends {
		var file struct {
			Pilot  string           `json:"pilot"`
			Events map[string]event `json:"events"`
		}
		if json.Unmarshal(raw, &file) != nil || file.Pilot == "" || strings.ToLower(strings.TrimSpace(file.Pilot)) == myName {
			continue
		}
		for id, value := range file.Events {
			pilot := strings.NewReplacer("\t", " ", "\n", " ", "\r", " ").Replace(file.Pilot)
			if total := ghostTotal(value.RaceGhost); total > 0 {
				if previous, found := best[id]; !found || total < previous.total {
					best[id] = choice{total: total, pilot: pilot, ghost: value.RaceGhost}
				}
				continue
			}
			// Files without the in-game ghost (before 0.9.29): a ghost rebuilt from the laps goes out of
			// step at the start, so no ghost is made from them.
		}
	}
	folder := filepath.Join(modFolder, "race_ghosts")
	os.MkdirAll(folder, 0o755) // the mod saves your own ghosts here too (Lua cannot create folders)
	// ghosts the mod had to leave in the mod folder because race_ghosts did not exist yet
	if loose, err := filepath.Glob(filepath.Join(modFolder, "race_ghost_*.txt")); err == nil {
		for _, path := range loose {
			target := filepath.Join(folder, strings.TrimPrefix(filepath.Base(path), "race_ghost_"))
			if _, err := os.Stat(target); err != nil {
				os.Rename(path, target)
			} else {
				os.Remove(path) // the one in race_ghosts is newer or equal: the mod reads that one first
			}
		}
	}
	// friend ghosts that are no longer the right ones (an older file, a friend removed) go away
	if old, err := filepath.Glob(filepath.Join(folder, "*.friend.txt")); err == nil {
		for _, path := range old {
			if _, found := best[strings.TrimSuffix(filepath.Base(path), ".friend.txt")]; !found {
				os.Remove(path)
			}
		}
	}
	for id, race := range best {
		var text strings.Builder
		if race.ghost != "" {
			// header: total, pilot, clock; the points as they are
			lines := strings.SplitN(strings.ReplaceAll(race.ghost, "\r", ""), "\n", 2)
			columns := strings.Split(lines[0], "\t")
			clock := ""
			if len(columns) > 2 {
				clock = columns[2]
			}
			fmt.Fprintf(&text, "%.3f\t%s\t%s\n", race.total, race.pilot, clock)
			if len(lines) > 1 {
				text.WriteString(lines[1])
			}
			race.laps = nil
		} else {
			fmt.Fprintf(&text, "%.3f\t%s\n", race.total, race.pilot)
		}
		offset, next := 0.0, 0.0
		for _, item := range race.laps {
			for _, point := range item.Trace {
				if len(point) < 4 || offset+point[1] < next {
					continue
				}
				if len(point) >= 8 { // height and heading (0.9.29)
					fmt.Fprintf(&text, "%.2f\t%.0f\t%.0f\t%.0f\t%.0f\n", offset+point[1], point[2], point[3], point[6], point[7])
				} else {
					fmt.Fprintf(&text, "%.2f\t%.0f\t%.0f\n", offset+point[1], point[2], point[3])
				}
				next = offset + point[1] + 0.1
			}
			if item.OfficialTime > 0 {
				offset += item.OfficialTime
			} else {
				offset += item.Time
			}
		}
		path := filepath.Join(folder, id+".friend.txt")
		if previous, err := os.ReadFile(path); err == nil && string(previous) == text.String() {
			continue
		}
		os.WriteFile(path, []byte(text.String()), 0o644)
	}
}

// ghostTotal reads the total from the first line of an in-game ghost ("total \t pilot \t clock").
func ghostTotal(ghost string) float64 {
	if ghost == "" {
		return 0
	}
	first, _, _ := strings.Cut(ghost, "\n")
	value, _, _ := strings.Cut(strings.TrimSpace(first), "\t")
	var total float64
	if _, err := fmt.Sscanf(value, "%g", &total); err != nil || len(strings.Split(ghost, "\n")) < 11 {
		return 0
	}
	return total
}

// addRaceGhosts puts your in-game ghost of each event (race_ghosts\<event>.txt, with the race timer,
// height and rotation) in your pilot file, so your friends' ghost of you is exactly yours (0.9.29).
func addRaceGhosts(modFolder string, content []byte) []byte {
	var file map[string]json.RawMessage
	if json.Unmarshal(content, &file) != nil {
		return content
	}
	var events map[string]map[string]json.RawMessage
	if json.Unmarshal(file["events"], &events) != nil {
		return content
	}
	added := 0
	for id, event := range events {
		ghost, err := os.ReadFile(filepath.Join(modFolder, "race_ghosts", id+".txt"))
		if err != nil || ghostTotal(string(ghost)) <= 0 {
			continue
		}
		encoded, _ := json.Marshal(string(ghost))
		event["raceGhost"] = encoded
		added++
	}
	if added == 0 {
		return content
	}
	file["events"], _ = json.Marshal(events)
	result, err := json.Marshal(file)
	if err != nil || len(result) > 32<<20 {
		return content
	}
	return result
}
