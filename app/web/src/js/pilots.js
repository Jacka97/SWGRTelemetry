  // ---------- Pilots: .swgr files to compare yourself with your friends, without internet ----------
  // Pilot name: the profile's; if there is none, a default one that each person changes in their profile
  const DEFAULT_PILOT_NAME = 'Anakin Skywalker';
  const myPilotName = () => String(preference('pilot_name') || '').trim() || DEFAULT_PILOT_NAME;
  const roundToMilliseconds = seconds => (seconds > 0 ? Math.round(seconds * 1000) / 1000 : null);
  // Pilot files of version 1 (0.9.17 and earlier) had Spanish keys: they are read as version 2
  const OLD_VEHICLE_NAMES = { Vaina: 'podracer', Coche: 'car', Moto: 'bike', Rasante: 'skimmer', Otros: 'other' };
  function readPilotFile(file) {
    if (!file || typeof file !== 'object') return null;
    if (file.format === 'swgr-pilot') return file.events && typeof file.events === 'object' ? file : null;
    if (file.formato !== 'swgr-piloto' || !file.eventos || typeof file.eventos !== 'object') return null;
    const events = {};
    for (const [eventId, old] of Object.entries(file.eventos)) {
      if (!old || typeof old !== 'object') continue;
      const lap = old.vuelta && typeof old.vuelta === 'object' ? old.vuelta : null;
      events[eventId] = { name: old.nombre, planet: old.planeta, vehicle: OLD_VEHICLE_NAMES[old.vehiculo] || old.vehiculo, plannedLaps: old.vueltas, total: old.total,
        bestLap: old.mejorVuelta, sectors: old.sectores, startSector: old.salidaS1, idealLap: old.ideal, date: old.fecha,
        bestLapTelemetry: lap ? { number: lap.n, time: lap.t, sectors: lap.sec, length: lap.L, isPointToPoint: lap.abierto, trace: lap.tr } : null };
    }
    return { format: 'swgr-pilot', version: 2, pilot: file.piloto, color: file.color, date: file.fecha, app: file.app, events };
  }
  function friendPilots() {
    const myName = String(preference('pilot_name') || '').trim().toLowerCase();   // with the default name nobody is hidden
    return ((state.data && state.data.friends) || []).filter(friend => String(friend.pilot || '').trim() && (!myName || String(friend.pilot).trim().toLowerCase() !== myName));
  }
  // An event's standings: you and your friends, from the fastest to the slowest
  function standings(eventId, event) {
    const rows = [];
    const myGameRecord = gameRecordOf(state.data, eventId);
    if (event && (event.recordTime || event.bestLap)) rows.push({ isMe: true, pilot: myPilotName() || 'Tú', color: myPilotColor(), total: event.recordTime || null,
      bestLap: event.bestLap ? event.bestLap.lap.time : null, sectors: event.bestSectors.map(best => (best ? best.value : null)), hasLapTelemetry: true });
    else if (myGameRecord) rows.push({ isMe: true, pilot: myPilotName() || 'Tú', color: myPilotColor(), total: myGameRecord.total, bestLap: null, sectors: [], hasLapTelemetry: false });
    for (const friend of friendPilots()) {
      const result = friend.events[eventId];
      if (result && (result.total > 0 || result.bestLap > 0)) rows.push({ pilot: String(friend.pilot), color: friend.color, friend, total: result.total > 0 ? +result.total : null,
        bestLap: result.bestLap > 0 ? +result.bestLap : null, sectors: Array.isArray(result.sectors) ? result.sectors : [],
        hasLapTelemetry: !!(result.bestLapTelemetry && Array.isArray(result.bestLapTelemetry.trace)), hasRaceTelemetry: !!(result.bestRaceTelemetry && Array.isArray(result.bestRaceTelemetry.laps)) });
    }
    rows.sort((first, second) => (first.total || 1e9) - (second.total || 1e9) || (first.bestLap || 1e9) - (second.bestLap || 1e9));
    return rows;
  }
  function friendsChip(event) {
    if (!friendPilots().length) return '';
    const rows = standings(event.id, event);
    if (rows.length < 2) return '';
    const myPosition = rows.findIndex(row => row.isMe) + 1;
    return '<span class="event-friends"><span class="position' + (myPosition === 1 ? ' first' : '') + '">' + myPosition + 'º</span> de ' + rows.length + ' entre amigos</span> · ';
  }
  function friendsPanel(event, inTab) {
    const allRows = standings(event.id, event);
    if (allRows.length < 2) return '';
    const shownFriends = allRows.filter(row => !row.isMe).slice(0, 3);
    const rows = allRows.filter(row => row.isMe || shownFriends.includes(row));
    const hiddenCount = allRows.length - rows.length;
    const sectorCount = Math.max(event.sectorCount || 0, ...rows.map(row => row.sectors.length));
    const showBestLap = event.plannedLaps !== 1;
    const bestOfColumn = valueOf => { const values = rows.map(valueOf).filter(value => value > 0); return values.length ? Math.min(...values) : null; };
    const bestTotal = bestOfColumn(row => row.total), bestLapTime = bestOfColumn(row => row.bestLap);
    const bestSectors = Array.from({ length: sectorCount }, (_, sectorIndex) => bestOfColumn(row => row.sectors[sectorIndex]));
    const myRow = rows.find(row => row.isMe);
    const isBestValue = (value, best) => value > 0 && best != null && Math.abs(value - best) < 0.0005;
    let html = (inTab ? '<div class="friends-pane">' : '<section class="panel"><div class="panel-header"><h2>Contra tus amigos</h2><span class="muted" title="el mejor tiempo de cada uno en este evento · resaltado, lo mejor de cada columna">el mejor tiempo de cada uno</span></div>') +
      '<div class="table-scroll"><table class="friends"><thead><tr><th>#</th><th>Piloto</th><th>' + (showBestLap ? 'Total' : 'Tiempo') + '</th><th>Dif.</th>' + (showBestLap ? '<th>Mejor vuelta</th>' : '') + '';
    for (let sectorNumber = 1; sectorNumber <= sectorCount; sectorNumber++) html += '<th>S' + sectorNumber + '</th>';
    html += '<th></th></tr></thead><tbody>';
    rows.forEach(row => {
      const difference = !row.isMe && myRow && myRow.total && row.total ? row.total - myRow.total : null;
      const position = allRows.indexOf(row);
      html += '<tr' + (row.isMe ? ' class="my-row"' : '') + '><td><span class="position' + (position === 0 && row.total ? ' first' : '') + '">' + (row.total ? position + 1 : '—') + '</span></td>' +
        '<td class="text">' + pilotDot(row.color) + '<b>' + escapeHtml(row.pilot) + '</b>' + (row.isMe ? ' <span class="tag">tú</span>' : row.friend.date ? ' <span class="muted">· archivo del ' + escapeHtml(String(row.friend.date).slice(0, 10)) + '</span>' : '') + '</td>' +
        '<td class="' + (isBestValue(row.total, bestTotal) ? 'best' : '') + '">' + (row.total ? formatTime(row.total) : '—') + '</td>' +
        '<td>' + (difference == null ? '—' : '<span class="' + (difference < 0 ? 'loss' : 'gain') + '" title="' + (difference < 0 ? 'te saca ' : 'le sacas ') + Math.abs(difference).toFixed(3) + ' s">' + formatSigned(difference) + '</span>') + '</td>' +
        (showBestLap ? '<td class="' + (isBestValue(row.bestLap, bestLapTime) ? 'best' : '') + '">' + (row.bestLap ? formatTime(row.bestLap) : '—') + '</td>' : '');
      for (let sectorIndex = 0; sectorIndex < sectorCount; sectorIndex++) {
        const sector = +row.sectors[sectorIndex], mySector = myRow && myRow.sectors[sectorIndex];
        html += '<td class="' + (isBestValue(sector, bestSectors[sectorIndex]) ? 'best' : '') + '"' + (!row.isMe && sector > 0 && mySector > 0 ? ' title="frente a ti: ' + formatSigned(sector - mySector) + ' s"' : '') + '>' + (sector > 0 ? sector.toFixed(3) : '—') + '</td>';
      }
      const compareButtons = (row.hasRaceTelemetry && showBestLap ? '<button type="button" class="button small" data-compare-friend-race="' + escapeHtml(row.pilot) + '">Comparar carrera</button> ' : '') +
        (row.hasLapTelemetry ? '<button type="button" class="button small" data-compare-friend="' + escapeHtml(row.pilot) + '">Comparar vuelta</button>' : '');
      html += '<td class="compare-cell">' + (row.isMe ? '' : compareButtons || '<span class="muted">solo tiempo</span>') + '</td></tr>';
    });
    html += '</tbody></table></div>' + (hiddenCount > 0 ? '<p class="more-friends muted">Y ' + hiddenCount + (hiddenCount === 1 ? ' amigo más' : ' amigos más') + ': <a data-navigate="social" href="#">ver todos en Social</a></p>' : '') +
      '<div class="note" title="' + '«Comparar vuelta» pone su mejor vuelta frente a tu mejor vuelta real. ' +
      (showBestLap ? '«Comparar carrera» pone su mejor carrera entera frente a la tuya, vuelta a vuelta. ' : '') +
      'Lo verás en la barra «A contra B», el mapa y la repetición, y en las gráficas. ' +
      (showBestLap ? 'Los sectores de esta tabla son los mejores de cada uno, no los de una sola vuelta. ' : '') +
      '«Solo tiempo»: su archivo trae el tiempo pero no la telemetría (récords importados del juego o un archivo de una versión anterior). ' +
      'El tiempo cuenta también el récord que importa el juego; «Comparar vuelta» usa la mejor vuelta grabada con el mod, que puede ser más lenta.' +
      '">Los botones de comparar llevan a su vuelta o carrera al mapa. Pasa el ratón aquí para más detalle.</div>' + (inTab ? '</div>' : '</section>');
    return html;
  }
  // Your friends' best laps of this event, as laps of the analysis (only if they are of the same course)
  const usableLapTelemetry = telemetry => telemetry && Array.isArray(telemetry.trace) && telemetry.trace.length >= 10 && telemetry.time > 0;
  // Another course or direction: the length of the lap does not match
  const otherCourse = (analysis, length) => analysis && analysis.lapLength && length && Math.abs(length - analysis.lapLength) / analysis.lapLength > 0.03;
  function lapFromFriendTelemetry(friend, telemetry, sessionLabel) {
    return { isFriend: true, pilot: String(friend.pilot), sessionLabel, number: telemetry.number || '', time: +telemetry.time,
      sectors: Array.isArray(telemetry.sectors) ? telemetry.sectors : null, measuredSectors: Array.isArray(telemetry.sectors) ? telemetry.sectors : [], incident: false, official: true,
      trace: telemetry.trace.filter(point => Array.isArray(point) && point.length >= 5).map(point => ({ distance: +point[0], time: +point[1], x: +point[2], y: +point[3], speed: +point[4], boost: BOOST_CODES[+point[5]] || '' })) };
  }
  function friendLaps(event, analysis) {
    const laps = [];
    for (const friend of friendPilots()) {
      const result = friend.events[event.id], telemetry = result && result.bestLapTelemetry;
      if (!usableLapTelemetry(telemetry) || otherCourse(analysis, telemetry.length)) continue;
      laps.push(lapFromFriendTelemetry(friend, telemetry, String(friend.pilot)));
    }
    return laps;
  }
  // Your friends' best laps 1 (their start), from pilot files of 0.9.25 on
  function friendStarts(event, analysis) {
    const laps = [];
    for (const friend of friendPilots()) {
      const result = friend.events[event.id], telemetry = result && result.bestStartTelemetry;
      if (!usableLapTelemetry(telemetry) || otherCourse(analysis, telemetry.length)) continue;
      const lap = lapFromFriendTelemetry(friend, telemetry, String(friend.pilot));
      lap.isFriendStart = true; lap.number = 1;
      if (telemetry.officialTime > 0 && Math.abs(telemetry.officialTime - lap.time) < 1.5) lap.officialTime = +telemetry.officialTime;
      laps.push(lap);
    }
    return laps;
  }
  // Your friends' best races (every lap of the attempt with their best total), from pilot files of 0.9.20 on
  function friendRaces(event, analysis) {
    const races = [];
    for (const friend of friendPilots()) {
      const result = friend.events[event.id], race = result && result.bestRaceTelemetry;
      if (!race || !Array.isArray(race.laps) || race.laps.length < 2 || !race.laps.every(usableLapTelemetry) || otherCourse(analysis, race.length)) continue;
      const entry = { pilot: String(friend.pilot), laps: race.laps.map(telemetry => {
        const lap = lapFromFriendTelemetry(friend, telemetry, String(friend.pilot));
        // As with your laps: the official time is shown only when it is close to the one measured
        if (telemetry.officialTime > 0 && Math.abs(telemetry.officialTime - lap.time) < 1.5) lap.officialTime = +telemetry.officialTime;
        return lap;
      }) };
      entry.total = +race.total > 0 ? +race.total : entry.laps.reduce((sum, lap) => sum + lap.time, 0);
      entry.laps.forEach(lap => { lap.friendRace = entry; });
      races.push(entry);
    }
    return races;
  }
  const officialLapTime = lap => (lap ? lap.officialTime || lap.time : null);
  // "Compare lap": your best real lap with telemetry (not the ideal one) against your friend's
  function bestOwnLap(analysis, event) {
    const ownLaps = analysis.laps.filter(lap => !lap.isIdeal && !lap.isFriend);
    const bestLap = event.bestLap && event.bestLap.session.telemetryFile ? event.bestLap : null;
    if (bestLap) {
      const label = (bestLap.session.date || bestLap.session.id).slice(5, 16);
      const sameSession = ownLaps.filter(lap => lap.sessionLabel === label);
      const match = sameSession.find(lap => lap.number === bestLap.lap.number && Math.abs(lap.time - bestLap.lap.time) < 1) ||
        sameSession.reduce((closest, lap) => (!closest || Math.abs(lap.time - bestLap.lap.time) < Math.abs(closest.time - bestLap.lap.time) ? lap : closest), null);
      if (match && !isStartLap(analysis, match)) return match;
    }
    const flying = ownLaps.filter(lap => !isStartLap(analysis, lap));
    return fastest(flying.length ? flying : ownLaps);
  }
  async function compareWithFriend(pilot, wholeRace) {
    const event = state.events.find(item => item.id === state.view.id);
    if (!event) return;
    if (!state.analysis) await (state.analysisLoading = loadAnalysis(event));
    const analysis = state.analysis;
    if (!analysis) { showToast('Marca algún intento tuyo en «Intentos» para compararte con ' + pilot); return; }
    // Carrera entera, o la vuelta que se estaba comparando (la 1 si no era una vuelta)
    const severalLaps = severalLapsEvent(analysis), number = comparedLapNumber();
    state.replay.scope = !severalLaps ? 'lap' : wholeRace ? 'race' : number > 1 ? 'L' + number : 'start';
    fitComparison(analysis);
    const item = comparisonCandidates(analysis).find(candidate => candidate.lap && candidate.lap.isFriend && candidate.lap.pilot === pilot);
    if (!item) { showToast((wholeRace ? 'La carrera de ' : 'La vuelta de ') + pilot + ' no es del mismo recorrido que la tuya'); renderLapTable(); drawAll(); return; }
    analysis.lapB = item.lap; state.replay.segment = null;
    if (wholeRace) state.replay.time = 0;
    if (isSimpleMode()) state.simpleRival = item.value;
    renderLapTable(); drawAll();
    const layout = byId('analysisLayout');
    if (layout) layout.scrollIntoView({ behavior: document.documentElement.classList.contains('no-animations') ? 'auto' : 'smooth' });
  }
  // Export: your best time of each event and the telemetry of your best lap (one point every 10 m)
  const fetchRawText = async path => (await fetchFromApp('/api/file?path=' + encodeURIComponent(path))).text();
  // An attempt analysed for the export (kept while exporting, as the best lap and the best race are often the same attempt)
  async function analyzeForExport(session, cache) {
    if (!session || !session.telemetryFile || !session.routeFile) return null;
    if (!cache[session.id]) cache[session.id] = (async () => {
      const route = parseRouteCsv(await fetchRawText(session.routeFile));
      const result = analyzeSession(route, parseSessionCsv(await fetchRawText(session.telemetryFile), vehicleTypeOfEvent(session.event)), 'export', rollingOf(session));
      return { result, length: Math.round(result.isPointToPoint ? result.span : route.points[route.points.length - 1][0]) };
    })();
    return cache[session.id];
  }
  // One point every 10 m: distance, time, x, y, speed, boost and (0.9.29) z, heading
  function traceForExport(lap) {
    const trace = [];
    let lastDistance = -Infinity;
    lap.trace.forEach((point, index) => {
      if (point.distance - lastDistance >= 1000 || index === lap.trace.length - 1) {
        const exported = [Math.round(point.distance), Math.round(point.time * 1000) / 1000, Math.round(point.x), Math.round(point.y), Math.round(point.speed * 10) / 10, BOOST_CODES.indexOf(point.boost || '')];
        // 0.9.29: height and heading, so your friends' in-game ghost of you flies at the right height and turns
        if (Number.isFinite(point.z) && Number.isFinite(point.heading)) exported.push(Math.round(point.z), Math.round(point.heading));
        trace.push(exported);
        lastDistance = point.distance;
      }
    });
    return trace;
  }
  async function bestLapForExport(event, cache) {
    const bestLap = event.bestLap;
    const analysed = bestLap && await analyzeForExport(bestLap.session, cache);
    if (!analysed) return null;
    const { result, length } = analysed;
    // The same lap (by number; its time measured in the telemetry can differ by a few tenths from the official one)
    const closest = result.laps.reduce((nearest, lap) => (!nearest || Math.abs(lap.time - bestLap.lap.time) < Math.abs(nearest.time - bestLap.lap.time) ? lap : nearest), null);
    const lap = result.laps.find(item => item.number === bestLap.lap.number && Math.abs(item.time - bestLap.lap.time) < 1) || (closest && Math.abs(closest.time - bestLap.lap.time) < 0.5 ? closest : null);
    if (!lap || lap.trace.length < 10) return null;
    return { number: lap.number, time: roundToMilliseconds(bestLap.lap.official ? bestLap.lap.time : lap.time), sectors: (lap.sectors || lap.measuredSectors || []).map(roundToMilliseconds),
      length, isPointToPoint: !!result.isPointToPoint, trace: traceForExport(lap) };
  }
  // Your best race: every lap of the attempt with your best total (only on events of several laps)
  // Your best lap 1 (the start), from the attempt where it was fastest (events of several laps)
  async function bestStartForExport(event, cache) {
    if (!(event.plannedLaps > 1)) return null;
    let best = null;
    for (const session of event.sessions) {
      if (!session.telemetryFile) continue;
      const lap = (session.laps || []).find(item => item.number === 1 && item.official && !item.incident);
      if (lap && (!best || lap.time < best.lap.time)) best = { session, lap };
    }
    if (!best) return null;
    const analysed = await analyzeForExport(best.session, cache);
    if (!analysed || analysed.result.isPointToPoint) return null;
    const lap = analysed.result.laps.find(item => item.number === 1);
    if (!lap || lap.trace.length < 10) return null;
    return { number: 1, time: roundToMilliseconds(lap.time), officialTime: roundToMilliseconds(best.lap.time), sectors: (lap.sectors || lap.measuredSectors || []).map(roundToMilliseconds),
      length: analysed.length, isPointToPoint: false, date: String(best.session.date || '').slice(0, 16), trace: traceForExport(lap) };
  }
  async function bestRaceForExport(event, cache) {
    const session = event.bestSession;
    if (!(event.plannedLaps > 1) || !session) return null;
    const analysed = await analyzeForExport(session, cache);
    if (!analysed || analysed.result.isPointToPoint) return null;
    const laps = analysed.result.laps.slice().sort((first, second) => first.number - second.number);
    if (laps.length < 2 || laps.length !== event.plannedLaps || laps.some(lap => lap.trace.length < 10)) return null;
    // "time" is the one measured, the one that matches the trace (the laps are joined with it, as yours are);
    // "officialTime" is the game's, when the summary has it (the first lap can differ by seconds: the measured one counts the start)
    const officialLaps = session.laps || [];
    return { date: String(session.date || '').slice(0, 16), total: roundToMilliseconds(session.total), length: analysed.length, isPointToPoint: false,
      laps: laps.map(lap => { const official = officialLaps.find(item => item.number === lap.number && item.official);
        return { number: lap.number, time: roundToMilliseconds(lap.time), officialTime: official ? roundToMilliseconds(official.time) : null,
          sectors: (lap.sectors || lap.measuredSectors || []).map(roundToMilliseconds), trace: traceForExport(lap) }; }) };
  }
  async function exportPilotFile() {
    const showMessage = html => { state.pilotMessage = html; if (byId('pilotMessage')) byId('pilotMessage').innerHTML = html; };
    const pilot = myPilotName();
    if (!pilot) { showMessage('<span class="loss">Antes crea tu perfil: </span><a data-navigate="profile" href="#">ponte un nombre de piloto</a>.'); return; }
    const events = state.events.filter(event => event.recordTime || event.bestLap);
    // Events with only the record imported from the game: their time goes too, for the friends' standings
    const withTelemetryIds = new Set(state.events.map(event => event.id));
    const recordsOnly = Object.keys(state.data.gameRecords || {}).filter(id => !withTelemetryIds.has(id)).map(id => ({ id, gameRecord: gameRecordOf(state.data, id) })).filter(item => item.gameRecord);
    if (!events.length && !recordsOnly.length) { showMessage('Aún no tienes tiempos que exportar.'); return; }
    byId('pilotExport').disabled = true;
    const file = { format: 'swgr-pilot', version: 2, pilot, color: myPilotColor(), date: new Date().toISOString().slice(0, 16).replace('T', ' '), app: state.data.version, events: {} };
    let prepared = 0, withLap = 0, withRace = 0, timeOnly = recordsOnly.length;
    const cache = {};
    for (const event of events) {
      showMessage('Preparando ' + (++prepared) + ' de ' + events.length + ': ' + escapeHtml(event.shortTitle || event.title) + '…');
      const gameRecord = gameRecordOf(state.data, event.id);
      const result = { name: event.title, planet: event.planet || '', vehicle: vehicleOf(event.id), plannedLaps: event.plannedLaps || null, total: roundToMilliseconds(event.recordTime),
        bestLap: event.plannedLaps === 1 ? roundToMilliseconds(Math.min(...[event.recordTime, event.bestLap && event.bestLap.lap.time].filter(value => value > 0))) : event.bestLap ? roundToMilliseconds(event.bestLap.lap.time) : null,
        sectors: event.bestSectors.map(best => (best ? roundToMilliseconds(best.value) : null)), startSector: event.bestStartSector ? roundToMilliseconds(event.bestStartSector.value) : null,
        idealLap: roundToMilliseconds(event.idealLap), date: event.bestSession ? String(event.bestSession.date || '').slice(0, 16) : '',
        attempts: event.attempts || 0, targetTime: event.targetSource && event.targetSource.target > 0 ? roundToMilliseconds(event.targetSource.target) : null,
        timeFrom: event.gameBest.total && event.recordTime === event.gameBest.total ? 'game' : 'mod' };
      if (!result.date && gameRecord) result.date = gameRecord.date;
      try { result.bestLapTelemetry = await bestLapForExport(event, cache); if (result.bestLapTelemetry) withLap++; } catch (error) { result.bestLapTelemetry = null; }
      try { result.bestRaceTelemetry = await bestRaceForExport(event, cache); if (result.bestRaceTelemetry) withRace++; } catch (error) { result.bestRaceTelemetry = null; }
      try { result.bestStartTelemetry = await bestStartForExport(event, cache); } catch (error) { result.bestStartTelemetry = null; }
      if (!result.bestLapTelemetry && !result.bestRaceTelemetry) timeOnly++;
      for (const sessionId of Object.keys(cache)) delete cache[sessionId];   // the next event uses other attempts
      file.events[event.id] = result;
    }
    for (const { id, gameRecord } of recordsOnly) {
      const titles = eventTitles(state.data, id, gameRecord);
      file.events[id] = { name: titles.title, planet: titles.planet || '', vehicle: vehicleOf(id), plannedLaps: null, total: roundToMilliseconds(gameRecord.total), bestLap: null, sectors: [], startSector: null,
        idealLap: null, date: gameRecord.date || '', attempts: gameRecord.attempts || 0, targetTime: gameRecord.target > 0 ? roundToMilliseconds(gameRecord.target) : null, timeFrom: 'game',
        bestLapTelemetry: null, bestRaceTelemetry: null, bestStartTelemetry: null };
    }
    try {
      const response = await postJson('/api/export-pilot', file);
      const { path } = await response.json();
      const eventCount = events.length + recordsOnly.length;
      showMessage('<b>Listo:</b> ' + eventCount + (eventCount === 1 ? ' evento' : ' eventos') + ' (' + withRace + ' con la carrera entera, ' + withLap + ' con la mejor vuelta, ' +
        timeOnly + ' solo con el tiempo) en <span class="numeric">' + escapeHtml(path) + '</span>. Te he abierto la carpeta: pásaselo a tus amigos.');
    } catch (error) { showMessage('<span class="loss">No se pudo guardar: ' + escapeHtml(error.message) + '</span>'); }
    byId('pilotExport').disabled = false;
  }
  async function importPilotFiles(fileList) {
    const files = [...(fileList || [])].filter(file => /\.swgr$/i.test(file.name));
    if (!files.length) { showToast('Eso no es un archivo de piloto (.swgr)'); return; }
    const added = [], failed = [];
    for (const file of files) {
      try {
        const response = await fetchFromApp('/api/add-friend', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: await file.text() });
        added.push((await response.json()).pilot);
      } catch (error) { failed.push(file.name + ': ' + error.message.trim()); }
    }
    if (added.length) showToast('Añadido: ' + added.join(', '));
    if (failed.length) showToast('No se pudo añadir ' + failed.join(' · '));
    await refreshData();
  }
  // El botón «Importar tiempos» de la barra de arriba abre el selector de archivos de piloto
  byId('importButton').addEventListener('click', () => byId('pilotFileInput').click());
  byId('pilotFileInput').addEventListener('change', changeEvent => { importPilotFiles(changeEvent.target.files); changeEvent.target.value = ''; });
  // .swgr files can be dragged onto any part of the window
  const draggingFiles = dragEvent => [...(dragEvent.dataTransfer && dragEvent.dataTransfer.types || [])].includes('Files');
  document.addEventListener('dragover', dragEvent => { if (draggingFiles(dragEvent)) { dragEvent.preventDefault(); const dropZone = document.querySelector('.drop-zone'); if (dropZone) dropZone.classList.add('drag-over'); } });
  document.addEventListener('dragleave', dragEvent => { if (!dragEvent.relatedTarget) { const dropZone = document.querySelector('.drop-zone'); if (dropZone) dropZone.classList.remove('drag-over'); } });
  document.addEventListener('drop', dragEvent => {
    if (!dragEvent.dataTransfer || !dragEvent.dataTransfer.files.length) return;
    dragEvent.preventDefault(); const dropZone = document.querySelector('.drop-zone'); if (dropZone) dropZone.classList.remove('drag-over');
    importPilotFiles(dragEvent.dataTransfer.files);
  });
