#!/usr/bin/env python3
"""Static-only checks; does not run Java, Gradle, native code, or compile anything."""
from pathlib import Path
from urllib.parse import unquote
import re, sys, xml.etree.ElementTree as ET
from aar_inventory import ROOT, inventory, argument_count

def main():
    problems=[]
    java=ROOT/'app/src/main/java'
    forbidden=[r'com\.makeid\.AndroidIoTTestTool',r'\b(?:HttpUtil|MkdNetHelper|CrashReport|MkdLockManagerNewer|MkdElectronicKeyManager)\b',
               r'import\s+(?:java\.net|okhttp3|retrofit2|android\.webkit)\.',r'implementation\s+project\s*\(']
    for p in java.rglob('*.java'):
        text=p.read_text()
        for pattern in forbidden:
            if re.search(pattern,text):problems.append(f'{p.name}: forbidden dependency {pattern}')
        if not text.endswith('\n') or any(line.rstrip()!=line for line in text.splitlines()):problems.append(p.name+': formatting')
    build=(ROOT/'app/build.gradle').read_text()
    if 'implementation project(' in build or '/Users/' in build:problems.append('Non-independent Gradle dependency')
    for filename in ['MakeID_XCFiberCheckLib_1.0.aar','makeid_bleconnectlib_1.1.aar']:
        if "files('libs/"+filename+"')" not in build:problems.append('AAR not referenced '+filename)
    ns='{http://schemas.android.com/apk/res/android}';tools='{http://schemas.android.com/tools}'
    manifest=ET.parse(ROOT/'app/src/main/AndroidManifest.xml').getroot()
    if manifest.find('application').get(ns+'allowBackup')!='false':problems.append('Backups enabled')
    for permission in manifest.findall('uses-permission'):
        if permission.get(ns+'name')=='android.permission.INTERNET' and permission.get(tools+'node')!='remove':problems.append('INTERNET enabled')
    ids=set();resources={}
    for p in (ROOT/'app/src/main/res').rglob('*.xml'):
        try:root=ET.parse(p).getroot()
        except ET.ParseError as error:problems.append(str(p)+': '+str(error));continue
        for element in root.iter():
            value=element.get(ns+'id','')
            if value.startswith('@+id/'):ids.add(value[5:])
        if p.parent.name.startswith('values'):
            for child in root:
                if child.get('name'):resources.setdefault(child.tag,set()).add(child.get('name'))
        else:resources.setdefault(p.parent.name.split('-')[0],set()).add(p.stem)
    for p in (ROOT/'app/src/main/res').rglob('*.xml'):
        for kind,name in re.findall(r'@([a-z]+)/([\w.]+)',re.sub(r'<!--.*?-->','',p.read_text(),flags=re.S)):
            if kind=='id':continue
            if name not in resources.get(kind,set()):problems.append(f'{p.name}: unresolved {kind}/{name}')
    for p in java.rglob('*.java'):
        for name in re.findall(r'R\.id\.(\w+)',p.read_text()):
            if name not in ids:problems.append(p.name+': unresolved ID '+name)
    # ViewBinding members must map to IDs in the actual layout, not merely some resource file.
    for filename,layout in [('MainActivity.java','activity_main.xml'),('FiberScanActivity.java','activity_fiber_scan.xml')]:
        source=next(java.rglob(filename))
        ids_in_layout=set()
        for element in ET.parse(ROOT/'app/src/main/res/layout'/layout).getroot().iter():
            value=element.get(ns+'id','')
            if value.startswith('@+id/'):
                parts=value[5:].split('_')
                ids_in_layout.add(parts[0]+''.join(x[:1].upper()+x[1:] for x in parts[1:]))
        accessed=set(re.findall(r'\bbinding\.(\w+)',source.read_text()))-{'getRoot'}
        for field in accessed-ids_in_layout:problems.append(filename+': unknown ViewBinding field '+field)
    records,classes=inventory()
    checksum_doc=(ROOT/'docs/SDK交付清单.md').read_text()
    for rec in records:
        if rec['sha256'] not in checksum_doc:problems.append('AAR changed from inventory '+rec['file'])
    parsed=0;calls=0;callbacks=0
    try:import javalang
    except ImportError:print('NOTE: optional Java parser unavailable; install requirements-static.txt for grammar/contracts')
    else:
        public=classes['com.makeid.mkdxcfiberchecklib.XCFiberCheckManager']['methods']
        methods={}
        for m in public:methods.setdefault(m['name'],set()).add(argument_count(m['descriptor']))
        interfaces={name.split('.')[-1]:info for name,info in classes.items() if '.listener.' in name or name.endswith('.ScanListener')}
        for p in (ROOT/'app/src').rglob('*.java'):
            try:tree=javalang.parse.parse(p.read_text())
            except (javalang.parser.JavaSyntaxError,javalang.tokenizer.LexerError) as error:
                problems.append('Java syntax '+p.name+': '+str(error));continue
            parsed+=1
            for imp in tree.imports:
                if imp.path.startswith(('com.makeid.blelibrary.','com.makeid.mkdxcfiberchecklib.')) and not imp.wildcard:
                    if imp.path not in classes:problems.append('Missing SDK class '+imp.path)
            for _,node in tree.filter(javalang.tree.MethodInvocation):
                if node.qualifier=='sdk' or node.qualifier=='XCFiberCheckManager':
                    if node.member not in methods or len(node.arguments) not in methods[node.member]:problems.append(f'{p.name}: SDK signature {node.member}/{len(node.arguments)}')
                    calls+=1
            for _,node in tree.filter(javalang.tree.ClassCreator):
                if node.type.name not in interfaces or node.body is None:continue
                supplied={(m.name,len(m.parameters)) for m in node.body if isinstance(m,javalang.tree.MethodDeclaration)}
                for m in interfaces[node.type.name]['methods']:
                    if m['name'].startswith('<') or not m['access']&0x0400:continue
                    if (m['name'],argument_count(m['descriptor'])) not in supplied:problems.append('Missing callback '+node.type.name+'.'+m['name'])
                callbacks+=1
    for p in [ROOT/'README.md',*(ROOT/'docs').rglob('*.md')]:
        if not p.is_file():continue
        for url in re.findall(r'\]\(([^)]+)\)',p.read_text()):
            if not re.match(r'\w+://',url) and not url.startswith('#') and not (p.parent/unquote(url.split('#')[0])).is_file():problems.append('Broken link '+url)
    if problems:
        for problem in problems:print('FAIL:',problem)
        return 1
    print('PASS: local AAR CRC/hash, independent dependencies, no old app/network/lock SDK, backups disabled')
    print('PASS: XML, resource references/IDs, doc links, formatting')
    print(f'PASS: {parsed} Java grammar parses; {calls} binary SDK name/arity checks; {callbacks} callback contracts (not compilation)')
    print('No Gradle, compilation, packaging, native execution or physical-device verification performed.')
    return 0
if __name__=='__main__':sys.exit(main())
