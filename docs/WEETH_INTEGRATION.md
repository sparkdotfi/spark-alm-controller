# weETH Integration

This document describes the weETH (wrapped eETH) integration with EtherFi, including the WEETHModule architecture and why it's necessary.

## Overview

weETH is EtherFi's wrapped version of eETH (staked ETH). The integration allows the ALM system to deposit ETH into EtherFi's staking system and receive yield-bearing weETH tokens.

## Why a Separate Module is Necessary

The weETH integration requires a dedicated `WEETHModule` contract due to EtherFi's withdrawal architecture:

### The Problem

1. **Withdrawal NFTs:** When requesting a withdrawal from EtherFi, the system doesn't return ETH directly. Instead, it mints a `WithdrawRequestNFT` to the requester.
2. **ALMProxy Limitations:** The ALMProxy cannot receive NFTs safely or process the claim workflow directly.
3. **ETH Handling:** The claim process returns raw ETH, which must be converted to WETH before returning to the ALMProxy.

### The Solution: WEETHModule

The `WEETHModule` acts as an intermediary that:
- Receives the `WithdrawRequestNFT` on behalf of the ALMProxy
- Claims withdrawals when finalized
- Converts received ETH to WETH
- Returns WETH to the ALMProxy

---

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   ALMProxy      │────▶│  WEETHModule     │────▶│   EtherFi       │
│   (WETH holder) │     │  (NFT receiver)  │     │  LiquidityPool  │
└─────────────────┘     └──────────────────┘     └─────────────────┘
        │                       │                        │
        │                       │                        ▼
        │                       │               ┌─────────────────┐
        │                       │◀──────────────│ WithdrawRequest │
        │                       │   (NFT)       │      NFT        │
        │                       │               └─────────────────┘
        │                       │
        │◀──────────────────────│
        │      (WETH)           │
```

## EtherFi Protocol Architecture

Understanding EtherFi's architecture is key to understanding why the module is necessary:

### Core Contracts

| Contract | Purpose |
|----------|---------|
| `weETH` | Wrapped eETH token (ERC-20), yield-bearing |
| `eETH` | Liquid staking token representing staked ETH |
| `LiquidityPool` | Core contract for deposits and withdrawal requests |
| `WithdrawRequestNFT` | NFT representing pending withdrawal requests |

### Token Flow

```
Deposit:  WETH → ETH → LiquidityPool → eETH shares → weETH
Withdraw: weETH → eETH → WithdrawRequestNFT → (wait) → ETH → WETH
```

---

## Operations

### Deposit (WETH → weETH)

**Function:** `MainnetController.depositToWeETH(amount, minSharesOut)`

**Flow:**
1. Unwrap WETH to ETH in ALMProxy
2. Deposit ETH to EtherFi's `LiquidityPool` (returns eETH shares)
3. Convert eETH shares to eETH amount
4. Wrap eETH to weETH
5. weETH remains in ALMProxy

**Rate Limit:** `LIMIT_WEETH_DEPOSIT`

### Request Withdrawal (weETH → NFT)

**Function:** `MainnetController.requestWithdrawFromWeETH(weETHModule, shares)`

**Flow:**
1. Unwrap weETH to eETH in ALMProxy
2. Approve eETH to LiquidityPool
3. Call `LiquidityPool.requestWithdraw()` with WEETHModule as receiver
4. WEETHModule receives the `WithdrawRequestNFT`

**Rate Limit:** `LIMIT_WEETH_REQUEST_WITHDRAW` (keyed by weETHModule address)

**Important:** The withdrawal request is not immediately claimable. EtherFi must finalize the request based on their liquidity and queue position.

### Claim Withdrawal (NFT → WETH)

**Function:** `MainnetController.claimWithdrawalFromWeETH(weETHModule, requestId)`

**Flow:**
1. ALMProxy calls `WEETHModule.claimWithdrawal(requestId)`
2. WEETHModule verifies the request is valid and finalized
3. WEETHModule calls `WithdrawRequestNFT.claimWithdraw(requestId)`
4. WEETHModule receives ETH
5. WEETHModule wraps ETH to WETH
6. WEETHModule transfers WETH to ALMProxy

**Rate Limit:** `LIMIT_WEETH_CLAIM_WITHDRAW` (keyed by weETHModule address)

---

## WEETHModule Contract

### Purpose

The `WEETHModule` is a minimal, upgradeable contract that:
- Holds `WithdrawRequestNFT` tokens on behalf of the ALMProxy
- Processes withdrawal claims
- Converts ETH to WETH

### Key Functions

```solidity
function claimWithdrawal(uint256 requestId) external returns (uint256 ethReceived)
```

**Access:** Only callable by the configured `almProxy`

**Checks:**
- Request must be valid (not already claimed, not invalidated)
- Request must be finalized (EtherFi has processed it)

**Actions:**
1. Claims the withdrawal from the NFT contract
2. Wraps received ETH to WETH
3. Transfers WETH to caller (ALMProxy)

### ERC-721 Receiver

The module implements `onERC721Received` to accept the `WithdrawRequestNFT`:

```solidity
function onERC721Received(address, address, uint256, bytes calldata) 
    external pure returns (bytes4) 
{
    return this.onERC721Received.selector;
}
```

### ETH Receiver

The module has a `receive()` function to accept ETH from the claim process:

```solidity
receive() external payable { }
```

---

## Security Considerations

### Rate Limit Whitelisting

The `weETHModule` address is embedded in the rate limit keys for withdrawal operations:
- `LIMIT_WEETH_REQUEST_WITHDRAW` + weETHModule address
- `LIMIT_WEETH_CLAIM_WITHDRAW` + weETHModule address

This ensures only governance-approved WEETHModule contracts can be used.

### EtherFi Admin Risk

**Risk:** EtherFi admins can invalidate withdrawal requests without returning funds.

**Mitigation:** Requests can also be revalidated. This is an accepted trust assumption for the EtherFi integration.

### Funds Never Stuck in Module

The WEETHModule:
- Only holds NFTs temporarily (between request and claim)
- Immediately converts and transfers WETH on claim
- Cannot accumulate ETH or WETH

---

## Operational Requirements

### Deployment

1. Deploy `WEETHModule` proxy with implementation
2. Initialize with admin and ALMProxy address
3. Configure rate limit keys in MainnetController:
   - `LIMIT_WEETH_DEPOSIT`
   - `makeAddressKey(LIMIT_WEETH_REQUEST_WITHDRAW, weETHModule)`
   - `makeAddressKey(LIMIT_WEETH_CLAIM_WITHDRAW, weETHModule)`

### Monitoring

- Track pending `WithdrawRequestNFT` IDs owned by the WEETHModule
- Monitor finalization status of pending requests
- Alert on requests that remain unfinalized for extended periods

### Checklist

- [ ] Deploy WEETHModule proxy
- [ ] Initialize with correct admin and ALMProxy
- [ ] Configure `LIMIT_WEETH_DEPOSIT` rate limit
- [ ] Configure `LIMIT_WEETH_REQUEST_WITHDRAW` rate limit (keyed by module address)
- [ ] Configure `LIMIT_WEETH_CLAIM_WITHDRAW` rate limit (keyed by module address)
- [ ] Verify module can receive ERC-721 tokens
- [ ] Verify module can receive ETH
