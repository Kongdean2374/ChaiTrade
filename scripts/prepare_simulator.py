import json,os,pathlib,subprocess,sys,time,uuid

RUNTIME='com.apple.CoreSimulator.SimRuntime.iOS-26-2'
name=os.environ.get('CHAI_SIMULATOR_NAME','iPhone 17 Pro')
if name not in ['iPhone 17 Pro','iPhone SE (3rd generation)']:raise SystemExit('Unsupported acceptance simulator name')
output=pathlib.Path('build/logs');output.mkdir(parents=True,exist_ok=True)
listing=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
devices=listing['devices'].get(RUNTIME,[])
types=json.loads(subprocess.check_output(['xcrun','simctl','list','devicetypes','--json']))['devicetypes']
device_type=next((t['identifier'] for t in types if t['name']==name),None)
if not device_type:raise SystemExit('Required '+name+' device type is unavailable')
def fresh():
 udid=subprocess.check_output(['xcrun','simctl','create','ChaiTrade acceptance '+str(uuid.uuid4()),device_type,RUNTIME],text=True).strip()
 return {'udid':udid,'state':'Shutdown'}
device=next((d for d in devices if d['name']==name),None) or fresh()
# Compiling for a simulator does not run the app or require booting a device.
# Actual UI jobs use the normal path below; no test or acceptance allowance changes.
if os.environ.get('CHAI_PREPARE_BUILD_ONLY')=='1':
 print(device['udid']);raise SystemExit(0)
# UI jobs own a fresh OS container as well as independent App account UUIDs.
# The runner image's default device retained a WebKit extension-launch stall
# (RunningBoardServices wait) across App relaunches. Keep the same runtime,
# device type, 180-second boot gate and all native App/test deadlines.
device=fresh()
records=[]
for attempt in range(2):
 started=time.monotonic();udid=device['udid']
 try:
  if device['state']!='Booted':
   boot=subprocess.run(['xcrun','simctl','boot',udid],timeout=60,stdout=sys.stderr,stderr=sys.stderr)
   if boot.returncode!=0:
    current=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','--json'],timeout=15))
    if not any(d['udid']==udid and d['state']=='Booted' for items in current['devices'].values() for d in items):raise subprocess.CalledProcessError(boot.returncode,boot.args)
  # The original180s system boot gate stays mandatory. A Home screenshot is
  # diagnostic output, not a replacement for the real App/XCTest acceptance.
  subprocess.run(['xcrun','simctl','bootstatus',udid,'-b'],check=True,timeout=180,stdout=sys.stderr,stderr=sys.stderr)
  # Prepare only Apple's Simulator, never ChaiTrade. Retain bounded diagnostic
  # failures instead of restarting an already booted host because PNG IO hung.
  developer=os.environ.get('DEVELOPER_DIR','/Applications/Xcode_26.2.app/Contents/Developer')
  simulator=pathlib.Path(developer)/'Applications/Simulator.app'
  diagnostics={}
  for label,command,limit in [
   ('hostGUI',['open','-a',str(simulator),'--args','-CurrentDeviceUDID',udid],20),
   ('homePNG',['xcrun','simctl','io',udid,'screenshot',str(output/f'simulator-home-before-app-{attempt+1}.png')],15)
  ]:
   try:
    subprocess.run(command,check=True,timeout=limit,stdout=sys.stderr,stderr=sys.stderr);diagnostics[label]={'completed':True}
   except (OSError,subprocess.CalledProcessError,subprocess.TimeoutExpired) as diagnostic_error:
    diagnostics[label]={'completed':False,'error':type(diagnostic_error).__name__,'limitSeconds':limit}
    print('Host diagnostic '+label+' failed; retained. Real App tests and their original deadlines are still required.',file=sys.stderr)
  records.append({'attempt':attempt+1,'udid':udid,'device':name,'hostBootSeconds':time.monotonic()-started,'ready':True,'diagnostics':diagnostics,'chaiTradePrelaunched':False,'appAcceptance':'not started; real tests required'})
  (output/'simulator-preparation.json').write_text(json.dumps(records,indent=2))
  print(udid);break
 except (subprocess.CalledProcessError,subprocess.TimeoutExpired) as error:
  records.append({'attempt':attempt+1,'udid':udid,'device':name,'hostBootSeconds':time.monotonic()-started,'ready':False,'error':type(error).__name__,'note':'Host simulator boot only; not iPhone app cold-start acceptance.'})
  (output/'simulator-preparation.json').write_text(json.dumps(records,indent=2))
  try:
   diagnostic=subprocess.run(['xcrun','simctl','list','devices','--json'],capture_output=True,text=True,timeout=15)
   (output/f'simulator-boot-failure-{attempt+1}.json').write_text(diagnostic.stdout)
  except (OSError,subprocess.TimeoutExpired):pass
  if attempt==1:raise
  print('Simulator host failed; evidence retained. Retrying once with a new identical device; same 180-second host boot limit.',file=sys.stderr)
  try:subprocess.run(['xcrun','simctl','shutdown',udid],timeout=15,stdout=sys.stderr,stderr=sys.stderr)
  except (OSError,subprocess.TimeoutExpired):pass
  # The default device reported Booted while bootstatus/IPC hung. Restart only
  # this disposable runner's simulator services before creating the clean retry.
  for process in ['Simulator','com.apple.CoreSimulator.CoreSimulatorService']:
   try:subprocess.run(['killall','-TERM',process],timeout=10,stdout=sys.stderr,stderr=sys.stderr)
   except (OSError,subprocess.TimeoutExpired):pass
  device=fresh()
  developer=os.environ.get('DEVELOPER_DIR','/Applications/Xcode_26.2.app/Contents/Developer')
  simulator=pathlib.Path(developer)/'Applications/Simulator.app'
  if simulator.is_dir():
   try:subprocess.run(['open','-a',str(simulator),'--args','-CurrentDeviceUDID',device['udid']],timeout=20,stdout=sys.stderr,stderr=sys.stderr)
   except (OSError,subprocess.TimeoutExpired):pass
