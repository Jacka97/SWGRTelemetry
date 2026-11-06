(function () {
  const byId = id => document.getElementById(id);
  const escapeHtml = text => String(text ?? '').replace(/[&<>"]/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[character]));
  const cssVariable = name => getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  const formatTime = seconds => {
    if (seconds == null || !isFinite(seconds) || seconds <= 0) return '—';
    const minutes = Math.floor(seconds / 60), rest = seconds - minutes * 60;
    return minutes > 0 ? minutes + ':' + rest.toFixed(3).padStart(6, '0') : rest.toFixed(3);
  };
  const formatSigned = value => (value >= 0 ? '+' : '−') + Math.abs(value).toFixed(3);
  // "1:21.500" or "19.800" -> seconds; null if empty, NaN if it is not a time
  const parseTime = text => {
    text = String(text || '').trim().replace(',', '.');
    if (!text) return null;
    const match = text.match(/^(?:(\d+):)?(\d+(?:\.\d+)?)$/);
    if (!match) return NaN;
    return (match[1] ? +match[1] * 60 : 0) + +match[2];
  };
  const fetchFromApp = async (path, options) => {
    const response = await fetch(path, options);
    if (!response.ok) throw new Error(await response.text());
    return response;
  };
  const postJson = (path, value) => fetchFromApp(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(value) });

