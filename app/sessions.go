package main

import (
	"bufio"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

// ---------- Reading the recorded sessions ----------

type Lap struct {
	Number   int       `json:"number"`
	Time     float64   `json:"time"`
	Sectors  []float64 `json:"sectors"`
	Valid    bool      `json:"valid"`
	Incident bool      `json:"incident"`
	Official bool      `json:"official"`
}

type Session struct {
	ID              string  `json:"id"`
	Folder          string  `json:"folder"` // folder relative to the mod's ("" = the mod folder itself)
	Track           string  `json:"track"`
	TelemetryFile   string  `json:"telemetryFile"` // relative path of the CSV (it can be .csv.gz, or empty)
	RouteFile       string  `json:"routeFile"`
	Date            string  `json:"date"`
	Event           string  `json:"event"`
	EventGuessed    bool    `json:"eventGuessed"`
	Mode            string  `json:"mode"`
	PlannedLaps     int     `json:"plannedLaps"`
	Laps            []Lap   `json:"laps"`
	Total           float64 `json:"total"`
	TotalCalculated bool    `json:"totalCalculated"`
	Target          float64 `json:"target"`
	TargetPlayer    string  `json:"targetPlayer"`
	Success         *bool   `json:"success"`
	Version         string  `json:"version"`
	HasBuild        bool    `json:"hasBuild"`
	Size            int64   `json:"size"`
}

// The summary is a readable text the mod writes in Spanish; these are its lines
var (
	summaryLapLine      = regexp.MustCompile(`^Vuelta (\d+): (\d+):(\d+\.\d+)`)
	summarySector       = regexp.MustCompile(`S(\d+) (\d+\.\d+)`)
	summaryHeaderLine   = regexp.MustCompile(`^== (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) \| ([^|]+) \|.*\| v([\d.]+) \|`)
	summaryEventLine    = regexp.MustCompile(`^Evento: (LDB_[A-Z0-9_]+) \| modo: ([^|]*)\| vueltas: (\d+)`)
	summaryResultLine   = regexp.MustCompile(`^Evento: (\d+):(\d+\.\d+)(?: \| objetivo (\d+):(\d+\.\d+) \(([^)]*)\) \| [+-]\d+\.\d+)?(?: \| (Conseguido|No conseguido))?`)
	sessionFileName     = regexp.MustCompile(`^(\d{8}_\d{6})(\.csv|\.csv\.gz|_summary\.txt|_resumen\.txt)$`)
	looseSessionName    = regexp.MustCompile(`^(?:telemetry|telemetria)_(\d{8}_\d{6})_(.+?)(\.csv|\.csv\.gz|_summary\.txt|_resumen\.txt)$`)
	summaryFileSuffixes = []string{"_summary.txt", "_resumen.txt"}
)

func minutesAndSeconds(minutes, seconds string) float64 {
	minuteValue, _ := strconv.ParseFloat(minutes, 64)
	secondValue, _ := strconv.ParseFloat(seconds, 64)
	return minuteValue*60 + secondValue
}

func parseSummary(path string, session *Session) {
	file, err := os.Open(path)
	if err != nil {
		return
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 64*1024), 1024*1024)
	for scanner.Scan() {
		line := strings.TrimRight(scanner.Text(), "\r")
		if match := summaryHeaderLine.FindStringSubmatch(line); match != nil {
			session.Date = match[1]
			session.Version = match[3]
			continue
		}
		if match := summaryEventLine.FindStringSubmatch(line); match != nil {
			session.Event = match[1]
			session.Mode = strings.TrimSpace(match[2])
			session.PlannedLaps, _ = strconv.Atoi(match[3])
			continue
		}
		if strings.HasPrefix(line, "Modo con build") {
			session.HasBuild = true
			continue
		}
		if match := summaryResultLine.FindStringSubmatch(line); match != nil {
			session.Total = minutesAndSeconds(match[1], match[2])
			if match[3] != "" {
				session.Target = minutesAndSeconds(match[3], match[4])
				session.TargetPlayer = match[5]
			}
			if match[6] != "" {
				succeeded := match[6] == "Conseguido"
				session.Success = &succeeded
			}
			continue
		}
		if match := summaryLapLine.FindStringSubmatch(line); match != nil {
			number, _ := strconv.Atoi(match[1])
			lap := Lap{Number: number, Time: minutesAndSeconds(match[2], match[3]), Official: !strings.Contains(line, "sin dato oficial")}
			sectorsPart, notes, _ := strings.Cut(line, "[")
			for _, sector := range summarySector.FindAllStringSubmatch(sectorsPart, -1) {
				value, _ := strconv.ParseFloat(sector[2], 64)
				lap.Sectors = append(lap.Sectors, value)
			}
			lap.Valid = !strings.Contains(notes, "no válidos") && !strings.Contains(notes, "salida parada") && len(lap.Sectors) > 0
			lap.Incident = strings.Contains(notes, "incidente")
			session.Laps = append(session.Laps, lap)
		}
	}
}

func fileSize(path string) int64 {
	if info, err := os.Stat(path); err == nil {
		return info.Size()
	}
	return 0
}

func stampDate(stamp string) string {
	parsed, err := time.Parse("20060102_150405", stamp)
	if err != nil {
		return ""
	}
	return parsed.Format("2006-01-02 15:04:05")
}

// The route of a track folder: route.csv, or ruta.csv while the files have not been renamed yet
func routeFileOf(modFolder, trackFolder string) string {
	for _, name := range []string{"route.csv", "ruta.csv"} {
		if exists(filepath.Join(modFolder, trackFolder, name)) {
			return filepath.ToSlash(filepath.Join(trackFolder, name))
		}
	}
	return filepath.ToSlash(filepath.Join(trackFolder, "route.csv"))
}

// Walks the mod folder: tracks/<track>/<date>.csv(.gz) + _summary.txt (circuitos/ and _resumen.txt
// while the mod still uses the old names), and loose sessions telemetry_<date>_<track>.* in the mod
// folder itself (the mod only writes them there if it cannot create the track's folder).
func scanSessions(modFolder string) []*Session {
	var sessions []*Session
	seen := map[string]bool{}
	for _, tracksFolder := range []string{"tracks", "circuitos"} {
		tracks, _ := os.ReadDir(filepath.Join(modFolder, tracksFolder))
		for _, track := range tracks {
			if !track.IsDir() {
				continue
			}
			folder := filepath.Join(tracksFolder, track.Name())
			files, _ := os.ReadDir(filepath.Join(modFolder, folder))
			stamps := map[string]bool{}
			for _, file := range files {
				if match := sessionFileName.FindStringSubmatch(file.Name()); match != nil {
					stamps[match[1]] = true
				}
			}
			for stamp := range stamps {
				if seen[stamp] {
					continue
				}
				seen[stamp] = true
				session := &Session{ID: stamp, Folder: filepath.ToSlash(folder), Track: track.Name(), RouteFile: routeFileOf(modFolder, folder), Date: stampDate(stamp)}
				basePath := filepath.Join(modFolder, folder, stamp)
				if fileSize(basePath+".csv") > 0 {
					session.TelemetryFile = filepath.ToSlash(filepath.Join(folder, stamp+".csv"))
				} else if fileSize(basePath+".csv.gz") > 0 {
					session.TelemetryFile = filepath.ToSlash(filepath.Join(folder, stamp+".csv.gz"))
				}
				session.Size = fileSize(basePath+".csv") + fileSize(basePath+".csv.gz")
				for _, suffix := range summaryFileSuffixes {
					if exists(basePath + suffix) {
						parseSummary(basePath+suffix, session)
						break
					}
				}
				sessions = append(sessions, session)
			}
		}
	}
	// Loose sessions in the mod folder itself
	rootFiles, _ := os.ReadDir(modFolder)
	looseSessions := map[string]*Session{}
	for _, file := range rootFiles {
		match := looseSessionName.FindStringSubmatch(file.Name())
		if match == nil || seen[match[1]] {
			continue
		}
		session := looseSessions[match[1]]
		if session == nil {
			track := match[2]
			session = &Session{ID: match[1], Track: track, Date: stampDate(match[1])}
			session.RouteFile = "route_" + track + ".csv"
			if !exists(filepath.Join(modFolder, session.RouteFile)) {
				session.RouteFile = "ruta_" + track + ".csv"
			}
			for _, tracksFolder := range []string{"tracks", "circuitos"} {
				if folder := filepath.Join(tracksFolder, track); exists(filepath.Join(modFolder, folder)) {
					session.RouteFile = routeFileOf(modFolder, folder)
					break
				}
			}
			looseSessions[match[1]] = session
			sessions = append(sessions, session)
		}
		switch match[3] {
		case ".csv", ".csv.gz":
			session.TelemetryFile = file.Name()
			session.Size += fileSize(filepath.Join(modFolder, file.Name()))
		default:
			parseSummary(filepath.Join(modFolder, file.Name()), session)
		}
	}
	// Event guessed for sessions from before v0.7: if only one identified event has been raced on
	// that track, that one is assumed.
	eventsByTrack := map[string]map[string]bool{}
	for _, session := range sessions {
		if session.Event != "" {
			if eventsByTrack[session.Track] == nil {
				eventsByTrack[session.Track] = map[string]bool{}
			}
			eventsByTrack[session.Track][session.Event] = true
		}
	}
	plannedLaps := map[string]int{}
	for _, session := range sessions {
		if session.PlannedLaps > 0 {
			plannedLaps[session.Event] = session.PlannedLaps
		}
	}
	for _, session := range sessions {
		keepOfficialLaps(session)
	}
	for _, session := range sessions {
		if session.Event == "" {
			if events := eventsByTrack[session.Track]; len(events) == 1 {
				for event := range events {
					session.Event = event
				}
				session.EventGuessed = true
			} else {
				session.Event = "TRACK:" + session.Track
				session.EventGuessed = true
			}
		}
		if session.PlannedLaps == 0 {
			session.PlannedLaps = plannedLaps[session.Event]
		}
		// Total calculated for old complete sessions (the sum of the official laps)
		if session.Total == 0 && session.PlannedLaps > 0 && len(session.Laps) == session.PlannedLaps {
			sum := 0.0
			allOfficial := true
			for _, lap := range session.Laps {
				sum += lap.Time
				allOfficial = allOfficial && lap.Official
			}
			if allOfficial {
				session.Total = sum
				session.TotalCalculated = true
			}
		}
	}
	sort.Slice(sessions, func(i, j int) bool { return sessions[i].ID > sessions[j].ID })
	return sessions
}

// The first versions of the mod counted the stretch from the grid as a lap (without an official
// time). If the session has official laps, only those count.
func keepOfficialLaps(session *Session) {
	official := 0
	for _, lap := range session.Laps {
		if lap.Official {
			official++
		}
	}
	if official == 0 || official == len(session.Laps) {
		return
	}
	var laps []Lap
	for _, lap := range session.Laps {
		if lap.Official {
			lap.Number = len(laps) + 1
			laps = append(laps, lap)
		}
	}
	session.Laps = laps
}
