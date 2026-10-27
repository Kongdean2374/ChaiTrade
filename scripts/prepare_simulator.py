import json,subprocess,sys
listing=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
devices=listing['devices'].get('com.apple.CoreSimulator.SimRuntime.iOS-26-2',[])
device=next((d for d in devices if d['name']=='iPhone 17 Pro'),None)
if not device:raise SystemExit('Required iPhone 17 Pro / iOS 26.2 simulator is unavailable')
udid=device['udid']
if device['state']!='Booted':subprocess.run(['xcrun','simctl','boot',udid],check=True,timeout=60,stdout=sys.stderr,stderr=sys.stderr)
subprocess.run(['xcrun','simctl','bootstatus',udid,'-b'],check=True,timeout=180,stdout=sys.stderr,stderr=sys.stderr)
print(udid)
