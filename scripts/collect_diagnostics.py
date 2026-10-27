import pathlib,shutil,subprocess,json
out=pathlib.Path('build/logs');out.mkdir(parents=True,exist_ok=True)
reports=pathlib.Path.home()/'Library/Logs/DiagnosticReports'
for path in list(reports.glob('ChaiTrade*.ips'))[-8:]:
 shutil.copy2(path,out/path.name)
 print('CRASH_REPORT',path.name)
 text=path.read_text(errors='replace')
 try:
  # Apple .ips contains a JSON header line followed by the report object.
  report=json.loads(text.split('\n',1)[1])
  print(json.dumps({k:report.get(k) for k in ['procName','exception','termination','asi','faultingThread']},ensure_ascii=False))
 except (ValueError,IndexError):print(text[:8000])
try:
 result=subprocess.run(['xcrun','simctl','spawn','booted','log','show','--last','15m','--style','compact','--predicate','process == "ChaiTrade"'],capture_output=True,text=True,timeout=40)
 tail='\n'.join(result.stdout.splitlines()[-200:]);(out/'app-system.log').write_text(tail);print(tail)
except (OSError,subprocess.TimeoutExpired) as e:print('DIAGNOSTIC_COLLECTION',type(e).__name__)

# Only DEBUG XCTest namespaces; never collect the production account directory.
try:
 container=subprocess.check_output(['xcrun','simctl','get_app_container','booted','org.chaitrade.app','data'],text=True).strip()
 sessions=pathlib.Path(container)/'Library/Application Support/ChaiTradeUITests'
 if sessions.is_dir():
  shutil.copytree(sessions,out/'ui-test-sessions',dirs_exist_ok=True)
  print('UI_TEST_SESSION_DATABASES_RETAINED',len(list(sessions.iterdir())))
except (OSError,subprocess.CalledProcessError) as e:print('UI_TEST_SESSION_COLLECTION',type(e).__name__)
