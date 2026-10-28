#!/usr/bin/env python3
import os,plistlib,re,subprocess
from versioning import ROOT,read_version
data=read_version();project=(ROOT/'ChaiTrade.xcodeproj/project.pbxproj').read_text()
assert re.findall(r'MARKETING_VERSION = "([^"]+)"',project)==[data['version']]*2,'Regenerate Xcode project after version changes'
assert re.findall(r'CURRENT_PROJECT_VERSION = "([^"]+)"',project)==[str(data['build'])]*2,'Debug/Release build numbers differ'
with (ROOT/'ChaiTrade/Info.plist').open('rb') as f:info=plistlib.load(f)
assert info['CFBundleShortVersionString']=='$(MARKETING_VERSION)' and info['CFBundleVersion']=='$(CURRENT_PROJECT_VERSION)'
if os.environ.get('CI')=='true':
    parent=subprocess.run(['git','rev-parse','--verify','HEAD^'],cwd=ROOT,capture_output=True,text=True)
    assert parent.returncode==0,'CI requires checkout fetch-depth: 2 for version verification'
    previous=parent.stdout.strip()
    changed=subprocess.check_output(['git','diff','--name-only',previous,'HEAD'],cwd=ROOT,text=True).splitlines()
    product_change=any(p.startswith(('ChaiTrade/','Packages/ChaiTradeCore/Sources/')) or p in ['scripts/generate_project.py','scripts/build_unsigned_ipa.sh'] for p in changed)
    if product_change:
        old=subprocess.run(['git','show',previous+':version.json'],cwd=ROOT,capture_output=True,text=True)
        if old.returncode==0:
            import json
            old=json.loads(old.stdout)
        else:
            text=subprocess.check_output(['git','show',previous+':ChaiTrade.xcodeproj/project.pbxproj'],cwd=ROOT,text=True)
            old={'version':re.search(r'MARKETING_VERSION = "([^"]+)"',text)[1],'build':int(re.search(r'CURRENT_PROJECT_VERSION = "([^"]+)"',text)[1])}
        assert tuple(map(int,data['version'].split('.')))>tuple(map(int,old['version'].split('.'))) and data['build']>old['build'],'App changes require increasing both version and build with scripts/bump_version.py'
print('Version settings verified:',data['version'],'build',data['build'])
