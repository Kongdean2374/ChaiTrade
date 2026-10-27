import json,subprocess,sys
listing=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
devices=listing['devices'].get('com.apple.CoreSimulator.SimRuntime.iOS-18-5',[])
device=next((d for d in devices if d['name']=='iPhone 16 Pro'),None)
if not device:raise SystemExit('Required iPhone 16 Pro / iOS 18.5 simulator is unavailable')
udid=device['udid']
if device['state']!='Booted':subprocess.run(['xcrun','simctl','boot',udid],check=True,timeout=60,stdout=sys.stderr,stderr=sys.stderr)
subprocess.run(['xcrun','simctl','bootstatus',udid,'-b'],check=True,timeout=180,stdout=sys.stderr,stderr=sys.stderr)
print(udid)
