"""Shared source of truth for Xcode, IPA metadata and intentional version increments."""
import json,pathlib,re
ROOT=pathlib.Path(__file__).resolve().parents[1]
def read_version():
    data=json.loads((ROOT/'version.json').read_text())
    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)',data.get('version','')) or type(data.get('build')) is not int or not 1<=data['build']<=2147483647:
        raise SystemExit('Invalid version.json: require major.minor.patch and a positive build number')
    return data
