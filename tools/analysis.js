// Lap analysis from the SWGR Telemetry mod's session CSV and its route.csv.
// It does not depend on the mod's version: checkpoint crossings are recalculated from the distance
// travelled, and the finish line is the checkpoint crossed when the OFFICIAL event shows up (the lap
// time published by the game).
// Distances are in centimetres along the route and times in seconds.

// route.csv: type,distance,x,y,z with "point" rows (the spline) and "checkpoint" rows.
// Files from 0.9.17 and earlier used P and C for the type.
function parseRouteCsv(text) {
  const points = [], checkpointDistances = [], checkpoints = [];
  for (const line of text.split(/\r?\n/).slice(1)) {
    const columns = line.split(',');
    if (columns.length < 5) continue;
    const type = columns[0], record = [+columns[1], +columns[2], +columns[3], +columns[4]];
    if (type === 'point' || type === 'P') points.push(record);
    else if (type === 'checkpoint' || type === 'C') {
      checkpointDistances.push(+columns[1]);
      checkpoints.push({ distance: +columns[1], x: +columns[2], y: +columns[3] });
    }
  }
  return { points, checkpointDistances, checkpoints };
}

// The session CSV: one sample per row. The columns are looked up by name, with the English names
// of 0.9.18 or the Spanish ones of the earlier versions.
function parseSessionCsv(text) {
  const lines = text.split(/\r?\n/);
  const header = lines[0].split(',');
  const columnOf = (...names) => names.map(name => header.indexOf(name)).find(index => index >= 0) ?? -1;
  const timeColumn = columnOf('time', 't'), distanceColumn = columnOf('distance', 'dist'), xColumn = columnOf('x'), yColumn = columnOf('y');
  const zColumn = columnOf('z'), headingColumn = columnOf('heading', 'rumbo');
  const speedColumn = columnOf('kmh'), eventColumn = columnOf('event', 'evento'), boostColumn = columnOf('boost');   // boost: from mod 0.9.25 on
  const samples = [];
  for (let index = 1; index < lines.length; index++) {
    const columns = lines[index].split(',');
    if (columns.length < 15) continue;
    const events = columns[eventColumn] || '';
    samples.push({ time: +columns[timeColumn], distance: +columns[distanceColumn], x: +columns[xColumn], y: +columns[yColumn], speed: +columns[speedColumn],
      official: events.includes('OFFICIAL') || events.includes('OFICIAL'), reset: events.includes('RESET') || events.includes('RETROCESO'),
      boost: boostColumn >= 0 ? (columns[boostColumn] || '') : '',
      z: zColumn >= 0 ? +columns[zColumn] : NaN, heading: headingColumn >= 0 ? +columns[headingColumn] : NaN });
  }
  return samples;
}

// Samples packed as "time,distance,x,y,speed,flags;..." (flags: 1 = official lap time, 2 = reset)
function unpackSamples(packed) {
  return packed.split(';').map(sample => {
    const columns = sample.split(',');
    const flags = +columns[5];
    return { time: +columns[0], distance: +columns[1], x: +columns[2], y: +columns[3], speed: +columns[4], official: (flags & 1) > 0, reset: (flags & 2) > 0 };
  });
}

function routeLength(route) { return route.points[route.points.length - 1][0]; }

// Driving direction relative to the spline: compares the recorded distance with the distance of the
// closest route point.
function detectDirection(route, samples) {
  const length = routeLength(route);
  let forward = 0, backward = 0;
  const moving = samples.filter(sample => sample.speed > 50);
  const step = Math.max(1, Math.floor(moving.length / 40));
  for (let index = 0; index < moving.length; index += step) {
    const sample = moving[index];
    let closestSquared = Infinity, closestDistance = 0;
    for (const point of route.points) {
      const squared = (point[1] - sample.x) ** 2 + (point[2] - sample.y) ** 2;
      if (squared < closestSquared) { closestSquared = squared; closestDistance = point[0]; }
    }
    const forwardGap = Math.abs(sample.distance - closestDistance), backwardGap = Math.abs(sample.distance - (length - closestDistance));
    if (Math.min(forwardGap, length - forwardGap) < Math.min(backwardGap, length - backwardGap)) forward++; else backward++;
  }
  return forward >= backward ? 1 : -1;
}

function analyzeSession(route, samples, name) {
  const length = routeLength(route);
  const direction = detectDirection(route, samples);
  // Checkpoint gates: position, distance in the driving direction and direction of the route
  const points = route.points;
  const gates = (route.checkpoints || route.checkpointDistances.map(distance => ({ distance, x: null, y: null }))).map(checkpoint => {
    let segment = 0;
    while (segment < points.length - 2 && points[segment + 1][0] < checkpoint.distance) segment++;
    const behind = points[Math.max(0, segment - 2)], ahead = points[Math.min(points.length - 1, segment + 3)];
    let tangentX = ahead[1] - behind[1], tangentY = ahead[2] - behind[2];
    const tangentLength = Math.hypot(tangentX, tangentY) || 1;
    tangentX = tangentX / tangentLength * direction; tangentY = tangentY / tangentLength * direction;
    const fraction = (checkpoint.distance - points[segment][0]) / ((points[segment + 1][0] - points[segment][0]) || 1);
    const x = checkpoint.x ?? points[segment][1] + fraction * (points[segment + 1][1] - points[segment][1]);
    const y = checkpoint.y ?? points[segment][2] + fraction * (points[segment + 1][2] - points[segment][2]);
    return { distance: direction === 1 ? checkpoint.distance : length - checkpoint.distance, x, y, tangentX, tangentY };
  }).sort((first, second) => first.distance - second.distance);
  const checkpointDistances = gates.map(gate => gate.distance);
  const GATE_RADIUS = 15000;
  // Checkpoint crossings, combining two methods:
  //  1. Progress along the route: its time matches the game's official time.
  //  2. Passing through the checkpoint's gate: finds the crossings the first method misses when you
  //     drive very far from the centre (alternative lines, weaving from edge to edge).
  const byRoute = [], byGate = [];
  const resetTimes = [];
  const lastByRoute = {}, lastByGate = {};
  for (let index = 1; index < samples.length; index++) {
    const previous = samples[index - 1], sample = samples[index];
    if (sample.reset) resetTimes.push(sample.time);
    if (!(sample.time > previous.time)) continue;
    const previousDistance = previous.distance, distance = sample.distance;
    const wrapsAround = previousDistance > 0.9 * length && distance < 0.1 * length;
    const step = wrapsAround ? distance + length - previousDistance : distance - previousDistance;
    if (step > 0 && step < 0.05 * length) {
      checkpointDistances.forEach((checkpointDistance, checkpoint) => {
        let fraction = null;
        if (wrapsAround) {
          if (checkpointDistance > previousDistance) fraction = (checkpointDistance - previousDistance) / step;
          else if (checkpointDistance <= distance) fraction = (checkpointDistance + length - previousDistance) / step;
        } else if (previousDistance < checkpointDistance && checkpointDistance <= distance) fraction = (checkpointDistance - previousDistance) / step;
        if (fraction === null) return;
        const crossingTime = previous.time + fraction * (sample.time - previous.time);
        if (lastByRoute[checkpoint] === undefined || crossingTime - lastByRoute[checkpoint] > 2) { lastByRoute[checkpoint] = crossingTime; byRoute.push({ time: crossingTime, checkpoint }); }
      });
    }
    if (Math.hypot(sample.x - previous.x, sample.y - previous.y) > 20000) continue;
    gates.forEach((gate, checkpoint) => {
      const sideBefore = (previous.x - gate.x) * gate.tangentX + (previous.y - gate.y) * gate.tangentY;
      const sideAfter = (sample.x - gate.x) * gate.tangentX + (sample.y - gate.y) * gate.tangentY;
      if (!(sideBefore < 0 && sideAfter >= 0)) return;
      const fraction = sideBefore / (sideBefore - sideAfter);
      if (Math.hypot(previous.x + fraction * (sample.x - previous.x) - gate.x, previous.y + fraction * (sample.y - previous.y) - gate.y) > GATE_RADIUS) return;
      let gapAlongRoute = Math.abs(sample.distance - gate.distance); gapAlongRoute = Math.min(gapAlongRoute, length - gapAlongRoute);
      if (gapAlongRoute > 0.25 * length) return;
      const crossingTime = previous.time + fraction * (sample.time - previous.time);
      if (lastByGate[checkpoint] === undefined || crossingTime - lastByGate[checkpoint] > 2) { lastByGate[checkpoint] = crossingTime; byGate.push({ time: crossingTime, checkpoint }); }
    });
  }
  const crossings = byRoute.slice();
  for (const crossing of byGate) {
    if (!byRoute.some(other => other.checkpoint === crossing.checkpoint && Math.abs(other.time - crossing.time) < 1.5)) crossings.push(crossing);
  }
  crossings.sort((first, second) => first.time - second.time);
  // Finish line: the checkpoint crossed next to the OFFICIAL event
  const officialTimes = samples.filter(sample => sample.official).map(sample => sample.time);
  const votes = {};
  for (const officialTime of officialTimes) {
    let closest = null, closestGap = 1.0;
    for (const crossing of crossings) { const gap = Math.abs(crossing.time - officialTime); if (gap <= closestGap) { closestGap = gap; closest = crossing; } }
    if (closest) votes[closest.checkpoint] = (votes[closest.checkpoint] || 0) + 1;
  }
  let finishCheckpoint = null, mostVotes = 0;
  for (const checkpoint in votes) if (votes[checkpoint] > mostVotes) { mostVotes = votes[checkpoint]; finishCheckpoint = +checkpoint; }
  let finishDistance, finishTimes;
  if (finishCheckpoint !== null) {
    finishDistance = checkpointDistances[finishCheckpoint];
    finishTimes = crossings.filter(crossing => crossing.checkpoint === finishCheckpoint).map(crossing => crossing.time);
  } else {
    // Without official data: the start of the route works as the finish line
    finishDistance = 0; finishTimes = [];
    for (let index = 1; index < samples.length; index++) {
      const previousDistance = samples[index - 1].distance, distance = samples[index].distance;
      if (previousDistance > 0.9 * length && distance < 0.1 * length) {
        finishTimes.push(samples[index - 1].time + (length - previousDistance) / (distance + length - previousDistance) * (samples[index].time - samples[index - 1].time));
      }
    }
  }
  // Open stage (point to point): the start is the first checkpoint in the driving direction and each
  // lap goes from its crossing to the finish; on a circuit, from finish to finish.
  const firstPoint = points[0], lastPoint = points[points.length - 1];
  const isPointToPoint = Math.hypot(lastPoint[1] - firstPoint[1], lastPoint[2] - firstPoint[2]) > 2000 && finishCheckpoint !== null;
  let startCheckpoint = null;
  if (isPointToPoint) startCheckpoint = checkpointDistances.map((_, checkpoint) => checkpoint).find(checkpoint => checkpoint !== finishCheckpoint && checkpointDistances[checkpoint] < finishDistance) ?? null;
  const originDistance = startCheckpoint !== null ? checkpointDistances[startCheckpoint] : finishDistance;
  const sectorCheckpoints = checkpointDistances.map((_, checkpoint) => checkpoint).filter(checkpoint => checkpoint !== finishCheckpoint && checkpoint !== startCheckpoint);
  const sectorCount = sectorCheckpoints.length + 1;
  const sectorStarts = sectorCheckpoints.map(checkpoint => (checkpointDistances[checkpoint] - originDistance + length) % length).sort((first, second) => first - second);
  const spans = [];
  if (startCheckpoint !== null) {
    const startTimes = crossings.filter(crossing => crossing.checkpoint === startCheckpoint).map(crossing => crossing.time);
    for (const end of finishTimes) {
      const start = startTimes.filter(time => time < end).pop();
      if (start !== undefined) spans.push([start, end]);
    }
  } else for (let index = 1; index < finishTimes.length; index++) spans.push([finishTimes[index - 1], finishTimes[index]]);
  const laps = [];
  for (const [start, end] of spans) {
    const time = end - start;
    if (time < 5 || time > 900) continue;
    const firstCrossing = {};
    let repeatedCrossings = 0;
    for (const crossing of crossings) {
      if (crossing.checkpoint === finishCheckpoint || crossing.checkpoint === startCheckpoint || crossing.time <= start + 0.25 || crossing.time >= end - 0.25) continue;
      if (firstCrossing[crossing.checkpoint] !== undefined) repeatedCrossings++; else firstCrossing[crossing.checkpoint] = crossing.time;
    }
    const sectorEnds = Object.values(firstCrossing).sort((first, second) => first - second);
    const allSectors = sectorEnds.length === sectorCount - 1;
    const sectors = [];
    let sectorStart = start;
    for (const sectorEnd of sectorEnds) { sectors.push(sectorEnd - sectorStart); sectorStart = sectorEnd; }
    sectors.push(end - sectorStart);
    const official = officialTimes.some(officialTime => Math.abs(officialTime - end) < 1.0);
    const incident = repeatedCrossings > 0 || resetTimes.some(resetTime => resetTime > start && resetTime <= end);
    // Trace: distance from the finish line and lap time
    const trace = [];
    for (const sample of samples) {
      if (sample.time < start - 0.05 || sample.time > end + 0.05) continue;
      let lapDistance;
      if (isPointToPoint) lapDistance = sample.distance - originDistance;
      else {
        lapDistance = (sample.distance - finishDistance + length) % length;
        if (sample.time - start < 2 && lapDistance > 0.8 * length) lapDistance -= length;
        if (end - sample.time < 2 && lapDistance < 0.2 * length) lapDistance += length;
      }
      trace.push({ distance: lapDistance, time: sample.time - start, x: sample.x, y: sample.y, speed: sample.speed, boost: sample.boost || '', z: sample.z, heading: sample.heading });
    }
    laps.push({ session: name, number: laps.length + 1, start, end, time, sectors: allSectors ? sectors : null,
      measuredSectors: sectors, official, incident, trace });
  }
  return { name, direction, routeLength: length, finishDistance, finishCheckpoint, startCheckpoint, isPointToPoint, originDistance,
    span: isPointToPoint ? finishDistance - originDistance : length, sectorCount, sectorStarts, laps };
}

// Lap time as a function of distance (monotonic: after a reset the first instant each distance is
// reached is the one kept).
function timeAtDistance(lap) {
  if (lap.timeByDistance) return lap.timeByDistance;
  const distances = [], times = [];
  let furthest = -Infinity;
  for (const point of lap.trace) {
    if (point.distance > furthest) { furthest = point.distance; distances.push(point.distance); times.push(point.time); }
  }
  lap.timeByDistance = { distances, times };
  return lap.timeByDistance;
}
// Linear interpolation of y at x, with xValues sorted from low to high
function interpolate(xValues, yValues, x) {
  if (x <= xValues[0]) return yValues[0];
  if (x >= xValues[xValues.length - 1]) return yValues[yValues.length - 1];
  let low = 0, high = xValues.length - 1;
  while (high - low > 1) { const middle = (low + high) >> 1; if (xValues[middle] <= x) low = middle; else high = middle; }
  const fraction = (x - xValues[low]) / (xValues[high] - xValues[low] || 1);
  return yValues[low] + fraction * (yValues[high] - yValues[low]);
}
// Time difference between two laps (A − B) at pointCount + 1 evenly spaced distances
function deltaSeries(lapA, lapB, length, pointCount) {
  const timesA = timeAtDistance(lapA), timesB = timeAtDistance(lapB);
  const series = [];
  for (let index = 0; index <= pointCount; index++) {
    const distance = length * index / pointCount;
    series.push({ distance, difference: interpolate(timesA.distances, timesA.times, distance) - interpolate(timesB.distances, timesB.times, distance) });
  }
  return series;
}

if (typeof module !== 'undefined') module.exports = { parseRouteCsv, parseSessionCsv, unpackSamples, analyzeSession, deltaSeries, timeAtDistance, interpolate };
