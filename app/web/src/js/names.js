  // ---------- Event names ----------
  // Nombres oficiales en inglés de los eventos (solo se usan en la página en inglés)
  const EVENT_NAMES_EN = {
    LDB_ARC_PRE_BIKE_COR_A_FWD: "Ice Needle",
    LDB_ARC_PRE_BIKE_DAL_B_FWD: "Jungle Flow",
    LDB_ARC_PRE_BIKE_HSK_P2P_REV: "River Runner",
    LDB_ARC_PRE_BIKE_MAS_A_FWD: "Scrap Cycler",
    LDB_ARC_PRE_BIKE_WHP_A_FWD: "Breakneck Arena",
    LDB_ARC_PRE_CAR_COR_A_REV: "Blizzard Piercer",
    LDB_ARC_PRE_CAR_DAL_A_FWD: "Magma Bend",
    LDB_ARC_PRE_CAR_SPA_A_FWD: "Crimson Ribbon",
    LDB_ARC_PRE_CAR_SPA_B_SHORT_02: "Cavern Drift",
    LDB_ARC_PRE_SKIMMER_HSK_A_FWD: "Wasteland Looper",
    LDB_ARC_PRE_SKIMMER_MAS_A_REV: "Iron Weaver",
    LDB_ARC_TMR_PLANE_BGL_PLANE_FWD: "King of the Racers",
    LDB_ARC_TMR_PLANE_COR_PLANE_FWD: "Veknoid's Charm",
    LDB_ARC_TMR_PLANE_COR_Plane_REV: "Er'kit Ambition",
    LDB_ARC_TMR_PLANE_DAL_PLANE_FWD: "Six-Limbed Fury",
    LDB_ARC_TMR_PLANE_DAL_Plane_REV: "Assassin's Ploy",
    LDB_ARC_TMR_PLANE_SPA_PLANE_FWD: "Hope of the Toong",
    LDB_ARC_TT_BIKE_COR_P2P_REV: "Speeder Bike Champion",
    LDB_ARC_TT_BIKE_DAL_A_SHORT_01: "Speeder Bike Ace",
    LDB_ARC_TT_BIKE_DAL_P2P_SHORT_05: "Little Ahlren",
    LDB_ARC_TT_BIKE_HSK_A_REV: "Shield Smart",
    LDB_ARC_TT_BIKE_MAS_B_SHORT_01: "Super Surge",
    LDB_ARC_TT_BIKE_MAS_P2P_FWD: "Ramjet Run",
    LDB_ARC_TT_BIKE_SPA_A_FWD: "CIZA T Speeder Bike",
    LDB_ARC_TT_BIKE_SPA_A_SHORT_01: "Salty Sprint",
    LDB_ARC_TT_BIKE_SPA_B_FWD: "Red-Eye Rush",
    LDB_ARC_TT_CAR_COR_A_FWD: "Brain Freeze",
    LDB_ARC_TT_CAR_DAL_A_FWD: "Fuel Frenzy",
    LDB_ARC_TT_CAR_DAL_B_FWD: "Lethal Lava",
    LDB_ARC_TT_CAR_DAL_B_REV: "DARC X Landspeeder",
    LDB_ARC_TT_CAR_HSK_A_FWD_MINES: "Hazard Eater",
    LDB_ARC_TT_CAR_HSK_P2P_FWD: "Total Hangtime",
    LDB_ARC_TT_CAR_HSK_SPECIAL_SHORT_02: "Acid Ringer",
    LDB_ARC_TT_CAR_MAS_A_REV: "Venting Machine",
    LDB_ARC_TT_CAR_MAS_A_SHORT_02: "Landspeeder Ace",
    LDB_ARC_TT_CAR_WHP_A_FWD: "The Experiment",
    LDB_ARC_TT_PLANE_BGL_PLANE_FWD: "Twin Sun Flight",
    LDB_ARC_TT_PLANE_COR_PLANE_REV: "Avalanche Engines",
    LDB_ARC_TT_PLANE_DAL_PLANE_REV: "Volcanic Velocity",
    LDB_ARC_TT_PLANE_MAS_B_PLANE: "Scrapper's Run",
    LDB_ARC_TT_PLANE_SPA_PLANE_FWD: "The Red and the White",
    LDB_ARC_TT_PLANE_WHP_PLANE_FWD: "Stadium Spectacular",
    LDB_ARC_TT_SKIMMER_COR_A_SHORT_02: "Pipeline Express",
    LDB_ARC_TT_SKIMMER_COR_B_FWD: "Night Flight",
    LDB_ARC_TT_SKIMMER_COR_P2P_SHORT_05: "Skim Speeder Pilot",
    LDB_ARC_TT_SKIMMER_DAL_A_SHORT_06: "Risky Rider",
    LDB_ARC_TT_SKIMMER_DAL_P2P_FWD: "Cool Runnings",
    LDB_ARC_TT_SKIMMER_HSK_B_REV: "Skim Speeder Ace",
    LDB_ARC_TT_SKIMMER_HSK_SPECIAL_SHORT_01: "Caustic Flood",
    LDB_ARC_TT_SKIMMER_MAS_P2P_FWD: "RAK S Skim Speeder",
    LDB_ARC_TT_SKIMMER_SPA_B_FWD_MINES: "Salt Mines",
    LDB_ARC_TT_SKIMMER_SPA_B_P2P: "Skim Speeder Champion",
    LDB_ARC_TT_SKIMMER_WHP_A_FWD: "Coliseum Blitz",
  };
  // Con el nombre oficial en inglés solo en la página en inglés; el nombre que pone el usuario manda siempre
  const officialEventName = eventId => PAGE_LANGUAGE === 'en' ? EVENT_NAMES_EN[eventId] || '' : '';
  // Nombres visibles de los planetas (sacados de game_records: el juego guarda el nombre de cada uno)
  const PLANET_NAMES = { DAL: 'Lantaana', MAS: 'Jakku', COR: 'Ando Prime', BGL: 'Tatooine', SPA: 'Crait', WHP: 'Derven Acos', HSK: 'Centinela 1' };
  // The game's vehicles: podracers (PLANE in the code) and three speeders: car, bike and skimmer
  const MIXED_CASE_CODE_WORDS = { Plane: 'Vaina' };
  const CODE_WORDS = { TT: 'Contrarreloj', BIKE: 'Moto', POD: 'Vaina', PODRACER: 'Vaina', LAND: 'Coche', LANDSPEEDER: 'Coche', SKIM: 'Rasante',
    SKIMSPEEDER: 'Rasante', SKIMMER: 'Rasante', CAR: 'Coche', PLANE: 'Vaina', P2P: 'punto a punto', TMR: 'Carrera por equipos', SHORT: 'corto', LONG: 'largo', REV: 'inverso', FWD: '', LOOP: 'circuito' };
  // A readable name built from the event code (LDB_ARC_<mode>_<vehicle>_<planet>_...)
  function describeEventCode(eventId, withoutPlanet, withoutVehicle) {
    if (eventId.startsWith('TRACK:')) return eventId.slice(6) + ' (evento sin identificar)';
    const words = eventId.replace(/^LDB_ARC_/, '').split('_');
    if (withoutVehicle) words.splice(1, 1);
    const described = words.map(word => PLANET_NAMES[word] ? (withoutPlanet ? '' : PLANET_NAMES[word]) : (CODE_WORDS[word] ?? MIXED_CASE_CODE_WORDS[word] ?? word)).filter(Boolean);
    const mode = described.shift() || '', vehicle = described.shift() || '';
    return [mode, vehicle, described.join(' ')].filter(Boolean).join(' · ');
  }

  // ---------- Records imported from the game (game_records.txt) ----------
  // Columns: total, attempts, name, planet, date, #1 time, category, planet code
  function gameRecordOf(data, eventId) {
    const line = (data.gameRecords || {})[eventId];
    if (!line) return null;
    const columns = line.split('\t');
    const total = parseFloat(columns[0]);
    return total > 0 ? { total, attempts: parseInt(columns[1]) || 0, name: columns[2] || '', planet: columns[3] || '', date: columns[4] || '',
      target: parseFloat(columns[5]) || null, category: parseInt(columns[6]) || null, planetCode: columns[7] || '' } : null;
  }
  function planetOf(gameRecord, eventId) {
    if (gameRecord && gameRecord.planet && !/^PLA_/.test(gameRecord.planet)) return gameRecord.planet;
    const code = eventId.replace(/^LDB_ARC_/, '').split('_')[2];
    return PLANET_NAMES[code] || '';
  }
  // The planet (shown in its own font) and the event name without the planet
  function eventTitles(data, eventId, gameRecord) {
    const planet = planetOf(gameRecord, eventId);
    const title = data.eventNames[eventId] || officialEventName(eventId) || (gameRecord && gameRecord.name) || describeEventCode(eventId, !!planet);
    // For cards and lists that already show the vehicle on its own
    const shortTitle = data.eventNames[eventId] || officialEventName(eventId) || (gameRecord && gameRecord.name) || describeEventCode(eventId, !!planet, true);
    return { planet, title, shortTitle };
  }
  // Aurebesh: only the lowercase letters a-z (that font's capitals and digits are other symbols)
  const toAurebesh = text => String(text || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z ]/g, '').replace(/\s+/g, ' ').trim();
  const aurebeshHtml = text => '<span class="aurebesh" aria-hidden="true">' + escapeHtml(toAurebesh(text)) + '</span>';
  const planetHtml = planet => planet ? '<div class="planet">' + escapeHtml(planet) + '</div>' + aurebeshHtml(planet) : '';
  // The Aurebesh font is optional: it is only shown if it is installed or in the fonts folder
  const fontsReady = (async () => {
    if (!document.fonts || !window.FontFace) return;
    const faces = Array.from(document.fonts).filter(face => /^SWGR (Aurebesh|Planet)/.test(face.family.replace(/["']/g, '')));
    await Promise.allSettled(faces.map(face => face.load()));
    if (faces.some(face => face.family.includes('Aurebesh') && face.status === 'loaded')) document.documentElement.classList.add('has-aurebesh');
    try { await document.fonts.ready; } catch (error) {}
  })();
  // Section titles carry their Aurebesh transcription
  new MutationObserver(() => {
    document.querySelectorAll('h2:not([data-aurebesh])').forEach(heading => { heading.dataset.aurebesh = '1'; heading.insertAdjacentHTML('beforeend', aurebeshHtml(heading.textContent)); });
  }).observe(document.body, { childList: true, subtree: true });
  function gameEventName(gameRecord, eventId) {
    if (!gameRecord || !gameRecord.name) return '';
    const planet = planetOf(gameRecord, eventId);
    return planet ? planet + ' · ' + gameRecord.name : gameRecord.name;
  }

