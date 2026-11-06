  // ---------- What is compared: always like with like ----------
  // The scope is state.replay.scope: 'race' (whole race), 'start' (lap 1), 'L2'… (lap 2…), 'lap' (the only lap of a one-lap event)
  // or a sector ('S1'…, only from the tables). A and B are of that kind: the same lap (or sector) of two races, or two whole races.
  const comparisonKind = () => (state.replay.scope === 'race' ? 'race' : state.replay.scope === 'start' ? 'start' : /^S\d+$/.test(state.replay.scope) ? 'sector' : 'lap');
  // The number of the lap being compared (null: the whole race or a sector)
  const comparedLapNumber = () => { const scope = state.replay.scope; return scope === 'start' || scope === 'lap' ? 1 : /^L\d+$/.test(scope) ? +scope.slice(1) : null; };
  // Lap 1 of an event of several laps: you start from the grid, so it is compared only with other laps 1
  const severalLapsEvent = analysis => !!(analysis && analysis.event && analysis.event.plannedLaps > 1 && !(analysis.track && analysis.track.isPointToPoint));
  const isStartLap = (analysis, lap) => !!lap && severalLapsEvent(analysis) && (lap === analysis.idealStartLap || lap.isFriendStart || (!lap.isIdeal && lap.number === 1));
  const fastest = laps => laps.filter(lap => !lap.incident).sort((first, second) => officialLapTime(first) - officialLapTime(second))[0] || laps[0] || null;
  // A whole race: an attempt of yours, or a friend's best race, with every lap of the event
  function isWholeRace(analysis, lap) {
    if (!lap || (lap.isIdeal && !lap.idealRace) || (lap.isFriend && !lap.friendRace)) return false;
    const laps = sessionLaps(analysis, lap), planned = analysis.event && analysis.event.plannedLaps;
    return laps.length > 1 && (!(planned > 1) || laps.length === planned);
  }
  const firstLapOfRace = (analysis, lap) => sessionLaps(analysis, lap)[0] || lap;
  // The time of a whole race: the game's total when there is one, if not the sum of its laps
  function raceTime(analysis, lap) {
    if (lap.friendRace) return lap.friendRace.total;
    if (lap.idealRace) return lap.idealRace.total;
    const session = analysis.event && analysis.event.sessions.find(item => item.id === lap.sessionId);
    return session && session.total > 0 ? session.total : sessionLaps(analysis, lap).reduce((sum, item) => sum + officialLapTime(item), 0);
  }
  // Your loaded whole races (their first laps stand for them), the fastest first
  function ownRaces(analysis) {
    const firstLaps = {};
    analysis.laps.forEach(lap => { if (isOwnLap(lap) && isWholeRace(analysis, lap)) { const first = firstLapOfRace(analysis, lap); firstLaps[first.sessionId] = first; } });
    return Object.values(firstLaps).sort((first, second) => raceTime(analysis, first) - raceTime(analysis, second));
  }
  // The attempt chosen in the list on the left (if it is loaded): A always comes from it
  function selectedSessionId(analysis) {
    const loaded = id => id && analysis.laps.some(lap => isOwnLap(lap) && lap.sessionId === id);
    const focused = focusedSession(analysis.event), best = analysis.event.bestSession;
    if (focused && loaded(focused.id)) return focused.id;
    if (best && loaded(best.id)) return best.id;
    const first = analysis.laps.find(lap => isOwnLap(lap));
    return first ? first.sessionId : null;
  }
  // Lap `number` of one of your attempts (the first one if it has no such number)
  function lapOfSession(analysis, sessionId, number) {
    const laps = analysis.laps.filter(lap => isOwnLap(lap) && lap.sessionId === sessionId).sort((first, second) => first.number - second.number);
    return laps.find(lap => lap.number === number) || (number === 1 ? laps[0] : null) || null;
  }
  // What B can be: the same thing as A (the whole race, or the same lap) of your friends and of your other races, the friends first
  function comparisonCandidates(analysis) {
    const kind = comparisonKind(), number = comparedLapNumber(), items = [];
    if (kind === 'sector' || !analysis.lapA) return items;
    const wholeRace = kind === 'race', severalLaps = severalLapsEvent(analysis), mySession = analysis.lapA.sessionId;
    const friends = [];
    if (severalLaps) {
      const lapCount = sessionLaps(analysis, analysis.lapA).length;
      (analysis.friendRaces || []).filter(race => !wholeRace || race.laps.length === lapCount).forEach(race => {
        const lap = wholeRace ? race.laps[0] : race.laps[number - 1];
        if (lap) friends.push({ lap, sortKey: race.total, text: wholeRace ? formatTime(race.total) : formatTime(officialLapTime(lap)) });
      });
    } else (analysis.friendLaps || []).forEach(lap => friends.push({ lap, sortKey: lap.time, text: formatTime(lap.time) }));
    friends.sort((first, second) => first.sortKey - second.sortKey).forEach(friend => items.push({ lap: friend.lap, value: lapValue(analysis, friend.lap), group: 'Amigos',
      label: friend.lap.pilot, detail: friend.lap.pilot + (severalLaps && !wholeRace ? ' · su vuelta ' + number : wholeRace ? ' · su mejor carrera' : ' · su mejor vuelta') + ' · ' + friend.text }));
    // Your other attempts, the fastest first; the ones not loaded are loaded when picked
    const sessionIds = severalLaps ? ownRaces(analysis).map(lap => lap.sessionId) : [...new Set(analysis.laps.filter(lap => isOwnLap(lap)).map(lap => lap.sessionId))];
    const totalOf = id => raceTime(analysis, lapOfSession(analysis, id, 1));
    sessionIds.filter(id => id !== mySession).sort((first, second) => totalOf(first) - totalOf(second)).forEach(id => {
      const lap = wholeRace ? firstLapOfRace(analysis, lapOfSession(analysis, id, 1)) : lapOfSession(analysis, id, number);
      if (!lap) return;
      items.push({ lap, value: lapValue(analysis, lap), group: 'Tus carreras', label: 'Tú · ' + lap.sessionLabel,
        detail: (wholeRace ? 'Tu carrera del ' : 'Tu vuelta ' + number + ' del ') + lap.sessionLabel + ' · ' + formatTime(wholeRace ? totalOf(id) : officialLapTime(lap)) });
    });
    const event = analysis.event, loaded = new Set(analysis.laps.map(lap => lap.sessionId));
    event.sessions.filter(session => session.telemetryFile && !loaded.has(session.id) && (session.laps || []).length === event.plannedLaps).slice().reverse().forEach(session => {
      items.push({ lap: null, value: 'race:' + session.id, group: 'Otras carreras tuyas (se cargan al comparar)', label: 'Tú · ' + (session.date || session.id).slice(5, 16) + (sessionTotalText(session) ? ' · ' + sessionTotalText(session) : '') });
    });
    return items;
  }
  // Puts A and B in line with the scope: A from the attempt chosen in the list, B the same thing of someone else
  // (keepB: the same rival as before if he is still there; if not, the fastest friend or your best other race)
  function fitComparison(analysis, keepB) {
    if (!analysis) return;
    state.replay.segment = null;
    if (comparisonKind() === 'sector') return;   // a sector is a stretch of the A and B that were there
    const mySession = selectedSessionId(analysis);
    if (!mySession) return;
    let lapA = null;
    if (comparisonKind() === 'race') {
      lapA = ownRaces(analysis).find(lap => lap.sessionId === mySession) || null;
      if (!lapA) { state.replay.scope = severalLapsEvent(analysis) ? 'start' : 'lap'; fitComparison(analysis, keepB); return; }
    } else lapA = lapOfSession(analysis, mySession, comparedLapNumber()) || analysis.lapA;
    const previousB = analysis.lapB;
    analysis.lapA = lapA;
    const items = comparisonCandidates(analysis).filter(item => item.lap && item.lap !== lapA);
    const sameRival = item => previousB && (previousB.isFriend ? item.lap.isFriend && item.lap.pilot === previousB.pilot : !item.lap.isFriend && !item.lap.isIdeal && item.lap.sessionId === previousB.sessionId);
    const chosen = (keepB && items.find(sameRival)) || items[0];
    analysis.lapB = chosen ? chosen.lap : null;
  }
  // How A and B are called in the bar: short, so that it fits the narrow map column (the long text is comparisonDetail)
  function comparisonName(analysis, lap) {
    if (!lap) return '—';
    if (lap.isIdeal || lap.idealRace) return lap.sessionLabel || 'Vuelta ideal';
    if (lap.isFriend || lap.friendRace || lap.isFriendStart) return lap.pilot;
    const event = analysis.event;
    const isBest = comparisonKind() === 'race' ? event && event.bestSession && event.bestSession.id === lap.sessionId
      : event && event.bestLap && lap.number === event.bestLap.lap.number && Math.abs(officialLapTime(lap) - event.bestLap.lap.time) < 0.0005;
    return 'Tú · ' + lap.sessionLabel + (isBest ? ' (tu mejor)' : '');
  }
  // The same, with every detail (tooltip)
  function comparisonDetail(analysis, lap) {
    if (!lap) return '—';
    if (lap.idealRace) return 'Carrera ideal (tu mejor salida y tus mejores vueltas)';
    if (lap === analysis.idealStartLap) return 'Vuelta 1 ideal (tus mejores salidas)';
    if (lap.isIdeal) return 'Vuelta ideal (tus mejores sectores)';
    if (lap.isFriendStart) return lap.pilot + ' · su mejor vuelta 1';
    if (lap.friendRace && comparisonKind() !== 'race') return lap.pilot + ' · su vuelta ' + (lap.friendRace.laps.indexOf(lap) + 1);
    if (lap.friendRace) return lap.pilot + ' · su mejor carrera';
    if (lap.isFriend) return lap.pilot + ' · su mejor vuelta';
    const event = analysis.event;
    if (comparisonKind() === 'race') return 'Tú · carrera del ' + lap.sessionLabel + (event && event.bestSession && event.bestSession.id === lap.sessionId ? ' (tu mejor)' : '');
    const isBestLap = event && event.bestLap && lap.number === event.bestLap.lap.number && Math.abs(officialLapTime(lap) - event.bestLap.lap.time) < 0.0005;
    if (comparisonKind() === 'start') return 'Tú · V1 (salida) del ' + lap.sessionLabel;
    return 'Tú · V' + lap.number + ' del ' + lap.sessionLabel + (isBestLap ? ' (tu mejor vuelta)' : '');
  }
  function comparisonTime(analysis, lap) {
    if (!lap) return null;
    const kind = comparisonKind();
    if (kind === 'race') return raceTime(analysis, lap);
    if (kind === 'sector') { const sector = +(lap.sectors || lap.measuredSectors || [])[+state.replay.scope.slice(1) - 1]; return sector > 0 ? sector : null; }
    return officialLapTime(lap);
  }
  function updateVersusBar() {
    const analysis = state.analysis;
    if (!analysis || !byId('versusBar')) return;
    const kind = comparisonKind(), format = value => (value > 0 ? (kind === 'sector' ? value.toFixed(3) : formatTime(value)) : '');
    const timeA = comparisonTime(analysis, analysis.lapA), timeB = comparisonTime(analysis, analysis.lapB);
    byId('selectedA').textContent = comparisonName(analysis, analysis.lapA); byId('selectedA').title = analysis.lapA ? comparisonDetail(analysis, analysis.lapA) : '';
    byId('selectedB').textContent = analysis.lapB ? comparisonName(analysis, analysis.lapB) : (kind === 'race' ? 'ninguna carrera con las mismas vueltas' : 'elige con quién');
    byId('selectedTimeA').textContent = format(timeA); byId('selectedTimeB').textContent = format(timeB);
    byId('legendLineB').style.background = analysis.lapB && analysis.lapB.isIdeal ? 'var(--best)' : 'var(--reference)';
    const difference = timeA > 0 && timeB > 0 ? timeA - timeB : null;
    byId('versusGap').innerHTML = difference == null ? '' : Math.abs(difference) < 0.0005 ? '<span class="tag">empate</span>'
      : '<b class="' + (difference < 0 ? 'gain' : 'loss') + '">A ' + (difference < 0 ? 'gana por ' : 'pierde por ') + Math.abs(difference).toFixed(3) + ' s</b>';
    if (byId('sectorTableTitle')) byId('sectorTableTitle').textContent = kind === 'race' ? 'Vuelta a vuelta' : 'Sector a sector';
    if (byId('chartsTitle')) byId('chartsTitle').textContent = kind === 'race' ? 'Diferencia y velocidad a lo largo de la carrera' : kind === 'start' ? 'Diferencia y velocidad en la vuelta 1 (salida)' : kind === 'lap' && comparedLapNumber() > 1 && severalLapsEvent(analysis) ? 'Diferencia y velocidad en la vuelta ' + comparedLapNumber() : kind === 'sector' ? 'Diferencia y velocidad en el sector ' + state.replay.scope : 'Diferencia y velocidad a lo largo de la vuelta';
  }
  // What the replay shows for the current scope: the two traces (A and B), cached until A, B or the scope change
  function replaySegment() {
    const analysis = state.analysis, replay = state.replay;
    if (!analysis || !analysis.lapA) return null;
    const lapKey = lap => lap ? [lap.sessionLabel, lap.number, lap.idealRace ? 'idealrace' : lap.isIdeal ? 'ideal' : lap.friendRace ? 'race' : lap.isFriendStart ? 'start' : '', lap.pilot || ''].join('|') : '-';
    const key = [replay.scope, lapKey(analysis.lapA), lapKey(analysis.lapB)].join('#');
    if (replay.segment && replay.segment.key === key && replay.segment.analysis === analysis) return replay.segment;
    let traceA = null, traceB = null, kind = 'lap', startDistance = 0, endDistance = analysis.lapLength, lapsA = null, lapsB = null, sectorNumber = null;
    if (replay.scope === 'race' && isOwnLap(analysis.lapA) && isWholeRace(analysis, analysis.lapA)) {
      kind = 'race';
      lapsA = sessionLaps(analysis, analysis.lapA); traceA = joinLaps(analysis, lapsA);
      const rival = raceRival(analysis, analysis.lapA, analysis.lapB);
      if (rival) { lapsB = rival.laps; traceB = joinLaps(analysis, lapsB); }
      endDistance = analysis.lapLength * traceA.lapCount;
    } else if (/^S\d+$/.test(replay.scope)) {
      const sectorIndex = +replay.scope.slice(1) - 1, bounds = sectorBounds(analysis);
      if (sectorIndex < bounds.length - 1) {
        kind = 'sector'; startDistance = bounds[sectorIndex]; endDistance = bounds[sectorIndex + 1]; sectorNumber = sectorIndex + 1;
        traceA = sliceLap(analysis.lapA, startDistance, endDistance); traceB = analysis.lapB ? sliceLap(analysis.lapB, startDistance, endDistance) : null;
      }
    }
    if (!traceA) {
      kind = 'lap'; traceA = { trace: analysis.lapA.trace, time: analysis.lapA.time };
      traceB = analysis.lapB ? { trace: analysis.lapB.trace, time: analysis.lapB.time } : null;
    }
    let zoomBox = null;
    if (kind === 'sector') {
      const xs = [], ys = [];
      [traceA, traceB].forEach(item => item && item.trace.forEach(point => { xs.push(point.x); ys.push(point.y); }));
      const minX = Math.min(...xs), maxX = Math.max(...xs), minY = Math.min(...ys), maxY = Math.max(...ys);
      const margin = Math.max(maxX - minX, maxY - minY) * 0.12 + 2000;
      zoomBox = { minX: minX - margin, maxX: maxX + margin, minY: minY - margin, maxY: maxY + margin };
    }
    replay.segment = { key, analysis, traceA, traceB, kind, startDistance, endDistance, zoomBox, nameB: referenceName(analysis.lapB), lapsA, lapsB, sectorNumber };
    return replay.segment;
  }
  function replayDuration() {
    const segment = replaySegment(), replay = state.replay;
    if (!segment) return 0;
    return replay.sync === 'samePoint' || !segment.traceB ? segment.traceA.time : Math.max(segment.traceA.time, segment.traceB.time);
  }
  // Where each car is at the replay's current instant
  function replayCars() {
    const segment = replaySegment(), replay = state.replay;
    if (!segment || replay.time == null) return null;
    const carA = lapPointAtTime(segment.traceA, replay.time);
    let carB = null, timeOfB = null;
    if (segment.traceB) {
      if (replay.sync === 'samePoint') {
        carB = lapPointAtDistance(segment.traceB, carA.distance);
        const timeByDistance = timeAtDistance(segment.traceB); timeOfB = interpolate(timeByDistance.distances, timeByDistance.times, carA.distance);
      } else carB = lapPointAtTime(segment.traceB, replay.time);
    }
    const lapIndexAt = (distance, lapCount) => Math.max(0, Math.min(lapCount - 1, Math.floor(distance / state.analysis.lapLength)));
    const lapIndexA = segment.lapsA ? lapIndexAt(carA.distance, segment.lapsA.length) : null;
    const lapIndexB = segment.lapsB ? (replay.sync === 'samePoint' || !carB ? lapIndexA : lapIndexAt(carB.distance, segment.lapsB.length)) : null;
    return { segment, carA, carB, timeOfB, lapIndexA, lapIndexB };
  }
  // ---------- Boost (ramjet / afterburner), recorded from mod 0.9.25 on ----------
  const BOOST_CODES = ['', 'N', 'A', 'R'];
  const BOOST_NAMES = { N: 'Normal', A: 'Postcombustión', R: 'Ramjet' };
  // What a trace was using at an instant: '' when its race has no boost data (recorded before 0.9.25)
  function boostAt(lap, time) {
    if (!lap || !lap.trace || time == null) return '';
    if (lap.hasBoost === undefined) lap.hasBoost = lap.trace.some(point => point.boost);
    if (!lap.hasBoost) return '';
    const trace = lap.trace;
    let low = 0, high = trace.length - 1;
    while (high - low > 1) { const middle = (low + high) >> 1; if (trace[middle].time <= time) low = middle; else high = middle; }
    return trace[low].boost || '';
  }
  // A and B in the replay: B at the same instant or, comparing at the same point, when it passed there
  function replayBoost(cars) {
    if (!cars) return { a: '', b: '' };
    const replay = state.replay;
    return { a: boostAt(cars.segment.traceA, replay.time), b: boostAt(cars.segment.traceB, replay.sync === 'samePoint' ? cars.timeOfB : replay.time) };
  }
  function showBoostTags(boost) {
    [['boostTagA', boost.a], ['boostTagB', boost.b]].forEach(([id, code]) => {
      const tag = byId(id);
      if (!tag) return;
      tag.style.visibility = code ? 'visible' : 'hidden'; tag.dataset.boost = code; tag.textContent = BOOST_NAMES[code] || '';
    });
  }
  function showReplayFrame() {
    const analysis = state.analysis, replay = state.replay;
    if (!analysis || !analysis.lapA || !byId('replayPosition')) return;
    const duration = replayDuration(), cars = replayCars();
    if (cars) {
      const { segment, carA, carB, timeOfB } = cars;
      state.hoverDistance = Math.min(segment.endDistance, Math.max(segment.startDistance, carA.distance));   // in the charts' stretch
      byId('replayPosition').value = Math.round(replay.time / (duration || 1) * 1000);
      byId('replayTime').textContent = formatTime(replay.time) === '—' ? '0.0' : formatTime(replay.time).replace(/(\.\d)\d\d$/, '$1');
      if (carB && replay.sync === 'samePoint') {
        const difference = replay.time - timeOfB;
        byId('replayGap').innerHTML = 'En el mismo punto: A lleva <b>' + replay.time.toFixed(2) + ' s</b> y ' + escapeHtml(segment.nameB) + ' <b>' + timeOfB.toFixed(2) + ' s</b> · ' +
          (difference <= 0 ? '<b class="gain">A gana ' + Math.abs(difference).toFixed(2) + ' s</b>' : '<b class="loss">A pierde ' + difference.toFixed(2) + ' s</b>');
      } else if (carB) {
        const timeByDistance = timeAtDistance(segment.traceB), gap = replay.time - interpolate(timeByDistance.distances, timeByDistance.times, carA.distance), meters = (carA.distance - carB.distance) / 100;
        byId('replayGap').innerHTML = 'A ' + (gap <= 0 ? '<b class="gain">va ' + Math.abs(gap).toFixed(2) + ' s por delante</b>' : '<b class="loss">va ' + gap.toFixed(2) + ' s por detrás</b>') +
          ' de ' + escapeHtml(segment.nameB) + ' · ' + Math.abs(meters).toFixed(0) + ' m';
      } else byId('replayGap').textContent = segment.kind === 'race' ? 'Elige en B otra carrera entera para ver la diferencia.' : 'Elige B para ver la diferencia.';
    } else { byId('replayGap').textContent = ''; byId('replayTime').textContent = '0:00.0'; byId('replayPosition').value = 0; }
    showBoostTags(replayBoost(cars));
    drawAll();
  }
  function replayTick(now) {
    const replay = state.replay;
    if (!replay.playing) return;
    if (!byId('replaySpeed')) { stopReplay(true); return; }   // the event screen was left while it played
    const elapsed = Math.min(0.1, (now - replay.lastFrame) / 1000); replay.lastFrame = now;
    replay.time = Math.min(replayDuration(), (replay.time || 0) + elapsed * (+byId('replaySpeed').value || 1));
    if (replay.time >= replayDuration()) stopReplay(false);
    showReplayFrame();
    if (replay.playing) replay.animationFrame = requestAnimationFrame(replayTick);
  }
  function stopReplay(reset) {
    const replay = state.replay; replay.playing = false; cancelAnimationFrame(replay.animationFrame);
    if (byId('replayPlay')) byId('replayPlay').textContent = '▶ Repetición';
    if (reset) { replay.time = null; state.hoverDistance = null; }
  }
  function startReplay() {
    const replay = state.replay;
    if (!state.analysis || !state.analysis.lapA) return;
    if (replay.time == null || replay.time >= replayDuration()) replay.time = 0;
    replay.playing = true; replay.lastFrame = performance.now(); if (byId('replayPlay')) byId('replayPlay').textContent = '❚❚ Pausa';
    replay.animationFrame = requestAnimationFrame(replayTick);
  }
  function setReplayScope(scope) {
    const replay = state.replay, analysis = state.analysis;
    replay.scope = scope; replay.segment = null;
    // What is compared changes: A and B become things of that kind (the same rival, if he has it)
    fitComparison(analysis, true);
    if (isSimpleMode() && analysis) useSimpleComparison(analysis);
    renderLapTable();
    if (byId('replayScope')) byId('replayScope').value = replay.scope;
    replay.time = 0; showReplayFrame();
  }
  document.addEventListener('click', clickEvent => {
    if (clickEvent.target.id === 'replayPlay' && state.analysis && state.analysis.lapA) { if (state.replay.playing) stopReplay(false); else startReplay(); return; }
    if (clickEvent.target.id === 'replayFollow') {
      const replay = state.replay; replay.followCar = !replay.followCar; clickEvent.target.setAttribute('aria-pressed', String(replay.followCar));
      if (replay.time == null) replay.time = 0;
      showReplayFrame(); return;
    }
    const scopeRow = clickEvent.target.closest('[data-replay-scope]');
    if (scopeRow && state.analysis) { setReplayScope(scopeRow.dataset.replayScope); if (!state.replay.playing) startReplay(); }
  });
  document.addEventListener('change', changeEvent => {
    if (changeEvent.target.id === 'replayScope') setReplayScope(changeEvent.target.value);
    else if (changeEvent.target.id === 'replaySync') {
      const replay = state.replay; replay.sync = changeEvent.target.value;
      if (replay.time != null) replay.time = Math.min(replay.time, replayDuration());
      showReplayFrame();
    }
  });
  document.addEventListener('input', inputEvent => {
    if (inputEvent.target.id !== 'replayPosition' || !state.analysis) return;
    state.replay.time = +inputEvent.target.value / 1000 * replayDuration(); showReplayFrame();
  });
  // Comparer of your choice: A and B can be any of your laps with telemetry or a friend's
  // (the ideal lap too), and the whole race of each attempt ("race:<id>"), including the
  // attempts not ticked: they are loaded when you compare.
  const sessionTotalText = session => (session && session.total ? formatTime(session.total) : '');
  const pickerOption = (value, text, selected, detail) => '<option value="' + escapeHtml(value) + '"' + (selected ? ' selected' : '') + (detail ? ' title="' + escapeHtml(detail) + '"' : '') + '>' + escapeHtml(text) + '</option>';
  // A is the attempt chosen in the list; B offers the same thing (whole race or same lap) of friends and of your other races
  function fillComparisonPickers() {
    const analysis = state.analysis;
    if (!analysis || !byId('compareA')) return;
    const kind = comparisonKind();
    byId('compareA').innerHTML = analysis.lapA ? pickerOption(lapValue(analysis, analysis.lapA), comparisonName(analysis, analysis.lapA), true) : '';
    byId('compareA').title = analysis.lapA ? comparisonDetail(analysis, analysis.lapA) : '';
    const groups = [];
    comparisonCandidates(analysis).forEach(item => {
      let group = groups.find(entry => entry.label === item.group);
      if (!group) { group = { label: item.group, items: [] }; groups.push(group); }
      group.items.push(item);
    });
    let html = analysis.lapB ? '' : '<option value="">—</option>';
    groups.forEach(group => { html += '<optgroup label="' + escapeHtml(group.label) + '">' + group.items.map(item => pickerOption(item.value, item.label, !!item.lap && item.lap === analysis.lapB, item.detail)).join('') + '</optgroup>'; });
    if (kind === 'sector' && analysis.lapB) html += pickerOption(lapValue(analysis, analysis.lapB), comparisonName(analysis, analysis.lapB), true);
    byId('compareB').innerHTML = html;
    byId('compareB').title = analysis.lapB ? comparisonDetail(analysis, analysis.lapB) : '';
  }
  document.addEventListener('change', async changeEvent => {
    if ((changeEvent.target.id !== 'compareA' && changeEvent.target.id !== 'compareB') || !state.analysis) return;
    const valueB = byId('compareB').value;
    // The race of an attempt that is not ticked: it is ticked and loaded
    const event = state.analysis.event;
    if (valueB.startsWith('race:') && event && !state.analysis.laps.some(lap => lap.sessionId === valueB.slice(5))) {
      const selection = selectedSessions(event), id = valueB.slice(5);
      selection.add(id); const checkbox = document.querySelector('[data-select-session="' + CSS.escape(id) + '"]'); if (checkbox) checkbox.checked = true;
      await (state.analysisLoading = loadAnalysis(event));
      if (!state.analysis) return;
    }
    const analysis = state.analysis;
    // The same lap of that attempt (the first lap for a whole race)
    const lapB = valueB.startsWith('race:') ? lapOfSession(analysis, valueB.slice(5), comparedLapNumber() || 1) : lapFromValue(analysis, valueB);
    const lapA = analysis.lapA;
    if (!lapA || (valueB && !lapB)) { showToast('Elige A y B'); renderLapTable(); return; }
    if (lapA === lapB) { showToast('Elige dos cosas distintas'); renderLapTable(); return; }
    if (comparisonKind() === 'race' && lapB && (!isWholeRace(analysis, lapA) || !raceRival(analysis, lapA, lapB))) { showToast('Esas dos carreras no tienen las mismas vueltas'); renderLapTable(); return; }
    analysis.lapB = lapB || null; state.replay.segment = null;
    if (comparisonKind() === 'race') state.replay.time = 0;
    renderLapTable(); drawAll();
  });
  // What can be compared: the whole race and each of its laps (lap 1 is the start); a sector only when it comes from a table
  function fillReplayScopes() {
    const picker = byId('replayScope'), analysis = state.analysis;
    if (!picker || !analysis) return;
    const replay = state.replay, planned = analysis.event.plannedLaps;
    const hasLaps = analysis.laps.some(lap => isOwnLap(lap));
    let html = '';
    if (severalLapsEvent(analysis)) {
      if (ownRaces(analysis).length) html += '<option value="race">Carrera entera</option>';
      if (hasLaps) html += '<option value="start">Vuelta 1 (salida)</option>';
      if (hasLaps) for (let lapNumber = 2; lapNumber <= planned; lapNumber++) html += '<option value="L' + lapNumber + '">Vuelta ' + lapNumber + '</option>';
    } else html = '<option value="lap">Carrera entera</option>';
    if (comparisonKind() === 'sector') html += '<option value="' + replay.scope + '">Sector ' + replay.scope + '</option>';
    picker.innerHTML = html;
    if (![...picker.options].some(option => option.value === replay.scope)) { replay.scope = picker.options.length ? picker.options[0].value : 'lap'; fitComparison(analysis); }
    picker.value = replay.scope;
    if (byId('replaySync')) byId('replaySync').value = replay.sync;
    if (byId('replayFollow')) byId('replayFollow').setAttribute('aria-pressed', String(replay.followCar));
  }
  // Sector by sector table: A against the reference, and who wins each stretch
  function renderSectorComparison() {
    const box = byId('sectorComparison'), analysis = state.analysis;
    if (!box) return;
    if (!analysis || !analysis.lapA) { box.innerHTML = ''; return; }
    const lapA = analysis.lapA, lapB = analysis.lapB, sectorCount = analysis.track ? analysis.track.sectorCount : 0, rows = [];
    const wholeRace = comparisonKind() === 'race';
    // The scope the lap row goes back to (the lap being compared before a sector was picked)
    if (comparisonKind() !== 'sector') state.replay.lapScope = state.replay.scope;
    if (wholeRace) {
      // Two whole races: lap by lap and the total
      const lapsA = sessionLaps(analysis, lapA), rival = raceRival(analysis, lapA, lapB);
      lapsA.forEach((lap, index) => rows.push({ scope: null, label: 'V' + lap.number, timeA: officialLapTime(lap), timeB: rival ? officialLapTime(rival.laps[index]) : null }));
      rows.push({ scope: 'race', label: 'Carrera (' + lapsA.length + ' vueltas)', timeA: raceTime(analysis, lapA), timeB: rival ? raceTime(analysis, lapB) : null });
    } else {
      // Two laps: sector by sector and the lap
      const sectorsA = lapA.sectors || lapA.measuredSectors || [], sectorsB = lapB ? (lapB.sectors || lapB.measuredSectors || []) : [];
      for (let sectorIndex = 0; sectorIndex < sectorCount; sectorIndex++) rows.push({ scope: 'S' + (sectorIndex + 1), label: 'S' + (sectorIndex + 1), timeA: +sectorsA[sectorIndex], timeB: +sectorsB[sectorIndex], isSector: true });
      rows.push({ scope: state.replay.lapScope || 'lap', label: 'Vuelta', timeA: officialLapTime(lapA), timeB: lapB ? officialLapTime(lapB) : null });
    }
    const formatCell = (value, isSector) => (value > 0 ? (isSector ? value.toFixed(3) : formatTime(value)) : '—');
    let html = '<table class="sector-table"><thead><tr><th>' + (wholeRace ? 'Vuelta' : 'Tramo') + '</th><th>A</th><th>B</th><th>Dif.</th><th>Gana</th></tr></thead><tbody>';
    for (const row of rows) {
      const difference = row.timeA > 0 && row.timeB > 0 ? row.timeA - row.timeB : null;
      html += '<tr' + (row.scope ? ' class="clickable' + (state.replay.scope === row.scope ? ' selected-a' : '') + '" data-replay-scope="' + row.scope + '" title="Repetir este tramo"' : '') + '><td class="text">' + escapeHtml(row.label) + '</td><td>' + formatCell(row.timeA, row.isSector) + '</td><td>' + formatCell(row.timeB, row.isSector) + '</td>' +
        '<td>' + (difference == null ? '—' : '<span class="' + (difference <= 0 ? 'gain' : 'loss') + '">' + formatSigned(difference) + '</span>') + '</td>' +
        '<td>' + (difference == null ? '' : Math.abs(difference) < 0.0005 ? '<span class="tag">empate</span>' : difference < 0 ? '<span class="tag success">A</span>' : '<span class="tag">B</span>') + '</td></tr>';
    }
    box.innerHTML = html + '</tbody></table><div class="note">' + (wholeRace ? 'Las dos carreras enteras, vuelta a vuelta. Toca «Carrera» para repetirla.' : 'Toca un tramo para repetirlo: la repetición, el zoom y las gráficas se centran en él.') + '</div>';
  }
