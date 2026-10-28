#!/usr/bin/env python3
import argparse,json,subprocess,sys
from versioning import ROOT,read_version
parser=argparse.ArgumentParser(description='Increment app version and build together, then regenerate Xcode settings')
parser.add_argument('part',choices=['patch','minor','major'],nargs='?',default='patch');args=parser.parse_args()
data=read_version();parts=list(map(int,data['version'].split('.')));index={'major':0,'minor':1,'patch':2}[args.part]
parts[index]+=1
for n in range(index+1,3):parts[n]=0
data={'version':'.'.join(map(str,parts)),'build':data['build']+1}
(ROOT/'version.json').write_text(json.dumps(data,indent=2)+'\n')
subprocess.run([sys.executable,str(ROOT/'scripts/generate_project.py')],check=True)
print('ChaiTrade',data['version'],'build',data['build'])
