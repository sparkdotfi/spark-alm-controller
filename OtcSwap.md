# Offchain Swap Support

This allows the SLL to perform an offchain swap while ensuring some constraints on how much capital has left the system at a time. It is intended to be used to gain access to liquidity from sources such as OTC Desks and exchanges.

The idea is to have funds sent from the ALM Proxy to the offchain destination. This contract will not be able to send any more funds to an exchange until the required balance is returned. You can think of it like a gating mechanism that only allows a maximum `X` of funds to be outside the system, per approved OTC exchange, at any time.

This will provide strong guarantees to Spark/Sky that at most `X` can be stolen/lost, per whitelisted OTC route, while still allowing for rapid throughput into an offchain market with high liquidity such as Binance. Below is a diagram outlining how the system works using Binance as an example.

![Offchain Swap Module](./Offchain%20Swap%20Module.png)

## OTC Swap Conditions

In order for an OTC swap to be performed `isOtcSwapReady(exchange)` must return `true`. This function has two main components:

### Slippage

`maxSlippages` mapped on `exchange`, used in the same way as other parts of the controller. This value calculates a minimum viable amount to be returned from a swap in order for it to be considered complete, so another can be performed.

### Recharge Rate

In the OTC struct, there is a value `rechargeRate` that is expressed in 18 decimals of token per second. This value increases over time after the initial swap is sent. This value is necessary in the case where the exchange does return a material amount of funds but it is below the configured `maxSlippage`. In order to prevent the configuration of the system from bricking swapping functionality, this mechanism allows the OTC swap returned amount to virtually "recharge" over time so that it will eventually get over the required amount.

The equation to determine if an OTC swap is ready is:

$$ claimedAmount + (blockTimestamp - sentTimestamp) \times rechargeRate \ge sentAmount \times maxSlippage $$

## Assumptions

- All whitelisted exchanges or OTC desks have no counterparty risk (i.e. they will asynchronously complete the trade) outside of slippage risks.
- All assets are tracking the same underlying. In other words, there will only be USD stablecoins. The value of these assets are treated the same (i.e. 1 USDT = 1 USDC). No yield-bearing versions, just 1:1.
- Assume that the funds return to the OTC Buffer contract via transfer. This is to accommodate most exchanges/OTC desks that only have the ability to complete the swap by sending token to an address (i.e. not being able to make any arbitrary contracts calls outside of the ERC20 spec).
- The maximum loss by the protocol is limited to the single outstanding OTC swap amount for a given exchange.
- The recharge rate is configured to be low enough that the system will not practically allow for multiple swaps in a row without receiving material funds from the exchange.
