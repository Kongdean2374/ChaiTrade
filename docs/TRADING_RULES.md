# Trading and risk models

All orders are local. Market buys consume asks; sells consume bids. Shadow depth is shared across orders within a source/liquidity event. Limit orders obey their limit. FOK previews the whole available plan; IOC cancels the rest. Post-only rejects a crossing limit. Reduce-only clamps to the remaining position and cannot reverse it.

Stop and trailing triggers retain their reference type. A triggered stop-market uses a new current reference for its 5% protection; a stop-limit can trigger without filling across a gap. DAY/GTD expiration is handled before execution. Amendments validate a candidate copy before changing the original order.

Bracket protection follows the parent fill quantity, subtracts exits, and replaces partial exits with a new protection group. A triggered exit cancels remaining parent quantity. OCO cancels its sibling atomically with first execution.

Gross realized PnL uses weighted average entry. Cash includes fees/taxes exactly once. Derivative notional is not an asset. Isolated/cross positions are limited to the current account and settlement currency. Cross maintenance includes other known cross positions and closing-fee estimates; missing risk prices pause evaluation. Liquidation is a disclosed local mark-settlement model; deficits remain recorded. Hedge mode and exchange-specific tiered liquidation are still unaccepted.

No current official calendar or fee regime is claimed. Rule editors explicitly save custom simulation rules and are blocked while a product has open orders/positions. Taiwan odd-lot/full-lot mechanisms and official rule-pack verification remain outstanding.
