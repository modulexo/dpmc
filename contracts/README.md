# DPMC – Dynamic Price Modeling Concept (On-Rails Sale)

> **On-rails token release** that prices by the **integral** of a pre-announced curve, mirrors a **decaying reward**, and streams a fixed share of every purchase to the **Fund** and **Global Shareholding** (plus optional referrers). Built with [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts) and [PRBMath](https://github.com/PaulRBerg/prb-math).

---

## Overview

**DPMC** sells a fixed `saleSupply` of ERC-20 tokens along a continuous price curve while releasing supply **only** when buyers pay for it.  
It prevents oversupply and hype dumps by **throttling circulating supply to real demand** and routing a programmable cut of each purchase into ecosystem treasuries (Fund & Shareholding).

- **Contract:** `DPMC.sol` (Solidity ^0.8.20)  
- **Dependencies:**  
  - OpenZeppelin 4.9.x  
  - PRBMath 4.0.x (UD60x18 fixed-point)  
- **Standards:** Ownable2Step, Pausable, ReentrancyGuard

---

## Economics

Let progress be `x ∈ [0,1]`, where:

x = tokensSold / saleSupply


**Price curve**  

p(x) = P0 + (P1 - P0) * (1 - exp(-K * x))

**Reward curve (mirror)**  

r(x) = R0 * (1 - x^ALPHA) // e.g. sqrt mirror when ALPHA = 0.5e18

**ETH charged** (integral pricing):  

ETH = saleSupply * ( I(x1) - I(x0) )

I(x) = P0*x + (P1-P0) * ( x - (1 - exp(-Kx)) / K )


---

## Why this matters

- ✅ **Fair to whales & minnows:** everyone pays the curve integral.  
- ✅ **No oversupply:** supply only mints against real paid demand.  
- ✅ **Early premium:** lower price + higher reward for early buyers.  
- ✅ **On-chain value capture:** Fund + Shareholding streams are automatic.  
- ✅ **DAO-ready:** parameters can be locked; ownership belongs to timelock/governor.

---

## Key Features

- Continuous **exponential price ramp** + mirrored **reward decay**.
- **Integral pricing** using PRBMath UD60x18.
- **Revenue rails** to Fund / Shareholding / Referrer (configurable).
- Safe: **Pausable**, **ReentrancyGuard**, **Ownable2Step**.
- View helpers for UIs:  
  - `price(x)` → price at progress `x`  
  - `rewardFactor(x)` → reward factor at progress `x`

---

## Contract Interface

### Public state
- `token` → ERC20 sold  
- `saleSupply` → total allocated to DPMC  
- `tokensSold` → current progress  
- `P0, P1, K, R0, ALPHA` → curve parameters (UD60x18)  
- `fundTreasury`, `shareholdingTreasury`, `fundBps`, `shareBps`, `referrerBps`  
- `paramsLocked` → freeze status  

### User flows
- `buy()` / `buyWithRef(address)` (payable ETH)  
- `price(uint256 x_ud)` → wei per token at progress `x`  
- `rewardFactor(uint256 x_ud)` → reward multiplier at `x`  

### Admin
- `pause()` / `unpause()`  
- `updateRails(fund, share, fundBps, shareBps, refBps)`  
- `updateCurve(P0,P1,K,R0,ALPHA)` (only before lock)  
- `lockParams()` → freeze economics  
- Rescue functions: `rescueERC20()`, `rescueETH()`  

---

## Parameters & Tuning

| Param   | Description                        | Example     |
|---------|------------------------------------|-------------|
| `P0`    | Initial price (wei per token)      | `1e14` (0.0001 ETH) |
| `P1`    | Target price (wei per token)       | `1e16` (0.01 ETH)   |
| `K`     | Steepness (higher = faster ramp)   | `0.05e18`   |
| `R0`    | Initial reward factor              | `0.50e18` (50%) |
| `ALPHA` | Reward decay power                 | `0.5e18` (sqrt) |

**Rails:**  
- `fundBps` → % to Fund Treasury (e.g., 300 = 3.00%)  
- `shareBps` → % to Shareholding (e.g., 200 = 2.00%)  
- `referrerBps` → % to optional referrer  

---

## Install / Build

### Remix (zero setup)
- Paste `DPMC.sol` into Remix.  
- Compiler: **0.8.20**, Optimizer: **ON (200)**.  
- Imports raw GitHub URLs (OZ 4.9.6, PRBMath 4.0.2).

### Local (Hardhat/Foundry)
```bash
npm install @openzeppelin/contracts @prb/math
# or
yarn add @openzeppelin/contracts @prb/math

Update imports to use package paths:

    import "@openzeppelin/contracts/access/Ownable2Step.sol";
    import "@prb/math/src/UD60x18.sol";
    import "@prb/math/src/ud60x18/Math.sol";


Deploy

DPMC(
  address token,
  uint256 saleSupply,        // e.g. 1_000_000e18
  uint256 P0_weiPerToken,
  uint256 P1_weiPerToken,
  uint256 K_ud,
  uint256 R0_ud,
  uint256 ALPHA_ud,
  address fundTreasury,
  address shareholdingTreasury
)

Steps:

    Deploy with chosen parameters.

    Transfer sale tokens into the contract.

    Configure rails if needed.

    Call lockParams() to freeze.

    Transfer ownership to DAO timelock.


Funding the Sale

    The contract must hold enough tokens to cover saleSupply + rewards.
        A safe start: saleSupply * (1 + R0)

KPIs to Track

    Progress % = tokensSold / saleSupply

    DEX spread = DEX price – DPMC price

    Fund & Shareholding inflows (ETH)

    Reward emitted (cumulative)

    Adoption velocity (time to 25% / 50% / 75%)

    Unique buyers & repeat purchases

Security Notes

    Sale uses Pausable + ReentrancyGuard.

    No mint: contract only transfers pre-funded tokens.

    Binary search solver capped at 60 iterations → ~1e-18 precision.

    Always lock params and DAO-control ownership after setup.

License

MIT © Modulexo

Attribution:

    OpenZeppelin Contracts 4.9.x

    PRBMath 4.0.x

Please keep attribution and share improvements via PRs.
