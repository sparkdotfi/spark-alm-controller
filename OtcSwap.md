# Offchain Swap Support

This allows the SLL to perform an offchain swap while ensuring some constraints on how much capital has left the system at a time. It is intended to be used to gain access to liquidity from sources such as OTC Desks and Exchanges.

The initial intended targets are to perform USDC<>USDT swaps via OTC Desk B2C2 and through Binance exchange.

The idea is to have funds sent from the ALM Proxy to the offchain destination. This contract will not be able to send any more funds until the required balance is returned. You can think of it like a gating mechanism that only allows a maximum X of funds to be outside the system at any time.

This will provide strong guarantees to Spark/Sky that at most $X can be stolen/lost while still allowing for rapid throughput into an offchain market with high liquidity such as Binance.

![Offchain Swap Module](./Offchain%20Swap%20Module.png)

## Assumptions

- All assets are tracking the same underlying. IE there will only be USD stablecoins. We treat the value of these assets the same. IE 1 USDT = 1 USDC. No yield-bearing versions, just 1:1.
- Assume that the funds return to the OTC Buffer contract via transfer. This is how most exchanges/OTC do withdrawals by sending to an address.
- The maximum loss by the protocol is limited to `amountIn * maxSlippage + rechargeRate * days`.

### Slippage Assumptions

The system implements slippage protection through the `maxSlippages` mapping, which defines the maximum acceptable slippage for each exchange/pool. Key assumptions include:

- **Slippage Tolerance**: The system typically uses slippage values between 0.98e18 (2% slippage) and 0.9995e18 (0.05% slippage), depending on the exchange and market conditions
- **Exchange-Specific Configuration**: Each exchange has its own `maxSlippage` value that can be set by the admin role
- **Slippage Validation**: Before allowing a swap, the system validates that the minimum amount received meets the slippage threshold: `minAmountOut >= amountIn * maxSlippage / 1e18`
- **OTC-Specific Slippage**: For OTC swaps, the system uses the same slippage mechanism but applies it to the recharge calculation to determine when funds can be claimed

### Recharge Rate Assumptions

The recharge rate mechanism ensures that funds gradually become available for claiming over time, providing a safety mechanism against potential losses:

- **Linear Recharge**: The recharge rate operates linearly over time using the formula: `claimed18 + (block.timestamp - sentTimestamp) * rechargeRate18`
- **Typical Recharge Rate**: The system would typically use a recharge rate of 10bps, though this is configurable per exchange
- **No Ceiling**: There is no upper limit on the recharge amount - it continues to accumulate linearly over time
- **Slippage Integration**: The recharge mechanism works in conjunction with slippage protection - funds can only be claimed when `getOtcClaimWithRecharge(exchange) >= sent18 * maxSlippage / 1e18`
