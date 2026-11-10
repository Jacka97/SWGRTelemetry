  // ---------- Opciones: panel en carrera (timing_panel.ini del mod) ----------
  // La app guarda los cambios en el archivo y el mod lo vuelve a leer al empezar cada carrera.
  // La muestra es la pantalla del juego reducida. El juego dibuja su interfaz sobre 3840 x 2160 y luego la
  // ajusta a tu resolución (en 1080p, a la mitad): con esa medida, la muestra sale igual que en el juego.
  // El panel se coloca arrastrándolo con el ratón.
  // Con otra forma de pantalla (preferencia panel_aspect) la muestra se ensancha o se estrecha: la interfaz sigue
  // midiendo 2160 de alto y el ancho cambia. La posición guardada es una proporción, así que el mod no cambia.
  const RACE_PANEL_SCREEN = { width: 3840, height: 2160 };
  const RACE_PANEL_WIDTHS = { '16x9': 3840, '16x10': 3456, '21x9': 5120, '32x9': 7680 };
  // Medidas de cada estilo del panel del juego (timing_panel.lua): ancho, relleno, alto de fila y letras
  const RACE_PANEL_LAYOUTS = {
    sith: { width: 236, padding: 10, rowHeight: 21, fonts: [12, 15, 11, 13, 11] },
    compact: { width: 214, padding: 8, rowHeight: 19, fonts: [11, 14, 10, 12, 10] },
  };
  // Paletas, en colores de pantalla (#RRGGBB). Sith y Gris son las de siempre del panel; las demás, las de los temas de la app
  const RACE_PANEL_PALETTES = {
    sith: { background: '#382222', topBar: '#ff7272', title: '#ff948f', label: '#d3c7c4', text: '#faf6f4', dim: '#b5a8a6', best: '#dcbdff', better: '#96e9c2', worse: '#ffe196', gain: '#96e9c2', loss: '#ffc185' },
    gray: { background: '#2b343b', topBar: 'none', title: '#d9e0e6', label: '#d9e0e6', text: '#f7f9fb', dim: '#c2cad3', best: '#dcb7ff', better: '#94f1ba', worse: '#ffe48f', gain: '#94f1ba', loss: '#ffaca8' },
    jedi: { background: '#0b1220', topBar: '#3d8bff', title: '#7fb3ff', label: '#8fa1bd', text: '#e6eefb', dim: '#56688a', best: '#c09bff', better: '#4fd18b', worse: '#f2c14e', gain: '#4fd18b', loss: '#ff8a3d' },
    imperial: { background: '#141619', topBar: '#dfe5ec', title: '#ffffff', label: '#9aa1aa', text: '#eef0f2', dim: '#636a73', best: '#b382ff', better: '#4fd18b', worse: '#f2c14e', gain: '#4fd18b', loss: '#ff5a4a' },
    galactic: { background: '#173139', topBar: '#ef6b3c', title: '#f39a63', label: '#a8b9b5', text: '#f1e8d6', dim: '#6c8789', best: '#c7a4ff', better: '#8fd88a', worse: '#f2c14e', gain: '#8fd88a', loss: '#ff9a5c' },
  };
  const RACE_PANEL_PALETTE_NAMES = [['sith', 'Sith'], ['gray', 'Gris'], ['jedi', 'Jedi'], ['imperial', 'Imperial'], ['galactic', 'Galactic Racer']];
  const RACE_PANEL_COLORS = [['background', 'Fondo', 'color_background'], ['topBar', 'Barra de arriba', 'color_top_bar'], ['title', 'Títulos', 'color_title'],
    ['label', 'Nombres', 'color_label'], ['text', 'Tiempos', 'color_text'], ['dim', 'Sin correr', 'color_dim'], ['best', 'Mejor sector', 'color_best'],
    ['better', 'Mejora', 'color_better'], ['worse', 'Empeora', 'color_worse'], ['gain', 'Ganas', 'color_gain'], ['loss', 'Pierdes', 'color_loss']];
  const RACE_PANEL_ROWS = [['live_difference', 'Diferencia en vivo'], ['sector_bars', 'Barras de sectores'], ['last_lap', 'Última vuelta'], ['best_lap', 'Mejor vuelta'],
    ['ideal_lap', 'Vuelta ideal'], ['speeds', 'Velocidades'], ['event_total', 'Total'], ['forecast', 'Previsto'], ['target', 'Objetivo']];
  // Lo que pone el mod si el archivo no dice nada (timing_panel.lua)
  const RACE_PANEL_DEFAULTS = { enabled: 'true', style: 'compact', x: '0.045', y: '0.265', scale: '1.15', opacity: '0.20', compare_with: 'best',
    last_lap: 'true', best_lap: 'true', ideal_lap: 'true', event_total: 'true', target: 'true', previous_sectors: 'true', live_difference: 'true',
    sector_bars: 'true', speeds: 'true', forecast: 'true' };
  state.racePanel = null;

  const racePanelValue = key => (state.racePanel && state.racePanel[key] !== undefined && state.racePanel[key] !== '' ? state.racePanel[key] : RACE_PANEL_DEFAULTS[key]);
  const racePanelOn = key => racePanelValue(key) !== 'false';
  // La paleta de partida: la del estilo (el estilo «current» de antes era la gris)
  const racePanelBasePalette = () => RACE_PANEL_PALETTES[racePanelValue('style') === 'current' ? 'gray' : 'sith'];
  function racePanelColor(key) {
    const entry = RACE_PANEL_COLORS.find(item => item[0] === key);
    const chosen = state.racePanel && state.racePanel[entry[2]];
    return chosen || racePanelBasePalette()[key];
  }
  const racePanelLayout = () => RACE_PANEL_LAYOUTS[racePanelValue('style') === 'compact' ? 'compact' : 'sith'];

  // Cuerpo de la sección (se rellena al leer el archivo)
  function racePanelBody() {
    // (los atributos van escritos enteros para que la revisión de la página los encuentre)
    // (cada atributo va escrito entero para que la revisión de la página lo encuentre igual en los dos idiomas)
    const placeButtons = items => items.map(([value, text]) => '<button type="button" data-race-panel-place="' + value + '">' + text + '</button>').join('');
    const valueButtons = items => items.map(([value, text]) => '<button type="button" data-value="' + value + '">' + text + '</button>').join('');
    const toggleButtons = items => items.map(([value, text]) => '<button type="button" data-race-panel-toggle="' + value + '">' + text + '</button>').join('');
    const paletteButtons = items => items.map(([value, text]) => '<button type="button" data-race-panel-palette="' + value + '">' + text + '</button>').join('');
    const places = [['0.02,0.03', 'Arriba a la izquierda'], ['0.5,0.03', 'Arriba en el centro'], ['0.98,0.03', 'Arriba a la derecha'], ['0.02,0.5', 'A la izquierda'],
      ['0.98,0.5', 'A la derecha'], ['0.02,0.97', 'Abajo a la izquierda'], ['0.98,0.97', 'Abajo a la derecha']];
    // Dos columnas: la pantalla de muestra y la colocación a un lado, el resto de opciones al otro (sin scroll)
    return '<div class="race-panel-editor"><div class="race-panel-left">' +
      '<div class="race-panel-screen" id="racePanelScreen"><div class="race-panel-stage" id="racePanelStage"><div class="race-panel-preview" id="racePanelPreview" title="Arrástralo para colocarlo"></div></div></div>' +
      '<p class="note">Arrastra el panel en la pantalla de muestra para colocarlo. Los cambios se aplican en la siguiente carrera.</p>' +
      '<div class="group"><span>Colocar en</span><div class="options">' + placeButtons(places) + '</div></div>' +
      '<div class="group"><span>Forma de tu pantalla</span><div class="options" data-preference="panel_aspect"><button type="button" data-value="16x9">16:9 · 1920x1080, 2560x1440, 4K</button><button type="button" data-value="16x10">16:10 · 1920x1200, 2560x1600</button><button type="button" data-value="21x9">21:9 · 2560x1080, 3440x1440</button><button type="button" data-value="32x9">32:9 · 5120x1440</button></div></div>' +
      '</div><div class="race-panel-right">' +
      '<div class="group"><span>Tamaño</span><input type="range" id="racePanelScale" min="0.6" max="2.2" step="0.05"><span class="muted" id="racePanelScaleText"></span></div>' +
      '<div class="group"><span>Opacidad del fondo</span><input type="range" id="racePanelOpacity" min="0" max="1" step="0.05"><span class="muted" id="racePanelOpacityText"></span></div>' +
      '<div class="group"><span>Estilo</span><div class="options" data-race-panel-key="style">' + valueButtons([['sith', 'Normal'], ['compact', 'Compacto']]) + '</div></div>' +
      '<div class="group"><span>Al empezar la carrera</span><div class="options" data-race-panel-key="enabled">' + valueButtons([['true', 'Se ve'], ['false', 'Oculto (Ctrl+F10)']]) + '</div></div>' +
      '<div class="group"><span>Sectores comparados con</span><div class="options" data-race-panel-key="compare_with">' + valueButtons([['best', 'Tu mejor sector'], ['previous', 'La vuelta anterior']]) + '</div></div>' +
      '<div class="group"><span>Filas</span><div class="options race-panel-rows">' + toggleButtons(RACE_PANEL_ROWS) + '</div></div>' +
      '<div class="group"><span>Colores</span><div class="options">' + paletteButtons(RACE_PANEL_PALETTE_NAMES) + '</div></div>' +
      '<div class="race-panel-colors">' + RACE_PANEL_COLORS.map(([key, text]) =>
        '<label><input type="color" data-race-panel-color="' + key + '"><span>' + text + '</span></label>').join('') + '</div>' +
      '</div></div>';
  }

  // Lee el archivo y prepara los controles
  async function loadRacePanel() {
    if (!byId('racePanelScreen')) return;
    try { state.racePanel = (await (await fetchFromApp('/api/timing-panel')).json()).values || {}; } catch (error) { state.racePanel = {}; }
    wireRacePanel();
    drawRacePanel();
  }
  // Guarda unos cambios (y los aplica ya a la muestra)
  function saveRacePanel(changes) {
    Object.assign(state.racePanel, changes);
    drawRacePanel();
    clearTimeout(state.racePanelSaveTimer);
    state.racePanelSaveTimer = setTimeout(async () => {
      const pending = state.racePanelPending || {}; state.racePanelPending = {};
      try {
        const response = await postJson('/api/timing-panel', { values: pending });
        if (!response.ok) throw new Error(await response.text());
        if (!state.racePanelSavedNotice) { state.racePanelSavedNotice = true; showToast('Panel guardado: se aplica en la siguiente carrera'); }
      } catch (error) { showToast('No se pudo guardar el panel: ' + error.message); }
    }, 350);
    state.racePanelPending = Object.assign(state.racePanelPending || {}, changes);
  }

  function wireRacePanel() {
    document.querySelectorAll('[data-race-panel-place]').forEach(button => button.addEventListener('click', () => {
      const [x, y] = button.dataset.racePanelPlace.split(',');
      saveRacePanel({ x, y });
    }));
    document.querySelectorAll('[data-race-panel-key] button').forEach(button => button.addEventListener('click', () => {
      saveRacePanel({ [button.parentElement.dataset.racePanelKey]: button.dataset.value });
    }));
    document.querySelectorAll('[data-race-panel-toggle]').forEach(button => button.addEventListener('click', () => {
      const key = button.dataset.racePanelToggle;
      saveRacePanel({ [key]: racePanelOn(key) ? 'false' : 'true' });
    }));
    document.querySelectorAll('[data-race-panel-palette]').forEach(button => button.addEventListener('click', () => {
      const palette = RACE_PANEL_PALETTES[button.dataset.racePanelPalette], changes = {};
      RACE_PANEL_COLORS.forEach(([key, , fileKey]) => { changes[fileKey] = palette[key]; });
      saveRacePanel(changes);
    }));
    document.querySelectorAll('[data-race-panel-color]').forEach(input => input.addEventListener('input', () => {
      const entry = RACE_PANEL_COLORS.find(item => item[0] === input.dataset.racePanelColor);
      saveRacePanel({ [entry[2]]: input.value });
    }));
    const slider = (id, key, digits) => byId(id).addEventListener('input', event => saveRacePanel({ [key]: (+event.target.value).toFixed(digits) }));
    slider('racePanelScale', 'scale', 2); slider('racePanelOpacity', 'opacity', 2);
    // Arrastrar el panel por la pantalla de muestra
    const preview = byId('racePanelPreview');
    preview.addEventListener('pointerdown', down => {
      const zoom = state.racePanelZoom || 1, layout = racePanelLayout(), scale = +racePanelValue('scale');
      const panelWidth = layout.width * scale, panelHeight = preview.offsetHeight * scale;
      const startLeft = preview.offsetLeft, startTop = preview.offsetTop;
      preview.setPointerCapture(down.pointerId);
      const move = event => {
        const left = Math.max(0, Math.min(RACE_PANEL_SCREEN.width - panelWidth, startLeft + (event.clientX - down.clientX) / zoom));
        const top = Math.max(0, Math.min(RACE_PANEL_SCREEN.height - panelHeight, startTop + (event.clientY - down.clientY) / zoom));
        state.racePanel.x = (left / Math.max(1, RACE_PANEL_SCREEN.width - panelWidth)).toFixed(3);
        state.racePanel.y = (top / Math.max(1, RACE_PANEL_SCREEN.height - panelHeight)).toFixed(3);
        drawRacePanel();
      };
      const up = () => {
        preview.removeEventListener('pointermove', move); preview.removeEventListener('pointerup', up);
        saveRacePanel({ x: state.racePanel.x, y: state.racePanel.y });
      };
      preview.addEventListener('pointermove', move); preview.addEventListener('pointerup', up);
    });
    if (!state.racePanelResizeWired) { state.racePanelResizeWired = true; window.addEventListener('resize', () => { if (byId('racePanelScreen')) drawRacePanel(); }); }
  }

  // La muestra: un panel parecido al del juego, con los colores, filas y medidas elegidos
  function drawRacePanel() {
    const screen = byId('racePanelScreen'), stage = byId('racePanelStage'), preview = byId('racePanelPreview');
    if (!screen || !state.racePanel) return;
    const layout = racePanelLayout(), compact = racePanelValue('style') === 'compact', color = racePanelColor;
    const [titleLabel, titleValue, labelSize, valueSize, differenceSize] = layout.fonts;
    const row = (label, value, difference, valueColor, differenceColor, sizes) => '<div class="race-panel-row" style="height:' + layout.rowHeight + 'px">' +
      '<span style="color:' + color('label') + ';font-size:' + (sizes ? sizes[0] : labelSize) + 'px">' + label + '</span>' +
      '<span style="color:' + (valueColor || color('text')) + ';font-size:' + (sizes ? sizes[1] : valueSize) + 'px">' + value + '</span>' +
      '<span style="color:' + (differenceColor || color('dim')) + ';font-size:' + differenceSize + 'px">' + (difference || '') + '</span></div>';
    let html = racePanelColor('topBar') !== 'none' ? '<div class="race-panel-top" style="background:' + color('topBar') + '"></div>' : '';
    html += row('<span style="color:' + color('title') + '">VUELTA 2</span>', '1:02.4', '', color('text'), null, [titleLabel, titleValue]);
    if (racePanelOn('live_difference')) html += row('DIF', '-0.214', '', color('gain'), null, [labelSize, titleValue + 4]);
    if (racePanelOn('sector_bars')) html += '<div class="race-panel-bars"><i style="background:' + color('best') + '"></i><i style="background:' + color('better') + '"></i><i style="background:' + color('dim') + '"></i></div>';
    html += row('S1', '11.204', '-0.120', color('best'), color('gain')) + row('S2', '17.512', '+0.084', color('worse'), color('loss')) + row('S3', '--', '', color('dim'));
    const bottom = [['last_lap', 'ÚLTIMA', '1:02.9', '+0.230'], ['best_lap', 'MEJOR', '1:01.9', ''], ['ideal_lap', 'IDEAL', '1:01.2', '0.700'],
      ['speeds', 'VEL.', '612', '298'], ['event_total', 'TOTAL', '2:07.3', ''], ['forecast', 'PREVISTO', '3:10.1', '-0.80'], ['target', 'OBJETIVO', '3:11.0', '']];
    bottom.forEach(([key, label, value, difference]) => {
      if (!racePanelOn(key) || (key === 'last_lap' && compact)) return;
      const differenceColor = difference.startsWith('-') ? color('gain') : difference.startsWith('+') ? color('loss') : color('dim');
      html += row(label, value, difference, null, differenceColor);
    });
    preview.innerHTML = html;
    // Fondo con su opacidad (la del juego), tamaño y posición
    const background = color('background'), opacity = +racePanelValue('opacity');
    const channels = [1, 3, 5].map(index => parseInt(background.slice(index, index + 2), 16) || 0);
    Object.assign(preview.style, { width: layout.width + 'px', padding: '0 ' + layout.padding + 'px ' + layout.padding / 2 + 'px', background: 'rgba(' + channels.join(',') + ',' + opacity + ')' });
    RACE_PANEL_SCREEN.width = RACE_PANEL_WIDTHS[preference('panel_aspect')] || 3840;
    screen.style.aspectRatio = RACE_PANEL_SCREEN.width + ' / ' + RACE_PANEL_SCREEN.height;
    stage.style.width = RACE_PANEL_SCREEN.width + 'px';
    const scale = +racePanelValue('scale'), zoom = screen.clientWidth / RACE_PANEL_SCREEN.width;
    state.racePanelZoom = zoom;
    stage.style.transform = 'scale(' + zoom + ')';
    const panelWidth = layout.width * scale, panelHeight = preview.offsetHeight * scale;
    preview.style.transform = 'scale(' + scale + ')';
    preview.style.left = (+racePanelValue('x') * Math.max(0, RACE_PANEL_SCREEN.width - panelWidth)) + 'px';
    preview.style.top = (+racePanelValue('y') * Math.max(0, RACE_PANEL_SCREEN.height - panelHeight)) + 'px';
    // Los controles, con lo elegido
    byId('racePanelScale').value = scale; byId('racePanelScaleText').textContent = Math.round(scale * 100) + ' %';
    byId('racePanelOpacity').value = opacity; byId('racePanelOpacityText').textContent = Math.round(opacity * 100) + ' %';
    document.querySelectorAll('[data-race-panel-key]').forEach(group => group.querySelectorAll('button').forEach(button => {
      const current = group.dataset.racePanelKey === 'style' && racePanelValue('style') === 'current' ? 'sith' : racePanelValue(group.dataset.racePanelKey);
      button.setAttribute('aria-pressed', String(button.dataset.value === current));
    }));
    document.querySelectorAll('[data-race-panel-toggle]').forEach(button => {
      const key = button.dataset.racePanelToggle;
      button.setAttribute('aria-pressed', String(racePanelOn(key)));
      button.disabled = key === 'last_lap' && compact;
    });
    document.querySelectorAll('[data-race-panel-color]').forEach(input => {
      const value = color(input.dataset.racePanelColor);
      input.value = /^#[0-9a-f]{6}$/i.test(value) ? value : '#000000';
    });
    document.querySelectorAll('[data-race-panel-palette]').forEach(button => {
      const palette = RACE_PANEL_PALETTES[button.dataset.racePanelPalette];
      button.setAttribute('aria-pressed', String(RACE_PANEL_COLORS.every(([key]) => color(key).toLowerCase() === palette[key].toLowerCase())));
    });
  }
