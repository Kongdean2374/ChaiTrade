# Offline world

125 stable `SIM:` IDs: 30 Taiwan-style stocks, 30 US-style stocks, 20 ETF, 20 crypto, 10 forex, 5 perpetual, 5 futures and 5 reference-only indices. These are fictional products and synthetic prices.

FNV-1a identifier mapping and SplitMix64 mixing feed independent common, sector and instrument factors. Interpolated time-scale factors produce correlated trends, mean reversion, volatility regimes and finite spread/depth. Model output is quantized to checked legal ticks before matching. Financial settlement never uses Double.

Authoritative time steps are 5 seconds; candles aggregate the same observed events. A chart query does not consume mutable RNG. Current candles stop at current simulation time. Future control changes begin at the next event and do not alter an already observed quote. Splits add a dated price factor rather than rewriting earlier raw prices.

1/2/5/10/60/100× change simulated elapsed time; matching still processes every event. Catch-up checkpoints at most 300 seconds per transaction, records the corresponding wall anchor, yields progress and can pause. B is frozen while A is active.

Remaining acceptance includes optimized year/month history generation, richer news/participant/market-impact models, detailed event scenarios, official session variants and measured device performance. The existing model is an implemented deterministic world, not a claim that every section-15 behavior has already been accepted.
