# DPMC – Dynamic Pricing Market Controller

**Buy on rails.**  
DPMC releases tokens only when paid demand arrives—price rises smoothly, rewards fade fairly, and every purchase streams value to the Fund and Global Shareholding.

🔗 **Demo:** [dpmc.modulexo.com](https://dpmc.modulexo.com)

---

## What is DPMC?

DPMC = an on-rails token release.  
It sells tokens at a mathematically defined price curve while:

- throttling supply to real paid demand,
- mirroring reward decay over time,
- and streaming a slice of every purchase to:
  - **Fund Treasury (umbrella/DAO)**
  - **Global Shareholding**
  - (optional) **Referrer**

No manual levers, no admin tricks—just rails defined before launch.

---

## How it works

### 1. Two rails, one ride
- **Price rail (blue curve):** starts low, accelerates upward.  
- **Reward rail (green curve):** starts high, fades as progress grows.  
*Analogy:* like a ski lift and downhill—early riders climb cheap and glide long; late riders climb faster, glide shorter.

### 2. Area pricing (integral)
You pay the *area under the curve*, not a snapshot price.  
*Analogy:* buying water as a river rises—each extra cm costs a bit more.

### 3. Supply throttle
- If DEX < DPMC → buyers go to DEX, DPMC pauses.  
- If DEX > DPMC → buyers use DPMC, supply releases fairly.  
*Analogy:* a pressure valve between tanks.

### 4. Revenue splits
Every purchase auto-streams native to Fund, Shareholding, (optional) Referrer.  
*Analogy:* every ticket cut at the gate is split instantly with the venue and season ticket holders.

### 5. Locked policy, DAO control
Parameters can be locked; ownership behind timelock/DAO.  
*Analogy:* railway signals run by city hall, not backroom switches.

---

## User & Partner Features

- **Predictable:** see exact tokens/reward before buying.  
- **No oversupply:** tokens only mint on purchase.  
- **Early premium:** early riders get best price + biggest reward.  
- **Transparent:** Fund + Shareholding get paid on-chain every tx.  
- **DEX-friendly:** self-balances with arbitrage, not promises.

---

## Parameters (the dials)

- `P0` / `P1`: start & target price  
- `K`: curve steepness  
- `R0`: initial reward %, `ALPHA`: reward decay  
- `BPS splits`: Fund %, Shareholding %, Referral %

These define the journey up-front. Then lock.

---

## KPIs to Track

- **Adoption & Progress:** progress %, unique/repeat buyers  
- **Market Sync:** spread vs DEX, arb events  
- **Economics:** avg price, reward emitted, Fund/Share inflows  
- **Curve Health:** current price, reward, sensitivity tests  
- **Referral:** volume, top referrers

---

## Quickstart (frontend)

```bash
cd frontend
yarn install   # or npm install
yarn start     # or npm start
