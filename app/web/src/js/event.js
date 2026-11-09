  // ---------- Event ----------
  // Pestañas del centro de la página del evento; se recuerda la última usada
  const EVENT_TABS = [['laps', 'Vueltas y sectores'], ['sectors', 'Sector a sector'], ['loss', 'Dónde pierdes tiempo'], ['charts', 'Gráficas'], ['progress', 'Progreso'], ['friends', 'Amigos']];
  state.eventTab = readStored('swgr.eventTab', 'laps');
  const focusedSessionByEvent = {};
  function renderEvent() {
    const event = state.events.find(item => item.id === state.view.id);
    let html = '<div class="event-view"><div class="event-header"><div class="event-title">' + planetHtml(event.planet) + '<h1 title="' + escapeHtml(event.id) + '">' + escapeHtml(event.title) + '</h1><span class="event-subtitle">' +
      [event.plannedLaps === 1 ? 'Tramo de una vuelta' : event.plannedLaps ? event.plannedLaps + ' vueltas' : '', event.gameRecord && event.gameRecord.attempts ? event.gameRecord.attempts + ' intentos en el juego' : ''].filter(Boolean).join(' · ') + '</span></div>' +
      '</div>';
    html += summaryHtml(event);

    // Tres columnas: los intentos, las pestañas de análisis y el mapa con la repetición
    html += '<div class="event-body" id="analysisLayout"><div class="event-left">' + leftPanelHtml(event) + '</div>';
    const friendsTab = friendsPanel(event, true);
    const tabs = EVENT_TABS.filter(([name]) => name === 'loss' ? !!event.sectorLosses : name === 'friends' ? !!friendsTab : true);
    html += '<section class="panel event-center tryhard-only"><div class="panel-header center-header"><h2>Análisis</h2></div><div class="focus-info" id="focusInfo">' + focusInfoHtml(event) + '</div><div class="tab-bar" role="tablist">' +
      tabs.map(([name, label]) => '<button type="button" data-tab="' + name + '" aria-pressed="false">' + label + '</button>').join('') + '</div><div class="tab-panes">';
    html += '<div class="tab-pane" data-pane="laps"><div class="table-scroll"><table id="lapTable"></table></div>' +
      '<div class="note" title="La vuelta ideal une tus mejores sectores entre los intentos marcados, con su trazada: compárate con ella para ver dónde se te escapa el tiempo.">Toca una vuelta para ponerla en A y «B» para compararla con A.</div></div>';
    html += '<div class="tab-pane" data-pane="sectors"><div class="pane-header"><h2 id="sectorTableTitle"></h2></div><div id="sectorComparison"></div></div>';
    if (event.sectorLosses) html += '<div class="tab-pane" data-pane="loss">' + lossHtml(event) + '</div>';
    html += '<div class="tab-pane" data-pane="charts"><div class="pane-header"><h2 id="chartsTitle"></h2></div><div class="readout" id="readout"></div>' +
      '<canvas id="deltaChart" height="120"></canvas><canvas id="speedChart" height="140"></canvas></div>';
    html += '<div class="tab-pane" data-pane="progress"><div class="pane-header"><h2>Progreso del tiempo total</h2><div class="legend">' +
      '<span><i class="legend-line" style="background:var(--accent)"></i>tus eventos completos</span>' +
      '<span><i class="legend-line" style="background:var(--warning)"></i>objetivo nº1</span>' +
      (event.gameBest.total ? '<span><i class="legend-line" style="background:var(--best)"></i>récord del juego</span>' : '') + '</div></div>' +
      '<canvas id="progressChart" height="110"></canvas></div>';
    if (friendsTab) html += '<div class="tab-pane" data-pane="friends">' + friendsTab + '</div>';
    html += '</div></section>';
    html += '<div class="analysis-map"><div class="panel map-panel"><div class="panel-header"><h2 style="color:var(--map-text)">Trazada</h2><div class="segmented"><button id="mapSpeedMode" aria-pressed="true">Velocidad</button><button id="mapGainMode" aria-pressed="false">Ganancia</button><button id="mapLinesMode" aria-pressed="false">Trazadas</button><button id="mapTrailMode" class="tryhard-only" aria-pressed="false">Estela</button></div></div>' +
      '<div class="versus-bar" id="versusBar"><label class="versus-kind">Comparar <select id="replayScope" aria-label="Qué comparar"><option value="lap">Vuelta</option></select></label>' + '<button type="button" class="fold-button versus-fold" data-versus-fold="1" aria-label="A B"></button>' +
      '<div class="versus-side"><i class="legend-line" style="background:var(--accent)"></i><span class="versus-tag">A</span><select id="compareA" class="tryhard-only" aria-label="A"></select><b id="selectedA" class="simple-only">—</b><div class="versus-sub"><span class="numeric" id="selectedTimeA"></span><span class="boost-tag" id="boostTagA" style="visibility:hidden"></span></div></div>' +
      '<div class="versus-side"><i class="legend-line" id="legendLineB" style="background:var(--reference)"></i><span class="versus-tag">B</span><select id="compareB" class="tryhard-only" aria-label="B"></select><select id="simpleRival" class="simple-only" aria-label="Contra quién"></select><b id="selectedB" class="visually-hidden">—</b><div class="versus-sub"><span class="numeric" id="selectedTimeB"></span><span class="versus-gap" id="versusGap"></span><span class="boost-tag" id="boostTagB" style="visibility:hidden"></span></div></div>' +
      '</div>' +
      '<div class="map-box"><canvas id="map"></canvas></div><div class="map-scale" id="mapScale"></div>' +
      '<div class="replay" id="replay"><div class="replay-options">' +
      '<label>Modo <select id="replaySync" aria-label="Cómo se comparan"><option value="realTime">A tiempo real</option><option value="samePoint">En el mismo punto</option></select></label>' +
      '<button type="button" class="button small" id="replayFollow" aria-pressed="false">Seguir coche</button></div>' +
      '<button type="button" class="button small" id="replayPlay" aria-label="Reproducir">▶ Repetición</button>' +
      '<select id="replaySpeed" aria-label="Velocidad de la repetición"><option value="1">×1</option><option value="2" selected>×2</option><option value="4">×4</option><option value="8">×8</option></select>' +
      '<input type="range" id="replayPosition" min="0" max="1000" value="0" aria-label="Momento de la vuelta"><span class="numeric" id="replayTime">0:00.0</span></div>' +
      '<div class="replay-gap numeric" id="replayGap"></div></div></div>';
    html += '</div></div>';
    byId('main').innerHTML = html;

    if (byId('gameRecordSave')) byId('gameRecordSave').onclick = async () => {
      const total = parseTime(byId('gameTotalInput').value), lap = parseTime(byId('gameLapInput').value);
      if (Number.isNaN(total) || Number.isNaN(lap)) { byId('gameRecordMessage').innerHTML = '<span class="loss">Usa el formato 1:21.500 o 19.800</span>'; return; }
      await saveValue('manualGameRecord', event.id, total || lap ? (total || '') + '|' + (lap || '') : '');
    };
    document.querySelectorAll('[data-select-session]').forEach(checkbox => checkbox.addEventListener('change', () => {
      const selection = selectedSessions(event);
      if (checkbox.checked) selection.add(checkbox.dataset.selectSession); else selection.delete(checkbox.dataset.selectSession);
      loadAnalysis(event);
    }));
    document.querySelectorAll('[data-compare-friend]').forEach(button => button.addEventListener('click', () => compareWithFriend(button.dataset.compareFriend, false)));
    document.querySelectorAll('[data-compare-friend-race]').forEach(button => button.addEventListener('click', () => compareWithFriend(button.dataset.compareFriendRace, true)));
    document.querySelectorAll('[data-attempt]').forEach(row => row.addEventListener('click', clickEvent => {
      if (!clickEvent.target.closest('input')) focusAttempt(event, row.dataset.attempt);
    }));
    byId('sectorTableTitle').textContent = 'Sector a sector';
    byId('chartsTitle').textContent = 'Diferencia y velocidad a lo largo de la vuelta';
    // Al abrir un evento se compara la carrera entera
    if (state.replay.eventId !== event.id) { state.replay.eventId = event.id; state.replay.scope = event.plannedLaps > 1 ? 'race' : 'lap'; state.replay.lapScope = null; }
    showEventTab(state.eventTab, false);
    state.analysisLoading = loadAnalysis(event);
  }
  // Franja de resumen: tu récord contra el objetivo nº1, el total ideal y las medias
  function summaryHtml(event) {
    const targetSource = event.targetSource, recordTime = event.recordTime;
    const gap = targetSource && recordTime ? recordTime - targetSource.target : null;
    const fromGame = event.gameBest.total && recordTime === event.gameBest.total;
    const source = !recordTime ? 'aún sin evento completo'
      : fromGame ? 'récord del juego' + (event.gameRecord && event.gameRecord.attempts ? ' · ' + event.gameRecord.attempts + ' intentos' : '')
      : 'con el mod · ' + escapeHtml((event.bestSession && event.bestSession.date || '').slice(0, 10));
    const item = (label, value, detail, extraClass) => '<div class="strip-item' + (extraClass ? ' ' + extraClass : '') + '"><span class="label">' + label + '</span><span class="strip-value numeric">' + value +
      '</span><span class="detail">' + (detail || '&nbsp;') + '</span></div>';
    let html = '<section class="summary-strip">' + item('Tu récord', formatTime(recordTime), source, 'strip-record');
    if (targetSource) {
      html += item('Objetivo nº1 · ' + escapeHtml(targetSource.targetPlayer || ''), formatTime(targetSource.target),
        gap == null ? '' : gap <= 0 ? '<span class="pill success">Nº1 batido · ' + formatSigned(gap) + '</span>' : '<span class="pill failure">a ' + gap.toFixed(3) + ' s del nº1</span>');
    }
    html += item('Total ideal', formatTime(event.idealTotal), event.idealTotal && recordTime
      ? 'frente a tu récord <span class="' + (event.idealTotal <= recordTime ? 'gain' : 'loss') + '">' + formatSigned(event.idealTotal - recordTime) + '</span>'
      : (event.plannedLaps > 1 ? 'vuelta 1 ideal + vuelta ideal en las demás' : 'vuelta ideal'));
    const recentTotals = event.completeSessions.slice(-5).map(session => session.total);
    if (recentTotals.length >= 2) html += item('Media últimos ' + recentTotals.length, formatTime(recentTotals.reduce((sum, total) => sum + total, 0) / recentTotals.length));
    html += item(event.plannedLaps === 1 ? 'Mejor pasada con el mod' : 'Mejor vuelta', event.bestLap ? formatTime(event.bestLap.lap.time) : '—',
      event.bestLap ? 'grabada ' + escapeHtml((event.bestLap.session.date || '').slice(0, 10)) : 'sin vueltas oficiales', 'tryhard-only');
    html += item('Vuelta ideal', formatTime(event.idealLap), event.idealLap && event.bestLap ? 'margen ' + (event.bestLap.lap.time - event.idealLap).toFixed(3) + ' s sobre tu mejor' : 'suma de tus mejores sectores', 'tryhard-only');
    html += item('Constancia', event.recentAverageLap ? formatTime(event.recentAverageLap) : '—',
      event.recentAverageLap && event.bestLap ? 'media últimas 10 · ' + formatSigned(event.recentAverageLap - event.bestLap.lap.time) + ' sobre tu mejor' : 'media de tus últimas 10 vueltas', 'tryhard-only');
    if (!event.gameRecord) html += '<div class="strip-item strip-game tryhard-only"><span class="label">Récord del juego (a mano)</span>' +
      '<label class="detail" for="gameTotalInput">Total</label><input id="gameTotalInput" placeholder="1:21.500" value="' + (event.gameBest.total ? formatTime(event.gameBest.total) : '') + '">' +
      '<label class="detail" for="gameLapInput">Mejor vuelta</label><input id="gameLapInput" placeholder="19.800" value="' + (event.gameBest.lap ? formatTime(event.gameBest.lap) : '') + '">' +
      '<button class="button small" id="gameRecordSave">Guardar</button><span class="detail" id="gameRecordMessage">Tus tiempos de antes del mod</span></div>';
    return html + '</section>';
  }
  // Dónde pierdes tiempo: una tabla por sector con la pérdida media y tu mejor tiempo
  function lossHtml(event) {
    const rows = event.sectorLosses.rows.slice().sort((first, second) => second.loss - first.loss);
    const worstSectors = rows.slice(0, 2).filter(row => row.loss > 0.01);
    const possibleGain = worstSectors.reduce((sum, row) => sum + row.loss, 0);
    let html = '';
    if (worstSectors.length) html += '<p class="loss-lead">Si igualas tu mejor ' + worstSectors.map(row => 'S' + (row.sectorIndex + 1)).join(' y ') + ', ganas <b class="numeric">' + possibleGain.toFixed(3) +
        ' s</b> por vuelta' + (event.plannedLaps > 1 ? ' (<b class="numeric">' + worstSectors.reduce((sum, row) => sum + row.loss * (row.sectorIndex === 0 ? event.plannedLaps - 1 : event.plannedLaps), 0).toFixed(2) + ' s</b> en el evento)' : '') + '.</p>';
    html += '<table class="loss-table"><thead><tr><th>Sector</th><th>Pérdida</th><th>Tu mejor</th><th>En tu mejor vuelta</th></tr></thead><tbody>';
    for (const row of rows) {
      html += '<tr><td class="loss-sector">S' + (row.sectorIndex + 1) + '</td><td class="loss">+' + row.loss.toFixed(3) + '</td><td>' + row.best.toFixed(3) + '</td><td>' +
        (row.lossInBestLap != null ? (row.lossInBestLap < 0.0005 ? '<span class="best">igual</span>' : '+' + row.lossInBestLap.toFixed(3)) : '—') + '</td></tr>';
    }
    html += '</tbody></table>';
    html += '<div class="note">media de tus últimas ' + event.sectorLosses.count + (event.plannedLaps > 1 ? ' vueltas' : ' pasadas') + ' limpias frente a tu mejor tiempo en cada sector' + (event.plannedLaps > 1 ? ' · el S1 de salida va aparte' : '') + '</div>';
    if (event.startSectorLoss) {
      const startLoss = event.startSectorLoss;
      html += '<p class="loss-start"><span class="tag">salida</span> El S1 de la vuelta 1 (sales con menos velocidad) se compara solo con tus otras salidas: tu mejor es <b class="numeric">' +
        startLoss.best.toFixed(3) + '</b> y de media en tus últimas ' + startLoss.count + ' pierdes <b class="numeric loss">+' + Math.max(0, startLoss.averageLoss).toFixed(3) + '</b>.</p>';
    }
    return html;
  }

  // Intento elegido en la lista: el que se analiza (por defecto, el del mejor total)
  function focusedSession(event) {
    const chosen = event.sessions.find(session => session.id === focusedSessionByEvent[event.id] && session.telemetryFile);
    if (chosen) return chosen;
    if (event.bestSession && event.bestSession.telemetryFile) return event.bestSession;
    return event.sessions.filter(session => session.telemetryFile).pop() || null;
  }
  // Lista compacta de intentos: fecha, total y tiempos de vuelta; pulsar uno lo elige y la casilla suma otros al análisis
  // Columna izquierda: en modo simple, Intentos y Amigos son pestañas del mismo panel
  state.simpleLeftTab = 'attempts';
  function leftPanelHtml(event) {
    const friends = friendsPanel(event, true), showFriends = friends && state.simpleLeftTab === 'friends';
    if (!friends) return attemptsHtml(event);
    const tab = (name, label, pressed) => '<button type="button" data-left-tab-button="' + name + '" aria-pressed="' + pressed + '">' + label + '</button>';
    const tabs = '<div class="tab-bar simple-only">' + tab('attempts', 'Intentos', !showFriends) + tab('friends', 'Amigos', !!showFriends) + '</div>';
    return attemptsHtml(event).replace('class="panel attempts-panel"', showFriends ? 'class="panel attempts-panel showing-friends"' : 'class="panel attempts-panel"')
      .replace('<div class="attempt-list">', tabs + '<div class="attempt-list">').replace('<div class="note">', '<div class="simple-friends simple-only">' + friends + '</div><div class="note">');
  }
  document.addEventListener('click', clickEvent => {
    const button = clickEvent.target.closest('[data-left-tab-button]');
    if (!button) return;
    state.simpleLeftTab = button.dataset.leftTabButton;
    button.closest('.attempts-panel').classList.toggle('showing-friends', state.simpleLeftTab === 'friends');
    button.parentElement.querySelectorAll('[data-left-tab-button]').forEach(item => item.setAttribute('aria-pressed', item === button));
  });
  function attemptsHtml(event) {
    const selected = selectedSessions(event), focused = focusedSession(event);
    let html = '<section class="panel attempts-panel"><div class="panel-header"><h2>Intentos</h2><span class="muted" title="Pulsa un intento para ver sus datos y marca la casilla para sumar otros al análisis. Se conservan los últimos ' + state.data.attemptsToKeep +
      ' por evento; el mejor total y la mejor vuelta se guardan siempre.">Pulsa uno para analizarlo</span></div><div class="attempt-list">';
    if (!event.completeSessions.length) html += '<p class="muted">Aún no hay carreras completas en este evento</p>';
    for (const session of event.completeSessions.slice().reverse()) {
      const isBestSession = event.bestSession === session;
      const explanation = [session.eventGuessed ? 'grabado antes de identificar eventos' : '', session.telemetryFile ? '' : 'su telemetría ya no se conserva'].filter(Boolean).join(' · ');
      const rowClasses = 'attempt' + (session.telemetryFile ? '' : ' faded-row') + (focused && focused.id === session.id ? ' focused' : '');
      html += '<div class="' + rowClasses + '" data-attempt="' + escapeHtml(session.id) + '"' +
        (explanation ? ' title="' + escapeHtml(explanation) + '"' : '') + '><input type="checkbox" class="checkbox" data-select-session="' + escapeHtml(session.id) + '"' +
        (selected.has(session.id) ? ' checked' : '') + (session.telemetryFile ? '' : ' disabled') + ' id="select-' + escapeHtml(session.id) + '">' +
        '<span class="attempt-date">' + escapeHtml((session.date || session.id).slice(5, 16)) + '</span>' +
        '<span class="attempt-total numeric' + (isBestSession ? ' best' : '') + '">' + (session.total ? formatTime(session.total) + (session.totalCalculated ? '*' : '') : '—') + '</span>';
      if (event.plannedLaps > 1) {
        html += '<span class="attempt-laps numeric">';
        for (let lapIndex = 0; lapIndex < event.plannedLaps; lapIndex++) {
          const lap = (session.laps || [])[lapIndex];
          html += '<span' + (lap && event.bestLap && event.bestLap.lap === lap ? ' class="best"' : '') + '>' + (lap ? formatTime(lap.time) + (lap.incident ? '<span class="tag failure">!</span>' : '') : '—') + '</span>';
        }
        html += '</span>';
      }
      html += '</div>';
    }
    return html + '</div><div class="note">* Total calculado sumando las vueltas oficiales. ! = vuelta con incidente (choque o retroceso). En gris: sin telemetría.</div></section>';
  }
  // Datos del intento elegido, sobre las pestañas: fecha, total, objetivo, resultado y etiquetas
  function focusInfoHtml(event) {
    const session = focusedSession(event);
    if (!session) return '';
    const isBestSession = event.bestSession === session, hasBestLap = event.bestLap && event.bestLap.session === session;
    return '<b class="numeric">' + escapeHtml((session.date || session.id).slice(0, 16)) + '</b>' +
      '<span class="numeric' + (isBestSession ? ' best' : '') + '">' + (session.total ? formatTime(session.total) + (session.totalCalculated ? '*' : '') : '—') + '</span>' +
      (session.total && session.target ? '<span class="muted">objetivo</span><span class="numeric ' + (session.total <= session.target ? 'gain' : 'loss') + '">' + formatSigned(session.total - session.target) + '</span>' : '') +
      '<div class="focus-tags">' + (isBestSession ? '<span class="tag highlight">récord</span>' : '') + (hasBestLap ? '<span class="tag highlight">mejor vuelta</span>' : '') +
      (session.success == null ? ''
        : (session.total > 0 && session.target > 0 && session.total <= session.target) ? '<span class="tag success">nº1 batido</span>'
        : session.success ? '<span class="tag">superado</span>' : '<span class="tag failure">no superado</span>') + '</div>';
  }
  // Pulsar un intento lo elige: la columna del centro y el mapa pasan a mostrar sus datos (en modo simple se suma a los cargados)
  function focusAttempt(event, sessionId) {
    const session = event.sessions.find(item => item.id === sessionId);
    if (!session || !session.telemetryFile) return;
    focusedSessionByEvent[event.id] = session.id;
    const selection = selectedSessions(event);
    if (!isSimpleMode()) selection.clear();
    selection.add(session.id);
    state.pendingFocusSession = session.id;
    document.querySelectorAll('[data-attempt]').forEach(row => {
      row.classList.toggle('focused', row.dataset.attempt === session.id);
      const checkbox = row.querySelector('[data-select-session]');
      if (checkbox) checkbox.checked = selection.has(row.dataset.attempt);
    });
    byId('focusInfo').innerHTML = focusInfoHtml(event);
    loadAnalysis(event);
  }
  // Muestra una pestaña del centro y dibuja lo que necesita tamaño (las gráficas no se pueden dibujar ocultas)
  function showEventTab(name, remember) {
    const panes = [...document.querySelectorAll('[data-pane]')];
    if (!panes.some(pane => pane.dataset.pane === name)) name = 'laps';
    if (remember) { state.eventTab = name; writeStored('swgr.eventTab', name); }
    panes.forEach(pane => pane.classList.toggle('active', pane.dataset.pane === name));
    document.querySelectorAll('[data-tab]').forEach(button => button.setAttribute('aria-pressed', button.dataset.tab === name));
    const event = state.events.find(item => item.id === state.view.id);
    if (name === 'progress' && event) drawProgress(event);
    if (name === 'charts' && state.analysis && state.analysis.event === event) drawAll();
  }
  document.addEventListener('click', clickEvent => {
    const button = clickEvent.target.closest('[data-tab]');
    if (button) showEventTab(button.dataset.tab, true);
  });
  const tile = (label, value, detail) => '<div class="tile"><span class="label">' + label + '</span><span class="value">' + value + '</span><span class="detail">' + (detail || '&nbsp;') + '</span></div>';

  // Saves a game record typed in by hand, an event name or a preference, then reloads the data
  async function saveValue(kind, key, value) {
    try {
      await postJson('/api/save', { kind, key, value: String(value) });
      await refreshData(true);
      showToast('Guardado');
    } catch (error) { showToast('No se pudo guardar: ' + error.message); }
  }

  // Attempts ticked for analysis (by default: the record, the one with the best lap and the latest one)
  const selectedSessionsByEvent = {};
  function selectedSessions(event) {
    if (!selectedSessionsByEvent[event.id]) {
      const selection = new Set();
      const withTelemetry = event.sessions.filter(session => session.telemetryFile);
      if (event.bestSession && event.bestSession.telemetryFile) selection.add(event.bestSession.id);
      if (event.bestLap && event.bestLap.session.telemetryFile) selection.add(event.bestLap.session.id);
      if (withTelemetry.length) selection.add(withTelemetry[withTelemetry.length - 1].id);
      // Attempts holding your best sectors, to build the ideal lap
      for (const best of event.bestSectors || []) if (best && best.session.telemetryFile) selection.add(best.session.id);
      selectedSessionsByEvent[event.id] = selection;
    }
    return selectedSessionsByEvent[event.id];
  }

  function drawProgress(event) {
    const canvas = byId('progressChart');
    const { context, width, height } = fitCanvas(canvas, 110);
    const points = event.completeSessions.map((session, index) => ({ index, value: session.total, session }));
    const referenceTimes = [event.targetSource && event.targetSource.target, event.gameBest.total].filter(Boolean);
    if (!points.length) {
      context.fillStyle = cssVariable('--text-muted'); context.font = '13px ' + cssVariable('--font-body');
      context.fillText('Aquí verás la evolución de tu tiempo total en cada evento completo.', 60, 40); return;
    }
    const values = points.map(point => point.value).concat(referenceTimes);
    let lowest = Math.min(...values), highest = Math.max(...values);
    const padding = Math.max(0.5, (highest - lowest) * 0.12); lowest -= padding; highest += padding;
    const margin = { left: 70, right: 16, top: 12, bottom: 24 };
    const xOf = index => margin.left + (points.length === 1 ? 0.5 : index / (points.length - 1)) * (width - margin.left - margin.right);
    const yOf = value => margin.top + (highest - value) / (highest - lowest) * (height - margin.top - margin.bottom);
    const gridStep = niceStep(highest - lowest, 4);
    context.font = '11px ' + cssVariable('--font-data'); context.fillStyle = cssVariable('--text-muted'); context.strokeStyle = cssVariable('--line'); context.textAlign = 'right'; context.textBaseline = 'middle';
    for (let value = Math.ceil(lowest / gridStep) * gridStep; value <= highest; value += gridStep) {
      const y = Math.round(yOf(value)) + 0.5;
      context.beginPath(); context.moveTo(margin.left, y); context.lineTo(width - margin.right, y); context.stroke();
      context.fillText(formatTime(value), margin.left - 6, y);
    }
    const referenceLine = (value, color, label) => {
      if (!value) return;
      context.strokeStyle = color; context.setLineDash([5, 4]); context.lineWidth = 1.5;
      context.beginPath(); context.moveTo(margin.left, yOf(value)); context.lineTo(width - margin.right, yOf(value)); context.stroke(); context.setLineDash([]);
      context.fillStyle = color; context.textAlign = 'left'; context.fillText(label, margin.left + 6, yOf(value) - 9);
    };
    referenceLine(event.targetSource && event.targetSource.target, cssVariable('--warning'), 'objetivo ' + formatTime(event.targetSource && event.targetSource.target));
    referenceLine(event.gameBest.total, cssVariable('--best'), 'récord del juego');
    const accent = cssVariable('--accent');
    if (points.length > 1) {
      const gradient = context.createLinearGradient(0, margin.top, 0, height - margin.bottom);
      gradient.addColorStop(0, accent + '40'); gradient.addColorStop(1, accent + '00');
      context.fillStyle = gradient;
      context.beginPath(); context.moveTo(xOf(points[0].index), height - margin.bottom);
      points.forEach(point => context.lineTo(xOf(point.index), yOf(point.value)));
      context.lineTo(xOf(points[points.length - 1].index), height - margin.bottom); context.closePath(); context.fill();
    }
    context.save(); context.shadowColor = accent; context.shadowBlur = 10;
    context.strokeStyle = accent; context.lineWidth = 2.2;
    context.beginPath(); points.forEach((point, order) => { order ? context.lineTo(xOf(point.index), yOf(point.value)) : context.moveTo(xOf(point.index), yOf(point.value)); }); context.stroke();
    context.restore();
    points.forEach(point => {
      const isBestSession = point.session === event.bestSession;
      context.fillStyle = isBestSession ? cssVariable('--best') : accent; context.strokeStyle = cssVariable('--background'); context.lineWidth = 2;
      context.beginPath(); context.arc(xOf(point.index), yOf(point.value), isBestSession ? 6 : 4, 0, Math.PI * 2); context.fill(); context.stroke();
    });
    // Labels: your best recorded event and the latest one
    const pointLabel = (point, text, color) => {
      context.font = '600 11px ' + cssVariable('--font-data'); context.fillStyle = color; context.textBaseline = 'bottom';
      const x = xOf(point.index); context.textAlign = x > width - 120 ? 'right' : x < margin.left + 60 ? 'left' : 'center';
      context.fillText(text, x, yOf(point.value) - 9);
    };
    if (event.bestSession) { const bestPoint = points.find(point => point.session === event.bestSession); if (bestPoint) pointLabel(bestPoint, 'mejor ' + formatTime(bestPoint.value), cssVariable('--best')); }
    const lastPoint = points[points.length - 1];
    if (lastPoint && lastPoint.session !== event.bestSession) pointLabel(lastPoint, 'último ' + formatTime(lastPoint.value), cssVariable('--text'));
    context.fillStyle = cssVariable('--text-muted'); context.textAlign = 'center'; context.textBaseline = 'top';
    context.fillText('intentos completos, del más antiguo al más reciente →', (margin.left + width - margin.right) / 2, height - margin.bottom + 6);
  }

