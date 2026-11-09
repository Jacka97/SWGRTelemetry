  // ---------- Home ----------
  // The vehicle of an event from its code (LDB_ARC_<mode>_<vehicle>_...)
  const VEHICLE_CODES = { BIKE: 'bike', CAR: 'car', SKIMMER: 'skimmer', PLANE: 'podracer', POD: 'podracer', PODRACER: 'podracer' };
  const VEHICLE_NAMES = { podracer: 'Vaina', car: 'Coche', bike: 'Moto', skimmer: 'Rasante', other: 'Otros' };
  const VEHICLE_ORDER = ['podracer', 'car', 'bike', 'skimmer', 'other'];
  const SPEEDERS = ['car', 'bike', 'skimmer'];
  const vehicleOf = eventId => VEHICLE_CODES[(eventId.replace(/^LDB_ARC_/, '').split('_')[1] || '').toUpperCase()] || 'other';
  const vehicleName = eventId => VEHICLE_NAMES[vehicleOf(eventId)];
  // Vehicle icons (drawn for this app): two engines pulling a pod, a landspeeder, a speeder bike and a skimmer
  const VEHICLE_ICONS = {
    podracer: '<rect x="2" y="5.5" width="9.5" height="3.6" rx="1.8"/><rect x="2" y="14.9" width="9.5" height="3.6" rx="1.8"/><path d="M11.5 7.3l5 3.6M11.5 16.7l5-3.6"/><path d="M16.5 10h3.2a2 2 0 0 1 0 4h-3.2z"/>',
    car: '<path d="M2.5 14.2c0-2.6 2.2-4.2 5.4-4.2h6.4c3.7 0 7.2 1.6 7.2 4.1 0 2-1.9 2.9-3.9 2.9H6.2c-2.3 0-3.7-.9-3.7-2.8z"/><path d="M8.2 10l2.4-3h3.6l1.6 3"/><path d="M5 20.2h14"/>',
    bike: '<path d="M2.5 13.2h12.8l5.2-2.2"/><path d="M6 13.2l2.2-3.4h4.2l1.2 3.4"/><path d="M18.6 7.8v6.2"/><path d="M4 17.6h14.5"/>',
    skimmer: '<path d="M2 14.2l9-5.2h6.2l4.8 4.2-2 2.1H4.2z"/><path d="M11 9l2.2 5.3"/><path d="M5 19.6h13.4"/>',
    other: '<circle cx="12" cy="12" r="7"/>' };
  const vehicleIcon = eventId => '<svg class="vehicle-icon" viewBox="0 0 24 24" aria-hidden="true">' + VEHICLE_ICONS[vehicleOf(eventId)] + '</svg>';
  const vehicleBadge = eventId => vehicleIcon(eventId) + escapeHtml(vehicleName(eventId));
  const CATEGORY_NAMES = { 1: 'Vuelo de prueba', 2: 'Carreras de vainas', 3: 'Despegar', 4: 'Precisión', 5: 'Ácido', 6: 'Fuego y hielo', 7: 'Avanzado', 8: 'Deluxe' };
  const categoryOf = eventId => { const gameRecord = gameRecordOf(state.data, eventId); return gameRecord && gameRecord.category ? gameRecord.category : null; };
  // Per-viewer conveniences kept in the browser: the chosen filters and home view
  const readStored = (key, fallback) => { try { return localStorage.getItem(key) || fallback; } catch (error) { return fallback; } };
  const writeStored = (key, value) => { try { localStorage.setItem(key, value); } catch (error) {} };
  // Every panel with a title can be folded (button at the right of its header); the app remembers which ones
  const foldedPanels = new Set(readStored('swgr.foldedPanels', '').split('|').filter(Boolean));
  // Carrusel de la portada: las flechas solo salen si la fila no cabe entera
  function refreshCarousels() {
    document.querySelectorAll('.event-carousel').forEach(carousel => {
      const grid = carousel.querySelector('.event-grid'), fits = grid.scrollWidth <= grid.clientWidth + 1;
      carousel.querySelectorAll('.carousel-button').forEach(button => { button.hidden = fits; });
    });
  }
  window.addEventListener('resize', refreshCarousels);
  document.addEventListener('click', clickEvent => {
    const button = clickEvent.target.closest('[data-carousel]');
    if (!button) return;
    const grid = button.parentElement.querySelector('.event-grid');
    grid.scrollBy({ left: +button.dataset.carousel * grid.clientWidth * 0.8, behavior: 'smooth' });
  });
  // Holograma: la tarjeta bajo el ratón se inclina hacia él, con un reflejo que lo sigue
  const tiltsCards = () => { const root = document.documentElement.classList; return root.contains('hologram') && !root.contains('no-animations'); };
  const TILT_TARGETS = '.event-card, .time-tile.clickable, .top-button, .options-nav button, .options-page .options button, .button, .filters button, .tab-bar button';
  let tiltFrame = 0;
  document.addEventListener('pointermove', pointerEvent => {
    const card = pointerEvent.target.closest && pointerEvent.target.closest(TILT_TARGETS);
    if (!card || !tiltsCards() || tiltFrame) return;
    const { clientX, clientY } = pointerEvent;
    tiltFrame = requestAnimationFrame(() => {
      tiltFrame = 0;
      const box = card.getBoundingClientRect(), x = (clientX - box.left) / box.width, y = (clientY - box.top) / box.height;
      card.style.setProperty('--tilt-x', ((0.5 - y) * 12).toFixed(2) + 'deg');
      card.style.setProperty('--tilt-y', ((x - 0.5) * 14).toFixed(2) + 'deg');
      card.style.setProperty('--glare-x', (x * 100).toFixed(1) + '%');
      card.style.setProperty('--glare-y', (y * 100).toFixed(1) + '%');
      card.classList.add('tilting');
    });
  });
  document.addEventListener('pointerout', pointerEvent => {
    const card = pointerEvent.target.closest && pointerEvent.target.closest(TILT_TARGETS);
    if (!card || (pointerEvent.relatedTarget && card.contains(pointerEvent.relatedTarget))) return;
    card.classList.remove('tilting');
    card.style.removeProperty('--tilt-x'); card.style.removeProperty('--tilt-y');
  });
  // Las columnas de Intentos y Trazada se pliegan hacia su lado; los demás paneles, hacia arriba
  const foldArrow = (panel, folded) => panel.classList.contains('attempts-panel') || panel.classList.contains('event-center') ? (folded ? '▸' : '◂') : panel.classList.contains('map-panel') ? (folded ? '◂' : '▸') : (folded ? '▸' : '▾');
  const panelKey = panel => (state.view ? state.view.name : '') + ':' + [...panel.parentElement.children].filter(item => item.classList.contains('panel')).indexOf(panel);
  new MutationObserver(() => {
    document.querySelectorAll('.panel > .panel-header:first-child:not([data-foldable])').forEach(header => {
      if (!header.querySelector('h2') || header.closest('.options-page')) return;   // en Opciones no hace falta plegar
      header.dataset.foldable = '1';
      const panel = header.parentElement;
      if (foldedPanels.has(panelKey(panel))) panel.classList.add('folded');
      header.insertAdjacentHTML('beforeend', '<button type="button" class="fold-button" data-fold-panel="1" title="Plegar o desplegar">' + foldArrow(panel, panel.classList.contains('folded')) + '</button>');
    });
  }).observe(document.body, { childList: true, subtree: true });
  document.addEventListener('click', clickEvent => {
    const button = clickEvent.target.closest('[data-fold-panel]');
    if (!button) return;
    const panel = button.closest('.panel'), folded = panel.classList.toggle('folded'), key = panelKey(panel);
    button.textContent = foldArrow(panel, folded);
    if (folded) foldedPanels.add(key); else foldedPanels.delete(key);
    writeStored('swgr.foldedPanels', [...foldedPanels].join('|'));
    if (state.analysis) requestAnimationFrame(drawAll);   // las columnas cambian de ancho: las gráficas y el mapa se dibujan a su tamaño nuevo
  });
  state.categoryFilter = readStored('swgr.categoryFilter', 'all');
  document.addEventListener('click', clickEvent => {
    const button = clickEvent.target.closest('[data-category-filter]'); if (!button) return;
    state.categoryFilter = button.dataset.categoryFilter;
    writeStored('swgr.categoryFilter', state.categoryFilter);
    renderHome();
  });
  state.vehicleFilter = readStored('swgr.vehicleFilter', 'all');
  document.addEventListener('click', clickEvent => {
    const button = clickEvent.target.closest('[data-vehicle-filter]');
    if (!button) return;
    state.vehicleFilter = button.dataset.vehicleFilter;
    writeStored('swgr.vehicleFilter', state.vehicleFilter);
    renderHome();
  });

  // ---------- Planet illustrations (drawn for this app) on top of the event cards ----------
  // One small landscape per planet, by the game's planet code names
  const PLANET_ART = {
    // Lantaana: volcanic jungle under a red sky
    Dalmatian: '<defs><linearGradient id="skyDalmatian" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a0705"/><stop offset="1" stop-color="#8c2a0c"/></linearGradient></defs>' +
      '<rect width="400" height="120" fill="url(#skyDalmatian)"/><path d="M150 120 L215 38 L232 34 L300 120Z" fill="#1c0a07"/><path d="M215 38 Q224 20 232 34 Q228 30 224 32 Q219 30 215 38Z" fill="#ff7a1a"/>' +
      '<path d="M222 40 Q228 70 218 120" stroke="#ff5a14" stroke-width="3" fill="none" opacity=".85"/><circle cx="224" cy="22" r="14" fill="#ff8a2a" opacity=".22"/>' +
      '<path d="M0 120 L0 82 Q20 66 34 84 Q46 62 62 82 Q80 70 92 90 L110 120Z" fill="#0d1a0c"/><path d="M290 120 L300 92 Q318 72 334 90 Q352 66 368 86 Q386 74 400 88 L400 120Z" fill="#0d1a0c"/>' +
      '<rect y="112" width="400" height="8" fill="#ff5a14" opacity=".35"/>',
    // Jakku: desert dunes and the ribs of an old wreck
    Mastiff: '<defs><linearGradient id="skyMastiff" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f2b86a"/><stop offset="1" stop-color="#e58a3a"/></linearGradient></defs>' +
      '<rect width="400" height="120" fill="url(#skyMastiff)"/><circle cx="320" cy="34" r="16" fill="#fff1c9" opacity=".9"/>' +
      '<path d="M120 96 Q150 40 190 30 M150 98 Q172 56 204 44 M182 100 Q196 70 220 60" stroke="#6b4426" stroke-width="5" fill="none" stroke-linecap="round"/>' +
      '<path d="M0 120 L0 92 Q70 70 140 94 Q210 112 270 88 Q330 66 400 90 L400 120Z" fill="#c9733a"/><path d="M0 120 L0 106 Q90 94 180 108 Q280 120 400 104 L400 120Z" fill="#a85a2a"/>',
    // Ando Prime: snowy peaks and ice under a pale sky
    Corgi: '<defs><linearGradient id="skyCorgi" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#9fc4e6"/><stop offset="1" stop-color="#e8f3fb"/></linearGradient></defs>' +
      '<rect width="400" height="120" fill="url(#skyCorgi)"/><path d="M0 120 L60 52 L96 82 L150 30 L210 92 L250 60 L310 98 L360 46 L400 76 L400 120Z" fill="#5f7f9e"/>' +
      '<path d="M150 30 L166 46 L156 44 L148 52 L140 40Z M360 46 L374 60 L364 58 L356 64 L350 56Z M60 52 L72 66 L62 64 L54 70Z" fill="#ffffff"/>' +
      '<path d="M0 120 L0 104 Q100 92 200 104 Q300 116 400 100 L400 120Z" fill="#f4fbff"/><g fill="#ffffff" opacity=".7"><circle cx="40" cy="20" r="1.6"/><circle cx="120" cy="14" r="1.2"/><circle cx="240" cy="22" r="1.6"/><circle cx="300" cy="12" r="1.2"/></g>',
    // Crait: white salt plain with red trails and mineral ridges
    Spaniel: '<defs><linearGradient id="skyCrait" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#b9c3cc"/><stop offset="1" stop-color="#eef1f3"/></linearGradient></defs>' +
      '<rect width="400" height="120" fill="url(#skyCrait)"/><path d="M0 92 L40 70 L70 84 L110 62 L150 86 L400 86 L400 120 L0 120Z" fill="#8a929a"/>' +
      '<path d="M0 120 L0 90 L400 90 L400 120Z" fill="#f7f7f5"/><path d="M40 120 Q140 100 230 92 M110 120 Q190 104 290 94 M260 120 Q300 104 360 96" stroke="#c4152a" stroke-width="4" fill="none" opacity=".85" stroke-linecap="round"/>',
    // Centinela 1: caustic pools and towers of an old station
    Husky: '<defs><linearGradient id="skyHusky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#16241a"/><stop offset="1" stop-color="#3d5a2a"/></linearGradient></defs>' +
      '<rect width="400" height="120" fill="url(#skyHusky)"/><rect x="250" y="34" width="14" height="64" fill="#1a1f1a"/><rect x="272" y="50" width="10" height="48" fill="#1a1f1a"/><rect x="292" y="24" width="8" height="74" fill="#1a1f1a"/>' +
      '<circle cx="296" cy="24" r="3" fill="#b6ff4a"/><path d="M0 120 L0 96 Q100 86 200 98 Q300 108 400 94 L400 120Z" fill="#20281c"/>' +
      '<ellipse cx="90" cy="106" rx="60" ry="6" fill="#a8f03a" opacity=".75"/><ellipse cx="330" cy="110" rx="44" ry="5" fill="#a8f03a" opacity=".6"/>',
    // Derven Acos: a stadium lit at night
    Whippet: '<defs><linearGradient id="skyWhippet" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0b0f2a"/><stop offset="1" stop-color="#3a2a5a"/></linearGradient></defs>' +
      '<rect width="400" height="120" fill="url(#skyWhippet)"/><path d="M60 120 L80 64 Q200 40 320 64 L340 120Z" fill="#1c1a30"/><path d="M80 64 Q200 40 320 64" stroke="#ffd27a" stroke-width="2" fill="none"/>' +
      '<g fill="#fff4c2"><circle cx="110" cy="56" r="3"/><circle cx="160" cy="48" r="3"/><circle cx="240" cy="48" r="3"/><circle cx="290" cy="56" r="3"/></g>' +
      '<g stroke="#fff4c2" stroke-width="1" opacity=".35"><path d="M110 56 L60 120"/><path d="M160 48 L130 120"/><path d="M240 48 L270 120"/><path d="M290 56 L340 120"/></g><rect y="112" width="400" height="8" fill="#141226"/>',
    // Tatooine: twin suns over the desert
    Beagle: '<defs><linearGradient id="skyBeagle" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f6d58f"/><stop offset="1" stop-color="#f0a85a"/></linearGradient></defs>' +
      '<rect width="400" height="120" fill="url(#skyBeagle)"/><circle cx="260" cy="40" r="13" fill="#fff7dc"/><circle cx="296" cy="50" r="9" fill="#ffe7a8"/>' +
      '<path d="M0 120 L0 80 L30 80 L36 70 L70 70 L76 80 L110 80 L110 120Z M300 120 L300 84 L330 84 L336 76 L372 76 L378 84 L400 84 L400 120Z" fill="#b8743e"/>' +
      '<path d="M0 120 L0 98 Q100 86 200 100 Q300 112 400 96 L400 120Z" fill="#d99256"/>',
    // Mystery: a nebula
    Mystery: '<rect width="400" height="120" fill="#120a24"/><circle cx="200" cy="60" r="70" fill="#7a3cff" opacity=".25"/><circle cx="160" cy="50" r="40" fill="#ff5fd2" opacity=".18"/>' +
      '<g fill="#ffffff"><circle cx="60" cy="30" r="1.4"/><circle cx="330" cy="24" r="1.2"/><circle cx="280" cy="90" r="1.4"/><circle cx="110" cy="96" r="1.1"/></g>' };
  // Without the code (sessions of events the game has not listed yet), the planet comes from the event's code
  const PLANET_CODE_OF_EVENT_CODE = { DAL: 'Dalmatian', MAS: 'Mastiff', COR: 'Corgi', SPA: 'Spaniel', HSK: 'Husky', WHP: 'Whippet', BGL: 'Beagle' };
  function planetCodeOf(eventId) {
    const gameRecord = gameRecordOf(state.data, eventId);
    if (gameRecord && gameRecord.planetCode && PLANET_ART[gameRecord.planetCode]) return gameRecord.planetCode;
    const code = eventId.replace(/^LDB_ARC_/, '').split('_').find(word => PLANET_CODE_OF_EVENT_CODE[word.toUpperCase()]);
    return code ? PLANET_CODE_OF_EVENT_CODE[code.toUpperCase()] : 'Mystery';
  }
  const planetArt = eventId => '<div class="event-art" aria-hidden="true"><svg class="planet-art" viewBox="0 0 400 120" preserveAspectRatio="xMidYMid slice">' + PLANET_ART[planetCodeOf(eventId)] + '</svg>' + vehicleIcon(eventId) + '</div>';

  // ---------- Home: events grouped by planet ----------
  function eventCard(event) {
    const targetSource = event.targetSource;
    const gap = targetSource && event.recordTime ? event.recordTime - targetSource.target : null;
    return '<button class="event-card" data-navigate="' + escapeHtml(event.id) + '" title="' + escapeHtml(event.id) + '">' + planetArt(event.id) +
      '<div><div class="event-vehicle">' + vehicleBadge(event.id) + '</div><div class="event-name">' + escapeHtml(event.shortTitle || event.title) + '</div></div>' +
      '<div class="event-figures">' +
      figure('Tu récord', formatTime(event.recordTime) + (targetSource && event.recordTime && event.recordTime <= targetSource.target + 1e-4 ? ' <span class="tag gold">oro</span>' : ''),
        event.gameBest.total && event.recordTime === event.gameBest.total ? 'del juego' : (event.bestSession ? 'con el mod' : '')) +
      figure('Objetivo nº1', targetSource ? formatTime(targetSource.target) : '—',
        gap == null ? (targetSource ? escapeHtml(targetSource.targetPlayer) : '') : '<span class="' + (gap <= 0 ? 'gain' : 'loss') + '">' + formatSigned(gap) + '</span>') +
      figure(event.plannedLaps === 1 ? 'Mejor con el mod' : 'Mejor vuelta', event.bestLap ? formatTime(event.bestLap.lap.time) : '—', event.idealLap ? 'ideal ' + formatTime(event.idealLap) : '') +
      '</div><div class="muted" style="font-size:.82rem">' + friendsChip(event) + event.attempts + (event.attempts === 1 ? ' intento · ' : ' intentos · ') +
      (event.plannedLaps === 1 ? 'tramo · ' : event.plannedLaps ? event.plannedLaps + ' vueltas · ' : '') + 'último ' + escapeHtml((event.lastDate || '').slice(0, 16)) + '</div>' +
      '</button>';
  }
  // "Times" view: one row per event, with the #1 time, the gold and your friends' times
  state.homeView = readStored('swgr.homeView', 'cards');
  document.addEventListener('click', clickEvent => {
    const button = clickEvent.target.closest('[data-home-view]'); if (!button) return;
    state.homeView = button.dataset.homeView;
    writeStored('swgr.homeView', state.homeView);
    renderHome(); if (preference('animations') !== 'off') playEntrance();
  });
  function goldCell(recordTime, targetTime) {
    if (!(targetTime > 0) || !(recordTime > 0)) return '<span class="muted">—</span>';
    return recordTime <= targetTime + 1e-4 ? '<span class="tag gold" title="Batiste el nº1 por ' + (targetTime - recordTime).toFixed(3) + ' s">oro</span>'
      : '<span class="loss" title="Te falta para el nº1">' + formatSigned(recordTime - targetTime) + '</span>';
  }
  // "Times" view: one tile per event, several per row: your record, the #1 time, the gold and your 3 best friends
  function timesGrid(group) {
    const topFriends = friendRanking().slice(0, 3);
    const items = group.events.map(event => ({ id: event.id, title: event.shortTitle || event.title, recordTime: event.recordTime, targetTime: event.targetSource && event.targetSource.target, attempts: event.attempts, hasTelemetry: true }))
      .concat(group.recordsOnly.map(item => ({ id: item.id, title: item.title, recordTime: item.gameRecord.total, targetTime: item.gameRecord.target, attempts: item.gameRecord.attempts, hasTelemetry: false })))
      .sort((first, second) => VEHICLE_ORDER.indexOf(vehicleOf(first.id)) - VEHICLE_ORDER.indexOf(vehicleOf(second.id)) || first.title.localeCompare(second.title));
    let html = '<div class="times-grid">';
    for (const item of items) {
      const friendTimes = topFriends.map(friend => { const result = friend.events[item.id]; return { friend, time: result && result.total > 0 ? +result.total : null }; }).filter(entry => entry.time);
      const fastest = Math.min(...[item.recordTime].concat(friendTimes.map(entry => entry.time)).filter(value => value > 0));
      const iAmFastest = item.recordTime > 0 && friendTimes.length && item.recordTime <= fastest + 1e-4;
      html += '<div class="' + (item.hasTelemetry ? 'time-tile clickable' : 'time-tile') + '"' + (item.hasTelemetry ? ' data-navigate="' + escapeHtml(item.id) + '"' : '') + ' title="' + escapeHtml(item.id) + '">' +
        '<div class="time-tile-title"><span class="event-vehicle">' + vehicleBadge(item.id) + '</span><span class="time-tile-name">' + escapeHtml(item.title) + '</span></div>' +
        '<div class="time-tile-record"><span class="numeric' + (iAmFastest ? ' best' : '') + '">' + (item.recordTime > 0 ? formatTime(item.recordTime) : '—') + '</span>' + (item.targetTime > 0 ? goldCell(item.recordTime, item.targetTime) : '') + '</div>' +
        '<div class="time-tile-detail muted">' + (item.targetTime > 0 ? 'nº1 <span class="numeric">' + formatTime(item.targetTime) + '</span> · ' : '') + (item.attempts || 0) + (item.attempts === 1 ? ' intento' : ' intentos') +
        (item.hasTelemetry ? '' : ' · sin telemetría') + '</div>' +
        (friendTimes.length ? '<div class="time-tile-friends">' + friendTimes.map(({ friend, time }) => '<span>' + pilotDot(friend.color) + escapeHtml(friend.pilot) + '</span><span class="numeric' + (time <= fastest + 1e-4 ? ' best' : '') + '">' + formatTime(time) + '</span>' +
          '<span class="numeric ' + (item.recordTime > 0 ? (time < item.recordTime ? 'loss' : 'gain') : 'muted') + '">' + (item.recordTime > 0 ? formatSigned(time - item.recordTime) : '') + '</span>').join('') + '</div>' : '') +
        '</div>';
    }
    return html + '</div>';
  }
  function renderHome() {
    const events = state.events;
    const withTelemetry = new Set(events.map(event => event.id));
    const recordsOnly = Object.keys(state.data.gameRecords || {}).filter(id => !withTelemetry.has(id)).map(id => ({ id, gameRecord: gameRecordOf(state.data, id) })).filter(item => item.gameRecord);
    if (!events.length && !recordsOnly.length) {
      byId('main').innerHTML = '<div class="panel"><div class="empty-state"><b>Aún no hay carreras grabadas</b>' +
        '<span>Juega un evento de Arcade con el mod activo y aparecerá aquí en cuanto termines.</span>' +
        '<span class="numeric muted">' + escapeHtml(state.data.modFolder) + '</span></div></div>';
      return;
    }
    // Filter by vehicle
    const allIds = events.map(event => event.id).concat(recordsOnly.map(item => item.id));
    const vehicles = [...new Set(allIds.map(vehicleOf))].sort((first, second) => VEHICLE_ORDER.indexOf(first) - VEHICLE_ORDER.indexOf(second));
    const speeders = vehicles.filter(vehicle => SPEEDERS.includes(vehicle));
    if (state.vehicleFilter !== 'all' && state.vehicleFilter !== 'speeders' && !vehicles.includes(state.vehicleFilter)) state.vehicleFilter = 'all';
    if (state.vehicleFilter === 'speeders' && !speeders.length) state.vehicleFilter = 'all';
    // Categories present (the ones the mod has read from the game)
    const categories = [...new Set(allIds.map(categoryOf).filter(Boolean))].sort((first, second) => first - second);
    if (state.categoryFilter !== 'all' && !categories.includes(+state.categoryFilter)) state.categoryFilter = 'all';
    const passesVehicle = id => state.vehicleFilter === 'all' || (state.vehicleFilter === 'speeders' ? SPEEDERS.includes(vehicleOf(id)) : vehicleOf(id) === state.vehicleFilter);
    const passes = id => passesVehicle(id) && (state.categoryFilter === 'all' || categoryOf(id) === +state.categoryFilter);
    // Groups by planet
    const groups = {};
    const groupOf = planet => (groups[planet || ''] ||= { planet: planet || '', events: [], recordsOnly: [] });
    for (const event of events) if (passes(event.id)) groupOf(event.planet).events.push(event);
    for (const item of recordsOnly) if (passes(item.id)) { const titles = eventTitles(state.data, item.id, item.gameRecord); groupOf(titles.planet).recordsOnly.push({ ...item, title: titles.shortTitle || titles.title }); }
    const orderedGroups = Object.values(groups).sort((first, second) => (!first.planet) - (!second.planet) || (second.events.length - first.events.length) || first.planet.localeCompare(second.planet));

    let html = '<div class="panel-header"><h1>Eventos de Arcade</h1><span class="muted">' + events.length + ' con telemetría · ' + recordsOnly.length + ' solo con récord del juego · ' +
      state.data.sessions.filter(session => !session.hasBuild).length + ' intentos grabados</span></div>';
    html += '<div class="home-tools"><div class="filters" role="group" aria-label="Filtrar por vehículo"><button type="button" data-vehicle-filter="all" aria-pressed="' + (state.vehicleFilter === 'all') + '">Todos</button>';
    // Podracers on their own; the speeders in a group: "Speeders" (all three) and each one separately
    const filterButton = (value, label, extraAttributes) => '<button type="button" data-vehicle-filter="' + escapeHtml(value) + '" aria-pressed="' + (state.vehicleFilter === value) + '"' + (extraAttributes || '') + '>' + escapeHtml(label) + '</button>';
    html += (vehicles.includes('podracer') ? filterButton('podracer', 'Vainas') : '') +
      (speeders.length ? '<span class="filter-group' + (state.vehicleFilter === 'speeders' || speeders.includes(state.vehicleFilter) ? ' active' : '') + '">' + filterButton('speeders', 'Speeders', ' class="filter-group-all"') +
        speeders.map(vehicle => filterButton(vehicle, VEHICLE_NAMES[vehicle])).join('') + '</span>' : '') +
      (vehicles.includes('other') ? filterButton('other', 'Otros') : '') + '</div>';
    html += '<div class="segmented" role="group" aria-label="Vista"><button type="button" data-home-view="cards" aria-pressed="' + (state.homeView !== 'times') + '">Tarjetas</button>' +
      '<button type="button" data-home-view="times" aria-pressed="' + (state.homeView === 'times') + '">Tiempos</button></div></div>';
    if (categories.length) {
      html += '<div class="filters categories" role="group" aria-label="Filtrar por categoría"><button type="button" data-category-filter="all" aria-pressed="' + (state.categoryFilter === 'all') + '">Todas</button>' +
        categories.map(category => '<button type="button" data-category-filter="' + category + '" aria-pressed="' + (+state.categoryFilter === category) + '">' +
          escapeHtml(CATEGORY_NAMES[category] || ('Categoría ' + category)) + '</button>').join('') + '</div>';
    }
    // Golds: records that beat the #1 time
    const listed = events.filter(event => passes(event.id)).map(event => ({ recordTime: event.recordTime, targetTime: event.targetSource && event.targetSource.target }))
      .concat(recordsOnly.filter(item => passes(item.id)).map(item => ({ recordTime: item.gameRecord.total, targetTime: item.gameRecord.target })));
    const withTarget = listed.filter(item => item.targetTime > 0), golds = withTarget.filter(item => item.recordTime > 0 && item.recordTime <= item.targetTime + 1e-4).length;
    if (withTarget.length) html += '<div class="gold-count">Oro (batir el nº1): <b>' + golds + '</b> de ' + withTarget.length + ' eventos</div>';
    for (const group of orderedGroups) {
      const count = group.events.length + group.recordsOnly.length;
      html += '<section class="planet-group"><header class="planet-group-header">' + (group.planet ? '<span class="planet">' + escapeHtml(group.planet) + '</span>' + aurebeshHtml(group.planet) : '<span class="planet-group-none">Otros planetas</span>') +
        '<span class="muted">' + count + (count === 1 ? ' evento' : ' eventos') + '</span></header>';
      if (state.homeView === 'times') { html += timesGrid(group) + '</section>'; continue; }
      // Una fila por planeta, que se desplaza de lado (carrusel)
      if (group.events.length) html += '<div class="event-carousel"><button type="button" class="carousel-button" data-carousel="-1" hidden>◂</button><div class="event-grid">' + group.events.map(eventCard).join('') + '</div><button type="button" class="carousel-button" data-carousel="1" hidden>▸</button></div>';
      if (group.recordsOnly.length) {
        group.recordsOnly.sort((first, second) => first.title.localeCompare(second.title));
        html += '<div class="planet-group-others"><span class="label">Sin telemetría todavía</span><div class="compact-list">' +
          group.recordsOnly.map(item => '<div class="compact-row" title="' + escapeHtml(item.id) + '"><span class="compact-title"><span class="event-vehicle">' + vehicleBadge(item.id) + '</span>' + escapeHtml(item.title) + '</span>' +
            '<span class="numeric">' + formatTime(item.gameRecord.total) + '</span><span class="muted compact-attempts">' + item.gameRecord.attempts + (item.gameRecord.attempts === 1 ? ' intento' : ' intentos') + '</span></div>').join('') +
          '</div></div>';
      }
      html += '</section>';
    }
    html += '<div class="note">Solo eventos de Arcade: el vehículo y la build son fijos y los tiempos se pueden comparar. Las carreras con build variable se graban pero no aparecen aquí. Los récords sin telemetría vienen del juego; corre el evento con el mod para ver sus vueltas y sectores.</div>';
    byId('main').innerHTML = html;
    refreshCarousels();
  }
  const figure = (label, value, detail) => '<div class="figure"><span class="label">' + label + '</span><span class="value">' + value + '</span><span class="detail">' + (detail || '&nbsp;') + '</span></div>';

