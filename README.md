# Flowroll — Smart Contracts

> **Omnichain, yield-bearing payroll and treasury protocol built natively on Initia.**

Flowroll lets employers deposit payroll once. For the entire cycle duration — from setup to payday — an automated yield agent deploys those idle funds into DeFi yield pools on Initia. On payday, the protocol automatically distributes exact salaries to every employee — on any chain they prefer — while returning the generated yield directly to the employer as free revenue. The protocol takes a small fee for doing the work.

Built for **INITIATE: Initia Hackathon Season 1**.

---

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [Architecture](#architecture)
- [Contract Reference](#contract-reference)
  - [YieldRouter](#yieldrouter)
  - [PayrollManager](#payrollmanager)
  - [PayrollDispatcher](#payrolldispatcher)
  - [PayVault](#payvault)
  - [FlowrollCredit](#flowrollcredit)
  - [FlowrollZapper](#flowrollzapper)
  - [MockPool](#mockpool)
  - [MockPoolAdapter](#mockpooladapter)
  - [MockUSDC](#mockusdc)
- [Key Design Decisions](#key-design-decisions)
- [Getting Started](#getting-started)
  - [Smart Contracts](#smart-contracts)
  - [Agent](#agent)
  - [Frontend](#frontend)
  - [Appchain](#appchain)
- [Environment Variables](#environment-variables)
- [Project Structure](#project-structure)
- [Security Considerations](#security-considerations)
- [Acknowledgements](#acknowledgements)

---

## Overview

Traditional crypto payroll forces a binary choice — either your money sits idle in a multisig earning nothing, or you take on complexity and risk to try to put it to work. Flowroll eliminates that tradeoff entirely.

The protocol is built around one core insight: **payroll capital is predictably idle until payday**. Between the moment an employer sets up payroll and payday, those funds can be generating yield. Flowroll automates that process end to end — deposit once, earn yield passively, pay employees on time, and keep the profit.

**For employers:**
- Set up payroll once — add employees with their salaries and set a payday
- Earn yield on idle capital throughout the entire cycle
- Keep generated yield as free revenue on top of normal operations
- The protocol takes a small percentage for doing the work

**For employees:**
- Receive exact salary on payday, on their preferred chain via bridge
- Optional Auto-Save — keep a percentage inside Flowroll to keep earning yield after payday
- Request salary in advance via FlowrollCredit — the requested amount is deducted from their payday payout without affecting the employer's yield

---

## How It Works

```
┌─────────────────────────────────────────────────────────────────────┐
│                        EMPLOYER SIDE                                │
│                                                                     │
│  1. Employer registers and creates a payroll group                  │
│  2. Adds employees (by .init username or wallet address)            │
│     with salaries and sets a payday                                 │
│  3. Calls setupPayroll() → funds flow to YieldRouter                │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                        YIELD FARMING                                │
│                                                                     │
│  4. Agent runs every N minutes (specified by Flowroll)              │
│  5. Scores all registered pools (APY × Liquidity × Risk × IL)       │
│  6. Deploys idle capital to highest-scoring pool via adapter        │
│  7. Rebalances if a significantly better pool appears               │
│  8. Buffer ladder ensures liquidity is always available for payday  │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                      FLOWROLLCREDIT                                 │
│                                                                     │
│  9.  Employee calls requestSalary(amount) to request advance        │
│  10. Employee calls repayDebt() to repay before payday              │
│      (unpaid balance is deducted from payday payout)                │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                           PAYDAY                                    │
│                                                                     │
│  11. Agent detects timeLeft == 0                                    │
│  12. YieldRouter withdraws all from pools                           │
│  13. Sends funds to PayrollDispatcher                               │
│  14. Dispatcher takes protocol fee from yield                       │
│  15. Returns remaining yield to employer                            │
│  16. Credits each employee's salary to PayVault                     │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                        EMPLOYEE SIDE                                │
│                                                                     │
│  17. Employee calls PayVault.claim() to claim full balance, or      │
│      PayVault.claimAndSave(amount, savePct, duration) to save a     │
│      portion and earn yield on it                                   │
│  18. Auto-Save portion → starts new YieldRouter cycle               │
│  19. Remainder → employee wallet                                    │
│  20. Employee bridges to preferred chain via Initia Bridge          │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Architecture

The protocol is composed of four core contracts, two auxiliary contracts, and a suite of local development mocks. Each contract has a single, clearly scoped responsibility.

```
┌──────────────────────────────────────────────────────────────┐
│                      PayrollManager                          │
│          Employer-facing entry point. Manages groups,        │
│          employees, salaries, and cycle lifecycle.           │
└──────────────────────┬───────────────────────────────────────┘
                       │ startCycle() / cancelCycle()
                       ▼
┌──────────────────────────────────────────────────────────────┐
│                       YieldRouter                            │
│       Core yield agent. Manages buffer ladder, pool          │
│       scoring, rebalancing, and payday settlement.           │
└──────────┬──────────────────────────────┬────────────────────┘
           │ deposit() / withdraw()        │ disburse()
           ▼                              ▼
┌─────────────────────┐      ┌───────────────────────────────┐
│   IPoolAdapter      │      │      PayrollDispatcher        │
│   (per pool)        │      │  Splits funds, takes fee,     │
│                     │      │  credits employees.           │
│  MockPoolAdapter    │      └──────────────┬────────────────┘
│  (local dev)        │                     │ credit()
└────────┬────────────┘                     ▼
         │                     ┌────────────────────────────┐
         ▼                     │          PayVault          │
┌─────────────────────┐        │  Employee savings layer.   │
│      MockPool       │        │  claim() or claimAndSave() │
│   (ERC4626 vault)   │        │  into new YieldRouter      │
│   Local dev only    │        │  cycles on employee's      │
└─────────────────────┘        │  behalf.                   │
                               └────────────────────────────┘

┌──────────────────────┐   ┌──────────────────────────────────┐
│   FlowrollCredit     │   │        FlowrollZapper            │
│  Salary advance and  │   │  Entry point for multi-step      │
│  debt repayment.     │   │  token routing and wrapping.     │
└──────────────────────┘   └──────────────────────────────────┘
```

### Adapter Pattern

`YieldRouter` never interacts with pools directly. Every pool has a deployed adapter contract implementing `IPoolAdapter`. This means:

- Adding a new pool = write an adapter + call `addPool()`. Zero changes to `YieldRouter`.
- Switching environments (local → testnet → mainnet) = register a different adapter address. Contract logic unchanged.
- Local development uses `MockPoolAdapter` wrapping `MockPool` (ERC4626).
- Testnet/mainnet will use real `InitiaDEX` adapters.

### Dynamic Buffer System

The buffer ladder is percentage-based, fully owner-configurable, and snapshotted onto each cycle at start time. This means:

- Any cycle duration — hours, days, or months — behaves proportionally.
- Mid-cycle owner config changes never affect running cycles.

Default buffer ladder (6 tiers):

| % of Cycle Remaining | Buffer % of Principal |
|---|---|
| ≥ 70% | 5% |
| ≥ 50% | 10% |
| ≥ 30% | 15% |
| ≥ 25% | 40% |
| ≥ 10% | 80% |
| < 10% (catch-all) | 105% (capped at principal) |

### Scoring Formula

```
Score = APY × LiquidityFactor × RiskMultiplier × ILRiskFactor
```

| Factor | Description |
|---|---|
| `APY` | Pool APY in basis points from adapter |
| `LiquidityFactor` | `min(1, poolTvl / idleAmount)` — penalizes shallow pools |
| `RiskMultiplier` | HIGH / MED / LOW based on % of cycle remaining |
| `ILRiskFactor` | 1.0 for stable pairs, 0.7 for volatile pairs |

---

## Contract Reference

### YieldRouter

**`src/YieldRouter.sol`**

The core yield agent. Employers (via PayrollManager) start cycles here. The off-chain agent calls `agentRebalance()` periodically.

#### Key Functions

| Function | Description |
|---|---|
| `startCycle(employer, totalDeposited, cycleDuration)` | Start a new payroll cycle. Snapshots buffer and risk config. Returns `cycleId`. |
| `cancelCycle(employer, cycleId)` | Cancel a cycle. Only allowed if `idleBalance == totalDeposited` (nothing deployed). |
| `agentRebalance(caller, cycleId)` | Main agent entry point. Handles payday, buffer adjustment, and rebalancing. |
| `calculateBuffer(caller, cycleId)` | Returns `bufferAmount`, `bufferBps`, `timeLeft` for a cycle. |
| `calculateIdleAmount(caller, cycleId)` | Returns USDC available for yield deployment. |
| `scorePool(poolIndex, idleAmount, timeLeft, highRiskThreshold, medRiskThreshold)` | Score a pool for deployment. Returns 0 if inactive or below APY floor. |
| `findBestPool(idleAmount, timeLeft, high, med)` | Returns index and score of the highest-scoring pool. |
| `findWorstAllocatedPool(caller, cycleId, idleAmount, timeLeft, high, med)` | Returns index and score of the lowest-scoring allocated pool. |
| `setBufferConfig(tierPcts, tierBps)` | Owner. Update global buffer config. Only affects future cycles. |
| `setRiskConfig(highPct, medPct)` | Owner. Update risk multiplier thresholds. |
| `addPool(adapterAddress, pool, isStablePair, minApyBps)` | Owner. Register a pool adapter. |
| `deactivatePool(poolIndex)` | Owner. Deactivate a pool from scoring. |

#### Key Structs

```solidity
struct PayrollCycle {
    uint256   cycleId;
    uint256   totalDeposited;
    uint256   cycleStartTime;
    uint256   payDay;
    uint256   cycleDuration;
    uint256[] tierThresholds;       // snapshotted absolute second thresholds
    uint256[] snapshotTierBps;      // snapshotted buffer bps
    uint256   highRiskThreshold;    // snapshotted in seconds
    uint256   medRiskThreshold;     // snapshotted in seconds
    uint256   idleBalance;
    bool      isActive;
    address   dispatcher;
}

struct BufferConfig {
    uint256[] tierPcts; // % of cycleDuration in bps, strictly descending
    uint256[] tierBps;  // buffer bps per tier, strictly ascending
}

struct RiskConfig {
    uint256 highThresholdPct; // % of cycleDuration for RISK_MULT_HIGH
    uint256 medThresholdPct;  // % of cycleDuration for RISK_MULT_MED
}
```

#### Constants

| Constant | Value | Description |
|---|---|---|
| `SCALE` | `10_000` | Basis point denominator |
| `IL_RISK_STABLE` | `10_000` | No IL risk (1.0x) |
| `IL_RISK_VOLATILE` | `7_000` | IL risk present (0.7x) |
| `RISK_MULT_HIGH` | `10_000` | >= highThreshold remaining |
| `RISK_MULT_MED` | `8_000` | >= medThreshold remaining |
| `RISK_MULT_LOW` | `6_000` | < medThreshold remaining |
| `REBALANCE_THRESHOLD` | `30` | Min score improvement to trigger rebalance |
| `MIN_APY_BPS` | `200` | Global 2% APY floor |
| `NO_POOL` | `type(uint256).max` | Sentinel: no pool found |

---

### PayrollManager

**`src/PayrollManager.sol`**

Employer-facing entry point. Manages employer registration, payroll groups, employee schedules, and cycle lifecycle. Employees can be identified by their `.init` username or wallet address — Flowroll resolves both.

#### Key Functions

| Function | Description |
|---|---|
| `registerEmployer()` | Self-registration. Anyone can register. |
| `createGroup(name, cycleDuration)` | Create an independent payroll group. Returns `groupId`. |
| `addEmployee(groupId, employee, salary)` | Add employee by wallet address or `.init` username. Blocked if group has active cycle. |
| `addEmployees(groupId, employees[], salaries[])` | Batch add. |
| `removeEmployee(groupId, employee)` | Remove employee. Blocked if group has active cycle. |
| `removeEmployees(groupId, employees[])` | Batch remove. |
| `updateSalary(groupId, employee, newSalary)` | Update salary. Blocked if group has active cycle. |
| `updateSalaries(groupId, employees[], newSalaries[])` | Batch update. |
| `setupPayroll(groupId)` | Pull USDC from employer and start YieldRouter cycle. Pass-through — no USDC held here. |
| `cancelCycle(groupId)` | Cancel active cycle. Delegates to YieldRouter. Full refund. |

#### Schedule Lock

`addEmployee`, `removeEmployee`, and `updateSalary` (and their batch variants) are all blocked while a group has an active cycle. This prevents `totalPayroll` from drifting out of sync with a running cycle.

#### Lazy Cycle State Reset

PayrollManager does not receive callbacks from YieldRouter. Instead, `_isGroupActive()` lazily checks whether the stored `activeCycleId` is still active in YieldRouter on each interaction. If the cycle has closed, `activeCycleId` is reset to `0` automatically.

---

### PayrollDispatcher

**`src/PayrollDispatcher.sol`**

Called by YieldRouter on payday. Splits the total payout: takes protocol fee from yield, returns remaining yield to employer, and credits each employee's salary to PayVault.

#### Key Functions

| Function | Description |
|---|---|
| `disburse(employer, cycleId, amount)` | Called by YieldRouter on payday. Derives yield from amount, takes fee, distributes. |
| `setPayVault(address)` | Owner. Set PayVault address. |
| `setFeeRecipient(address)` | Owner. |
| `setFeeBps(uint256)` | Owner. Max 20% (2_000 bps). |

#### Payout Calculation

```solidity
uint256 yieldEarned   = amount > totalDeposited ? amount - totalDeposited : 0;
uint256 fee           = (yieldEarned * feeBps) / SCALE;   // → feeRecipient
uint256 employerReturn = yieldEarned - fee;                // → employer wallet
uint256 employeeTotal  = amount > totalDeposited ? totalDeposited : amount;

// For each employee:
share = (salary × employeeTotal) / totalPayroll
PayVault.credit(employee, share)
```

---

### PayVault

**`src/PayVault.sol`**

Employee savings layer. Receives salary credits from PayrollDispatcher. Employees claim when ready, with an optional Auto-Save via `claimAndSave()` that automatically starts a new YieldRouter yield cycle on their behalf.

#### Key Functions

| Function | Description |
|---|---|
| `credit(employee, amount)` | Called by PayrollDispatcher. Adds to employee's claimable balance. |
| `claim(amount)` | Employee claims their full available balance. Transferred to employee wallet. |
| `claimAndSave(amount, savePct, duration)` | Claim with auto-save. The `savePct` portion starts a new YieldRouter cycle for `duration` seconds. Remainder transferred to employee. |
| `disburse(employee, cycleId, amount)` | Called by YieldRouter when an auto-save cycle matures. Credits employee balance. |

#### State

```solidity
struct AutoSaveCycle {
    uint256 cycleId;
    uint256 amountSaved;
    uint256 startTime;
    uint256 duration;
    bool    isActive;
}

mapping(address => uint256)                        private balances;
mapping(address => AutoSaveCycle[])                private autoSaveCycles;
mapping(address => mapping(uint256 => uint256))    private cycleIndex;
mapping(address => mapping(uint256 => bool))       private cycleSettled;
```

---

### FlowrollCredit

**`src/FlowrollCredit.sol`**

Salary advance module. Employees can request a portion of their upcoming salary before payday. Any outstanding debt is deducted from their payday payout automatically, without affecting the employer's yield cycle.

#### Key Functions

| Function | Description |
|---|---|
| `requestSalary(amount)` | Employee requests a salary advance up to their entitled amount. |
| `repayDebt()` | Employee repays their outstanding advance before payday. |

---

### FlowrollZapper

**`src/FlowrollZapper.sol`**

Entry point for multi-step token routing and wrapping operations. Allows users to enter the protocol from non-USDC tokens in a single transaction.

---

### MockPool

**`src/mocks/MockPool.sol`**

ERC4626-based yield vault for local development and testnet. Simulates a real InitiaDEX pool.

Yield simulation works by injecting USDC directly into the vault contract via `simulateYield()`. This inflates `totalAssets()` while `totalSupply()` stays constant — so every share appreciates. When an adapter redeems shares, it gets back more USDC than it deposited. The delta is the yield. No claim functions needed.

| Function | Description |
|---|---|
| `simulateYield(amount)` | Owner mints MockUSDC and transfers into vault. Inflates share price. |
| `setApyBps(uint256)` | Owner. Update reported APY for scoring formula. |
| `getTvl()` | Returns `totalAssets()`. |
| `sharesToValue(shares)` | Returns USDC value of a specific number of shares at current exchange rate. |

---

### MockPoolAdapter

**`src/adapters/MockPoolAdapter.sol`**

Stateless adapter wrapping `MockPool`. Implements `IPoolAdapter`. Used in all local tests and testnet development.

**Zero-balance pattern:** The adapter holds no USDC or shares between transactions. On deposit, USDC flows from YieldRouter → adapter → vault in one transaction. On withdrawal, USDC flows from vault directly to YieldRouter (the ERC4626 `redeem()` receiver parameter handles this).

---

### MockUSDC

**`src/mocks/MockUSDC.sol`**

Minimal ERC20 with 6 decimals and an owner-gated `mint()` function. Mirrors real USDC in decimal precision. Used across all local tests.

---

## Key Design Decisions

### Why ERC4626 for MockPool?

ERC4626 is the standard for tokenized yield vaults. It gives us battle-tested share/asset conversion math, a standardized interface that mirrors real DeFi vaults, and implicit yield accounting — no separate `pendingYield` mappings, no claim functions. Yield is embedded in the exchange rate automatically.

### Why percentage-based buffer tiers?

Hardcoded day thresholds only make sense for one specific cycle duration. Percentage-based thresholds scale automatically — 70% remaining always means 70% regardless of whether the cycle is hours or months.

### Why snapshot configs onto each cycle?

If the owner changes buffer or risk config mid-cycle, running cycles should not be affected. An employer deposited under one set of rules and should be governed by those rules for the lifetime of that cycle. Snapshotting at `startCycle()` provides this guarantee cleanly.

### Why is cross-chain handled on the frontend?

Rather than embedding IBC transfer calls into `PayrollDispatcher`, cross-chain bridging is handled via the Initia bridge widget on the frontend. This avoids dependency on testnet-specific IBC channel IDs, eliminates the need to resolve USDC denom strings on-chain, and produces better UX — employees control when and where they bridge.

### Why does PayVault implement IPayrollDispatcher?

Auto-save cycles in PayVault are YieldRouter cycles started on the employee's behalf. When they mature, YieldRouter calls `disburse()` on whoever is registered as the dispatcher for that cycle. For auto-save cycles, that dispatcher is PayVault itself. PayVault knows which employee owns which cycle from its own mapping, so it credits the right balance directly.

### Why is the agent off-chain?

`agentRebalance()` just needs to be called periodically. The contract responds correctly whenever it is called — it doesn't care when. The timing and scheduling logic lives in an off-chain agent that reads active cycles, checks buffer and pool scores, and calls `agentRebalance()` only when needed. This keeps the contracts clean and gas-efficient.

### Why does FlowrollCredit not affect employer yield?

Salary advances are funded from a separate credit pool, not from the employer's deposited payroll. The employer's cycle continues unaffected. On payday, the outstanding debt is simply deducted from the employee's credited share before it hits their PayVault balance.

---

## Getting Started

### Smart Contracts

#### Prerequisites

- [Foundry](https://getfoundry.sh/) — `curl -L https://foundry.paradigm.xyz | bash`
- [Git](https://git-scm.com/)
- [Weave](https://docs.weave.xyz) — for running a local Initia appchain

#### Installation

```bash
git clone https://github.com/your-org/flowroll-contracts
cd flowroll-contracts
forge install
```

#### Build

```bash
forge build
```

#### Test

Run the full test suite:

```bash
forge test
```

Run a specific test contract:

```bash
forge test --match-contract PayrollManagerTest -vv
```

Run a specific test function:

```bash
forge test --match-test test_startCycle_pullsUSDCFromCaller -vv
```

Run with gas reporting:

```bash
forge test --gas-report
```

Run coverage:

```bash
forge coverage
```

#### Deploy

Deployment is a five-step process: start your appchain, deploy the contracts, fill in your `.env` with the deployed addresses, wire the contracts together, then seed the pools with initial liquidity.

**1. Start your local appchain**

```bash
weave rollup start -d
```

This spins up a local Initia appchain. Wait until it is fully running before proceeding.

**2. Deploy contracts**

```bash
forge script script/Deploy.s.sol \
  --rpc-url $RPC \
  --private-key $TESTNET_PRIVATE_KEY \
  --broadcast
```

The script will print all deployed contract addresses. Copy them into your `.env` before continuing.

**3. Configure your `.env`**

```bash
cp .env.example .env
```

Fill in the deployed addresses printed in the previous step, along with your deployer key and RPC URL. See [Environment Variables](#environment-variables) for the full reference.

**4. Wire the contracts**

Once all addresses are set in `.env`, run:

```bash
chmod +x scripts/wire.sh
./scripts/wire.sh
```

This sets all cross-contract references — YieldRouter, PayrollManager, PayrollDispatcher, PayVault, and FlowrollCredit — and registers the stable and volatile pool adapters.

**5. Seed the pools**

```bash
chmod +x scripts/seed.sh
./scripts/seed.sh
```

Mints MockUSDC, deposits initial TVL into both pools, and funds the Zapper with native token and USDC.

---

**Optional — Simulate yield (testnet/dev only)**

To inflate pool share prices and test the yield flow end to end, run these two scripts in order:

```bash
chmod +x scripts/sh/simulate-yield.sh
./scripts/sh/simulate-yield.sh
```

This mints MockUSDC and injects it directly into both pools via `simulateYield()`, inflating the share price to simulate earned yield.

```bash
chmod +x scripts/sh/change-pool-apys.sh
./scripts/sh/change-pool-apys.sh
```

This sets the reported APY on both pools — stable at 30% (3000 bps) and volatile at 5% (500 bps) — so the agent's scoring formula has realistic values to work with.

> Only use these in local or testnet environments.
---

### Agent

The off-chain rebalance agent is a TypeScript service that monitors active cycles and calls `agentRebalance()` on YieldRouter at the appropriate intervals.

#### Prerequisites

- Node.js >= 18
- `npm` or `yarn`

#### Setup

```bash
cd scripts/agent
npm install
cp .env.example .env
# Fill in your .env values (see Environment Variables)
```

#### Run

```bash
npm start
```

The agent reads its configuration from `config.ts`, maintains state in `agent-state.json`, and writes logs to `agent.log`. Webhook notifications (if configured) are handled by `webhook.ts`.

---

### Frontend

> Setup instructions coming soon.

---

### Appchain

> Setup instructions coming soon.

---

## Environment Variables

Copy `.env.example` to `.env` and fill in the values:

```bash
cp .env.example .env
```

| Variable | Description |
|---|---|
| `NETWORK` | Set to `anvil` or `testnet` |
| `TESTNET_PRIVATE_KEY` | Your testnet deployer private key — never commit this |
| `PK` | Alias for the active private key used by scripts |
| `AGENT_OPERATOR` | Wallet address authorized to call `agentRebalance()` |
| `FEE_RECIPIENT` | Wallet address that receives protocol fees |
| `RPC` | Active RPC URL — set to `ANVIL_RPC_URL` or `TESTNET_RPC_URL` |
| `DEPLOYER` | Your deployer wallet address |
| `MOCK_USDC_ADDRESS` | Deployed MockUSDC contract address |
| `STABLE_POOL_ADDRESS` | Deployed stable MockPool address |
| `VOLATILE_POOL_ADDRESS` | Deployed volatile MockPool address |
| `STABLE_ADAPTER_ADDRESS` | Deployed stable MockPoolAdapter address |
| `VOLATILE_ADAPTER_ADDRESS` | Deployed volatile MockPoolAdapter address |
| `YIELD_ROUTER_ADDRESS` | Deployed YieldRouter address |
| `PAYROLL_MANAGER_ADDRESS` | Deployed PayrollManager address |
| `PAYROLL_DISPATCHER_ADDRESS` | Deployed PayrollDispatcher address |
| `PAY_VAULT_ADDRESS` | Deployed PayVault address |
| `FLOWROLL_CREDIT_ADDRESS` | Deployed FlowrollCredit address |
| `FLOWROLL_ZAPPER_ADDRESS` | Deployed FlowrollZapper address |
| `DEPLOYMENT_BLOCK` | Block number of the deployment — used by the agent |

> Deployed addresses are printed by `forge script script/Deploy.s.sol` — fill them in after running step 2.

---
## Project Structure

```
flowroll-contracts/
├── src/
│   ├── adapters/
│   │   ├── BasePoolAdapter.sol
│   │   └── MockPoolAdapter.sol
│   ├── interfaces/
│   │   ├── IERC20.sol
│   │   ├── IFlowrollCredit.sol
│   │   ├── IPayrollDispatcher.sol
│   │   ├── IPayrollManager.sol
│   │   ├── IPayVault.sol
│   │   ├── IPool.sol
│   │   ├── IPoolAdapter.sol
│   │   └── IYieldRouter.sol
│   ├── mocks/
│   │   ├── MockERC20.sol
│   │   ├── MockPool.sol
│   │   └── MockUSDC.sol
│   ├── FlowrollCredit.sol
│   ├── FlowrollZapper.sol
│   ├── PayrollDispatcher.sol
│   ├── PayrollManager.sol
│   ├── PayVault.sol
│   └── YieldRouter.sol
├── test/
│   ├── base/
│   │   ├── FlowrollCreditBase.t.sol
│   │   ├── PayrollDispatcherBase.t.sol
│   │   ├── PayrollManagerBase.t.sol
│   │   ├── PayVaultBase.t.sol
│   │   ├── SharedBase.t.sol
│   │   └── YieldRouterBase.t.sol
│   └── unit/
│       ├── adapter/
│       │   └── MockAdapterTest.t.sol
│       ├── flowrollcredit/
│       │   └── FlowrollCreditTest.t.sol
│       ├── payrolldispatcher/
│       │   └── PayrollDispatcherTest.t.sol
│       ├── payrollmanager/
│       │   └── PayrollManagerTest.t.sol
│       ├── payVault/
│       │   └── PayVaultTest.t.sol
│       ├── tokens/
│       │   └── FlowrollZapperTest.t.sol
│       └── yieldrouter/
│           ├── YieldRouterAccess.t.sol
│           ├── YieldRouterBuffer.t.sol
│           ├── YieldRouterCycle.t.sol
│           ├── YieldRouterRebalance.t.sol
│           └── YieldRouterScoring.t.sol
├── scripts/
│   └── agent/
│       ├── abis/
│       │   └── YieldRouter.json
│       ├── .env
│       ├── agent-state.json
│       ├── agent.log
│       ├── config.ts
│       ├── discover.ts
│       ├── health.ts
│       ├── index.ts
│       ├── logger.ts
│       ├── package.json
│       ├── package-lock.json
│       ├── rebalance.ts
│       ├── state.ts
│       ├── tsconfig.json
│       ├── types.ts
│       └── webhook.ts
├── lib/
│   ├── forge-std/
│   └── openzeppelin-contracts/
├── foundry.toml
├── .env.example
└── README.md
```

---

## Security Considerations

**Reentrancy:** `agentRebalance()`, `cancelCycle()`, and `setupPayroll()` all use `nonReentrant`. The most sensitive path — payday settlement — marks `cycle.isActive = false` before any external calls.

**Access control:** `agentRebalance()` is restricted to `agentOperator` and `owner`. `startCycle()` and `cancelCycle()` are restricted to `treasury` (PayrollManager) and `owner`. Pool management and config changes are `onlyOwner`.

**Config snapshot isolation:** Buffer and risk configs are snapshotted onto each cycle at `startCycle()`. Owner config changes never affect running cycles.

**Schedule lock:** Employee list and salary mutations in PayrollManager are blocked while a group has an active cycle. This prevents `totalPayroll` from drifting out of sync with a funded cycle.

**Adapter zero-balance:** `MockPoolAdapter` holds no USDC between transactions. This eliminates the adapter as a theft vector.

**APY floor:** Every pool has both a global floor (`MIN_APY_BPS = 200`, 2%) and a per-pool override `minApyBps`. Pools below their effective floor score 0 and are never deployed into.

**Buffer cap:** `bufferAmount` is always capped at `totalDeposited`. The 105% catch-all tier can never return more than the principal.

> ⚠️ These contracts have not been audited. Do not use in production with real funds.

---

## Acknowledgements

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) — ERC4626, ERC20, Ownable, Pausable, ReentrancyGuard, SafeERC20
- [Foundry](https://github.com/foundry-rs/foundry) — Smart contract development framework
- [Initia](https://initia.xyz) — The Interwoven ecosystem this protocol is built for
- [InterwovenKit](https://docs.initia.xyz/interwovenkit/introduction) — Frontend integration toolkit