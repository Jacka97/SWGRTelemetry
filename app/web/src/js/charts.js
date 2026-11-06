  // Speed colours of each theme, from the slowest to the fastest
  const SPEED_PALETTES = { sith: ['#4a2f86', '#8a1f66', '#c4152a', '#ff3b2f', '#ff9a3d', '#ffe6a6'],
    galactic: ['#1f5f6b', '#2f8f95', '#8fd6d2', '#f2c14e', '#ef6b3c', '#fff0d0'],
    jedi: ['#1b2a6b', '#2340b8', '#3d8bff', '#7fd0ff', '#f0d38a', '#ffffff'],
    imperial: ['#3a3f47', '#6b737e', '#a9b2bd', '#e6ebf0', '#ff8a3d', '#ff3b2f'] };
  let speedPalette = SPEED_PALETTES.sith;
  // The colour of a speed, given as a fraction (0 = slowest, 1 = fastest) of the lap's range
  function speedColor(fraction) {
    speedPalette = SPEED_PALETTES[document.documentElement.dataset.theme] || SPEED_PALETTES.sith;
    fraction = Math.max(0, Math.min(1, fraction));
    const stops = speedPalette.length - 1, index = Math.min(stops - 1, Math.floor(fraction * stops)), within = fraction * stops - index;
    const from = parseInt(speedPalette[index].slice(1), 16), to = parseInt(speedPalette[index + 1].slice(1), 16);
    const channel = shift => Math.round(((from >> shift) & 255) * (1 - within) + ((to >> shift) & 255) * within);
    return 'rgb(' + channel(16) + ',' + channel(8) + ',' + channel(0) + ')';
  }
  function mixColors(firstColor, secondColor, fraction) {
    const channels = color => { const value = parseInt(color.replace('#', ''), 16); return [(value >> 16) & 255, (value >> 8) & 255, value & 255]; };
    const first = channels(firstColor), second = channels(secondColor);
    return 'rgb(' + first.map((value, index) => Math.round(value * (1 - fraction) + second[index] * fraction)).join(',') + ')';
  }
  state.mapMode = 'speed';
  // Colores de la estela blanca y del freno (el freno usa el rojo de pérdida del tema)
  const TRAIL_COLORS = { white: '#ffffff', both: '#ffb3b3' };
  const TRAIL_LEGEND = '<span><i class="legend-line" style="background:#ffffff"></i> estela blanca</span><span><i class="legend-line" style="background:var(--loss)"></i> freno</span>';

  function drawMap() {
    const analysis = state.analysis, canvas = byId('map');
    if (!canvas) return;
    const { context, width, height } = fitCanvas(canvas);
    context.clearRect(0, 0, width, height);
    if (!analysis) return;
    const bounds = analysis.bounds, padding = 46, replay = state.replay;
    const cars = replay && replay.time != null ? replayCars() : null;
    let view = bounds;
    if (cars && cars.segment.kind === 'sector' && cars.segment.zoomBox) view = cars.segment.zoomBox;
    const scaleToFit = box => Math.min((width - 2 * padding) / ((box.maxX - box.minX) || 1), (height - 2 * padding) / ((box.maxY - box.minY) || 1));
    let scale = scaleToFit(view), centerX = (view.minX + view.maxX) / 2, centerY = (view.minY + view.maxY) / 2;
    if (cars && replay.followCar) { scale = Math.max(scale, scaleToFit(bounds) * 4); centerX = cars.carA.x; centerY = cars.carA.y; }
    const toScreen = (x, y) => [width / 2 + (x - centerX) * scale, height / 2 + (y - centerY) * scale];
    context.lineCap = 'round'; context.lineJoin = 'round';
    context.strokeStyle = cssVariable('--map-track'); context.lineWidth = 14;
    context.beginPath(); analysis.route.points.forEach((point, index) => { const [x, y] = toScreen(point[1], point[2]); index ? context.lineTo(x, y) : context.moveTo(x, y); }); context.stroke();
    // Whole race: the lap each car is on is the one drawn
    let lapA = analysis.lapA, lapB = analysis.lapB;
    if (cars && cars.segment.kind === 'race') { lapA = cars.segment.lapsA[cars.lapIndexA]; if (cars.segment.lapsB && cars.lapIndexB != null) lapB = cars.segment.lapsB[cars.lapIndexB]; }
    const linesMode = state.mapMode === 'lines';
    // Estela (tryhard): dónde usas la estela blanca (el cuadrado) y dónde frenas
    const trailMode = state.mapMode === 'trail' && !isSimpleMode();
    // The sector being replayed, highlighted on the track
    if (cars && cars.segment.kind === 'sector') {
      context.save(); context.strokeStyle = cssVariable('--accent'); context.globalAlpha = 0.22; context.lineWidth = 26; context.beginPath();
      for (let step = 0; step <= 60; step++) {
        const lapDistance = cars.segment.startDistance + (cars.segment.endDistance - cars.segment.startDistance) * step / 60;
        const [x, y] = toScreen(...routePointAt(analysis, lapDistanceToRouteDistance(analysis, lapDistance)));
        step ? context.lineTo(x, y) : context.moveTo(x, y);
      }
      context.stroke(); context.restore();
    }
    if (lapB) {
      context.strokeStyle = lapB.isIdeal ? cssVariable('--best') : cssVariable('--reference'); context.lineWidth = linesMode ? 4 : 2; context.globalAlpha = linesMode ? 0.95 : 0.85;
      context.beginPath(); lapB.trace.forEach((point, index) => { const [x, y] = toScreen(point.x, point.y); index ? context.lineTo(x, y) : context.moveTo(x, y); }); context.stroke();
      context.globalAlpha = 1;
    }
    let scaleHtml = '';
    if (lapA) {
      let lowestSpeed = Infinity, highestSpeed = -Infinity;
      lapA.trace.forEach(point => { lowestSpeed = Math.min(lowestSpeed, point.speed); highestSpeed = Math.max(highestSpeed, point.speed); });
      lowestSpeed = Math.floor(lowestSpeed / 50) * 50; highestSpeed = Math.ceil(highestSpeed / 50) * 50;
      let gainRate = null;
      if (state.mapMode === 'gain' && lapB) {
        const series = deltaSeries(lapA, lapB, analysis.lapLength, 1200), distances = series.map(point => point.distance), differences = series.map(point => point.difference), halfWindow = 1500;
        // Seconds gained (negative) or lost per metre around a distance
        gainRate = distance => (interpolate(distances, differences, distance + halfWindow) - interpolate(distances, differences, distance - halfWindow)) / (2 * halfWindow / 100);
      }
      context.save(); context.strokeStyle = cssVariable('--accent'); context.globalAlpha = 0.18; context.lineWidth = 12; context.filter = 'blur(4px)';
      context.beginPath(); lapA.trace.forEach((point, index) => { const [x, y] = toScreen(point.x, point.y); index ? context.lineTo(x, y) : context.moveTo(x, y); }); context.stroke();
      context.restore();
      context.lineWidth = 4;
      if (linesMode) {
        context.strokeStyle = cssVariable('--accent'); context.globalAlpha = 0.95; context.beginPath();
        lapA.trace.forEach((point, index) => { const [x, y] = toScreen(point.x, point.y); index ? context.lineTo(x, y) : context.moveTo(x, y); });
        context.stroke(); context.globalAlpha = 1;
      } else for (let index = 1; index < lapA.trace.length; index++) {
        const from = lapA.trace[index - 1], to = lapA.trace[index];
        let color;
        if (trailMode) {
          const code = to.trail || '';
          color = code.includes('W') && code.includes('B') ? TRAIL_COLORS.both : code.includes('W') ? TRAIL_COLORS.white : code.includes('B') ? cssVariable('--loss') : mixColors(cssVariable('--map-track'), cssVariable('--map-text'), 0.35);
        } else if (gainRate) {
          const intensity = Math.max(-1, Math.min(1, gainRate(to.distance) / 0.004));
          color = intensity < 0 ? mixColors(cssVariable('--map-text'), cssVariable('--gain'), -intensity) : mixColors(cssVariable('--map-text'), cssVariable('--loss'), intensity);
        } else color = speedColor((to.speed - lowestSpeed) / (highestSpeed - lowestSpeed || 1));
        context.strokeStyle = color;
        const [x1, y1] = toScreen(from.x, from.y), [x2, y2] = toScreen(to.x, to.y);
        context.beginPath(); context.moveTo(x1, y1); context.lineTo(x2, y2); context.stroke();
      }
      scaleHtml = linesMode ? '<span><i class="legend-line" style="background:var(--accent)"></i> A</span><span><i class="legend-line" style="background:' + (lapB && lapB.isIdeal ? 'var(--best)' : 'var(--reference)') + '"></i> ' + escapeHtml(referenceName(lapB)) + '</span>'
        : trailMode ? TRAIL_LEGEND
        : gainRate ? '<span style="color:var(--gain)">ganas tiempo</span><span class="scale-bar" style="background:linear-gradient(90deg,' + cssVariable('--gain') + ',' + cssVariable('--map-text') + ',' + cssVariable('--loss') + ')"></span><span style="color:var(--loss)">pierdes tiempo</span>'
        : '<span>' + lowestSpeed + '</span><span class="scale-bar" style="background:linear-gradient(90deg,' + speedPalette.join(',') + ')"></span><span>' + highestSpeed + ' km/h</span>';
    }
    if (state.mapMode === 'gain' && !lapB) scaleHtml = '<span>Elige una vuelta de referencia para ver dónde ganas o pierdes.</span>';
    byId('mapScale').innerHTML = scaleHtml;
    const track = analysis.track;
    if (track) {
      const marks = [{ distance: 0, label: track.isPointToPoint ? 'SALIDA' : 'META', isLine: true }]
        .concat(track.sectorStarts.map((distance, index) => ({ distance, label: 'S' + (index + 1) + '→S' + (index + 2) })));
      if (track.isPointToPoint) marks.push({ distance: track.span, label: 'META', isLine: true });
      context.font = '600 11px ' + cssVariable('--font-display');
      marks.forEach(mark => {
        const routeDistance = lapDistanceToRouteDistance(analysis, mark.distance);
        const [startX, startY] = toScreen(...routePointAt(analysis, routeDistance)), [aheadX, aheadY] = toScreen(...routePointAt(analysis, routeDistance + 300));
        let normalX = -(aheadY - startY), normalY = aheadX - startX; const normalLength = Math.hypot(normalX, normalY) || 1; normalX /= normalLength; normalY /= normalLength;
        context.strokeStyle = mark.isLine ? '#fff1ef' : cssVariable('--map-text'); context.lineWidth = mark.isLine ? 3 : 1.5;
        context.beginPath(); context.moveTo(startX - normalX * 12, startY - normalY * 12); context.lineTo(startX + normalX * 12, startY + normalY * 12); context.stroke();
        context.fillStyle = mark.isLine ? '#fff1ef' : cssVariable('--map-text'); context.textAlign = 'center'; context.textBaseline = 'middle';
        context.fillText(mark.label, Math.min(width - 24, Math.max(24, startX + normalX * 24)), Math.min(height - 8, Math.max(8, startY + normalY * 24)));
      });
    }
    if (cars) {
      // The two cars, with their labels; in real time, joined by the distance between them
      const colorB = lapB && lapB.isIdeal ? cssVariable('--best') : cssVariable('--reference');
      const pointA = toScreen(cars.carA.x, cars.carA.y), pointB = cars.carB ? toScreen(cars.carB.x, cars.carB.y) : null;
      if (pointB && replay.sync !== 'samePoint') {
        context.save(); context.setLineDash([4, 4]); context.strokeStyle = cssVariable('--map-text'); context.globalAlpha = 0.7; context.lineWidth = 1.5;
        context.beginPath(); context.moveTo(pointA[0], pointA[1]); context.lineTo(pointB[0], pointB[1]); context.stroke(); context.restore();
        const metersApart = Math.abs(cars.carA.distance - cars.carB.distance) / 100;
        if (metersApart >= 1) {
          context.font = '600 11px ' + cssVariable('--font-data'); context.fillStyle = cssVariable('--map-text'); context.textAlign = 'center'; context.textBaseline = 'bottom';
          context.fillText(metersApart.toFixed(0) + ' m', (pointA[0] + pointB[0]) / 2, (pointA[1] + pointB[1]) / 2 - 4);
        }
      }
      const carLabel = (x, y, color, text, above) => {
        context.font = '700 11px ' + cssVariable('--font-display');
        const labelWidth = context.measureText(text).width + 12, labelTop = above ? y - 22 : y + 10;
        context.fillStyle = color; context.globalAlpha = 0.92; context.fillRect(x + 8, labelTop, labelWidth, 16); context.globalAlpha = 1;
        context.fillStyle = '#0b0b0d'; context.textAlign = 'left'; context.textBaseline = 'middle'; context.fillText(text, x + 14, labelTop + 8.5);
      };
      const carDot = (x, y, color) => {
        context.fillStyle = color; context.strokeStyle = cssVariable('--map-background'); context.lineWidth = 2.5;
        context.beginPath(); context.arc(x, y, 8, 0, Math.PI * 2); context.fill(); context.stroke();
      };
      const wholeRace = cars.segment.kind === 'race', lapOfB = wholeRace && cars.lapIndexB != null ? ' · V' + (cars.lapIndexB + 1) : '';
      // Next to each car, the boost it is using (only when it is using one: the map stays clean)
      const boost = replayBoost(cars), boostText = code => (code === 'A' || code === 'R' ? ' · ' + BOOST_NAMES[code] : '');
      if (pointB) { carDot(pointB[0], pointB[1], colorB); carLabel(pointB[0], pointB[1], colorB, cars.segment.nameB + lapOfB + boostText(boost.b), false); }
      carDot(pointA[0], pointA[1], cssVariable('--accent')); carLabel(pointA[0], pointA[1], cssVariable('--accent'), 'A' + (wholeRace ? ' · V' + (cars.lapIndexA + 1) : '') + boostText(boost.a), true);
    } else if (state.hoverDistance != null) {
      const chart = chartWindow();
      [[chart && chart.traceB, lapB && lapB.isIdeal ? cssVariable('--best') : cssVariable('--reference')], [chart && chart.traceA, cssVariable('--accent')]].forEach(([trace, color]) => {
        if (!trace) return;
        const point = lapPointAtDistance(trace, state.hoverDistance), [x, y] = toScreen(point.x, point.y);
        context.fillStyle = color; context.strokeStyle = cssVariable('--map-background'); context.lineWidth = 2;
        context.beginPath(); context.arc(x, y, 6, 0, Math.PI * 2); context.fill(); context.stroke();
      });
    }
  }

  const CHART_MARGIN = { left: 52, right: 14, top: 12, bottom: 24 };
  // Axes of the charts along the lap: horizontal grid with its values, sector lines and sector names
  // The stretch the charts show: the lap, the sector or the whole race, with A and B over it and the names along the axis
  function chartWindow() {
    const analysis = state.analysis, segment = replaySegment();
    if (!analysis || !segment || !analysis.track) return null;
    const marks = [];
    if (segment.kind === 'race') segment.lapsA.forEach((lap, index) => marks.push({ start: index * analysis.lapLength, end: (index + 1) * analysis.lapLength, label: 'V' + lap.number, strong: true }));
    else if (segment.kind === 'sector') marks.push({ start: segment.startDistance, end: segment.endDistance, label: 'S' + segment.sectorNumber });
    else { const bounds = sectorBounds(analysis); for (let index = 0; index < bounds.length - 1; index++) marks.push({ start: bounds[index], end: bounds[index + 1], label: 'S' + (index + 1) }); }
    return { kind: segment.kind, start: segment.startDistance, end: segment.endDistance, traceA: segment.traceA, traceB: segment.traceB, marks };
  }
  function drawChartFrame(context, width, height, lowestValue, highestValue, formatValue, gridStep, chart) {
    const xOf = distance => CHART_MARGIN.left + (distance - chart.start) / ((chart.end - chart.start) || 1) * (width - CHART_MARGIN.left - CHART_MARGIN.right);
    const yOf = value => CHART_MARGIN.top + (1 - (value - lowestValue) / (highestValue - lowestValue)) * (height - CHART_MARGIN.top - CHART_MARGIN.bottom);
    context.font = '11px ' + cssVariable('--font-data'); context.fillStyle = cssVariable('--text-muted'); context.strokeStyle = cssVariable('--line'); context.lineWidth = 1;
    context.textAlign = 'right'; context.textBaseline = 'middle';
    for (let value = Math.ceil(lowestValue / gridStep) * gridStep; value <= highestValue + 1e-9; value += gridStep) {
      const y = Math.round(yOf(value)) + 0.5;
      context.beginPath(); context.moveTo(CHART_MARGIN.left, y); context.lineTo(width - CHART_MARGIN.right, y); context.stroke();
      context.fillText(formatValue(value), CHART_MARGIN.left - 6, y);
    }
    // Lines between the sectors (or, in a race, solid between the laps) and their names under the axis
    chart.marks.forEach((mark, index) => {
      if (!index) return;
      const x = Math.round(xOf(mark.start)) + 0.5;
      context.setLineDash(mark.strong ? [] : [3, 3]); context.globalAlpha = mark.strong ? 0.9 : 1;
      context.beginPath(); context.moveTo(x, CHART_MARGIN.top); context.lineTo(x, height - CHART_MARGIN.bottom); context.stroke(); context.globalAlpha = 1;
    });
    context.setLineDash([]); context.textAlign = 'center'; context.textBaseline = 'top';
    chart.marks.forEach(mark => context.fillText(mark.label, (xOf(mark.start) + xOf(mark.end)) / 2, height - CHART_MARGIN.bottom + 6));
    return { xOf, yOf };
  }
  function drawHoverLine(context, xOf, height) {
    if (state.hoverDistance == null) return;
    const x = Math.round(xOf(state.hoverDistance)) + 0.5;
    context.strokeStyle = cssVariable('--text'); context.globalAlpha = 0.5;
    context.beginPath(); context.moveTo(x, CHART_MARGIN.top); context.lineTo(x, height - CHART_MARGIN.bottom); context.stroke(); context.globalAlpha = 1;
  }
  function drawDeltaChart() {
    const canvas = byId('deltaChart'); if (!canvas) return;
    const { context, width, height } = fitCanvas(canvas, 120);
    context.clearRect(0, 0, width, height);
    const analysis = state.analysis, chart = chartWindow();
    if (!analysis || !chart || !chart.traceB) {
      context.fillStyle = cssVariable('--text-muted'); context.font = '13px ' + cssVariable('--font-body');
      context.fillText(chart && chart.kind === 'race' ? 'Elige en B otra carrera entera para ver la diferencia.' : 'Elige B para ver la diferencia.', CHART_MARGIN.left, 30); return;
    }
    const timesA = timeAtDistance(chart.traceA), timesB = timeAtDistance(chart.traceB), series = [];
    for (let index = 0; index <= 600; index++) {
      const distance = chart.start + (chart.end - chart.start) * index / 600;
      series.push({ distance, difference: interpolate(timesA.distances, timesA.times, distance) - interpolate(timesB.distances, timesB.times, distance) });
    }
    let largest = 0.2; series.forEach(point => { largest = Math.max(largest, Math.abs(point.difference)); });
    const gridStep = niceStep(2 * largest, 4); largest = Math.ceil(largest / gridStep) * gridStep;
    const { xOf, yOf } = drawChartFrame(context, width, height, -largest, largest, value => (value > 0 ? '+' : value < 0 ? '−' : '') + Math.abs(value).toFixed(gridStep < 0.1 ? 2 : 1), gridStep, chart);
    [['--loss', 1], ['--gain', -1]].forEach(([colorVariable, sign]) => {
      const color = cssVariable(colorVariable), gradient = context.createLinearGradient(0, yOf(sign * largest), 0, yOf(0));
      gradient.addColorStop(0, color + '66'); gradient.addColorStop(1, color + '0d');
      context.fillStyle = gradient;
      context.beginPath(); context.moveTo(xOf(chart.start), yOf(0));
      series.forEach(point => context.lineTo(xOf(point.distance), yOf(sign > 0 ? Math.max(0, point.difference) : Math.min(0, point.difference))));
      context.lineTo(xOf(chart.end), yOf(0)); context.closePath(); context.fill();
    });
    context.strokeStyle = cssVariable('--line-strong'); context.lineWidth = 1;
    context.beginPath(); context.moveTo(xOf(chart.start), Math.round(yOf(0)) + 0.5); context.lineTo(xOf(chart.end), Math.round(yOf(0)) + 0.5); context.stroke();
    context.save(); context.shadowColor = 'rgba(255,255,255,.35)'; context.shadowBlur = 6;
    context.strokeStyle = cssVariable('--text'); context.lineWidth = 1.8;
    context.beginPath(); series.forEach((point, index) => { index ? context.lineTo(xOf(point.distance), yOf(point.difference)) : context.moveTo(xOf(point.distance), yOf(point.difference)); }); context.stroke();
    context.restore();
    // The final difference, at the end of the line
    const final = series[series.length - 1];
    if (final) {
      context.font = '600 12px ' + cssVariable('--font-data'); context.textAlign = 'right'; context.textBaseline = 'middle';
      context.fillStyle = final.difference > 0 ? cssVariable('--loss') : cssVariable('--gain');
      // Inside the chart: below the line if it is at the top, and the other way round
      const labelY = Math.max(CHART_MARGIN.top + 22, Math.min(height - CHART_MARGIN.bottom - 10, yOf(final.difference) + (yOf(final.difference) < CHART_MARGIN.top + 30 ? 14 : -14)));
      context.fillText(formatSigned(final.difference) + ' s', xOf(chart.end) - 6, labelY);
    }
    context.font = '11px ' + cssVariable('--font-display'); context.fillStyle = cssVariable('--text-muted'); context.textAlign = 'left'; context.textBaseline = 'top';
    context.fillText('DIFERENCIA A − B (s)', CHART_MARGIN.left + 4, CHART_MARGIN.top + 2);
    drawHoverLine(context, xOf, height);
  }
  function drawSpeedChart() {
    const canvas = byId('speedChart'); if (!canvas) return;
    const { context, width, height } = fitCanvas(canvas, 140);
    context.clearRect(0, 0, width, height);
    const analysis = state.analysis, chart = chartWindow();
    if (!analysis || !chart) return;
    const inside = point => point.distance >= chart.start && point.distance <= chart.end;
    const lines = [chart.traceB && { trace: chart.traceB, isA: false }, { trace: chart.traceA, isA: true }].filter(Boolean);
    let highestSpeed = 0, lowestSpeed = Infinity;
    lines.forEach(line => line.trace.trace.forEach(point => { if (inside(point)) { highestSpeed = Math.max(highestSpeed, point.speed); lowestSpeed = Math.min(lowestSpeed, point.speed); } }));
    if (!isFinite(lowestSpeed)) return;
    const gridStep = niceStep(Math.max(10, highestSpeed - lowestSpeed), 4);
    const { xOf, yOf } = drawChartFrame(context, width, height, Math.max(0, Math.floor(lowestSpeed / gridStep) * gridStep), Math.ceil(highestSpeed / gridStep) * gridStep, value => value.toFixed(0), gridStep, chart);
    lines.forEach(line => {
      context.save();
      if (line.isA) { context.shadowColor = cssVariable('--accent'); context.shadowBlur = 8; }
      context.strokeStyle = line.isA ? cssVariable('--accent') : (analysis.lapB && analysis.lapB.isIdeal ? cssVariable('--best') : cssVariable('--reference')); context.lineWidth = line.isA ? 2.2 : 1.5;
      context.beginPath(); let started = false;
      line.trace.trace.forEach(point => {
        if (!inside(point)) return;
        started ? context.lineTo(xOf(point.distance), yOf(point.speed)) : context.moveTo(xOf(point.distance), yOf(point.speed)); started = true;
      });
      context.stroke(); context.restore();
    });
    // Tryhard: bajo la gráfica, dónde usa cada uno la estela blanca (el cuadrado) y dónde frena; A abajo, B encima
    if (!isSimpleMode()) lines.forEach(line => {
      const rowY = height - CHART_MARGIN.bottom - (line.isA ? 5 : 10);
      const points = line.trace.trace;
      for (let index = 1; index < points.length; index++) {
        const from = points[index - 1], to = points[index], code = to.trail || '';
        if (!code || !inside(to)) continue;
        context.fillStyle = code.includes('W') ? (code.includes('B') ? TRAIL_COLORS.both : TRAIL_COLORS.white) : cssVariable('--loss');
        context.fillRect(xOf(from.distance), rowY, Math.max(1, xOf(to.distance) - xOf(from.distance)), 4);
      }
    });
    context.font = '11px ' + cssVariable('--font-display'); context.fillStyle = cssVariable('--text-muted'); context.textAlign = 'left'; context.textBaseline = 'top';
    context.fillText('VELOCIDAD (km/h)', CHART_MARGIN.left + 4, CHART_MARGIN.top + 2);
    context.textAlign = 'right'; context.fillText(analysis.track && analysis.track.isPointToPoint ? 'metros desde la salida →' : 'metros desde la meta →', width - CHART_MARGIN.right - 2, CHART_MARGIN.top + 2);
    drawHoverLine(context, xOf, height);
  }
  // The line under the chart titles: speeds and difference at the point under the mouse
  function showReadout() {
    const analysis = state.analysis, distance = state.hoverDistance, element = byId('readout'), chart = chartWindow();
    if (!element || !analysis || distance == null || !chart) return;
    const timeA = interpolate(timeAtDistance(chart.traceA).distances, timeAtDistance(chart.traceA).times, distance);
    // In a whole race, the lap and the metres into it
    const where = chart.kind === 'race' ? 'V' + (Math.min(chart.marks.length - 1, Math.floor(distance / analysis.lapLength)) + 1) + ' · ' + ((distance % analysis.lapLength) / 100).toFixed(0) + ' m' : (distance / 100).toFixed(0) + ' m';
    let html = '<b>' + where + '</b> · <span style="color:var(--accent)">A ' + lapPointAtDistance(chart.traceA, distance).speed.toFixed(0) + ' km/h</span>';
    if (chart.traceB) {
      const timeB = interpolate(timeAtDistance(chart.traceB).distances, timeAtDistance(chart.traceB).times, distance);
      html += ' · <span style="color:var(--reference)">B ' + lapPointAtDistance(chart.traceB, distance).speed.toFixed(0) + ' km/h</span> · dif. <b class="' + (timeA - timeB > 0 ? 'loss' : 'gain') + '">' + formatSigned(timeA - timeB) + ' s</b>';
    }
    element.innerHTML = html;
  }
  function drawAll() { drawMap(); drawDeltaChart(); drawSpeedChart(); showReadout(); }
  // To redraw from outside (for instance after changing styles); the app does not need it on its own
  window.SWGR = { redraw: () => { render(); if (state.analysis) drawAll(); } };
  function hoverChart(pointerEvent) {
    if (!state.analysis) return;
    if (state.replay.time != null) { if (state.replay.playing) return; stopReplay(true); }
    const box = pointerEvent.currentTarget.getBoundingClientRect(), chart = chartWindow();
    if (!chart) return;
    const distance = chart.start + (pointerEvent.clientX - box.left - CHART_MARGIN.left) / (box.width - CHART_MARGIN.left - CHART_MARGIN.right) * (chart.end - chart.start);
    state.hoverDistance = distance >= chart.start && distance <= chart.end ? distance : null;
    drawAll();
  }
  const isLapChart = element => element.id === 'deltaChart' || element.id === 'speedChart';
  document.addEventListener('pointermove', pointerEvent => { if (isLapChart(pointerEvent.target)) hoverChart({ currentTarget: pointerEvent.target, clientX: pointerEvent.clientX }); });
  document.addEventListener('pointerout', pointerEvent => { if (isLapChart(pointerEvent.target) && state.hoverDistance != null) { state.hoverDistance = null; drawAll(); } });
  const MAP_MODE_BUTTONS = { mapSpeedMode: 'speed', mapGainMode: 'gain', mapLinesMode: 'lines', mapTrailMode: 'trail' };
  document.addEventListener('click', clickEvent => {
    const mode = MAP_MODE_BUTTONS[clickEvent.target.id];
    if (!mode) return;
    state.mapMode = mode;
    Object.entries(MAP_MODE_BUTTONS).forEach(([buttonId, buttonMode]) => byId(buttonId).setAttribute('aria-pressed', state.mapMode === buttonMode));
    drawMap();
  });
  let resizeFrame = 0;
  window.addEventListener('resize', () => {
    cancelAnimationFrame(resizeFrame);
    resizeFrame = requestAnimationFrame(() => {
      if (state.view.name !== 'event') return;
      const event = state.events.find(item => item.id === state.view.id);
      if (event && state.eventTab === 'progress') drawProgress(event);
      drawAll();
    });
  });

