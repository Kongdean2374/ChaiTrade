import Foundation

private struct CatalogEntry {
    var asset:String,symbol:String,name:String,exchange:String,currency:String,sector:String,base:String,tick:String,step:String,price:String,provider:String,multiplier:String
}
public enum InstrumentCatalog {
    public static let version=2
    private static let entries:[CatalogEntry]=[
        CatalogEntry(asset:"taiwanStock",symbol:"2330",name:"台積電",exchange:"TWSE",currency:"TWD",sector:"半導體",base:"2330",tick:"0.01",step:"1",price:"100",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2317",name:"鴻海",exchange:"TWSE",currency:"TWD",sector:"電子",base:"2317",tick:"0.01",step:"1",price:"113",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2454",name:"聯發科",exchange:"TWSE",currency:"TWD",sector:"半導體",base:"2454",tick:"0.01",step:"1",price:"126",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2308",name:"台達電",exchange:"TWSE",currency:"TWD",sector:"電子",base:"2308",tick:"0.01",step:"1",price:"139",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2303",name:"聯電",exchange:"TWSE",currency:"TWD",sector:"半導體",base:"2303",tick:"0.01",step:"1",price:"152",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2412",name:"中華電",exchange:"TWSE",currency:"TWD",sector:"電信",base:"2412",tick:"0.01",step:"1",price:"165",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2881",name:"富邦金",exchange:"TWSE",currency:"TWD",sector:"金融",base:"2881",tick:"0.01",step:"1",price:"178",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2882",name:"國泰金",exchange:"TWSE",currency:"TWD",sector:"金融",base:"2882",tick:"0.01",step:"1",price:"191",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2891",name:"中信金",exchange:"TWSE",currency:"TWD",sector:"金融",base:"2891",tick:"0.01",step:"1",price:"204",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2886",name:"兆豐金",exchange:"TWSE",currency:"TWD",sector:"金融",base:"2886",tick:"0.01",step:"1",price:"217",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2884",name:"玉山金",exchange:"TWSE",currency:"TWD",sector:"金融",base:"2884",tick:"0.01",step:"1",price:"230",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2892",name:"第一金",exchange:"TWSE",currency:"TWD",sector:"金融",base:"2892",tick:"0.01",step:"1",price:"243",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2885",name:"元大金",exchange:"TWSE",currency:"TWD",sector:"金融",base:"2885",tick:"0.01",step:"1",price:"256",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"5880",name:"合庫金",exchange:"TWSE",currency:"TWD",sector:"金融",base:"5880",tick:"0.01",step:"1",price:"269",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2890",name:"永豐金",exchange:"TWSE",currency:"TWD",sector:"金融",base:"2890",tick:"0.01",step:"1",price:"282",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2002",name:"中鋼",exchange:"TWSE",currency:"TWD",sector:"鋼鐵",base:"2002",tick:"0.01",step:"1",price:"295",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"1301",name:"台塑",exchange:"TWSE",currency:"TWD",sector:"塑化",base:"1301",tick:"0.01",step:"1",price:"308",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"1303",name:"南亞",exchange:"TWSE",currency:"TWD",sector:"塑化",base:"1303",tick:"0.01",step:"1",price:"321",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"1326",name:"台化",exchange:"TWSE",currency:"TWD",sector:"塑化",base:"1326",tick:"0.01",step:"1",price:"334",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2603",name:"長榮",exchange:"TWSE",currency:"TWD",sector:"航運",base:"2603",tick:"0.01",step:"1",price:"347",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2609",name:"陽明",exchange:"TWSE",currency:"TWD",sector:"航運",base:"2609",tick:"0.01",step:"1",price:"360",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2615",name:"萬海",exchange:"TWSE",currency:"TWD",sector:"航運",base:"2615",tick:"0.01",step:"1",price:"373",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2618",name:"長榮航",exchange:"TWSE",currency:"TWD",sector:"航空",base:"2618",tick:"0.01",step:"1",price:"386",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2610",name:"華航",exchange:"TWSE",currency:"TWD",sector:"航空",base:"2610",tick:"0.01",step:"1",price:"399",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2357",name:"華碩",exchange:"TWSE",currency:"TWD",sector:"電子",base:"2357",tick:"0.01",step:"1",price:"412",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2382",name:"廣達",exchange:"TWSE",currency:"TWD",sector:"電子",base:"2382",tick:"0.01",step:"1",price:"425",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"3231",name:"緯創",exchange:"TWSE",currency:"TWD",sector:"電子",base:"3231",tick:"0.01",step:"1",price:"438",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"2376",name:"技嘉",exchange:"TWSE",currency:"TWD",sector:"電子",base:"2376",tick:"0.01",step:"1",price:"451",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"3711",name:"日月光投控",exchange:"TWSE",currency:"TWD",sector:"半導體",base:"3711",tick:"0.01",step:"1",price:"464",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"taiwanStock",symbol:"3008",name:"大立光",exchange:"TWSE",currency:"TWD",sector:"電子",base:"3008",tick:"0.01",step:"1",price:"477",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"AAPL",name:"Apple",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"AAPL",tick:"0.01",step:"1",price:"50",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"MSFT",name:"Microsoft",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"MSFT",tick:"0.01",step:"1",price:"57",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"NVDA",name:"NVIDIA",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"NVDA",tick:"0.01",step:"1",price:"64",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"AMZN",name:"Amazon",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"AMZN",tick:"0.01",step:"1",price:"71",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"GOOGL",name:"Alphabet",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"GOOGL",tick:"0.01",step:"1",price:"78",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"META",name:"Meta Platforms",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"META",tick:"0.01",step:"1",price:"85",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"TSLA",name:"Tesla",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"TSLA",tick:"0.01",step:"1",price:"92",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"AVGO",name:"Broadcom",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"AVGO",tick:"0.01",step:"1",price:"99",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"AMD",name:"Advanced Micro Devices",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"AMD",tick:"0.01",step:"1",price:"106",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"INTC",name:"Intel",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"INTC",tick:"0.01",step:"1",price:"113",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"ADBE",name:"Adobe",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"ADBE",tick:"0.01",step:"1",price:"120",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"NFLX",name:"Netflix",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"NFLX",tick:"0.01",step:"1",price:"127",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"COST",name:"Costco",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"COST",tick:"0.01",step:"1",price:"134",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"PEP",name:"PepsiCo",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"PEP",tick:"0.01",step:"1",price:"141",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"CSCO",name:"Cisco",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"CSCO",tick:"0.01",step:"1",price:"148",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"QCOM",name:"Qualcomm",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"QCOM",tick:"0.01",step:"1",price:"155",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"TXN",name:"Texas Instruments",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"TXN",tick:"0.01",step:"1",price:"162",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"AMAT",name:"Applied Materials",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"AMAT",tick:"0.01",step:"1",price:"169",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"INTU",name:"Intuit",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"INTU",tick:"0.01",step:"1",price:"176",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"ISRG",name:"Intuitive Surgical",exchange:"NASDAQ",currency:"USD",sector:"美國企業",base:"ISRG",tick:"0.01",step:"1",price:"183",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"JPM",name:"JPMorgan Chase",exchange:"NYSE",currency:"USD",sector:"美國企業",base:"JPM",tick:"0.01",step:"1",price:"190",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"V",name:"Visa",exchange:"NYSE",currency:"USD",sector:"美國企業",base:"V",tick:"0.01",step:"1",price:"197",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"MA",name:"Mastercard",exchange:"NYSE",currency:"USD",sector:"美國企業",base:"MA",tick:"0.01",step:"1",price:"204",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"BRK.B",name:"Berkshire Hathaway B",exchange:"NYSE",currency:"USD",sector:"美國企業",base:"BRK.B",tick:"0.01",step:"1",price:"211",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"XOM",name:"Exxon Mobil",exchange:"NYSE",currency:"USD",sector:"美國企業",base:"XOM",tick:"0.01",step:"1",price:"218",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"JNJ",name:"Johnson & Johnson",exchange:"NYSE",currency:"USD",sector:"美國企業",base:"JNJ",tick:"0.01",step:"1",price:"225",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"UNH",name:"UnitedHealth Group",exchange:"NYSE",currency:"USD",sector:"美國企業",base:"UNH",tick:"0.01",step:"1",price:"232",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"PG",name:"Procter & Gamble",exchange:"NYSE",currency:"USD",sector:"美國企業",base:"PG",tick:"0.01",step:"1",price:"239",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"KO",name:"Coca-Cola",exchange:"NYSE",currency:"USD",sector:"美國企業",base:"KO",tick:"0.01",step:"1",price:"246",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"usStock",symbol:"DIS",name:"Walt Disney",exchange:"NYSE",currency:"USD",sector:"美國企業",base:"DIS",tick:"0.01",step:"1",price:"253",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"0050",name:"元大台灣50",exchange:"TWSE",currency:"TWD",sector:"ETF",base:"0050",tick:"0.01",step:"1",price:"30",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"0056",name:"元大高股息",exchange:"TWSE",currency:"TWD",sector:"ETF",base:"0056",tick:"0.01",step:"1",price:"33",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"006208",name:"富邦台50",exchange:"TWSE",currency:"TWD",sector:"ETF",base:"006208",tick:"0.01",step:"1",price:"36",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"00878",name:"國泰永續高股息",exchange:"TWSE",currency:"TWD",sector:"ETF",base:"00878",tick:"0.01",step:"1",price:"39",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"00919",name:"群益台灣精選高息",exchange:"TWSE",currency:"TWD",sector:"ETF",base:"00919",tick:"0.01",step:"1",price:"42",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"00929",name:"復華台灣科技優息",exchange:"TWSE",currency:"TWD",sector:"ETF",base:"00929",tick:"0.01",step:"1",price:"45",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"00713",name:"元大台灣高息低波",exchange:"TWSE",currency:"TWD",sector:"ETF",base:"00713",tick:"0.01",step:"1",price:"48",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"00692",name:"富邦公司治理",exchange:"TWSE",currency:"TWD",sector:"ETF",base:"00692",tick:"0.01",step:"1",price:"51",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"00757",name:"統一FANG+",exchange:"TWSE",currency:"TWD",sector:"ETF",base:"00757",tick:"0.01",step:"1",price:"54",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"00646",name:"元大S&P500",exchange:"TWSE",currency:"TWD",sector:"ETF",base:"00646",tick:"0.01",step:"1",price:"57",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"SPY",name:"SPDR S&P 500 ETF Trust",exchange:"NYSE ARCA",currency:"USD",sector:"ETF",base:"SPY",tick:"0.01",step:"1",price:"60",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"QQQ",name:"Invesco QQQ Trust",exchange:"NASDAQ",currency:"USD",sector:"ETF",base:"QQQ",tick:"0.01",step:"1",price:"63",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"VOO",name:"Vanguard S&P 500 ETF",exchange:"NYSE ARCA",currency:"USD",sector:"ETF",base:"VOO",tick:"0.01",step:"1",price:"66",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"VTI",name:"Vanguard Total Stock Market ETF",exchange:"NYSE ARCA",currency:"USD",sector:"ETF",base:"VTI",tick:"0.01",step:"1",price:"69",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"IVV",name:"iShares Core S&P 500 ETF",exchange:"NYSE ARCA",currency:"USD",sector:"ETF",base:"IVV",tick:"0.01",step:"1",price:"72",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"IWM",name:"iShares Russell 2000 ETF",exchange:"NYSE ARCA",currency:"USD",sector:"ETF",base:"IWM",tick:"0.01",step:"1",price:"75",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"DIA",name:"SPDR Dow Jones Industrial Average ETF",exchange:"NYSE ARCA",currency:"USD",sector:"ETF",base:"DIA",tick:"0.01",step:"1",price:"78",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"ARKK",name:"ARK Innovation ETF",exchange:"NYSE ARCA",currency:"USD",sector:"ETF",base:"ARKK",tick:"0.01",step:"1",price:"81",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"GLD",name:"SPDR Gold Shares",exchange:"NYSE ARCA",currency:"USD",sector:"ETF",base:"GLD",tick:"0.01",step:"1",price:"84",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"etf",symbol:"TLT",name:"iShares 20+ Year Treasury Bond ETF",exchange:"NYSE ARCA",currency:"USD",sector:"ETF",base:"TLT",tick:"0.01",step:"1",price:"87",provider:"alpaca",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"BTC-USD",name:"Bitcoin 比特幣",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"BTC",tick:"0.01",step:"0.00000001",price:"50000",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"ETH-USD",name:"Ethereum 以太幣",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"ETH",tick:"0.01",step:"0.00000001",price:"2500",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"SOL-USD",name:"Solana",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"SOL",tick:"0.01",step:"0.00000001",price:"12",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"XRP-USD",name:"XRP",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"XRP",tick:"0.0001",step:"0.000001",price:"13",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"ADA-USD",name:"Cardano",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"ADA",tick:"0.00001",step:"0.00000001",price:"14",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"DOGE-USD",name:"Dogecoin",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"DOGE",tick:"0.00001",step:"0.1",price:"15",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"AVAX-USD",name:"Avalanche",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"AVAX",tick:"0.001",step:"0.00000001",price:"16",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"LINK-USD",name:"Chainlink",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"LINK",tick:"0.001",step:"0.01",price:"17",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"DOT-USD",name:"Polkadot",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"DOT",tick:"0.0001",step:"0.00000001",price:"18",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"LTC-USD",name:"Litecoin",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"LTC",tick:"0.001",step:"0.00000001",price:"19",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"BCH-USD",name:"Bitcoin Cash",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"BCH",tick:"0.01",step:"0.00000001",price:"20",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"ATOM-USD",name:"Cosmos",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"ATOM",tick:"0.0001",step:"0.01",price:"21",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"UNI-USD",name:"Uniswap",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"UNI",tick:"0.0001",step:"0.000001",price:"22",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"AAVE-USD",name:"Aave",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"AAVE",tick:"0.01",step:"0.001",price:"23",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"NEAR-USD",name:"NEAR Protocol",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"NEAR",tick:"0.0001",step:"0.001",price:"24",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"ALGO-USD",name:"Algorand",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"ALGO",tick:"0.00001",step:"0.1",price:"25",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"ICP-USD",name:"Internet Computer",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"ICP",tick:"0.0001",step:"0.0001",price:"26",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"XLM-USD",name:"Stellar",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"XLM",tick:"0.000001",step:"0.00000001",price:"27",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"ETC-USD",name:"Ethereum Classic",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"ETC",tick:"0.001",step:"0.00000001",price:"28",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"crypto",symbol:"FIL-USD",name:"Filecoin",exchange:"Coinbase Exchange",currency:"USD",sector:"數位資產",base:"FIL",tick:"0.0001",step:"0.001",price:"29",provider:"coinbase",multiplier:"1"),
        CatalogEntry(asset:"forex",symbol:"EUR/USD",name:"歐元／美元（自訂模擬合約）",exchange:"參考匯率",currency:"USD",sector:"外匯",base:"EUR",tick:"0.00001",step:"1",price:"1.12",provider:"twelveData",multiplier:"1"),
        CatalogEntry(asset:"forex",symbol:"GBP/USD",name:"英鎊／美元（自訂模擬合約）",exchange:"參考匯率",currency:"USD",sector:"外匯",base:"GBP",tick:"0.00001",step:"1",price:"1.12",provider:"twelveData",multiplier:"1"),
        CatalogEntry(asset:"forex",symbol:"USD/JPY",name:"美元／日圓（自訂模擬合約）",exchange:"參考匯率",currency:"JPY",sector:"外匯",base:"USD",tick:"0.001",step:"1",price:"150",provider:"twelveData",multiplier:"1"),
        CatalogEntry(asset:"forex",symbol:"AUD/USD",name:"澳幣／美元（自訂模擬合約）",exchange:"參考匯率",currency:"USD",sector:"外匯",base:"AUD",tick:"0.00001",step:"1",price:"1.12",provider:"twelveData",multiplier:"1"),
        CatalogEntry(asset:"forex",symbol:"USD/CAD",name:"美元／加幣（自訂模擬合約）",exchange:"參考匯率",currency:"CAD",sector:"外匯",base:"USD",tick:"0.00001",step:"1",price:"1.12",provider:"twelveData",multiplier:"1"),
        CatalogEntry(asset:"forex",symbol:"USD/CHF",name:"美元／瑞郎（自訂模擬合約）",exchange:"參考匯率",currency:"CHF",sector:"外匯",base:"USD",tick:"0.00001",step:"1",price:"1.12",provider:"twelveData",multiplier:"1"),
        CatalogEntry(asset:"forex",symbol:"NZD/USD",name:"紐幣／美元（自訂模擬合約）",exchange:"參考匯率",currency:"USD",sector:"外匯",base:"NZD",tick:"0.00001",step:"1",price:"1.12",provider:"twelveData",multiplier:"1"),
        CatalogEntry(asset:"forex",symbol:"EUR/JPY",name:"歐元／日圓（自訂模擬合約）",exchange:"參考匯率",currency:"JPY",sector:"外匯",base:"EUR",tick:"0.001",step:"1",price:"150",provider:"twelveData",multiplier:"1"),
        CatalogEntry(asset:"forex",symbol:"GBP/JPY",name:"英鎊／日圓（自訂模擬合約）",exchange:"參考匯率",currency:"JPY",sector:"外匯",base:"GBP",tick:"0.001",step:"1",price:"150",provider:"twelveData",multiplier:"1"),
        CatalogEntry(asset:"forex",symbol:"EUR/GBP",name:"歐元／英鎊（自訂模擬合約）",exchange:"參考匯率",currency:"GBP",sector:"外匯",base:"EUR",tick:"0.00001",step:"1",price:"1.12",provider:"twelveData",multiplier:"1"),
        CatalogEntry(asset:"perpetual",symbol:"BTCUSDT",name:"Bitcoin 比特幣 USDT 線性永續（模擬）",exchange:"Binance USDⓈ-M",currency:"USDT",sector:"加密合約",base:"BTC",tick:"0.01",step:"0.001",price:"50000",provider:"binance",multiplier:"1"),
        CatalogEntry(asset:"perpetual",symbol:"ETHUSDT",name:"Ethereum 以太幣 USDT 線性永續（模擬）",exchange:"Binance USDⓈ-M",currency:"USDT",sector:"加密合約",base:"ETH",tick:"0.01",step:"0.001",price:"2500",provider:"binance",multiplier:"1"),
        CatalogEntry(asset:"perpetual",symbol:"SOLUSDT",name:"Solana USDT 線性永續（模擬）",exchange:"Binance USDⓈ-M",currency:"USDT",sector:"加密合約",base:"SOL",tick:"0.01",step:"0.001",price:"100",provider:"binance",multiplier:"1"),
        CatalogEntry(asset:"perpetual",symbol:"XRPUSDT",name:"XRP USDT 線性永續（模擬）",exchange:"Binance USDⓈ-M",currency:"USDT",sector:"加密合約",base:"XRP",tick:"0.01",step:"0.001",price:"100",provider:"binance",multiplier:"1"),
        CatalogEntry(asset:"perpetual",symbol:"ADAUSDT",name:"Cardano USDT 線性永續（模擬）",exchange:"Binance USDⓈ-M",currency:"USDT",sector:"加密合約",base:"ADA",tick:"0.01",step:"0.001",price:"100",provider:"binance",multiplier:"1"),
        CatalogEntry(asset:"future",symbol:"TXF202611",name:"臺股期貨 2026年11月（模擬現金結算）",exchange:"TAIFEX",currency:"TWD",sector:"指數期貨",base:"TXF202611",tick:"1",step:"1",price:"20000",provider:"fugleFutures",multiplier:"200"),
        CatalogEntry(asset:"future",symbol:"MXF202611",name:"小型臺指期貨 2026年11月（模擬現金結算）",exchange:"TAIFEX",currency:"TWD",sector:"指數期貨",base:"MXF202611",tick:"1",step:"1",price:"20000",provider:"fugleFutures",multiplier:"50"),
        CatalogEntry(asset:"future",symbol:"TE202611",name:"電子期貨 2026年11月（模擬現金結算）",exchange:"TAIFEX",currency:"TWD",sector:"指數期貨",base:"TE202611",tick:"0.05",step:"1",price:"20000",provider:"fugleFutures",multiplier:"4000"),
        CatalogEntry(asset:"future",symbol:"TF202611",name:"金融期貨 2026年11月（模擬現金結算）",exchange:"TAIFEX",currency:"TWD",sector:"指數期貨",base:"TF202611",tick:"0.2",step:"1",price:"20000",provider:"fugleFutures",multiplier:"1000"),
        CatalogEntry(asset:"future",symbol:"ESZ6",name:"E-mini S&P 500 2026年12月（模擬現金結算）",exchange:"CME",currency:"USD",sector:"指數期貨",base:"ESZ6",tick:"0.25",step:"1",price:"5000",provider:"",multiplier:"50"),
        CatalogEntry(asset:"index",symbol:"IX0001",name:"臺灣加權指數",exchange:"TWSE",currency:"TWD",sector:"市場指數",base:"IX0001",tick:"0.01",step:"1",price:"20000",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"index",symbol:"IX0039",name:"臺灣電子類指數",exchange:"TWSE",currency:"TWD",sector:"市場指數",base:"IX0039",tick:"0.01",step:"1",price:"20000",provider:"fugle",multiplier:"1"),
        CatalogEntry(asset:"index",symbol:"SPX",name:"S&P 500 指數",exchange:"S&P DJI",currency:"USD",sector:"市場指數",base:"SPX",tick:"0.01",step:"1",price:"5000",provider:"",multiplier:"1"),
        CatalogEntry(asset:"index",symbol:"DJI",name:"道瓊工業指數",exchange:"S&P DJI",currency:"USD",sector:"市場指數",base:"DJI",tick:"0.01",step:"1",price:"5000",provider:"",multiplier:"1"),
        CatalogEntry(asset:"index",symbol:"IXIC",name:"NASDAQ 綜合指數",exchange:"NASDAQ",currency:"USD",sector:"市場指數",base:"IXIC",tick:"0.01",step:"1",price:"5000",provider:"",multiplier:"1"),
    ]
    public static func builtIn(mode:Mode)throws->[Instrument]{
        try entries.map{entry in
            let asset=AssetClass(rawValue:entry.asset)!,provider=ProviderID(rawValue:entry.provider)
            let namespace=entry.exchange.replacingOccurrences(of:" ",with:"_")
            let identifier=mode == .offline ? "SIM:\(namespace):\(entry.symbol)":"\(provider?.rawValue ?? namespace):\(entry.symbol)"
            var rules=try RulePack(tick:Amount(entry.tick),quantityStep:Amount(entry.step))
            rules.version="catalog-sim-2";rules.multiplier=try Amount(entry.multiplier)
            rules.source="ChaiTrade 本機模擬費率與契約；商品身份參考官方目錄，非真實委託服務"
            if entry.exchange=="TWSE"{
                rules.timeZone="Asia/Taipei";rules.weekdaysOnly=true;rules.openMinute=540;rules.closeMinute=810
                if asset != .index{rules.priceTicks=try (asset == .etf ? [("50","0.01"),(nil,"0.05")]:[("10","0.01"),("50","0.05"),("100","0.1"),("500","0.5"),("1000","1"),(nil,"5")]).map{PriceTickBand(below:try $0.0.map(Amount.init),tick:try Amount($0.1))}}
                rules.fees.taker=try Amount("0.001425");rules.fees.maker=rules.fees.taker;rules.fees.minimum=try Amount("1")
                rules.fees.sellTax=try Amount(asset == .etf ? "0.001":"0.003")
                rules.settlementBusinessDays=2;ExchangeCalendarFacts.applyTaiwan(to:&rules)
            }else if [.usStock,.etf].contains(asset) || (asset == .index && entry.currency=="USD"){rules.timeZone="America/New_York";rules.weekdaysOnly=true;rules.openMinute=570;rules.closeMinute=960;rules.settlementBusinessDays=1;ExchangeCalendarFacts.applyUS(to:&rules)}
            if asset == .crypto || asset == .perpetual{rules.fees.taker=try Amount("0.001");rules.fees.maker=try Amount("0.0005")}
            if asset.derivative{
                rules.riskTiers=[RiskTier(upperNotional:try Amount("50000"),initialRate:try Amount("0.05"),maintenanceRate:try Amount("0.005"),maxLeverage:20),RiskTier(upperNotional:try Amount("250000"),initialRate:try Amount("0.1"),maintenanceRate:try Amount("0.01"),maxLeverage:10),RiskTier(upperNotional:nil,initialRate:try Amount("0.2"),maintenanceRate:try Amount("0.025"),maxLeverage:5)]
                rules.collateralFactor = .one
            }
            if mode == .offline,asset == .perpetual{rules.carrySchedule=CarrySchedule(longRate:try Amount("0.0001"),shortRate:try Amount("-0.0001"))}
            if asset == .forex{
                rules.timeZone="America/New_York";rules.sessions=[TradingSession(openMinute:1025,closeMinute:1019,weekdays:[1,2,3,4,5])]
                rules.source+="；本機週盤採紐約週日17:05至週五16:59、每日16:59–17:05休息；參考OANDA一般時段，非全外匯統一制度，節日與NZD額外休息未套用"
                if mode == .offline{rules.carrySchedule=CarrySchedule(interval:86400,longRate:try Amount("0.00005"),shortRate:try Amount("0.00005"),kind:"interest")}
            }
            if asset == .future{rules.expiry=entry.exchange=="CME" ? 1797604200:1794979800;if mode == .offline{rules.dailySettlementMinute=entry.exchange=="CME" ? 960:825};rules.timeZone=entry.exchange=="CME" ? "America/Chicago":"Asia/Taipei"}
            if asset == .future,entry.exchange=="CME"{
                rules.sessions=[TradingSession(openMinute:1020,closeMinute:960,weekdays:[1,2,3,4,5])]
                rules.source+="；CME一般盤芝加哥週日17:00至週五16:00，每日16:00–17:00休息；節日例外須另核對，本機每日結算時點為模擬模型"
            }
            if asset == .future,entry.exchange=="TAIFEX"{
                rules.weekdaysOnly=true;rules.openMinute=525;rules.closeMinute=825
                rules.sessions=[TradingSession(openMinute:525,closeMinute:825),TradingSession(openMinute:900,closeMinute:300)]
                rules.holidays=ExchangeCalendarFacts.taiwanTradingHolidays;rules.calendarYears=[2026]
                rules.source+="；日盤08:45–13:45／夜盤15:00–次日05:00，到期日13:30；節前夜盤例外待核驗"
            }
            var instrument=Instrument(id:identifier,symbol:entry.symbol,name:entry.name,asset:asset,currency:entry.currency,rules:rules,initialPrice:mode == .offline ? try Amount(entry.price):.zero,provider:mode == .online ? provider:nil)
            let market:MarketDomain=[.crypto,.perpetual].contains(asset) ? .crypto:[.forex,.future].contains(asset) ? .other:.stocks
            instrument.identity=InstrumentIdentity(exchange:entry.exchange,market:market,baseAsset:entry.base,unit:asset == .crypto || asset == .perpetual ? entry.base:asset == .forex ? "單位":asset == .future ? "口":asset == .index ? "點":"股",boardLot:entry.exchange=="TWSE" && asset != .index ? 1000:1,sector:entry.sector)
            instrument.identity!.catalogVersion=version
            if entry.exchange=="TAIFEX"{instrument.sourceSymbol=["TXF202611":"TXFK6","MXF202611":"MXFK6","TE202611":"EXFK6","TF202611":"FXFK6"][entry.symbol]}
            if mode == .offline,[.crypto,.perpetual].contains(asset){instrument.liquidity=Int(min(1e12,max(1000,10000/instrument.initialPrice.displayDouble/rules.quantityStep.displayDouble)))}
            if mode == .online && asset == .future{instrument.requiresRuleConfirmation=true}
            return instrument
        }
    }
    /// Additive migration. Legacy SIM IDs retain their original names, rules, prices,
    /// positions and histories; no synthetic old asset is silently relabelled as a company.
    public static func migrate(_ source:AccountState)throws->AccountState{
        var state=source
        guard state.productPreferences?.catalogMigrated != true else{return state}
        let additions=try builtIn(mode:state.mode),known=Set(state.instruments.map(\.id))
        for n in state.instruments.indices{
            if let match=additions.first(where:{$0.id==state.instruments[n].id}){state.instruments[n].identity=match.identity;if state.mode == .online{state.instruments[n].identity!.catalogVersion=0}}
            else if state.mode == .offline,state.instruments[n].identity == nil{
                let old=state.instruments[n]
                var identity=InstrumentIdentity(exchange:"歷史模擬",market:old.market,baseAsset:old.symbol,unit:old.quantityUnit,sector:"歷史商品")
                identity.legacy=true;state.instruments[n].identity=identity
            }
        }
        state.instruments += additions.filter{!known.contains($0.id)}
        if state.productPreferences==nil{state.productPreferences=ProductPreferences()}
        state.productPreferences!.catalogMigrated=true
        return state
    }
}
