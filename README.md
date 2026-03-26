# Treasury.init — Yield Agent

## Overview

The yield agent is the autonomous engine of Treasury.init. It takes idle payroll capital and deploys it into curated DeFi pools on InitiaDEX, earning yield for the employer while guaranteeing full salary disbursement on payday.

---

## Architecture

```
YieldRouter.sol          ← Core smart contract (Solidity, Initia EVM)
MockPool.sol             ← Mock InitiaDEX pools for testnet dev
agent/agent.js           ← Backend agent script (Node.js, ethers.js v6)
script/Deploy.s.sol      ← Foundry deployment script
test/YieldRouter.t.sol   ← Foundry unit tests
```

---

## Buffer Ladder

The agent never risks the payroll principal. A safety buffer is maintained based on days left until payday:

| Days Left | Buffer % | Example ($50k payroll) | Idle for Yield |
|-----------|----------|------------------------|----------------|
| 25+       | 10%      | $5,000                 | $45,000        |
| 15        | 40%      | $20,000                | $30,000        |
| 5         | 105%     | $50,000 (capped)       | ~$0            |
| 0         | 105%     | $50,000 (capped)       | $0             |

**Early withdrawal trigger:** Buffer is adjusted 1 day early to guarantee liquidity.

---

## Scoring Formula

Every run, the agent scores available pools:

```
Score = APY × LiquidityFactor × RiskMultiplier × ILRiskFactor
```

| Component       | Description                                      | Range      |
|----------------|--------------------------------------------------|------------|
| APY             | Current pool APY in basis points                 | Real data  |
| LiquidityFactor | min(1, Pool TVL / Idle Amount)                  | 0.0 – 1.0  |
| RiskMultiplier  | Decreases as payday approaches (1.0 → 0.6)      | 0.6 – 1.0  |
| ILRiskFactor    | 1.0 for stable pairs, 0.7 for volatile pairs    | 0.7 or 1.0 |

**Rebalance threshold:** Only rebalances if score improvement > 0.3 points (gas cost equivalent).

**Minimum APY floor:** If no pool clears 2% APY, all funds move to reserve.

---

## Pool Whitelist

For MVP (hackathon scope), pools are manually curated:

| Pool              | Type     | Est. APY | IL Risk |
|-------------------|----------|----------|---------|
| USDC-iUSD Stable  | Stable   | 8%       | None    |
| USDC-INIT Weighted| Volatile | 12%      | Present |
| Super Safe Reserve| Stable   | 4%       | None    |

> Phase 2: Dynamic pool discovery from InitiaDEX registry.

---

## Setup

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install forge-std
forge install foundry-rs/forge-std

# Install Node dependencies
npm install

# Copy and fill environment variables
cp .env.example .env
```

---

## Run Tests

```bash
forge test -vv
```

For full simulation with console output:

```bash
forge test -vvv --match-test test_Full30DayCycleSimulation
```

---

## Deploy to Initia Testnet

```bash
forge script script/Deploy.s.sol \
  --rpc-url $INITIA_RPC_URL \
  --broadcast \
  --private-key $DEPLOYER_KEY
```

After deployment, copy the printed addresses into your `.env` file.

---

## Run the Agent

```bash
# Run once
npm run agent

# Run on 6-hour schedule
npm run agent:loop

# Demo mode: simulate full 30-day cycle
npm run agent:simulate
```

---

## On-Chain Logging

Every agent action is logged on-chain with a plain-English description:

```
"Day 15: Buffer increased to 40%. Withdrew $15,000 from USDC-INIT Weighted 
for safety and rebalanced $30,000 to USDC-iUSD Stable."
```

These logs power the AI Insights box on the employer dashboard.

---

## Principal Protection Guarantee

- Buffer always ≥ total payroll amount near payday
- Only stable pools eligible when Risk Multiplier is low
- IL Risk Factor penalizes volatile pairs in scoring
- Early withdrawal trigger provides 24h liquidity cushion
- Minimum APY floor prevents deployment into dead pools
