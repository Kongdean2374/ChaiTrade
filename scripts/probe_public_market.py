"""An optional read-only live probe. Source failures are evidence, never fabricated success."""
import datetime,json,pathlib,urllib.request
result={'checkedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'simulation':'all orders remain local','sources':[]}
for name,url,required in [('Coinbase Exchange','https://api.exchange.coinbase.com/products/BTC-USD/ticker',['time','price','bid','ask']),('Binance public futures','https://fapi.binance.com/fapi/v1/premiumIndex?symbol=BTCUSDT',['markPrice','time'])]:
 try:
  req=urllib.request.Request(url,headers={'User-Agent':'ChaiTrade/1.0 market-data-only'})
  with urllib.request.urlopen(req,timeout=15) as response:
   data=json.load(response)
   if not all(k in data for k in required):raise ValueError('schema mismatch')
   result['sources'].append({'name':name,'status':'passed','http':response.status,'fields':list(data.keys()),'marketValuesRetained':False})
 except Exception as e:result['sources'].append({'name':name,'status':'external-condition-blocked','reason':str(e)})
pathlib.Path('build/logs').mkdir(parents=True,exist_ok=True)
pathlib.Path('build/logs/live-market-probe.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
print(json.dumps(result,ensure_ascii=False,indent=2))
