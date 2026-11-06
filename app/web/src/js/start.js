  // Start: a loading screen with a saber that lights up as it progresses; the app shows up complete
  // when the data, the fonts and the telemetry are there, and then the entrance animation plays.
  (async () => {
    const startTime = performance.now();
    const loadingStep = (percent, text) => { byId('loaderBlade').style.width = percent + '%'; byId('loaderStep').textContent = text; };
    loadingStep(12, 'Leyendo tus carreras…');
    try { await refreshData(true); }
    catch (error) {
      byId('main').innerHTML = '<div class="panel"><div class="empty-state"><b>No se pudieron leer los datos</b><span>' + escapeHtml(error.message) + '</span></div></div>';
    }
    loadingStep(55, 'Cargando fuentes…');
    await Promise.race([fontsReady, sleep(2500)]).catch(() => {});
    if (state.data) showLanguage(currentLanguage());   // Aurebesh depends on the font: it is applied once the font is loaded
    if (state.analysisLoading) { loadingStep(80, 'Preparando la telemetría…'); await Promise.race([state.analysisLoading, sleep(6000)]).catch(() => {}); }
    loadingStep(100, 'Listo');
    // Let the saber be seen lighting up even if everything loads very quickly
    const animated = !document.documentElement.classList.contains('no-animations');
    await sleep(animated ? Math.max(0, 750 - (performance.now() - startTime)) + 250 : 0);
    document.documentElement.classList.add('booted');
    byId('loader').classList.add('finished');
    playPowerOnSweep();
    playEntrance();
    setTimeout(() => { const loader = byId('loader'); if (loader) loader.remove(); }, 700);
  })();
  setInterval(pollForChanges, 3000);
})();
