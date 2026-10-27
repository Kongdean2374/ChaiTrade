import datetime,hashlib,json,pathlib,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
def command(args):return subprocess.check_output(args,cwd=root,text=True).strip()
ipa=root/'dist/ChaiTrade-unsigned.ipa'
info={'commit':command(['git','rev-parse','HEAD']),'createdAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'xcode':command(['xcodebuild','-version']),'swift':command(['swift','--version']),'sdk':command(['xcrun','--sdk','iphoneos','--show-sdk-version']),'sha256':hashlib.sha256(ipa.read_bytes()).hexdigest(),'signing':'unsigned; installation requires separate user signing','validation':{'core':'see core-tests.log','live':'production Coinbase adapter in core-tests.log','ui':'see ui-tests.log','T45':'see stress-100000.json and stress-tests.log','device':'not executed'},'dependencies':json.loads((root/'ChaiTrade/Resources/ChartWeb/dependency-lock.json').read_text())}
(root/'dist/build-info.json').write_text(json.dumps(info,ensure_ascii=False,indent=2)+'\n')
