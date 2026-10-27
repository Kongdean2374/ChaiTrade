"""Bounded repository hygiene checks; not a guarantee against every secret format."""
import pathlib,re,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
paths=subprocess.check_output(['git','ls-files'],cwd=root,text=True).splitlines()
blocked={'.p12','.p8','.mobileprovision','.sqlite','.sqlite3','.chaitrade','.key'}
patterns=[re.compile(r'github_pat_[A-Za-z0-9_]{40,}'),re.compile(r'gh[pousr]_[A-Za-z0-9]{30,}'),re.compile('-----BEGIN '+r'(?:RSA |EC |OPENSSH )?PRIVATE KEY-----')]
errors=[]
for name in paths:
 p=root/name
 if p.suffix.lower() in blocked or p.name.startswith('.env'):errors.append(name+': forbidden private/runtime file')
 try:text=p.read_text()
 except UnicodeDecodeError:continue
 if any(pattern.search(text) for pattern in patterns):errors.append(name+': potential credential; value omitted')
if errors:raise SystemExit('\n'.join(errors))
print('Tracked-file secret-format and runtime-data checks passed; no credential values printed')
