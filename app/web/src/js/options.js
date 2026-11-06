  // ---------- Data and automatic updates ----------
  let toastTimer = 0;
  function showToast(message) {
    const toast = byId('toast'); toast.textContent = message; toast.hidden = false;
    clearTimeout(toastTimer); toastTimer = setTimeout(() => { toast.hidden = true; }, message.length > 80 ? 7000 : 3500);
  }
  // Language: Spanish, English or Aurebesh (written over the English page). Each base language is a
  // page of its own: switching between Spanish and English reloads the app, Aurebesh only changes the font.
  // It is saved in preferences.txt.
  const PAGE_LANGUAGE = 'es';
  const LANGUAGE_SHORT_NAMES = { es: 'ES', en: 'EN', aurebesh: 'Aurebesh' };
  const currentLanguage = () => { const language = preference('language'); return PAGE_LANGUAGE === 'es' ? 'es' : language === 'aurebesh' ? 'aurebesh' : 'en'; };
  function showLanguage(language) {
    const aurebeshShown = language === 'aurebesh' && aurebeshFontInstalled();
    document.documentElement.classList.toggle('language-aurebesh', aurebeshShown);
    const shown = aurebeshShown ? 'aurebesh' : PAGE_LANGUAGE;
    byId('languageNames').innerHTML = ['es', 'en', 'aurebesh'].map(item => (item === shown ? '<b>' + LANGUAGE_SHORT_NAMES[item] + '</b>' : LANGUAGE_SHORT_NAMES[item])).join('&nbsp;·&nbsp;');
    if (state.analysis) drawAll();
  }
  const reloadPage = () => (window.__swgrReload || (() => location.reload()))();
  // Repaints the current screen keeping the scroll position
  function repaintInPlace() { const scrollPosition = window.scrollY; render(); window.scrollTo(0, scrollPosition); if (state.analysis) drawAll(); }
  async function chooseLanguage(language) {
    if (language === 'aurebesh' && !aurebeshFontInstalled()) { showAurebeshMissing(); return; }
    await savePreference('language', language);
    if ((language === 'es' ? 'es' : 'en') !== PAGE_LANGUAGE) { reloadPage(); return; }
    showLanguage(language); applyPreferences();
    repaintInPlace();
  }
  // Options page: theme, hologram, animations, language and the ghost; saved in preferences.txt
  const THEME_NAMES = { sith: 'Sith', jedi: 'Jedi', imperial: 'Imperial', galactic: 'Galactic Racer' };
  const PREFERENCE_DEFAULTS = { theme: 'sith', hologram: 'off', animations: 'on', language: 'es', mode: 'tryhard', ghost_color: 'cyan',
    ghost_enabled: 'on', ghost_transparency: 'medium', ghost_trail: 'off', ghost_trail_transparency: 'low', ghost_flame_mode: 'game' };   // ghost_*: el mod las lee al empezar la siguiente carrera
  // Simple mode shows the essentials; Tryhard (the default) the whole analysis
  const isSimpleMode = () => preference('mode') === 'simple';
  const preference = key => ((state.data && state.data.preferences) || {})[key] || PREFERENCE_DEFAULTS[key];
  function setAnimations(enabled) { document.documentElement.classList.toggle('no-animations', !enabled); }
  function applyPreferences() {
    const root = document.documentElement;
    const theme = preference('theme');
    if (theme !== 'sith' && THEME_NAMES[theme]) root.dataset.theme = theme; else delete root.dataset.theme;
    const hologram = preference('hologram');
    root.classList.toggle('hologram', hologram === 'normal' || hologram === 'soft' || hologram === 'strong');
    root.classList.toggle('hologram-soft', hologram === 'soft');
    root.classList.toggle('hologram-strong', hologram === 'strong');
    setAnimations(preference('animations') !== 'off');
    root.classList.toggle('mode-simple', isSimpleMode());
    document.querySelectorAll('#modeButton [data-mode]').forEach(label => label.classList.toggle('chosen', label.dataset.mode === preference('mode')));
    document.querySelectorAll('#main [data-preference]').forEach(group => group.querySelectorAll('button').forEach(button =>
      button.setAttribute('aria-pressed', String(button.dataset.value === shownPreference(group.dataset.preference)))));
  }
  // El valor que marca cada grupo de botones: la llama «No» es ghost_flame = off (la guarda el mod aparte del modo)
  const shownPreference = key => key === 'language' ? currentLanguage() : key === 'ghost_flame_mode' && preference('ghost_flame') === 'off' ? 'off' : preference(key);
  function savePreference(key, value) {
    if (state.data) { state.data.preferences = state.data.preferences || {}; state.data.preferences[key] = value; }
    return postJson('/api/save', { kind: 'preference', key, value }).catch(() => {});
  }
  // The mode button of the top bar switches between Simple and Tryhard
  byId('modeButton').addEventListener('click', () => {
    savePreference('mode', isSimpleMode() ? 'tryhard' : 'simple'); applyPreferences();
    repaintInPlace();
    if (preference('animations') !== 'off') playEntrance();
  });
  // Los grupos de botones de la página de Opciones (cada uno guarda su preferencia)
  document.addEventListener('click', clickEvent => {
    const button = clickEvent.target.closest('.options-page [data-preference] button[data-value]'); if (!button) return;
    const key = button.closest('[data-preference]').dataset.preference, value = button.dataset.value, before = preference(key);
    if (key === 'language') { chooseLanguage(value); return; }
    savePreference(key, value);
    // La llama tiene un solo grupo en la app, pero el mod lee dos claves: el modo (game/own) y si está encendida (on/off)
    if (key === 'ghost_flame_mode') savePreference('ghost_flame', value === 'off' ? 'off' : 'on');
    applyPreferences();
    if (key === 'theme' || key === 'mode') repaintInPlace();
    if (key === 'hologram' && value !== 'off' && before === 'off') playPowerOnSweep();   // only when it is turned on
    if (preference('animations') !== 'off') playEntrance();
  });
  // Without the SF Distant Galaxy Symbols font there is no Aurebesh to show: the options page explains what is missing
  const aurebeshFontInstalled = () => document.documentElement.classList.contains('has-aurebesh');
  function showAurebeshMissing() {
    state.optionsSection = 'optionsAppearance';
    if (state.view.name !== 'options') navigate({ name: 'options' }); else showOptionsSection('optionsAppearance');
    const explanation = byId('aurebeshMissing'); explanation.classList.remove('highlighted'); void explanation.offsetWidth; explanation.classList.add('highlighted');
  }
  // The button at the top: Spanish → English → Aurebesh (if the font is there) → Spanish
  byId('languageButton').addEventListener('click', () => {
    const language = currentLanguage(), next = language === 'es' ? 'en' : language === 'en' && aurebeshFontInstalled() ? 'aurebesh' : 'es';
    chooseLanguage(next);
  });
  // ---------- Notices: the mod's version against the app's, and safe mode ----------
  function compareVersions(first, second) {
    const firstParts = String(first).split('.').map(Number), secondParts = String(second).split('.').map(Number);
    for (let index = 0; index < Math.max(firstParts.length, secondParts.length); index++) {
      const difference = (firstParts[index] || 0) - (secondParts[index] || 0);
      if (difference) return difference;
    }
    return 0;
  }
  // The parts of the mod that safe mode can turn off (the mod's names, and the ones of 0.9.17 and earlier)
  const SAFE_MODE_PARTS = { timing_panel: 'el panel de tiempos', game_records: 'la lectura de tus récords del juego', record_search: 'la búsqueda de récords (Ctrl+Shift+K)',
    race_hook: 'la grabación de carreras', recording: 'la grabación', event_names: 'la lectura de los nombres de evento del juego',
    ghost_search: 'la búsqueda de fantasmas (Ctrl+Shift+G)', ghost_test: 'la prueba del fantasma en pista', race_ghost: 'el fantasma en pista', ghost_look: 'el aspecto del fantasma', ghost_vehicle: 'copiar tu vehículo para el fantasma', state_watch: 'el diagnóstico de estados del vehículo', ghost_trail: 'la estela del fantasma',
    panel: 'el panel de tiempos', records: 'la lectura de tus récords del juego', busqueda: 'la búsqueda de récords (Ctrl+Shift+K)',
    carrera: 'la grabación de carreras', grabacion: 'la grabación', nombres: 'la lectura de los nombres de evento del juego' };
  function renderNotices() {
    const data = state.data, notices = [];
    if (data.modVersion && data.expectedModVersion && data.modVersion !== data.expectedModVersion) {
      notices.push(compareVersions(data.modVersion, data.expectedModVersion) < 0
        ? '<span><b>El mod está desactualizado.</b> Tienes la v' + escapeHtml(data.modVersion) + ' y esta app va con la v' + escapeHtml(data.expectedModVersion) + ': copia la carpeta <b>Scripts</b> del mismo paquete que la app.</span>'
        : '<span><b>La app está desactualizada.</b> Tu mod es la v' + escapeHtml(data.modVersion) + ' y esta app (v' + escapeHtml(data.version) + ') va con la v' + escapeHtml(data.expectedModVersion) +
          ': usa el GalacticRacerTelemetry.exe del mismo paquete que el mod.</span>');
    }
    // safe_mode.txt: one line per part turned off: part \t blocked|session \t reason \t detail
    const turnedOff = String(data.safeMode || '').split('\n').map(line => line.split('\t')).filter(columns => columns[0]);
    if (turnedOff.length) notices.push('<span><b>Modo seguro del mod.</b> ' + turnedOff.map(([part, scope, reason, detail]) => 'Se ha desactivado ' + escapeHtml(SAFE_MODE_PARTS[part] || part) +
      (scope === 'session' || scope === 'sesion' ? ' en tu última partida' : '') + ' porque ' + escapeHtml(reason || 'algo falló') + (detail ? ' (' + escapeHtml(detail) + ')' : '') + '.').join(' ') +
      ' Lo demás sigue funcionando.</span><button type="button" class="button small" id="safeModeRetry">Volver a intentarlo</button>');
    const seenVersion = preference('seen_changes_version');
    if (data.version && seenVersion !== data.version && state.view.name !== 'options')
      notices.push('<span><b>Novedades de la ' + escapeHtml(data.version) + ':</b> ' + escapeHtml(CHANGELOG[0].items.slice(0, 3).map(item => item.replace(/:.*/, '')).join(' · ')) + '…</span>' +
        '<button type="button" class="button small" data-navigate="about">Ver novedades</button><button type="button" class="button small" id="changesSeen">Entendido</button>');
    byId('notices').innerHTML = notices.map(notice => '<div class="notice">' + notice + '</div>').join('');
    if (byId('changesSeen')) byId('changesSeen').onclick = () => { savePreference('seen_changes_version', data.version); renderNotices(); };
    if (byId('safeModeRetry')) byId('safeModeRetry').onclick = async () => {
      try { await fetchFromApp('/api/retry-safe-mode', { method: 'POST' }); showToast('Hecho: el mod lo volverá a intentar la próxima vez que abras el juego'); await refreshData(); }
      catch (error) { showToast('No se pudo: ' + error.message); }
    };
  }

