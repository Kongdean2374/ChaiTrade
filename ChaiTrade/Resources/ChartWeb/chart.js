'use strict';
let chart,series,volume,lastData,extra=[],priceLines=[],mode='';
const root=document.getElementById('chart'),svg=document.getElementById('drawings');
function instrumentPriceFormat(data){
 const precision=Math.max(0,Math.min(12,Number.isInteger(data.pricePrecision)?data.pricePrecision:2));
 const minMove=Number.isFinite(data.priceTick)&&data.priceTick>0?data.priceTick:10**(-precision);
 return {type:'price',precision,minMove};
}
function displayedPrice(value){return new Intl.NumberFormat('zh-TW',{maximumFractionDigits:instrumentPriceFormat(lastData||{}).precision}).format(value);}
function chartTimeFormat(time,kind,zone){
 if(typeof time!=='number')return `${time.year}-${String(time.month).padStart(2,'0')}-${String(time.day).padStart(2,'0')}`;
 const date=new Date(time*1000);
 const options=kind===0?{year:'numeric'}:kind===1?{year:'numeric',month:'2-digit'}:kind===2?{month:'2-digit',day:'2-digit'}:kind==='full'?{year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}:{hour:'2-digit',minute:'2-digit',hourCycle:'h23'};
 return new Intl.DateTimeFormat('zh-TW',{...options,timeZone:zone||'UTC'}).format(date);
}
function create(data){
 if(chart)chart.remove();
 const font=Math.max(10,Math.min(20,Number(data.fontSize)||12)),zone=data.timeZone||'UTC';
 document.body.style.background=data.dark?'#101318':'#fff';document.body.style.color=data.dark?'#a6b0c0':'#444';
 document.documentElement.style.setProperty('--chart-font',font+'px');
 document.documentElement.style.setProperty('--chart-top',(font+15)+'px');
 document.documentElement.style.setProperty('--chart-bottom',(font+25)+'px');
 document.getElementById('credit').textContent='TradingView Lightweight Charts™ · 模擬交易 · '+zone;

 chart=LightweightCharts.createChart(root,{autoSize:true,handleScroll:{mouseWheel:true,pressedMouseMove:true,horzTouchDrag:true,vertTouchDrag:data.fullscreen===true},handleScale:{axisPressedMouseMove:{time:data.fullscreen===true,price:data.fullscreen===true},mouseWheel:true,pinch:true},layout:{background:{color:data.dark?'#101318':'#fff'},textColor:data.dark?'#a6b0c0':'#444',fontSize:font,attributionLogo:false},grid:{vertLines:{color:'#77777712'},horzLines:{color:'#77777712'}},localization:{locale:"zh-TW",timeFormatter:time=>chartTimeFormat(time,"full",zone)},timeScale:{tickMarkFormatter:(time,kind)=>chartTimeFormat(time,kind,zone),timeVisible:true,secondsVisible:false,borderColor:'#3335'},rightPriceScale:{borderColor:'#3335'},crosshair:{mode:LightweightCharts.CrosshairMode.Normal}});
 const up=data.taiwan?'#e65c66':'#35b792',down=data.taiwan?'#35b792':'#e65c66';
 series=chart.addSeries(data.line?LightweightCharts.LineSeries:LightweightCharts.CandlestickSeries,data.line?{color:'#ffb454',lineWidth:2}:{upColor:up,downColor:down,borderVisible:false,wickUpColor:up,wickDownColor:down});
 volume=chart.addSeries(LightweightCharts.HistogramSeries,{priceFormat:{type:'volume'},priceScaleId:'volume',lastValueVisible:false,priceLineVisible:false});
 volume.priceScale().applyOptions({scaleMargins:{top:0.85,bottom:0}});
 extra=[];priceLines=[];
 chart.subscribeCrosshairMove(param=>{const c=param.seriesData.get(series);if(c){document.getElementById('ohlc').textContent=data.line?`模擬交易 · ${displayedPrice(c.value)}`:`O ${displayedPrice(c.open)}  H ${displayedPrice(c.high)}  L ${displayedPrice(c.low)}  C ${displayedPrice(c.close)}`;}});
 chart.timeScale().subscribeVisibleLogicalRangeChange(draw);
}
window.render=function(data){
 const key=[data.id,data.line,data.taiwan,data.dark,data.timeZone,data.fontSize,data.fullscreen].join('|'),changed=mode!==key;
 if(changed){create(data);mode=key;}
 lastData=data;
 series.applyOptions({priceFormat:instrumentPriceFormat(data)});
 const clean=data.candles.filter(c=>Number.isFinite(c.close)&&c.time>0);
 series.setData(data.line?clean.map(c=>({time:c.time,value:c.close})):clean);
 volume.setData(clean.filter(c=>c.volume!==null&&Number.isFinite(c.volume)).map(c=>({time:c.time,value:c.volume,color:(c.close>=c.open)===!!data.taiwan?'#e65c6638':'#35b79238'})));
 for(const s of extra)chart.removeSeries(s);extra=[];
 for(const o of data.overlays){const s=chart.addSeries(LightweightCharts.LineSeries,{color:o.color,lineWidth:1,priceLineVisible:false,lastValueVisible:false},o.pane||0);s.setData(o.data);extra.push(s);}
 for(const l of priceLines)series.removePriceLine(l);priceLines=[];
 for(const l of data.lines){priceLines.push(series.createPriceLine({price:l.price,color:l.color,lineWidth:1,lineStyle:2,title:l.title,axisLabelVisible:true}));}
 if(changed)chart.timeScale().fitContent();
 draw();
};
function draw(){
 if(!lastData||!series)return;svg.replaceChildren();
 const x=t=>chart.timeScale().timeToCoordinate(t),y=p=>series.priceToCoordinate(p),w=root.clientWidth,h=root.clientHeight;
 function el(tag,attrs){const e=document.createElementNS('http://www.w3.org/2000/svg',tag);for(const[k,v]of Object.entries(attrs))e.setAttribute(k,String(v));svg.append(e);}
 function line(x1,y1,x2,y2,color='#ffb454'){if([x1,y1,x2,y2].every(v=>v!==null&&Number.isFinite(v)))el('line',{x1,y1,x2,y2,stroke:color,'stroke-width':1});}
 for(const d of lastData.drawings){const x1=x(d.time1),x2=x(d.time2),y1=y(d.price1),y2=y(d.price2);
  if(d.kind==='horizontal')line(0,y1,w,y1);
  if(d.kind==='vertical')line(x1,0,x1,h);
  if(d.kind==='trend')line(x1,y1,x2,y2);
  if(d.kind==='rectangle'&&[x1,x2,y1,y2].every(v=>v!==null))el('rect',{x:Math.min(x1,x2),y:Math.min(y1,y2),width:Math.abs(x2-x1),height:Math.abs(y2-y1),fill:'#ffb45416',stroke:'#ffb454'});
  if(d.kind==='fibonacci')for(const ratio of [0,.236,.382,.5,.618,.786,1]){const yy=y(d.price1+(d.price2-d.price1)*ratio);line(x1,yy,x2,yy,'#c792ea');}
 }
}
document.getElementById('reset').onclick=()=>{if(chart)chart.timeScale().fitContent();};
new ResizeObserver(draw).observe(root);
let drag=null;
root.addEventListener('pointerdown',e=>{
 if(!lastData||!series)return;
 const bounds=root.getBoundingClientRect(),yy=e.clientY-bounds.top;
 const hit=lastData.lines.find(l=>l.id&&Math.abs(series.priceToCoordinate(l.price)-yy)<8);
 if(hit){drag={id:hit.id,y:yy};root.setPointerCapture(e.pointerId);e.preventDefault();e.stopImmediatePropagation();}
},true);
root.addEventListener('pointermove',e=>{if(drag){drag.y=e.clientY-root.getBoundingClientRect().top;e.preventDefault();e.stopImmediatePropagation();}},true);
root.addEventListener('pointerup',e=>{
 if(!drag)return;
 const price=series.coordinateToPrice(e.clientY-root.getBoundingClientRect().top),id=drag.id;drag=null;
 e.preventDefault();e.stopImmediatePropagation();
 if(price>0&&Number.isFinite(price)&&window.webkit?.messageHandlers?.intent){window.webkit.messageHandlers.intent.postMessage({type:'amend',account:lastData.account,epoch:lastData.epoch,instrument:lastData.id,orderID:id,price});}
},true);
