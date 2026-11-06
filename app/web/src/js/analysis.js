  // ---------- Lap analysis (map, difference, speed) ----------
  async function fetchText(path) {
    if (state.fileCache[path]) return state.fileCache[path];
    const text = await (await fetchFromApp('/api/file?path=' + encodeURIComponent(path))).text();
    state.fileCache[path] = text;
    return text;
  }

  // Arranque lanzado: el total y la vuelta oficial de la carrera, para que el análisis empiece en el GO
  // (core.js ya marca las vueltas de esos eventos, también las de antes del cambio)
  function rollingOf(session) {
    const lap = (session.laps || [])[0];
    return lap && lap.rolling && lap.officialLap ? { total: session.total || lap.time, officialLap: lap.officialLap } : null;
  }

  async function loadAnalysis(event) {
    const selection = selectedSessions(event);
    const chosen = event.sessions.filter(session => selection.has(session.id) && session.telemetryFile);
    const loadToken = Symbol();
    state.analysisLoadToken = loadToken;
    byId('readout').textContent = chosen.length ? 'Cargando telemetría…' : 'Marca algún intento en la lista para analizar sus vueltas.';
    if (!chosen.length) { state.analysis = null; drawAll(); byId('lapTable').innerHTML = ''; return; }
    try {
      const route = parseRouteCsv(await fetchText(chosen[chosen.length - 1].routeFile));
      const loaded = [];
      for (const session of chosen) loaded.push({ label: (session.date || session.id).slice(5, 16), samples: parseSessionCsv(await fetchText(session.telemetryFile), vehicleTypeOfEvent(session.event)), session });
      if (state.analysisLoadToken !== loadToken) return;
      const routeLength = route.points[route.points.length - 1][0];
      const analysis = { route, routeLength, lapLength: routeLength, laps: [], track: null, event };
      for (const item of loaded) {
        const result = analyzeSession(route, item.samples, item.label, rollingOf(item.session));
        if (!analysis.track || result.finishCheckpoint !== null) analysis.track = result;
        result.laps.forEach(lap => {
          lap.sessionLabel = item.label; lap.sessionId = item.session.id;
          // The game's official time (the one in the summary); the one measured in the telemetry can differ by a few tenths
          const official = (item.session.laps || []).find(summaryLap => summaryLap.number === lap.number);
          if (official && official.official && Math.abs(official.time - lap.time) < 1.5) lap.officialTime = official.time;
          analysis.laps.push(lap);
        });
      }
      // On a point-to-point stage the charts go from the start to the finish
      if (analysis.track && analysis.track.isPointToPoint) analysis.lapLength = analysis.track.span;
      const previousA = state.analysis && state.analysis.lapA;
      const sameLap = previous => previous && analysis.laps.find(lap => lap.sessionLabel === previous.sessionLabel && lap.number === previous.number);
      const cleanLaps = analysis.laps.filter(lap => !lap.incident).sort((first, second) => officialLapTime(first) - officialLapTime(second));   // by the game's official time
      analysis.idealLap = buildIdealLap(analysis);
      analysis.idealStartLap = buildIdealLap(analysis, true);
      analysis.idealRace = buildIdealRace(analysis);
      analysis.friendLaps = friendLaps(event, analysis);
      analysis.friendRaces = friendRaces(event, analysis);
      analysis.friendStarts = friendStarts(event, analysis);
      analysis.lapA = sameLap(previousA) || bestOwnLap(analysis, event) || cleanLaps[0] || analysis.laps[0];
      analysis.lapB = null;
      // A es el intento elegido en la lista y B el rival por defecto (el amigo más rápido o tu mejor carrera)
      fitComparison(analysis);
      if (isSimpleMode()) state.simpleRival = analysis.lapB ? lapValue(analysis, analysis.lapB) : '';
      state.pendingFocusSession = null;
      prepareMap(analysis);
      state.analysis = analysis;
      renderLapTable(); drawAll();
      byId('readout').textContent = 'Pasa el ratón por las gráficas para ver cada punto en el mapa.';
    } catch (error) {
      // A file that is no longer where the data said (the app moves the first race of a new circuit into
      // its folder, and compresses long sessions): the data is read again, which loads the analysis again
      if (state.analysisLoadToken !== loadToken) return;
      if (!state.analysisRetriedAt || performance.now() - state.analysisRetriedAt > 15000) {
        state.analysisRetriedAt = performance.now(); state.fileCache = {};
        await refreshData();
        return;
      }
      byId('readout').textContent = 'No se pudo cargar la telemetría: ' + error.message;
      showToast('No se pudo cargar la telemetría de tus intentos. Cierra y vuelve a abrir la app; si sigue, guarda log.txt y la carpeta tracks para revisarlo.');
    }
  }

  // Ideal lap: joins the stretch of each best sector (among the loaded attempts), with its trace and
  // its time, to use it as a reference.
  // startLap: the ideal lap 1 of an event of several laps (your best start S1, the rest your best sectors);
  // if not, the ideal flying lap (the start S1 does not count, it is slower).
  // Laps with an incident, or a sector whose trace does not match its time, are left out: their line would jump.
  function buildIdealLap(analysis, startLap) {
    if (!analysis.track) return null;
    const sectorCount = analysis.track.sectorCount;
    const bounds = [0].concat(analysis.track.sectorStarts).concat([analysis.lapLength]);
    const bestSectors = Array(sectorCount).fill(null);
    const severalLaps = analysis.event && analysis.event.plannedLaps > 1;
    if (startLap && !severalLaps) return null;
    for (const lap of analysis.laps) {
      if (!lap.sectors || lap.sectors.length !== sectorCount || lap.incident) continue;
      lap.sectors.forEach((value, sectorIndex) => {
        if (severalLaps && (startLap ? lap.number !== 1 : lap.number === 1)) return;   // laps 1 only in the ideal lap 1, and never in the flying one
        const measured = +(lap.measuredSectors || [])[sectorIndex];
        if (measured > 0 && Math.abs(measured - value) > 0.3) return;
        if (!bestSectors[sectorIndex] || value < bestSectors[sectorIndex].value) bestSectors[sectorIndex] = { value, lap };
      });
    }
    if (bestSectors.some(best => !best)) return null;
    // Each sector keeps its own trace, with its times stretched to its official time: no jumps in time where they join
    const trace = [];
    let elapsed = 0;
    bestSectors.forEach((best, sectorIndex) => {
      const timeByDistance = timeAtDistance(best.lap);
      const startTime = interpolate(timeByDistance.distances, timeByDistance.times, bounds[sectorIndex]);
      const endTime = interpolate(timeByDistance.distances, timeByDistance.times, bounds[sectorIndex + 1]);
      const stretch = endTime > startTime ? best.value / (endTime - startTime) : 1;
      for (const point of best.lap.trace) {
        if (point.distance < bounds[sectorIndex] || point.distance > bounds[sectorIndex + 1]) continue;
        trace.push({ distance: point.distance, time: elapsed + (interpolate(timeByDistance.distances, timeByDistance.times, point.distance) - startTime) * stretch,
          x: point.x, y: point.y, speed: point.speed });
      }
      elapsed += best.value;
    });
    trace.sort((first, second) => first.distance - second.distance);
    // Where two sectors of different laps join, the two racing lines (and speeds) are blended over 30 m
    const BLEND = 1500;
    for (const point of trace) {
      for (let boundary = 1; boundary < sectorCount; boundary++) {
        const before = bestSectors[boundary - 1].lap, after = bestSectors[boundary].lap, middle = bounds[boundary];
        if (before === after || Math.abs(point.distance - middle) >= BLEND) continue;
        let share = (point.distance - (middle - BLEND)) / (2 * BLEND); share = share * share * (3 - 2 * share);
        const pointBefore = lapPointAtDistance(before, point.distance), pointAfter = lapPointAtDistance(after, point.distance);
        point.x = pointBefore.x + (pointAfter.x - pointBefore.x) * share; point.y = pointBefore.y + (pointAfter.y - pointBefore.y) * share;
        point.speed = pointBefore.speed + (pointAfter.speed - pointBefore.speed) * share;
      }
    }
    return { isIdeal: true, sessionLabel: startLap ? 'Vuelta 1 ideal' : 'Vuelta ideal', number: startLap ? 1 : '', time: elapsed, sectors: bestSectors.map(best => best.value), measuredSectors: bestSectors.map(best => best.value),
      sourceLaps: bestSectors.map(best => best.lap.sessionLabel + ' V' + best.lap.number), trace, incident: false };
  }
  // The ideal race: your ideal lap 1 (with your best start) and then the ideal lap on every other lap
  // Con vueltas de verdad (de los intentos cargados): tu mejor vuelta 1 y tus mejores vueltas lanzadas,
  // una distinta para cada vuelta que queda (si no hay bastantes, se repite la mejor)
  function buildIdealRace(analysis) {
    const plannedLaps = analysis.event && analysis.event.plannedLaps;
    if (!(plannedLaps > 1)) return null;
    const cleanLaps = analysis.laps.filter(lap => !lap.incident && lap.official).sort((first, second) => officialLapTime(first) - officialLapTime(second));
    const startLap = cleanLaps.find(lap => lap.number === 1);
    const flyingLaps = cleanLaps.filter(lap => lap.number !== 1);
    if (!startLap || !flyingLaps.length) return null;
    const race = { laps: [] };
    race.laps.push(Object.assign({}, startLap, { number: 1, time: officialLapTime(startLap), idealRace: race, sessionLabel: 'Carrera ideal' }));
    for (let lapNumber = 2; lapNumber <= plannedLaps; lapNumber++) {
      const lap = flyingLaps[Math.min(lapNumber - 2, flyingLaps.length - 1)];
      race.laps.push(Object.assign({}, lap, { number: lapNumber, time: officialLapTime(lap), idealRace: race, sessionLabel: 'Carrera ideal' }));
    }
    race.total = race.laps.reduce((sum, lap) => sum + lap.time, 0);
    return race;
  }

  // Simple mode compares your best lap with one rival: a friend, the ideal lap or the best lap of another attempt of yours
  function simpleRivals(analysis) {
    return comparisonCandidates(analysis).filter(item => item.lap && item.lap !== analysis.lapA).map(item => ({ value: item.value, label: item.label, detail: item.detail || item.label, lap: item.lap }));
  }
  function useSimpleComparison(analysis) {
    const chosen = simpleRivals(analysis).find(rival => rival.value === state.simpleRival);
    if (chosen) analysis.lapB = chosen.lap;
    state.replay.segment = null;
  }
  function fillSimpleRivalPicker() {
    const picker = byId('simpleRival'), analysis = state.analysis;
    if (!picker || !analysis) return;
    const rivals = simpleRivals(analysis), selected = analysis.lapB ? lapValue(analysis, analysis.lapB) : '';
    picker.innerHTML = rivals.length ? rivals.map(rival => '<option value="' + escapeHtml(rival.value) + '"' + (rival.value === selected ? ' selected' : '') + ' title="' + escapeHtml(rival.detail) + '">' + escapeHtml(rival.label) + '</option>').join('')
      : '<option value="">' + (comparisonKind() === 'race' ? 'Corre otra carrera entera o añade el archivo de un amigo' : 'Corre otra vez para tener con quién compararte') + '</option>';
  }
  document.addEventListener('change', changeEvent => {
    if (changeEvent.target.id !== 'simpleRival' || !state.analysis || !changeEvent.target.value) return;
    state.simpleRival = changeEvent.target.value;
    useSimpleComparison(state.analysis);
    renderLapTable(); drawAll();
  });

  // Values of the lap pickers and of the table rows: "lap:<index>", "friend:<index>", "ideal", "race:<session id>"
  // "friendrace:<index>:<lap index>" is a lap of a friend's best race (the first lap stands for the whole race)
  const lapValue = (analysis, lap) => lap.isFriendStart ? 'friendstart:' + analysis.friendStarts.indexOf(lap) : lap.idealRace ? 'idealrace' : lap === analysis.idealStartLap ? 'idealstart' : lap === analysis.idealLap ? 'ideal' : lap.friendRace ? 'friendrace:' + analysis.friendRaces.indexOf(lap.friendRace) + ':' + lap.friendRace.laps.indexOf(lap)
    : lap.isFriend ? 'friend:' + analysis.friendLaps.indexOf(lap) : 'lap:' + analysis.laps.indexOf(lap);
  function lapFromValue(analysis, value) {
    if (value === 'ideal') return analysis.idealLap;
    if (value === 'idealrace') return analysis.idealRace ? analysis.idealRace.laps[0] : null;
    if (value === 'idealstart') return analysis.idealStartLap || null;
    if (value.startsWith('friendstart:')) return (analysis.friendStarts || [])[+value.slice(12)] || null;
    if (!value) return null;
    const [kind, index, lapIndex] = value.split(':');
    if (kind === 'friendrace') { const race = (analysis.friendRaces || [])[+index]; return race ? race.laps[+lapIndex || 0] || null : null; }
    return kind === 'friend' ? analysis.friendLaps[+index] : kind === 'lap' ? analysis.laps[+index] : null;
  }
  function renderLapTable() {
    if (state.replay) { stopReplay(true); if (byId('replayGap')) byId('replayGap').textContent = ''; }
    const analysis = state.analysis, event = analysis.event;
    const sectorCount = analysis.track ? analysis.track.sectorCount : 1;
    const selectionClasses = lap => (lap === analysis.lapA ? ' selected-a' : '') + (lap === analysis.lapB ? ' selected-b' : '');
    let html = '<thead><tr><th>Vuelta</th><th>Tiempo</th>';
    for (let sectorNumber = 1; sectorNumber <= sectorCount; sectorNumber++) html += '<th>S' + sectorNumber + '</th>';
    html += '<th></th></tr></thead><tbody>';
    if (analysis.idealLap) {
      const lap = analysis.idealLap;
      html += '<tr class="clickable ideal-row' + selectionClasses(lap) + '" data-lap="ideal"><td class="text"><b class="best">Vuelta ideal</b> <span class="muted" title="' + escapeHtml(lap.sourceLaps.join(' · ')) + '">mejores sectores</span></td>' +
        '<td class="best">' + formatTime(lap.time) + '</td>' + lap.sectors.map((value, sectorIndex) => '<td class="best" title="' + escapeHtml(lap.sourceLaps[sectorIndex]) + '">' + value.toFixed(3) + '</td>').join('') +
        '<td><button class="button small" data-reference="ideal">B</button></td></tr>';
    }
    (analysis.friendLaps || []).forEach(lap => {
      const value = lapValue(analysis, lap);
      html += '<tr class="clickable friend-row' + selectionClasses(lap) + '" data-lap="' + value + '"><td class="text"><b>' + escapeHtml(lap.pilot) + '</b> <span class="muted">su mejor vuelta</span></td>' +
        '<td>' + formatTime(officialLapTime(lap)) + '</td>';
      for (let sectorIndex = 0; sectorIndex < sectorCount; sectorIndex++) { const sector = (lap.sectors || [])[sectorIndex]; html += '<td>' + (sector > 0 ? (+sector).toFixed(3) : '—') + '</td>'; }
      html += '<td><button class="button small" data-reference="' + value + '">B</button></td></tr>';
    });
    // Laps grouped by attempt; open are the ones holding A, the reference or your best lap
    state.openLapGroups = state.openLapGroups || {};
    const groups = [];
    analysis.laps.forEach(lap => {
      let group = groups[groups.length - 1];
      if (!group || group.label !== lap.sessionLabel) { group = { label: lap.sessionLabel, laps: [] }; groups.push(group); }
      group.laps.push(lap);
    });
    groups.forEach((group, groupIndex) => {
      const key = event.id + '|' + group.label;
      const holdsSelection = group.laps.some(lap => lap === analysis.lapA || lap === analysis.lapB || (event.bestLap && Math.abs(officialLapTime(lap) - event.bestLap.lap.time) < 0.01));
      const open = state.openLapGroups[key] ?? holdsSelection;
      const fastest = group.laps.reduce((best, lap) => (!best || officialLapTime(lap) < officialLapTime(best) ? lap : best), null);
      html += '<tr class="group-row' + (open ? ' open' : '') + '" data-group="' + groupIndex + '" data-group-key="' + escapeHtml(key) + '"><td class="text" colspan="' + (sectorCount + 3) + '"><span class="chevron" aria-hidden="true">▸</span><b>' + escapeHtml(group.label) + '</b>' +
        '<span class="muted"> · ' + group.laps.length + (group.laps.length === 1 ? ' vuelta' : ' vueltas') + ' · mejor <span class="numeric">' + formatTime(officialLapTime(fastest)) + '</span></span></td></tr>';
      group.laps.forEach(lap => {
        const value = lapValue(analysis, lap);
        const isStartLap = event.plannedLaps > 1 && lap.number === 1;
        html += '<tr class="clickable lap-row' + selectionClasses(lap) + '" data-lap="' + value + '" data-in-group="' + groupIndex + '"' + (open ? '' : ' hidden') + '><td class="text">V' + lap.number +
          (isStartLap ? '<span class="tag" title="Vuelta de salida: su S1 se compara solo con otras salidas">salida</span>' : '') + (lap.incident ? '<span class="tag failure">incidente</span>' : '') + '</td>';
        html += '<td class="' + (event.bestLap && Math.abs(officialLapTime(lap) - event.bestLap.lap.time) < 0.01 ? 'best' : '') + '">' + formatTime(officialLapTime(lap)) + '</td>';
        const sectors = lap.sectors || lap.measuredSectors;
        for (let sectorIndex = 0; sectorIndex < sectorCount; sectorIndex++) {
          const sector = sectors[sectorIndex];
          const best = isStartLap && sectorIndex === 0 ? event.bestStartSector : event.bestSectors[sectorIndex];
          const isBestSector = lap.sectors && best && sector != null && Math.abs(sector - best.value) < 0.01;
          html += '<td class="' + (isBestSector ? 'best' : '') + '">' + (sector != null ? sector.toFixed(3) : '—') + '</td>';
        }
        html += '<td><button class="button small" data-reference="' + value + '">B</button></td></tr>';
      });
    });
    byId('lapTable').innerHTML = html + '</tbody>';
    fillComparisonPickers(); fillSimpleRivalPicker(); fillReplayScopes(); renderSectorComparison();
    updateVersusBar();
    byId('lapTable').onclick = clickEvent => {
      const groupRow = clickEvent.target.closest('tr.group-row');
      if (groupRow) {
        const open = !groupRow.classList.contains('open');
        groupRow.classList.toggle('open', open); state.openLapGroups[groupRow.dataset.groupKey] = open;
        byId('lapTable').querySelectorAll('tr[data-in-group="' + groupRow.dataset.group + '"]').forEach(row => { row.hidden = !open; });
        return;
      }
      const referenceButton = clickEvent.target.closest('[data-reference]');
      // The table holds laps: picking one there compares laps (or the sector being compared)
      const pickedRow = referenceButton || clickEvent.target.closest('tr[data-lap]');
      if (pickedRow) {
        const picked = lapFromValue(analysis, (referenceButton ? referenceButton.dataset.reference : pickedRow.dataset.lap));
        const pickedNumber = +picked.number, severalLaps = severalLapsEvent(analysis);
        const wantedKind = !severalLaps ? (comparisonKind() === 'sector' ? state.replay.scope : 'lap')
          : comparisonKind() === 'sector' ? state.replay.scope
          : pickedNumber >= 1 && !picked.isIdeal ? (pickedNumber === 1 ? 'start' : 'L' + pickedNumber) : comparisonKind() === 'race' ? 'start' : state.replay.scope;
        if (wantedKind !== state.replay.scope) {
          state.replay.scope = wantedKind; state.replay.segment = null;
          if (referenceButton) { analysis.lapB = picked; fitComparison(analysis); if (picked !== analysis.lapA) analysis.lapB = picked; }
          else { analysis.lapA = picked; fitComparison(analysis); analysis.lapA = picked; if (analysis.lapB === picked) analysis.lapB = null; }
          renderLapTable(); drawAll(); return;
        }
      }
      if (referenceButton) { const lap = lapFromValue(analysis, referenceButton.dataset.reference); if (lap !== analysis.lapA) analysis.lapB = lap; renderLapTable(); drawAll(); return; }
      const row = clickEvent.target.closest('tr[data-lap]');
      if (!row) return;
      const lap = lapFromValue(analysis, row.dataset.lap);
      if (lap === analysis.lapB) analysis.lapB = analysis.lapA;
      analysis.lapA = lap; renderLapTable(); drawAll();
    };
  }

  function fitCanvas(canvas, cssHeight) {
    const box = canvas.getBoundingClientRect();
    const pixelRatio = window.devicePixelRatio || 1;
    const width = Math.max(10, box.width), height = cssHeight || Math.max(10, box.height);
    if (cssHeight) canvas.style.height = cssHeight + 'px';
    canvas.width = Math.round(width * pixelRatio); canvas.height = Math.round(height * pixelRatio);
    const context = canvas.getContext('2d');
    context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
    return { context, width, height };
  }
  // A round grid step (1, 2, 2.5 or 5 times a power of ten) giving about `divisions` lines over `span`
  function niceStep(span, divisions) {
    const rawStep = span / divisions, powerOfTen = Math.pow(10, Math.floor(Math.log10(rawStep)));
    for (const multiple of [1, 2, 2.5, 5, 10]) if (rawStep <= multiple * powerOfTen) return multiple * powerOfTen;
    return 10 * powerOfTen;
  }
  function prepareMap(analysis) {
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    const include = (x, y) => { minX = Math.min(minX, x); maxX = Math.max(maxX, x); minY = Math.min(minY, y); maxY = Math.max(maxY, y); };
    analysis.route.points.forEach(point => include(point[1], point[2]));
    analysis.laps.forEach(lap => lap.trace.forEach(point => include(point.x, point.y)));
    analysis.bounds = { minX, maxX, minY, maxY };
  }
  // Position on the route's spline at a distance along it
  function routePointAt(analysis, routeDistance) {
    const points = analysis.route.points, length = analysis.routeLength;
    routeDistance = ((routeDistance % length) + length) % length;
    let low = 0, high = points.length - 1;
    while (high - low > 1) { const middle = (low + high) >> 1; if (points[middle][0] <= routeDistance) low = middle; else high = middle; }
    const fraction = (routeDistance - points[low][0]) / (points[high][0] - points[low][0] || 1);
    return [points[low][1] + fraction * (points[high][1] - points[low][1]), points[low][2] + fraction * (points[high][2] - points[low][2])];
  }
  // A lap distance (from the finish line, or from the start of a point-to-point stage) as a distance along the route's spline
  function lapDistanceToRouteDistance(analysis, lapDistance) {
    const length = analysis.routeLength, origin = analysis.track.isPointToPoint ? analysis.track.originDistance : analysis.track.finishDistance;
    const distanceDriven = ((origin + lapDistance) % length + length) % length;
    return analysis.track.direction === 1 ? distanceDriven : length - distanceDriven;
  }
  function lapPointAtDistance(lap, distance) {
    const trace = lap.trace;
    if (distance <= trace[0].distance) return trace[0];
    const index = trace.findIndex(point => point.distance >= distance);
    if (index <= 0) return trace[trace.length - 1];
    const before = trace[index - 1], after = trace[index], fraction = (distance - before.distance) / ((after.distance - before.distance) || 1);
    return { x: before.x + fraction * (after.x - before.x), y: before.y + fraction * (after.y - before.y), speed: before.speed + fraction * (after.speed - before.speed) };
  }
  // Position of a lap at the instant `time` (seconds since its start)
  function lapPointAtTime(lap, time) {
    if (!lap.timeOrderedTrace) {
      const points = []; let lastTime = -Infinity;
      for (const point of lap.trace) if (point.time > lastTime) { points.push(point); lastTime = point.time; }
      lap.timeOrderedTrace = points;
    }
    const trace = lap.timeOrderedTrace;
    if (time <= trace[0].time) return trace[0];
    if (time >= trace[trace.length - 1].time) return trace[trace.length - 1];
    let low = 0, high = trace.length - 1;
    while (high - low > 1) { const middle = (low + high) >> 1; if (trace[middle].time <= time) low = middle; else high = middle; }
    const before = trace[low], after = trace[high], fraction = (time - before.time) / ((after.time - before.time) || 1);
    return { distance: before.distance + fraction * (after.distance - before.distance), x: before.x + fraction * (after.x - before.x), y: before.y + fraction * (after.y - before.y),
      speed: before.speed + fraction * (after.speed - before.speed) };
  }
  // Replay: a sector, the lap or the whole race; in real time or with both cars at the same point
  state.replay = { time: null, playing: false, lastFrame: 0, animationFrame: 0, scope: 'lap', sync: 'realTime', followCar: false, segment: null };
  const referenceName = lap => !lap ? 'B' : lap.isIdeal ? 'ideal' : lap.isFriend ? lap.pilot : 'B';
  function sectorBounds(analysis) { return analysis.track ? [0].concat(analysis.track.sectorStarts).concat([analysis.lapLength]) : [0, analysis.lapLength]; }
  // A stretch of a lap, with the time set to zero when it enters it
  function sliceLap(lap, startDistance, endDistance) {
    const timeByDistance = timeAtDistance(lap), startTime = interpolate(timeByDistance.distances, timeByDistance.times, startDistance), endTime = interpolate(timeByDistance.distances, timeByDistance.times, endDistance);
    const trace = lap.trace.filter(point => point.distance >= startDistance && point.distance <= endDistance)
      .map(point => ({ distance: point.distance, time: point.time - startTime, x: point.x, y: point.y, speed: point.speed, boost: point.boost, trail: point.trail }));
    return trace.length > 1 ? { trace, time: endTime - startTime } : null;
  }
  // All the laps of an attempt, in order
  function sessionLaps(analysis, lap) {
    if (lap.friendRace) return lap.friendRace.laps;
    if (lap.idealRace) return lap.idealRace.laps;
    return analysis.laps.filter(item => item.sessionLabel === lap.sessionLabel && !item.isIdeal && !item.isFriend).sort((first, second) => first.number - second.number);
  }
  function joinLaps(analysis, laps) {
    const trace = []; let distanceOffset = 0, timeOffset = 0;
    laps.forEach(lap => {
      lap.trace.forEach(point => { if (point.distance >= 0 || !trace.length) trace.push({ distance: point.distance + distanceOffset, time: point.time + timeOffset, x: point.x, y: point.y, speed: point.speed, boost: point.boost, trail: point.trail }); });
      distanceOffset += analysis.lapLength; timeOffset += lap.time;
    });
    return trace.length > 1 ? { trace, time: timeOffset, lapCount: laps.length } : null;
  }
  const isOwnLap = lap => lap && !lap.isIdeal && !lap.isFriend;
  // The rival of a whole race: another attempt of yours with the same laps or, if not, the reference repeated on every lap
  function raceRival(analysis, lapA, lapB) {
    if (!lapA || !lapB || !isWholeRace(analysis, lapB) || (!lapB.friendRace && !lapB.idealRace && lapB.sessionId === lapA.sessionId)) return null;
    const lapsA = sessionLaps(analysis, lapA), lapsB = sessionLaps(analysis, lapB);
    return lapsB.length === lapsA.length ? { laps: lapsB } : null;
  }

