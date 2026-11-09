// Static checks for the app's page, so a renamed name never stays half renamed:
//  1. names used but never declared (and not a browser global or an analyzer function)
//  2. names declared and never used
//  3. object fields read but never written anywhere (in the page, the analyzer or the server's JSON)
//  4. element ids looked up (byId('...')) that no markup creates
//  5. classes used in markup or scripts without any style, and styles of classes nobody uses
//  6. data-* attributes read (dataset.name, [data-name]) that no markup writes, and the other way round
// Usage: node check_web.js template.html analysis.js server.go [more .go files]
const fs = require('fs');
const parser = require('@babel/parser');
const traverse = require('@babel/traverse').default;

const [templatePath, analyzerPath, ...goPaths] = process.argv.slice(2);
const template = fs.readFileSync(templatePath, 'utf8');
const analyzer = fs.readFileSync(analyzerPath, 'utf8');
const pageScript = [...template.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(match => match[1]).find(code => !code.includes('__ANALYSIS__'));
const styles = template.slice(template.indexOf('<style>'), template.indexOf('</style>'));
const markup = template.slice(template.indexOf('</style>'), template.indexOf('<script>'));
let problems = 0;
const report = message => { problems++; console.log(message); };

const BROWSER_GLOBALS = new Set(['document', 'window', 'getComputedStyle', 'fetch', 'Error', 'Math', 'JSON', 'String', 'Number', 'Array', 'Object', 'Set', 'Map',
  'Promise', 'Symbol', 'isFinite', 'parseInt', 'parseFloat', 'setTimeout', 'clearTimeout', 'setInterval', 'requestAnimationFrame', 'cancelAnimationFrame',
  'performance', 'localStorage', 'location', 'MutationObserver', 'CSS', 'Date', 'Infinity', 'NaN', 'undefined', 'console', 'Boolean', 'RegExp']);
const analyzerAst = parser.parse(analyzer, { sourceType: 'script' });
const analyzerFunctions = new Set(analyzerAst.program.body.filter(node => node.type === 'FunctionDeclaration').map(node => node.id.name));

// ---- 1 and 2: names
const pageAst = parser.parse(pageScript, { sourceType: 'script', errorRecovery: false });
traverse(pageAst, {
  Identifier(path) {
    if (!path.isReferencedIdentifier()) return;
    const name = path.node.name;
    if (path.scope.hasBinding(name) || BROWSER_GLOBALS.has(name) || analyzerFunctions.has(name)) return;
    report('page: "' + name + '" is used but never declared (line ' + path.node.loc.start.line + ')');
  },
  Scope(path) {
    for (const [name, binding] of Object.entries(path.scope.bindings)) {
      if (!binding.referenced && binding.kind !== 'param') {
        if (binding.path.isCatchClause() || (binding.path.parentPath && binding.path.parentPath.isArrayPattern())) continue;
        report('page: "' + name + '" is declared but never used (line ' + binding.identifier.loc.start.line + ')');
      }
    }
  },
});
traverse(analyzerAst, {
  Identifier(path) {
    if (!path.isReferencedIdentifier()) return;
    const name = path.node.name;
    if (path.scope.hasBinding(name) || BROWSER_GLOBALS.has(name) || name === 'module') return;
    report('analyzer: "' + name + '" is used but never declared (line ' + path.node.loc.start.line + ')');
  },
});

// ---- 3: fields
const written = new Set(), read = new Map();
const collectFields = (ast, label) => traverse(ast, {
  MemberExpression(path) {
    if (path.node.computed || path.node.property.type !== 'Identifier') return;
    const name = path.node.property.name;
    const parent = path.parentPath;
    const isWrite = (parent.isAssignmentExpression() && parent.node.left === path.node) || (parent.isUpdateExpression()) || parent.isUnaryExpression({ operator: 'delete' });
    if (isWrite) written.add(name);
    else if (!read.has(name)) read.set(name, label + ' line ' + path.node.loc.start.line);
  },
  ObjectProperty(path) { if (!path.node.computed && path.node.key.type === 'Identifier') written.add(path.node.key.name); if (path.node.key.type === 'StringLiteral') written.add(path.node.key.value); },
  ObjectMethod(path) { if (path.node.key.type === 'Identifier') written.add(path.node.key.name); },
  ObjectPattern(path) { path.node.properties.forEach(property => { if (property.key && property.key.type === 'Identifier' && !read.has(property.key.name)) read.set(property.key.name, label + ' destructured line ' + property.loc.start.line); }); },
});
collectFields(pageAst, 'page'); collectFields(analyzerAst, 'analyzer');
// The server's JSON: struct tags and the keys of the maps it writes
for (const goPath of goPaths) {
  const go = fs.readFileSync(goPath, 'utf8');
  for (const match of go.matchAll(/json:"([^",]+)/g)) written.add(match[1]);
  for (const match of go.matchAll(/"([a-zA-Z]+)":\s/g)) written.add(match[1]);
}
// dataset fields come from the data-* attributes of the markup
for (const match of template.matchAll(/\bdata-([a-z][a-z-]*)=/g)) written.add(match[1].replace(/-([a-z])/g, (_, letter) => letter.toUpperCase()));
// Pilot files of version 1 are read with their Spanish keys (readPilotFile translates them)
'formato piloto fecha eventos vuelta nombre planeta vehiculo vueltas mejorVuelta sectores salidaS1 ideal n t sec L abierto tr'.split(' ').forEach(name => written.add(name));
const builtins = new Set();
for (const value of [Array.prototype, String.prototype, Number.prototype, Object.prototype, Promise.prototype, Math, JSON, Object, Array, Number, Promise, Function.prototype, RegExp.prototype, Set.prototype, Map.prototype, Symbol.prototype])
  for (const name of Object.getOwnPropertyNames(value)) builtins.add(name);
const DOM_FIELDS = 'id target classList dataset innerHTML textContent value checked disabled hidden style background width height options files types relatedTarget clientX deltaY button scrollWidth scrollBy setProperty removeProperty currentTarget dataTransfer key ' +
  'documentElement body fonts family status ready offsetWidth scrollY devicePixelRatio FontFace getElementById querySelector querySelectorAll closest addEventListener setAttribute insertAdjacentHTML ' +
  'getBoundingClientRect getContext offsetHeight offsetLeft offsetTop clientWidth clientY setPointerCapture pointerId removeEventListener scrollIntoView click focus blur contentEditable onclick onblur onkeydown selectAllChildren getSelection preventDefault stopPropagation reload text json ok ' +
  'beginPath moveTo lineTo stroke fill arc closePath fillText fillRect measureText clearRect save restore setTransform setLineDash createLinearGradient addColorStop strokeStyle fillStyle lineWidth ' +
  'lineCap lineJoin globalAlpha font textAlign textBaseline shadowColor shadowBlur filter left top escape load observe getPropertyValue isReferencedIdentifier now getItem setItem ' +
  'toggle add remove contains __swgrReload SWGR redraw module exports message scrollTo toISOString children parentElement';
DOM_FIELDS.split(/\s+/).forEach(name => builtins.add(name));
for (const [name, where] of read) if (!written.has(name) && !builtins.has(name)) report('field ".' + name + '" is read (' + where + ') but never written');

// ---- 4: ids
const allText = template;
const declaredIds = new Set([...allText.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]));
for (const match of pageScript.matchAll(/byId\('([^']+)'\)/g)) if (!declaredIds.has(match[1])) report('id "' + match[1] + '" is looked up but no markup has it');
for (const match of pageScript.matchAll(/'#([a-zA-Z][\w-]*)/g)) if (!declaredIds.has(match[1]) && !/^[0-9a-fA-F]{3,8}$/.test(match[1])) report('id "#' + match[1] + '" is used in a selector but no markup has it');
for (const match of styles.matchAll(/#([a-zA-Z][\w-]*)\s*[{,:\s.]/g)) if (!declaredIds.has(match[1]) && !/^[0-9a-fA-F]{3,8}$/.test(match[1])) report('style for id "#' + match[1] + '" but no markup has it');

// ---- 5: classes
const withoutComments = styles.replace(/\/\*[\s\S]*?\*\//g, '').replace(/url\([^)]*\)|"[^"]*"/g, '');
const styledClasses = new Set();
for (const rule of withoutComments.split('}')) {
  // Every part before a "{" is a selector (several of them inside an @media block); the last part holds declarations
  const parts = rule.split('{');
  for (const selector of parts.slice(0, -1)) for (const match of selector.matchAll(/\.([a-zA-Z][\w-]*)/g)) styledClasses.add(match[1]);
}
const usedClasses = new Set();
const addClasses = text => text.split(/\s+/).filter(name => /^[a-z][a-z0-9-]*$/.test(name)).forEach(name => usedClasses.add(name));
for (const match of (markup + pageScript).matchAll(/class="([^"]*)"/g)) addClasses(match[1].replace(/'\s*\+[^+]*\+\s*'/g, ' '));
for (const match of pageScript.matchAll(/classList\.(?:add|remove|toggle|contains)\('([^']+)'/g)) addClasses(match[1]);
for (const match of pageScript.matchAll(/(?:querySelector(?:All)?|closest)\('([^']+)'\)/g)) for (const name of match[1].matchAll(/\.([a-zA-Z][\w-]*)/g)) usedClasses.add(name[1]);
// classes added by concatenation: ' selected-a', ' open', ' first'... and class names held in data (colorClass)
for (const match of pageScript.matchAll(/'\s?([a-z][a-z-]*(?: [a-z][a-z-]*)*)'/g)) for (const name of match[1].split(' ')) if (styledClasses.has(name)) usedClasses.add(name);
const STATE_CLASSES = new Set(['booted', 'off', 'mine', 'no-aurebesh']);   // no-aurebesh is set by the Taller
// Words caught inside a concatenated class attribute (class="' + (value <= fastest ...) + '"), not classes
const NOT_CLASSES = new Set(['fastest']);
for (const name of usedClasses) if (!styledClasses.has(name) && !STATE_CLASSES.has(name) && !NOT_CLASSES.has(name)) report('class "' + name + '" is used but has no style');
for (const name of styledClasses) if (!usedClasses.has(name) && !STATE_CLASSES.has(name)) report('class "' + name + '" has a style but nobody uses it');

// ---- 6: data attributes
const toDataset = attribute => attribute.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
const writtenData = new Set([...(markup + pageScript).matchAll(/\bdata-([a-z][a-z-]*)=/g)].map(match => toDataset(match[1])));
for (const match of pageScript.matchAll(/dataset\.([a-zA-Z]+)\s*=/g)) writtenData.add(match[1]);
const readData = new Set([...pageScript.matchAll(/dataset\.([a-zA-Z]+)/g)].map(match => match[1]));
for (const match of (pageScript + styles).matchAll(/\[data-([a-z][a-z-]*)/g)) readData.add(toDataset(match[1]));
for (const name of readData) if (!writtenData.has(name)) report('data attribute "' + name + '" is read but never written');
for (const name of writtenData) if (!readData.has(name) && !['color'].includes(name)) report('data attribute "' + name + '" is written but never read');

console.log(problems ? problems + ' problem(s)' : 'no problems');
process.exit(problems ? 1 : 0);
