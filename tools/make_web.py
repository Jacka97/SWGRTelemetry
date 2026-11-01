"""Builds the app's two pages: index.html (Spanish, the original) and index_en.html (generated),
with the lap analyzer built in, and checks them."""
import re, subprocess, sys
import os
TOOLS = os.path.dirname(os.path.abspath(__file__)) + '/'
WEB = TOOLS + '../app/web/'
subprocess.run([sys.executable, TOOLS + 'english.py'], check=True)
analyzer = open(TOOLS + 'analysis.js', encoding='utf-8').read()
analyzer = re.sub(r'\n?if \(typeof module[^\n]*\n?', '\n', analyzer)   # the node export is only for the tests
for template, page in (('template.html', 'index.html'), ('template_en.html', 'index_en.html')):
    text = open(WEB + template, encoding='utf-8').read()
    open(WEB + page, 'w', encoding='utf-8').write(text.replace('__ANALYSIS__', analyzer))
# Syntax check of both pages (a badly escaped apostrophe breaks the English page)
syntax = subprocess.run(['node', '-e', '''
const fs = require("fs"); let failed = 0;
for (const page of ["index.html", "index_en.html"]) {
  const html = fs.readFileSync("''' + WEB + '''" + page, "utf8");
  for (const script of html.matchAll(/<script>([\\s\\S]*?)<\\/script>/g)) { try { new Function(script[1]); } catch (error) { console.log(page + ": " + error.message); failed = 1; } }
}
process.exit(failed);'''], capture_output=True, text=True)
if syntax.returncode:
    print('SYNTAX ERROR:', syntax.stdout); sys.exit(1)
# Names left half renamed: undeclared or unused names, fields never written, ids, classes and data attributes
names = subprocess.run(['node', TOOLS + 'check_web.js', WEB + 'template.html', TOOLS + 'analysis.js'] + sorted(__import__('glob').glob(TOOLS + '../app/*.go')), capture_output=True, text=True)
if names.returncode:
    print('NAME CHECK FAILED:\n' + names.stdout); sys.exit(1)
# The English page must keep exactly the same markup: the same classes, ids and data attributes, in the same order
def markup_names(path):
    text = open(path, encoding='utf-8').read()
    return re.findall(r'(?:class|id|data-[a-z-]+)="[^"]*"', text)
spanish_names, english_names = markup_names(WEB + 'template.html'), markup_names(WEB + 'template_en.html')
if spanish_names != english_names:
    import difflib
    print('THE ENGLISH PAGE CHANGED THE MARKUP:'); print('\n'.join(list(difflib.unified_diff(spanish_names, english_names, lineterm='', n=1))[:30])); sys.exit(1)
print('index.html + index_en.html (syntax, names and markup OK)')
