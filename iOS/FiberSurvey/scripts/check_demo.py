#!/usr/bin/env python3
"""Static contract checks only. Does not compile Objective-C or invoke xcodebuild."""
from pathlib import Path
import hashlib
import json
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
errors = []
def check(condition, message):
    if not condition:
        errors.append(message)

required = [
    'FiberSurvey/Core/FSCDeviceFilterParser.h', 'FiberSurvey/Core/FSCDeviceFilterParser.m',
    'FiberSurvey/Core/FSCBoundedStore.h', 'FiberSurvey/Core/FSCBoundedStore.m',
    'FiberSurvey/Core/FSCSessionState.h', 'FiberSurvey/Core/FSCSessionState.m',
    'FiberSurvey/Core/FSCCentralStateGate.h', 'FiberSurvey/Core/FSCCentralStateGate.m',
    'FiberSurvey/Models/FSCScanItem.h', 'FiberSurvey/Models/FSCScanItem.m',
    'FiberSurvey/Controllers/FSCFiberSurveyController.h', 'FiberSurvey/Controllers/FSCFiberSurveyController.m',
    'FiberSurvey/Controllers/FSCScanViewController.h', 'FiberSurvey/Controllers/FSCScanViewController.m',
    'README.md', 'docs/使用说明.md', 'docs/验证记录.md',
]
for rel in required:
    check((ROOT / rel).is_file(), f'Missing implementation: {rel}')
if errors:
    print('\n'.join('FAIL: ' + e for e in errors)); sys.exit(1)

# xcproj is JSON-with-trailing-commas; read only, never rewrite via json.dumps.
project = (ROOT / 'FiberSurvey.xcodeproj/project.xcproj').read_text()
settings = json.loads(re.sub(r',\s*([\]}])', r'\1', project))
app = next(t for t in settings['targets'] if t['name'] == 'FiberSurvey')
bs = app['build-settings']
check(bs['PRODUCT_BUNDLE_IDENTIFIER'] == 'com.makeid.fibersurvey.FiberSurvey', 'Bundle ID')
check('INFOPLIST_KEY_UIMainStoryboardFile' not in bs, 'Legacy Main build setting')
check(bs.get('SUPPORTED_PLATFORMS') == 'iphoneos', 'Device only platform')
check('$(PROJECT_DIR)/Vendor' in str(bs.get('FRAMEWORK_SEARCH_PATHS')), 'Relative framework path')
if re.search(r'"DEVELOPMENT_TEAM":\s*"[^"\s]+"', project):
    print('NOTE: local signing Team is set; external recipients must choose their own Team/Profile.')
# Native linking and embedding must each own one reference per SDK. A script must
# never claim the same Framework output as the native copy phase.
def files_in(entries):
    for entry in entries:
        yield entry
        yield from files_in(entry.get('children', []))

embed_phases = [phase for phase in app['build-phases'] if isinstance(phase, dict)
                and phase.get('kind') == 'copy'
                and phase.get('bundle-base-path') == 'frameworks-directory']
check(len(embed_phases) == 1, 'Expected one native Embed Frameworks phase')
embed_references = {f"FiberSurvey/copy/{phase.get('name')}" for phase in embed_phases}
for sdk in ('MkdBLEConnectLib', 'MkdXCFiberCheckLib'):
    references = [entry for entry in files_in(settings['files'])
                  if Path(entry.get('path', '')).name == sdk + '.framework']
    memberships = [membership for entry in references for membership in entry.get('target-membership', [])]
    check(memberships.count('FiberSurvey/frameworks') == 1, f'Expected one native link: {sdk}')
    embeds = [membership for membership in memberships if isinstance(membership, dict)
              and membership.get('build-phase') in embed_references]
    check(len(embeds) == 1 and embeds[0].get('code-sign-on-copy') is True,
          f'Expected one native Embed & Sign: {sdk}')
    for phase in app['build-phases']:
        if not isinstance(phase, dict) or phase.get('kind') != 'script':
            continue
        check(not any(sdk + '.framework' in output for output in phase.get('output-paths', [])),
              f'Duplicate Framework output claimed by script: {sdk}')
    check(sdk not in str(bs.get('OTHER_LDFLAGS', [])), f'Redundant manual framework link: {sdk}')
check('embed-frameworks.sh' not in str(app['build-phases']), 'Legacy SDK embedding script still enabled')
info = plistlib.loads((ROOT / 'FiberSurvey/Info.plist').read_bytes())
check(bool(info.get('NSBluetoothAlwaysUsageDescription')), 'Bluetooth privacy key')
check('UIBackgroundModes' not in info, 'Unexpected background BLE')
scene = info['UIApplicationSceneManifest']
check(scene['UIApplicationSupportsMultipleScenes'] is False, 'Multiple scenes')
check('UISceneStoryboardFile' not in str(scene), 'Legacy Scene storyboard')
sources = '\n'.join(p.read_text() for p in (ROOT / 'FiberSurvey').rglob('*') if p.suffix in ('.m', '.h'))
controller = (ROOT / 'FiberSurvey/Controllers/FSCFiberSurveyController.m').read_text()
for forbidden in ('NSURLSession', 'NSURLConnection', 'AFNetworking', 'WKWebView', 'setNotifyValue:', 'writeValue:', 'setValue:localName', 'recvDataCallback =', 'connectionStateChangedBlock ='):
    check(forbidden not in sources, f'Unexpected network / BLE bypass: {forbidden}')
check('FSCSDKWriteSafetyValidated = NO' in controller, 'Unsafe SDK write guard changed')
for token in ('restartRequired', 'operationID', 'sessionID', 'scanID', 'systemUptime', 'shutdownAllWithSuccess:', 'canShutdown', 'clearDeviceIdFilter', 'deviceIdFilter', 'searchDevicesForTimeout:', 'observeCentralManagerState:', 'FSCSessionConnectedUnverified'):
    check(token in sources, f'Missing safety/API contract: {token}')
manifest = ROOT / 'Vendor/SHA256SUMS'
if manifest.is_file():
    for line in manifest.read_text().splitlines():
        digest, rel = line.split('  ', 1)
        file = ROOT / 'Vendor' / rel
        check(file.is_file() and hashlib.sha256(file.read_bytes()).hexdigest() == digest, f'SDK changed: {rel}')
else:
    print('NOTE: Vendor/SHA256SUMS is absent; SDK delivery hash verification was NOT performed.')
for p in (ROOT / 'FiberSurvey').rglob('*.storyboard'):
    ET.parse(p)
for p in list((ROOT / 'FiberSurvey').rglob('*.m')) + list((ROOT / 'FiberSurvey').rglob('*.h')):
    check('TODO' not in p.read_text(), 'Placeholder: ' + str(p))
# Public manager methods actually used by this Demo must exist in the delivered headers.
header = (ROOT / 'Vendor/MkdXCFiberCheckLib.framework/Headers/MKDXCFiberCheckManager.h').read_text()
def selectors(text):
    found = set()
    for declaration in re.findall(r'^[-+]\s*\([^)]*\)\s*(.*?)[;{]', text, re.M | re.S):
        names = re.findall(r'\b([a-zA-Z_]\w*)\s*:', declaration)
        if names:
            found.add(':'.join(names) + ':')
        else:
            first = re.match(r'\w+', declaration)
            if first:
                found.add(first.group())
    return found
expected_api = {'shared', 'sdkVersion', 'observeCentralManagerState:', 'searchDevicesForTimeout:success:complete:fail:',
                'stopScan', 'connectPeripheral:success:fail:', 'disconnect', 'setDeviceIdFilter:',
                'clearDeviceIdFilter', 'shutdownAllWithSuccess:failure:'}
check(expected_api <= selectors(header), 'Delivered SDK public selector mismatch')
expected_delegate = {'xcfiberDidUpdateConnectionState:', 'xcfiberDidReceivePowerChange:powerUp:',
                     'xcfiberDidReceiveDevicePowerOn:', 'xcfiberDidReceiveDevicePowerOff:', 'xcfiberDidReceiveRawJson:isSend:'}
check(expected_delegate <= selectors(controller), 'Missing SDK delegate implementation')
for path in list((ROOT / 'FiberSurvey').rglob('*.m')) + list((ROOT / 'FiberSurvey').rglob('*.h')) + list((ROOT / 'FiberSurveyTests').rglob('*.m')):
    text = path.read_text()
    # Lexical sanity check only, explicitly not an Objective-C parser/compiler.
    stripped = re.sub(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', '', text, flags=re.S)
    stack = []
    for character in stripped:
        if character in '([{': stack.append(character)
        elif character in ')]}':
            if not stack or stack.pop() != {')': '(', ']': '[', '}': '{'}[character]:
                errors.append('Unbalanced delimiters: ' + str(path.relative_to(ROOT)))
                break
    check(not stack, 'Unclosed delimiters: ' + str(path.relative_to(ROOT)))
    for include in re.findall(r'^#import "([^"]+)"', text, re.M):
        check((path.parent / include).is_file(), 'Missing local import: ' + include)

if errors:
    print('\n'.join('FAIL: ' + e for e in errors)); sys.exit(1)
print(f'PASS: {len(required)} implementation/doc files; project/Scene/privacy/link/embed; safety guards; offline boundary; optional SDK manifest check; unique native Framework producers')
print('STATIC ONLY: no Objective-C compilation, XCTest, App build, SDK rebuild or physical-device validation.')
