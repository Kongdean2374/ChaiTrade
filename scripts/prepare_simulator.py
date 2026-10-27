import json,subprocess,sys,os
listing=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
devices=listing['devices'].get('com.apple.CoreSimulator.SimRuntime.iOS-26-2',[])
name=os.environ.get('CHAI_SIMULATOR_NAME','iPhone 17 Pro')
if name not in ['iPhone 17 Pro','iPhone SE (3rd generation)']:raise SystemExit('Unsupported acceptance simulator name')
device=next((d for d in devices if d['name']==name),None)
if not device and name=='iPhone SE (3rd generation)':
 udid=subprocess.check_output(['xcrun','simctl','create',name,'com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation','com.apple.CoreSimulator.SimRuntime.iOS-26-2'],text=True).strip()
 device={'udid':udid,'state':'Shutdown'}
if not device:raise SystemExit('Required '+name+' / iOS 26.2 simulator is unavailable')
udid=device['udid']
if device['state']!='Booted':subprocess.run(['xcrun','simctl','boot',udid],check=True,timeout=60,stdout=sys.stderr,stderr=sys.stderr)
subprocess.run(['xcrun','simctl','bootstatus',udid,'-b'],check=True,timeout=180,stdout=sys.stderr,stderr=sys.stderr)
print(udid)
