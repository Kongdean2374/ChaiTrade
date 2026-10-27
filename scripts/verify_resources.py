import hashlib,json,pathlib,re
root=pathlib.Path(__file__).resolve().parents[1]
web=root/'ChaiTrade/Resources/ChartWeb'
lock=json.loads((web/'dependency-lock.json').read_text())
assert hashlib.sha256((web/'lightweight-charts.js').read_bytes()).hexdigest()==lock['sha256']
assert (root/'ChaiTrade/Resources/Licenses/LightweightCharts-LICENSE').stat().st_size>1000
assert (root/'ChaiTrade/Assets.xcassets/AppIcon.appiconset/AppIcon.png').is_file()
for p in (root/'ChaiTrade').rglob('*.swift'):
 text=p.read_text()
 assert 'TODO' not in text and 'fatalError(' not in text,p
for p in web.glob('*.html'):
 assert 'https://cdn.' not in p.read_text()
print('Offline resources, dependency checksum, icon and license verified')
