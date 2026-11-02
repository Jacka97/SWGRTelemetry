// Static checks for the mod's Lua files, so a renamed variable or field never stays half renamed:
//  1. globals: every name that is not declared local must be a known Lua or UE4SS global
//  2. fields: every field that is read (object.field) must also be written somewhere
//     (assigned or set in a table constructor), unless it belongs to the game or to UE4SS
//  3. unused locals: declared and never used (often the leftover of a rename)
// Usage: node check_lua.js file.lua [more.lua]
const fs = require('fs');
const luaparse = require('luaparse');

const KNOWN_GLOBALS = new Set(['print', 'io', 'os', 'math', 'string', 'table', 'pcall', 'xpcall', 'tostring', 'tonumber', 'type',
  'ipairs', 'pairs', 'select', 'error', 'assert', 'dofile', 'debug', '_G', 'next', 'setmetatable', 'getmetatable', 'rawget', 'rawset',
  // UE4SS
  'StaticFindObject', 'FindAllOf', 'FName', 'FText', 'StaticConstructObject', 'LoopInGameThreadWithDelay', 'LoopInGameThreadAfterFrames', 'RegisterKeyBind', 'RegisterHook', 'Key',
  'ModifierKey', 'ExecuteInGameThread', 'ForEachUObject', 'LoadAsset']);
// Fields that come from Lua, UE4SS or the game (read but never written by the mod)
const EXTERNAL_FIELDS = new Set(['X', 'Y', 'Z', 'R', 'G', 'B', 'A', 'Pawn', 'K', 'CONTROL', 'SHIFT', 'Font', 'Size', 'SpecifiedColor', 'n',
  'source', 'traceback', 'clock', 'date', 'time', 'execute', 'remove', 'rename', 'open', 'lines', 'floor', 'max', 'min', 'abs', 'sqrt', 'deg',
  'rad', 'cos', 'sin', 'atan', 'char', 'huge', 'format', 'concat', 'sort', 'insert', 'pack', 'unpack', 'getinfo', 'match', 'gsub', 'gmatch', 'find', 'lower', 'sub', 'stop']);

let problems = 0;
// Fields are checked across all the files together (the panel's fields are used by main.lua)
const fieldsRead = new Map(), fieldsWritten = new Set();
const fieldReport = [];
for (const path of process.argv.slice(2)) {
  const code = fs.readFileSync(path, 'utf8');
  const ast = luaparse.parse(code, { luaVersion: '5.3', locations: true, scope: true, comments: false });
  const scopes = [new Map()];
  const declared = [];
  const report = (line, message) => { problems++; console.log(path + ':' + line + ': ' + message); };
  const lookup = name => { for (let i = scopes.length - 1; i >= 0; i--) if (scopes[i].has(name)) return scopes[i].get(name); return null; };
  const declare = (identifier, kind) => {
    const entry = { name: identifier.name, line: identifier.loc.start.line, used: false, kind };
    scopes[scopes.length - 1].set(identifier.name, entry);
    declared.push(entry);
  };
  const useName = node => {
    const entry = lookup(node.name);
    if (entry) entry.used = true;
    else if (!KNOWN_GLOBALS.has(node.name)) report(node.loc.start.line, 'global "' + node.name + '" (not a known Lua/UE4SS name)');
  };
  const block = (body, setup) => { scopes.push(new Map()); if (setup) setup(); body.forEach(statement); scopes.pop(); };
  function expression(node, isCallee) {
    if (!node) return;
    switch (node.type) {
      case 'Identifier': useName(node); break;
      case 'MemberExpression':
        expression(node.base);
        if (node.indexer === '.') {
          const list = fieldsRead.get(node.identifier.name) || [];
          list.push(path + ':' + node.loc.start.line); fieldsRead.set(node.identifier.name, list);
        }
        break;
      case 'IndexExpression': expression(node.base); expression(node.index); break;
      case 'CallExpression': expression(node.base, true); node.arguments.forEach(a => expression(a)); break;
      case 'StringCallExpression': expression(node.base, true); break;
      case 'TableCallExpression': expression(node.base, true); expression(node.arguments); break;
      case 'TableConstructorExpression':
        node.fields.forEach(field => {
          if (field.type === 'TableKeyString') fieldsWritten.add(field.key.name);
          if (field.type === 'TableKey') expression(field.key);
          expression(field.value);
        });
        break;
      case 'BinaryExpression': case 'LogicalExpression': expression(node.left); expression(node.right); break;
      case 'UnaryExpression': expression(node.argument); break;
      case 'FunctionDeclaration': functionNode(node); break;
      case 'StringLiteral': {   // fields set through a computed key, e.g. settings[setting.key]
        const text = node.raw.slice(1, -1);
        if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(text)) fieldsWritten.add(text);
        break;
      }
      default: break;  // other literals, varargs
    }
  }
  function functionNode(node) {
    scopes.push(new Map());
    node.parameters.forEach(p => { if (p.type === 'Identifier') declare(p, 'parameter'); });
    node.body.forEach(statement);
    scopes.pop();
  }
  function assignTarget(target) {
    if (target.type === 'Identifier') {
      const entry = lookup(target.name);
      if (!entry && !KNOWN_GLOBALS.has(target.name)) report(target.loc.start.line, 'assignment to global "' + target.name + '"');
    } else if (target.type === 'MemberExpression') {
      expression(target.base);
      fieldsWritten.add(target.identifier.name);
    } else if (target.type === 'IndexExpression') { expression(target.base); expression(target.index); }
  }
  function statement(node) {
    switch (node.type) {
      case 'LocalStatement':
        node.init.forEach(e => expression(e));
        node.variables.forEach(v => declare(v, 'local'));
        break;
      case 'AssignmentStatement': node.init.forEach(e => expression(e)); node.variables.forEach(assignTarget); break;
      case 'CallStatement': expression(node.expression); break;
      case 'FunctionDeclaration':
        if (node.isLocal) { declare(node.identifier, 'function'); functionNode(node); }
        else {
          if (node.identifier && node.identifier.type === 'MemberExpression') { expression(node.identifier.base); fieldsWritten.add(node.identifier.identifier.name); }
          else if (node.identifier) assignTarget(node.identifier);
          functionNode(node);
        }
        break;
      case 'ReturnStatement': node.arguments.forEach(e => expression(e)); break;
      case 'IfStatement':
        node.clauses.forEach(c => { if (c.condition) expression(c.condition); block(c.body); });
        break;
      case 'WhileStatement': expression(node.condition); block(node.body); break;
      case 'RepeatStatement': scopes.push(new Map()); node.body.forEach(statement); expression(node.condition); scopes.pop(); break;
      case 'DoStatement': block(node.body); break;
      case 'ForNumericStatement':
        expression(node.start); expression(node.end); expression(node.step);
        block(node.body, () => declare(node.variable, 'loop'));
        break;
      case 'ForGenericStatement':
        node.iterators.forEach(e => expression(e));
        block(node.body, () => node.variables.forEach(v => declare(v, 'loop')));
        break;
      default: break;  // break, goto, label
    }
  }
  block(ast.body);
  for (const entry of declared) if (!entry.used && entry.name !== '_' && entry.kind !== 'loop' && entry.kind !== 'parameter') report(entry.line, 'local "' + entry.name + '" is never used');
}
for (const [field, places] of fieldsRead) {
  if (fieldsWritten.has(field) || EXTERNAL_FIELDS.has(field) || /^[A-Z]/.test(field) || /^b[A-Z]/.test(field) || /^m[A-Z]/.test(field)) continue;
  problems++; console.log(places[0] + ': field ".' + field + '" is read (' + places.length + 'x) but never written');
}
console.log(problems ? problems + ' problem(s)' : 'no problems');
process.exit(problems ? 1 : 0);
