  // ---------- Profile: your pilot name and your colour (how your friends see you) ----------
  const PILOT_COLORS = ['#ff3b3b', '#ff9a3d', '#f2c14e', '#4cd07d', '#3db8ff', '#7a6cff', '#ff5fd2', '#e8e8e8'];
  const isValidColor = color => /^#[0-9a-f]{6}$/i.test(String(color || ''));
  const myPilotColor = () => (isValidColor(preference('color')) ? preference('color') : PILOT_COLORS[0]);
  const pilotDot = color => '<i class="pilot-dot" style="background:' + (isValidColor(color) ? color : 'var(--text-muted)') + '"></i>';
  const ordinal = number => number + 'º';
  function myStatistics() {
    const eventIds = new Set(state.events.filter(event => event.recordTime).map(event => event.id).concat(Object.keys(state.data.gameRecords || {})));
    let golds = 0;
    eventIds.forEach(eventId => {
      const event = state.events.find(item => item.id === eventId), gameRecord = gameRecordOf(state.data, eventId);
      const recordTime = event ? event.recordTime : gameRecord && gameRecord.total, targetTime = event && event.targetSource ? event.targetSource.target : gameRecord && gameRecord.target;
      if (recordTime > 0 && targetTime > 0 && recordTime <= targetTime + 1e-4) golds++;
    });
    return { eventCount: eventIds.size, golds };
  }
  // Cuerpo del panel «Perfil» de Opciones: nombre y color del piloto, y cómo te ven tus amigos
  function profileBody() {
    const color = myPilotColor(), statistics = myStatistics();
    return '<div class="profile-split"><div>' +
      '<label class="muted" for="profileName" style="font-size:.8rem">Nombre de piloto</label>' +
      '<div class="pilot-row"><input id="profileName" maxlength="40" autocomplete="off" placeholder="Por ejemplo: Darth Tito" value="' + escapeHtml(myPilotName()) + '"></div>' +
      '<label class="muted" style="font-size:.8rem">Tu color</label><div class="swatches">' +
      PILOT_COLORS.map(swatch => '<button type="button" class="swatch" data-color="' + swatch + '" aria-pressed="' + (swatch === color) + '" style="background:' + swatch + ';--pilot-color:' + swatch + '" aria-label="Color ' + swatch + '"></button>').join('') + '</div>' +
      '<p class="note">Se guarda en tu PC y va dentro de tu archivo de piloto, así tus amigos te ven con tu nombre y tu color.</p></div>' +
      '<div><label class="muted" style="font-size:.8rem">Así te ven</label>' +
      '<div class="profile-card" style="--pilot-color:' + color + '"><span class="profile-name" id="profilePreview">' + escapeHtml(myPilotName() || 'Tu nombre') + '</span>' +
      '<span class="muted">' + statistics.eventCount + (statistics.eventCount === 1 ? ' evento con tiempo' : ' eventos con tiempo') + ' · ' + statistics.golds + (statistics.golds === 1 ? ' oro' : ' oros') + '</span></div></div></div>';
  }
  function wireProfile() {
    const typedName = () => byId('profileName').value.replace(/[\t\r\n]/g, ' ').trim();
    byId('profileName').addEventListener('input', () => { byId('profilePreview').textContent = byId('profileName').value.trim() || 'Tu nombre'; });
    byId('profileName').addEventListener('change', () => { savePreference('pilot_name', typedName()); });
    document.querySelectorAll('[data-color]').forEach(button => button.addEventListener('click', () => {
      savePreference('pilot_name', typedName());
      savePreference('color', button.dataset.color); repaintInPlace();
    }));
  }

  // ---------- Opciones: perfil, archivos de piloto, fantasma en pista, apariencia, panel en carrera y «Acerca de» ----------
  const optionsHeader = (title, description) => '<div class="panel-header"><h2>' + title + '</h2></div><p class="muted options-description">' + description + '</p>';
  const optionsPanel = (id, title, description, body, extraClass) =>
    '<section class="panel options-panel' + (extraClass ? ' ' + extraClass : '') + '" id="' + id + '">' + optionsHeader(title, description) + body + '</section>';
  // Cuerpo del panel «Tu archivo de piloto»: exportar tus tiempos
  const pilotFileBody = () =>
    '<button type="button" class="button" id="pilotExport">Exportar mis tiempos</button>' +
    '<p class="note" id="pilotMessage">' + (state.pilotMessage || 'Lleva tu mejor tiempo de cada evento (total, mejor vuelta y sectores, también los récords importados del juego) y la telemetría de tu mejor carrera entera, de tu mejor vuelta y de tu mejor vuelta 1 (salida): velocidad y trazada. Se guarda en la carpeta <b>shared</b> del mod. No lleva nada más de tu PC.') + '</p>' +
    '<p class="note">Para compararte con un amigo, entra en un evento: en «Contra tus amigos» pulsa «Comparar carrera» o «Comparar vuelta». En el comparador A/B también aparecen en «Amigos».</p>';
  // Cuerpo del panel «Archivos de tus amigos»: la lista con «Quitar» y el botón para añadir
  const friendsBody = () => {
    const friends = friendPilots();
    return '<div class="drop-zone-header"><label class="button" for="pilotFileInput" tabindex="0">Añadir archivo…</label></div>' +
      (friends.length ? '<div class="friends-list">' + friends.map(friend => '<div class="friend-item"><b>' + pilotDot(friend.color) + escapeHtml(friend.pilot) + '</b><span class="muted">' + friendFileContents(friend) + ' · archivo del ' +
        escapeHtml(String(friend.date || '').slice(0, 10)) + '</span><button type="button" class="button small" data-remove-friend="' + escapeHtml(friend.pilot) + '">Quitar</button></div>').join('') + '</div>'
        : '<p class="muted">Todavía no tienes ninguno. Arrastra aquí un archivo <b>.swgr</b> o pulsa «Añadir archivo…».</p>');
  };
  // Grupos de botones del fantasma en pista (el mod los lee al empezar la siguiente carrera)
  const ghostOptionsBody = () =>
    '<div class="group"><span>Fantasma en pista</span><div class="options" data-preference="ghost_enabled"><button type="button" data-value="on">Sí</button><button type="button" data-value="off">No</button></div></div>' +
    '<div class="group"><span>Color del fantasma en pista</span><div class="options" data-preference="ghost_color"><button type="button" data-value="cyan">Cian</button><button type="button" data-value="white">Blanco</button><button type="button" data-value="red">Rojo</button><button type="button" data-value="green">Verde</button><button type="button" data-value="gold">Dorado</button><button type="button" data-value="purple">Morado</button></div></div>' +
    '<div class="group"><span>Transparencia del fantasma</span><div class="options" data-preference="ghost_transparency"><button type="button" data-value="low">Baja</button><button type="button" data-value="medium">Media</button><button type="button" data-value="high">Alta</button></div></div>' +
    '<div class="group"><span>Llama del fantasma</span><div class="options" data-preference="ghost_flame_mode"><button type="button" data-value="game">Del juego</button><button type="button" data-value="own">Propia</button><button type="button" data-value="off">No</button></div></div>' +
    '<div class="group"><span>Estela del fantasma</span><div class="options" data-preference="ghost_trail"><button type="button" data-value="on">Sí</button><button type="button" data-value="off">No</button></div></div>' +
    '<div class="group"><span>Transparencia de la estela</span><div class="options" data-preference="ghost_trail_transparency"><button type="button" data-value="low">Baja</button><button type="button" data-value="medium">Media</button><button type="button" data-value="high">Alta</button></div></div>';
  // Grupos de botones de la apariencia de la app
  const appearanceBody = () =>
    '<div class="group"><span>Tema</span><div class="options" data-preference="theme"><button type="button" data-value="sith">Sith</button><button type="button" data-value="jedi">Jedi</button><button type="button" data-value="imperial">Imperial</button><button type="button" data-value="galactic">Galactic Racer</button></div></div>' +
    '<div class="group"><span>Modo</span><div class="options" data-preference="mode"><button type="button" data-value="simple">Simple</button><button type="button" data-value="tryhard">Tryhard</button></div></div>' +
    '<div class="group"><span>Efecto holograma</span><div class="options" data-preference="hologram"><button type="button" data-value="off">No</button><button type="button" data-value="soft">Suave</button><button type="button" data-value="normal">Normal</button><button type="button" data-value="strong">Fuerte</button></div></div>' +
    '<div class="group"><span>Animaciones</span><div class="options" data-preference="animations"><button type="button" data-value="on">Sí</button><button type="button" data-value="off">No</button></div></div>' +
    '<div class="group"><span>Idioma</span><div class="options" data-preference="language"><button type="button" data-value="es">Español</button><button type="button" data-value="en">English</button><button type="button" data-value="aurebesh" class="aurebesh-option">Aurebesh</button></div>' +
    '<span class="aurebesh-missing" id="aurebeshMissing">El aurebesh necesita la fuente SF Distant Galaxy Symbols (ShyFonts, gratis para uso personal). No va dentro de la app por su licencia: instálala en Windows o ponla en la carpeta «fonts» y vuelve a abrir la app.</span></div>';
  // Apartados de Opciones, en el orden del menú lateral
  const OPTIONS_SECTIONS = [['optionsProfile', 'Perfil'], ['optionsPilotFile', 'Tu archivo de piloto'], ['optionsFriends', 'Archivos de tus amigos'],
    ['optionsGhost', 'Fantasma en pista'], ['optionsAppearance', 'Apariencia de la app'], ['optionsRacePanel', 'Panel en carrera'], ['optionsAbout', 'Acerca de']];
  state.optionsSection = readStored('swgr.optionsSection', 'optionsProfile');
  function showOptionsSection(id) {
    if (!OPTIONS_SECTIONS.some(([sectionId]) => sectionId === id)) id = 'optionsProfile';
    state.optionsSection = id;
    try { localStorage.setItem('swgr.optionsSection', id); } catch (error) { /* sin almacenamiento: no se recuerda */ }
    document.querySelectorAll('.options-content > section').forEach(section => { section.hidden = section.id !== id; });
    document.querySelectorAll('[data-options-section]').forEach(button => button.setAttribute('aria-pressed', button.dataset.optionsSection === id ? 'true' : 'false'));
    if (id === 'optionsRacePanel') drawRacePanel();   // la muestra se mide cuando se ve
  }
  function renderOptions() {
    const data = state.data;
    if (data.version && preference('seen_changes_version') !== data.version) savePreference('seen_changes_version', data.version);   // only once: saving must not repaint
    let html = '<div class="panel-header"><h1>Opciones</h1><span class="muted">Tu perfil, tus archivos de piloto y el aspecto de la app</span></div>';
    html += optionsPanel('optionsProfile', 'Perfil', 'Tu nombre y tu color, que ven tus amigos en Social.', profileBody());
    html += optionsPanel('optionsPilotFile', 'Tu archivo de piloto', 'Exporta tus tiempos para pasárselos a tus amigos.', pilotFileBody());
    html += optionsPanel('optionsFriends', 'Archivos de tus amigos', 'Los archivos .swgr que has añadido para compararte con ellos.', friendsBody(), 'drop-zone');
    html += optionsPanel('optionsGhost', 'Fantasma en pista', 'Cómo se ve tu fantasma en la carrera; se aplica en la siguiente.', ghostOptionsBody());
    html += optionsPanel('optionsAppearance', 'Apariencia de la app', 'Tema, modo, efectos e idioma de esta ventana.', appearanceBody());
    html += optionsPanel('optionsRacePanel', 'Panel en carrera', 'Dónde se ve el panel de tiempos en la carrera, su tamaño, sus colores y sus filas.', racePanelBody());
    html += aboutSection();
    // Menú lateral con los apartados; a la derecha solo se ve el elegido (se recuerda el último)
    const nav = OPTIONS_SECTIONS.map(([id, title]) => '<button type="button" data-options-section="' + id + '">' + title + '</button>').join('');
    const header = html.slice(0, html.indexOf('</div>') + 6), sections = html.slice(header.length);
    byId('main').innerHTML = '<div class="options-page">' + header + '<nav class="options-nav">' + nav + '</nav><div class="options-content">' + sections + '</div></div>';
    document.querySelectorAll('[data-options-section]').forEach(button => button.addEventListener('click', () => showOptionsSection(button.dataset.optionsSection)));
    showOptionsSection(state.optionsSection);
    wireProfile();
    byId('pilotExport').addEventListener('click', exportPilotFile);
    document.querySelectorAll('[data-remove-friend]').forEach(button => button.addEventListener('click', async () => {
      await postJson('/api/remove-friend', { pilot: button.dataset.removeFriend });
      showToast('Quitado ' + button.dataset.removeFriend); await refreshData();
    }));
    applyPreferences();   // marca los botones elegidos
    renderNotices();
    loadRacePanel();
  }

  // ---------- Social: your times against all your friends' ----------
  // Friends from the best to the worst: their average position (from 0 to 1) in the events they have
  function friendRanking() {
    const friends = friendPilots(), scores = {};
    const eventIds = new Set(); friends.forEach(friend => Object.keys(friend.events).forEach(eventId => eventIds.add(eventId)));
    eventIds.forEach(eventId => {
      const rows = standings(eventId, state.events.find(event => event.id === eventId)).filter(row => row.total);
      rows.forEach((row, position) => {
        if (row.isMe) return;
        const score = (scores[row.pilot] ||= { sum: 0, count: 0 });
        score.sum += rows.length > 1 ? position / (rows.length - 1) : 0; score.count++;
      });
    });
    const averagePosition = friend => (scores[friend.pilot] ? scores[friend.pilot].sum / scores[friend.pilot].count : 9);
    return friends.slice().sort((first, second) => averagePosition(first) - averagePosition(second));
  }
  state.versusPilot = readStored('swgr.versusPilot', '');
  function socialRows(friends) {
    const eventIds = new Set(Object.keys(state.data.gameRecords || {}));
    friends.forEach(friend => Object.keys(friend.events).forEach(eventId => eventIds.add(eventId)));
    state.events.forEach(event => eventIds.add(event.id));
    return [...eventIds].map(eventId => {
      const event = state.events.find(item => item.id === eventId);
      const rows = standings(eventId, event).filter(row => row.total);
      const friendResult = friends.map(friend => friend.events[eventId]).find(Boolean) || {}, gameRecord = gameRecordOf(state.data, eventId);
      const titles = eventTitles(state.data, eventId, gameRecord);
      return { eventId, event, rows, title: event ? (event.shortTitle || event.title) : (titles.shortTitle || titles.title || friendResult.name || describeEventCode(eventId)),
        planet: event ? event.planet : (titles.planet || friendResult.planet || '') };
    }).filter(item => item.rows.some(row => !row.isMe));
  }
  // What a friend's file brings: events, and how many with the whole race or the best lap
  function friendFileContents(friend) {
    const results = Object.values(friend.events || {}).filter(Boolean);
    const races = results.filter(result => result.bestRaceTelemetry && Array.isArray(result.bestRaceTelemetry.laps)).length;
    const laps = results.filter(result => result.bestLapTelemetry && Array.isArray(result.bestLapTelemetry.trace)).length;
    return results.length + (results.length === 1 ? ' evento' : ' eventos') + (races ? ' · ' + races + ' con carrera entera' : '') + ' · ' + laps + ' con vuelta';
  }
  function renderSocial() {
    const friends = friendRanking();
    let html = '<div class="panel-header"><h1>Social</h1><span class="muted">Tus tiempos frente a los de tus amigos, sin internet: cada uno exporta su archivo de piloto y os lo pasáis por WhatsApp, Discord o un USB.</span></div>';
    if (friends.length) {
      const eventRows = socialRows(friends).sort((first, second) => String(first.planet).localeCompare(String(second.planet)) || first.title.localeCompare(second.title));
      const MY_KEY = '\u0000me';
      const wins = {};
      eventRows.forEach(item => { const winner = item.rows[0]; if (winner) { const key = winner.isMe ? MY_KEY : winner.pilot; wins[key] = (wins[key] || 0) + 1; } });
      const myName = myPilotName() || 'Tú';
      const winChip = (key, count) => {
        const isMe = key === MY_KEY, friend = friends.find(item => item.pilot === key);
        return '<span class="win' + (isMe ? ' mine' : '') + '">' + pilotDot(isMe ? myPilotColor() : friend && friend.color) + '<b class="numeric">' + count + '</b>' + escapeHtml(isMe ? myName : key) + '</span>';
      };
      html += '<section class="panel"><div class="panel-header"><h2>Clasificación</h2><div class="wins">' + Object.entries(wins).sort((first, second) => second[1] - first[1]).map(([key, count]) => winChip(key, count)).join('') +
        '<span class="muted">eventos ganados</span></div></div><div class="table-scroll"><table class="social"><thead><tr><th>Evento</th><th>' + pilotDot(myPilotColor()) + escapeHtml(myName) + '</th>' +
        friends.map(friend => '<th>' + pilotDot(friend.color) + escapeHtml(friend.pilot) + '</th>').join('') + '</tr></thead><tbody>';
      for (const item of eventRows) {
        const fastest = item.rows[0] && item.rows[0].total, myRow = item.rows.find(row => row.isMe), myIndex = item.rows.indexOf(myRow);
        const timeCell = (value, extraHtml) => '<td class="' + (value > 0 && Math.abs(value - fastest) < 1e-4 ? 'best' : '') + '">' + (value > 0 ? formatTime(value) : '—') + (extraHtml || '') + '</td>';
        html += '<tr' + (item.event ? ' class="clickable" data-navigate="' + escapeHtml(item.eventId) + '"' : '') + ' title="' + escapeHtml(item.event ? item.eventId : 'Aún no lo has corrido con el mod: córrelo para ver el análisis') + '"><td class="text"><span class="event-vehicle">' + vehicleBadge(item.eventId) + '</span> ' + escapeHtml(item.title) +
          (item.planet ? ' <span class="muted">· ' + escapeHtml(item.planet) + '</span>' : '') + '</td>' +
          timeCell(myRow && myRow.total, myRow ? ' <span class="position' + (myIndex === 0 ? ' first' : '') + '" style="font-size:.8em">' + ordinal(myIndex + 1) + '</span>' : '') +
          friends.map(friend => { const row = item.rows.find(candidate => !candidate.isMe && candidate.pilot === friend.pilot); return timeCell(row && row.total); }).join('') + '</tr>';
      }
      html += '</tbody></table></div><div class="note">Resaltado, el más rápido de cada evento. Toca un evento para ver la comparación completa, con sectores y la vuelta de cada uno; los que aún no has corrido con el mod no se abren (solo tienes el récord del juego).</div></section>';
      // Head to head
      const rival = friends.find(friend => friend.pilot === state.versusPilot) || friends[0];
      const pairs = eventRows.map(item => ({ item, mine: item.rows.find(row => row.isMe), theirs: item.rows.find(row => !row.isMe && row.pilot === rival.pilot) }))
        .filter(pair => pair.mine && pair.theirs && pair.mine.total && pair.theirs.total);
      const won = pairs.filter(pair => pair.mine.total < pair.theirs.total - 1e-4).length, lost = pairs.filter(pair => pair.mine.total > pair.theirs.total + 1e-4).length;
      pairs.sort((first, second) => (second.mine.total - second.theirs.total) - (first.mine.total - first.theirs.total));
      html += '<section class="panel"><div class="panel-header"><h2>Cara a cara</h2><div class="compare-picker" style="margin:0"><label for="versusPicker">Contra</label><select id="versusPicker">' +
        friends.map(friend => '<option value="' + escapeHtml(friend.pilot) + '"' + (friend === rival ? ' selected' : '') + '>' + escapeHtml(friend.pilot) + '</option>').join('') + '</select></div></div>';
      if (pairs.length) {
        html += '<div class="versus-summary wins"><span class="win mine">' + pilotDot(myPilotColor()) + '<b class="numeric">' + won + '</b>' + escapeHtml(myName) + ' gana</span><span class="win">' + pilotDot(rival.color) + '<b class="numeric">' + lost + '</b>' + escapeHtml(rival.pilot) + ' gana</span>' +
          '<span class="muted">' + pairs.length + ' eventos en común · ordenados de donde más pierdes a donde más ganas</span></div>' +
          '<div class="table-scroll"><table><thead><tr><th>Evento</th><th>' + escapeHtml(myName) + '</th><th>' + escapeHtml(rival.pilot) + '</th><th>Dif.</th></tr></thead><tbody>' +
          pairs.map(pair => {
            const difference = pair.mine.total - pair.theirs.total;
            return '<tr' + (pair.item.event ? ' class="clickable" data-navigate="' + escapeHtml(pair.item.eventId) + '"' : '') + '><td class="text"><span class="event-vehicle">' + vehicleBadge(pair.item.eventId) + '</span> ' + escapeHtml(pair.item.title) + '</td>' +
              '<td class="' + (difference < 0 ? 'best' : '') + '">' + formatTime(pair.mine.total) + '</td><td class="' + (difference > 0 ? 'best' : '') + '">' + formatTime(pair.theirs.total) + '</td><td><span class="' + (difference <= 0 ? 'gain' : 'loss') + '">' + formatSigned(difference) + '</span></td></tr>';
          }).join('') +
          '</tbody></table></div>';
      } else html += '<p class="muted">Todavía no tenéis eventos en común con tiempo.</p>';
      html += '</section>';
    } else html += '<section class="panel"><div class="empty-state"><b>Aún no tienes amigos añadidos</b><span>Pulsa «Importar tiempos» arriba (o arrastra aquí un archivo .swgr) y aparecerán la clasificación y el cara a cara. Tu perfil y tu archivo de piloto están en Opciones.</span></div></section>';
    byId('main').innerHTML = html;
    if (byId('versusPicker')) byId('versusPicker').addEventListener('change', changeEvent => { state.versusPilot = changeEvent.target.value; writeStored('swgr.versusPilot', state.versusPilot); renderSocial(); });
    document.querySelectorAll('[data-remove-friend]').forEach(button => button.addEventListener('click', async () => {
      await postJson('/api/remove-friend', { pilot: button.dataset.removeFriend });
      showToast('Quitado ' + button.dataset.removeFriend); await refreshData();
    }));
  }

  async function refreshData(scrollToTop) {
    const data = await (await fetchFromApp('/api/data')).json();
    if (data.error === 'modFolderNotFound') {
      byId('main').innerHTML = '<div class="panel"><div class="empty-state"><b>No encuentro la carpeta del mod</b><span>Copia esta app dentro de la carpeta SWGRTelemetry (junto a README.txt) y vuelve a abrirla.</span></div></div>';
      byId('liveIndicator').classList.add('off'); return;
    }
    data.sessions = Array.isArray(data.sessions) ? data.sessions : [];
    for (const key of ['eventRecords', 'manualGameRecords', 'gameRecords', 'eventNames', 'preferences']) if (!data[key] || typeof data[key] !== 'object') data[key] = {};
    data.friends = Array.isArray(data.friends) ? data.friends.map(readPilotFile).filter(Boolean) : [];
    const hasNewSession = state.data && data.sessions.length > state.data.sessions.length;
    state.data = data; state.changeStamp = data.changeStamp;
    showLanguage(currentLanguage());
    applyPreferences();
    renderNotices();
    if (hasNewSession) { showToast('Nueva sesión grabada'); state.fileCache = {}; Object.keys(selectedSessionsByEvent).forEach(eventId => delete selectedSessionsByEvent[eventId]); }
    const scrollPosition = window.scrollY;
    // Repainting for new data does not play the entrance animation again
    clearTimeout(state.entranceTimer); byId('main').classList.remove('entering');
    render();
    if (!scrollToTop) window.scrollTo(0, scrollPosition);
  }
  async function pollForChanges() {
    try {
      const { changeStamp } = await (await fetchFromApp('/api/change-stamp')).json();
      byId('liveIndicator').classList.remove('off');
      if (changeStamp !== state.changeStamp) await refreshData();
    } catch (error) { byId('liveIndicator').classList.add('off'); }
  }
