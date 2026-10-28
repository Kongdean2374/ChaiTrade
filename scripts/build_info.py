import datetime,hashlib,json,pathlib,plistlib,shutil,subprocess,zipfile
from versioning import read_version
root=pathlib.Path(__file__).resolve().parents[1]
def command(args):return subprocess.check_output(args,cwd=root,text=True).strip()
ipa=root/'dist/ChaiTrade-unsigned.ipa'
version=read_version()
with zipfile.ZipFile(ipa) as archive:bundle=plistlib.loads(archive.read('Payload/ChaiTrade.app/Info.plist'))
assert bundle['CFBundleShortVersionString']==version['version'] and bundle['CFBundleVersion']==str(version['build']),'Built IPA does not match source version'
info={'commit':command(['git','rev-parse','HEAD']),'createdAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'xcode':command(['xcodebuild','-version']),'swift':command(['swift','--version']),'sdk':command(['xcrun','--sdk','iphoneos','--show-sdk-version']),'sha256':hashlib.sha256(ipa.read_bytes()).hexdigest(),'signing':'unsigned; installation requires separate user signing','validation':{'core':'see core-tests.log','live':'production Coinbase adapter in core-tests.log','ui':'see ui-tests.log','T45':'see stress-100000.json and stress-tests.log','device':'not executed'},'dependencies':json.loads((root/'ChaiTrade/Resources/ChartWeb/dependency-lock.json').read_text())}
info.update({'version':bundle['CFBundleShortVersionString'],'build':bundle['CFBundleVersion']})
versioned=ipa.with_name('ChaiTrade-'+version['version']+'-'+str(version['build'])+'-unsigned.ipa')
if versioned.exists():
    assert hashlib.sha256(versioned.read_bytes()).hexdigest()==info['sha256'],'Existing versioned IPA differs; do not overwrite it'
else:shutil.copy2(ipa,versioned)
versioned.with_suffix(versioned.suffix+'.sha256').write_text(info['sha256']+'  '+versioned.name+'\n')
info['versionedIPA']=versioned.name
(root/'dist/build-info.json').write_text(json.dumps(info,ensure_ascii=False,indent=2)+'\n')
