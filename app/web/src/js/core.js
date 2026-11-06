  // ---------- Model ----------
  const state = { data: null, view: { name: 'home' }, changeStamp: null, fileCache: {}, analysis: null };

  function buildEvents(data) {
    const eventsById = {};
    for (const session of data.sessions) {
      if (session.hasBuild) continue;
      (eventsById[session.event] ||= { id: session.event, sessions: [] }).sessions.push(session);
    }
    const events = Object.values(eventsById).map(event => summarizeEvent(event, data));
    events.sort((first, second) => (second.lastDate || '').localeCompare(first.lastDate || ''));
    return events;
  }
  function summarizeEvent(event, data) {
    const sessions = event.sessions.slice().sort((first, second) => first.id.localeCompare(second.id));
    event.sessions = sessions;
    event.gameRecord = gameRecordOf(data, event.id);
    event.name = data.eventNames[event.id] || (officialEventName(event.id) && [planetOf(event.gameRecord, event.id), officialEventName(event.id)].filter(Boolean).join(' · ')) || gameEventName(event.gameRecord, event.id) || describeEventCode(event.id);
    Object.assign(event, eventTitles(data, event.id, event.gameRecord));
    event.lastDate = sessions.length ? sessions[sessions.length - 1].date || sessions[sessions.length - 1].id : '';
    event.plannedLaps = Math.max(0, ...sessions.map(session => session.plannedLaps || 0));
    // Arranque lanzado (tramos que empiezan a cronometrar la vuelta en una puerta tras una carrerilla): el
    // tiempo que cuenta es el total desde el GO. Las carreras de antes del cambio traían la vuelta oficial
    // (desde la puerta): pasan a valer el total del evento y se quedan sin sectores.
    // Bonificación (Precisión): las vueltas de antes no la descontaban; cuenta su total, pero no sus vueltas
    event.bonus = sessions.some(session => (session.laps || []).some(lap => lap.bonusEvent));
    if (event.bonus) for (const session of sessions) for (const lap of session.laps || []) {
      if (!lap.bonusEvent) { lap.valid = false; lap.official = false; }
    }
    event.rolling = event.plannedLaps === 1 && sessions.some(session => (session.laps || []).some(lap => lap.rolling));
    if (event.rolling) for (const session of sessions) for (const lap of session.laps || []) {
      if (lap.rolling) continue;
      lap.rolling = true; lap.officialLap = lap.time; lap.sectors = []; lap.valid = false;
      if (session.total > lap.time + 1) lap.time = session.total; else lap.official = false;   // sin total no se puede comparar
    }
    event.attempts = sessions.length;
    event.completeSessions = sessions.filter(session => session.total > 0);
    event.bestSession = event.completeSessions.reduce((best, session) => (!best || session.total < best.total ? session : best), null);
    const withTarget = sessions.filter(session => session.target > 0);
    event.targetSource = withTarget.length ? withTarget[withTarget.length - 1] : null;
    // No races with a target: the #1 time that the mod imports from the Arcade list
    if (!event.targetSource && event.gameRecord && event.gameRecord.target) event.targetSource = { target: event.gameRecord.target, targetPlayer: 'nº1 del juego' };
    // Sectors: the most common count among valid laps
    const lapsBySectorCount = {};
    let bestLap = null;
    const allLaps = [];
    // solo las carreras completas: los intentos sin terminar (reinicios) no cuentan para los mejores ni el ideal
    for (const session of sessions) for (const lap of session.incomplete ? [] : session.laps || []) {
      allLaps.push({ session, lap });
      if (lap.official && (!bestLap || lap.time < bestLap.lap.time)) bestLap = { session, lap };
      if (lap.valid) lapsBySectorCount[lap.sectors.length] = (lapsBySectorCount[lap.sectors.length] || 0) + 1;
    }
    event.bestLap = bestLap;
    const sectorCount = +Object.keys(lapsBySectorCount).sort((first, second) => lapsBySectorCount[second] - lapsBySectorCount[first])[0] || 0;
    event.sectorCount = sectorCount;
    // Start lap (lap 1 of an event with several laps): only its S1 is different, because it starts with
    // less speed. That S1 is kept apart; the rest of lap 1 counts like any other lap.
    const severalLaps = event.plannedLaps > 1;
    const isStartLap = lap => severalLaps && lap.number === 1;
    const isStartSector = (lap, sectorIndex) => isStartLap(lap) && sectorIndex === 0;
    event.bestSectors = Array(sectorCount).fill(null);
    event.bestStartSector = null;
    for (const { session, lap } of allLaps) {
      // las vueltas con incidente (choque, retroceso) no cuentan: un sector recortado haría el ideal irreal
      if (!lap.valid || lap.incident || lap.sectors.length !== sectorCount) continue;
      lap.sectors.forEach((value, sectorIndex) => {
        if (isStartSector(lap, sectorIndex)) { if (!event.bestStartSector || value < event.bestStartSector.value) event.bestStartSector = { value, session, lap }; }
        else if (!event.bestSectors[sectorIndex] || value < event.bestSectors[sectorIndex].value) event.bestSectors[sectorIndex] = { value, session, lap };
      });
    }
    event.idealLap = sectorCount && event.bestSectors.every(Boolean) ? event.bestSectors.reduce((sum, best) => sum + best.value, 0) : null;
    event.idealStartLap = severalLaps && event.idealLap && event.bestStartSector ? event.idealLap - event.bestSectors[0].value + event.bestStartSector.value : null;
    // Total ideal. Con varias vueltas, con vueltas que has dado de verdad: tu mejor vuelta 1 y tus mejores
    // vueltas lanzadas (una distinta para cada vuelta que queda; si no hay bastantes, se repite la mejor).
    // Repetir la vuelta ideal por sectores en todas daba un total que nadie puede hacer.
    event.idealTotal = null;
    if (severalLaps) {
      const realLaps = allLaps.filter(item => item.lap.official && !item.lap.incident).map(item => item.lap);
      const bestStart = realLaps.filter(isStartLap).reduce((best, lap) => (!best || lap.time < best.time ? lap : best), null);
      const flyingTimes = realLaps.filter(lap => !isStartLap(lap)).map(lap => lap.time).sort((first, second) => first - second);
      if (bestStart && flyingTimes.length) {
        event.idealTotal = bestStart.time;
        for (let index = 0; index < event.plannedLaps - 1; index++) event.idealTotal += flyingTimes[Math.min(index, flyingTimes.length - 1)];
      }
    } else if (event.idealLap && event.plannedLaps) event.idealTotal = event.idealLap;
    // Consistency: the average of your last 10 clean laps against your best lap
    const cleanLaps = allLaps.filter(item => item.lap.official && !item.lap.incident && !isStartLap(item.lap)).slice(-10);
    event.recentAverageLap = cleanLaps.length >= 3 ? cleanLaps.reduce((sum, item) => sum + item.lap.time, 0) / cleanLaps.length : null;
    // Where you lose time: the average of your last 10 clean laps in each sector against your best sector
    const comparableLaps = allLaps.filter(item => item.lap.valid && !item.lap.incident && item.lap.sectors.length === sectorCount);
    const recentLaps = comparableLaps.filter(item => !isStartLap(item.lap)).slice(-10);
    const recentStarts = comparableLaps.filter(item => isStartLap(item.lap)).slice(-10);
    event.startSectorLoss = event.bestStartSector && recentStarts.length >= 2 ? { count: recentStarts.length, best: event.bestStartSector.value,
      averageLoss: recentStarts.reduce((sum, item) => sum + item.lap.sectors[0], 0) / recentStarts.length - event.bestStartSector.value } : null;
    event.sectorLosses = null;
    if (sectorCount >= 2 && recentLaps.length >= 3 && event.bestSectors.every(Boolean)) {
      const bestLapWithSectors = bestLap && bestLap.lap.valid && bestLap.lap.sectors.length === sectorCount ? bestLap.lap : null;
      event.sectorLosses = { count: recentLaps.length, rows: event.bestSectors.map((best, sectorIndex) => {
        const laps = comparableLaps.filter(item => !isStartSector(item.lap, sectorIndex)).slice(-10);
        const average = laps.reduce((sum, item) => sum + item.lap.sectors[sectorIndex], 0) / laps.length;
        return { sectorIndex, best: best.value, average, loss: average - best.value, lossInBestLap: bestLapWithSectors ? bestLapWithSectors.sectors[sectorIndex] - best.value : null };
      }) };
    }
    // Game record: imported by the mod from the Arcade menu; otherwise the one typed in by hand
    const manualRecord = (data.manualGameRecords[event.id] || '').split('|');
    event.gameBest = { total: (event.gameRecord && event.gameRecord.total) || parseFloat(manualRecord[0]) || null, lap: parseFloat(manualRecord[1]) || null, imported: !!event.gameRecord };
    event.recordTime = Math.min(...[event.bestSession && event.bestSession.total, event.gameBest.total].filter(value => value > 0));
    if (!isFinite(event.recordTime)) event.recordTime = null;
    return event;
  }

  // ---------- Navigation ----------
  const sleep = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
  // The hologram's "TV powering on" sweep: only when the app opens or the effect is turned on
  function playPowerOnSweep() {
    const root = document.documentElement;
    if (!root.classList.contains('hologram') || root.classList.contains('no-animations')) return;
    root.classList.remove('powering-on'); void root.offsetWidth; root.classList.add('powering-on');
    clearTimeout(state.powerOnTimer); state.powerOnTimer = setTimeout(() => root.classList.remove('powering-on'), 1300);
  }
  function playEntrance() {
    const main = byId('main');
    main.classList.remove('entering'); void main.offsetWidth; main.classList.add('entering');
    // Removed when it ends: if the page is painted again later (new data, a saved setting) it does not animate again
    clearTimeout(state.entranceTimer); state.entranceTimer = setTimeout(() => main.classList.remove('entering'), 1200);
  }
  async function navigate(view) {
    const main = byId('main'), topBar = document.querySelector('.topbar');
    const navigation = state.currentNavigation = Symbol();
    state.view = view;
    if (view.name === 'event') state.analysis = null;
    state.analysisLoading = null;
    main.classList.add('pending'); topBar.classList.add('loading');
    const slowNotice = setTimeout(() => byId('pageLoading').classList.add('visible'), 250);
    render();
    window.scrollTo(0, 0);
    await Promise.race([Promise.resolve(state.analysisLoading), sleep(6000)]).catch(() => {});
    clearTimeout(slowNotice);
    if (state.currentNavigation !== navigation) return;
    byId('pageLoading').classList.remove('visible'); topBar.classList.remove('loading');
    main.classList.remove('pending');
    playEntrance();
  }
  function renderBreadcrumbs() {
    const view = state.view;
    // Where you are; the way back home is the brand, so in narrow windows only the current page is shown
    const home = '<a data-navigate="home">Eventos de Arcade</a>';
    const current = view.name === 'social' ? 'Social' : view.name === 'options' ? 'Opciones'
      : view.name === 'event' ? (state.events.find(item => item.id === view.id) || { name: view.id }).name : null;
    byId('breadcrumbs').innerHTML = current == null ? home : '<span class="breadcrumb-root">' + home + ' <span>›</span></span> <b>' + escapeHtml(current) + '</b>';
  }
  document.addEventListener('click', clickEvent => {
    const link = clickEvent.target.closest('[data-navigate]');
    if (!link) return;
    const target = link.dataset.navigate;
    if (target === 'home' || target === 'social' || target === 'options') navigate({ name: target });
    else if (target === 'profile') navigate({ name: 'options' });   // enlaces viejos: el perfil vive ahora en Opciones
    else if (target === 'about') { state.optionsSection = 'optionsAbout'; navigate({ name: 'options' }); }
    else navigate({ name: 'event', id: target });
  });

  function render() {
    if (!state.data) return;
    state.events = buildEvents(state.data);
    renderBreadcrumbs();
    if (state.view.name === 'event' && state.events.some(event => event.id === state.view.id)) renderEvent();
    else if (state.view.name === 'social') renderSocial();
    else if (state.view.name === 'options') renderOptions();
    else renderHome();
  }

