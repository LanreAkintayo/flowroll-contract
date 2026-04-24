# flowroll-contract

> Smart contracts and off-chain routing agent for the Flowroll protocol.

This repo is a submodule of the [Flowroll monorepo](https://github.com/LanreAkintayo/flowroll). For a full overview of the protocol and instructions to run the entire stack, see the root README there.

---

## Table of Contents

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
- [Environment Variables](#environment-variables)
  - [Agent Environment Variables](#agent-environment-variable)
- [Project Structure](#project-structure)
- [Security Considerations](#security-considerations)

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
uint256 yieldEarned    = amount > totalDeposited ? amount - totalDeposited : 0;
uint256 fee            = (yieldEarned * feeBps) / SCALE;   // → feeRecipient
uint256 employerReturn = yieldEarned - fee;                 // → employer wallet
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

Entry point for multi-step token routing and wrapping operations. Allows users to enter the protocol from non-USDC tokens in a single transaction. This is for the purpose of testing the protocol.

---

### MockPool

**`src/mocks/MockPool.sol`**

ERC4626-based yield vault for local development and testnet to an InitiaDEX pool.

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


### Why is the agent off-chain?

`agentRebalance()` just needs to be called periodically. The contract responds correctly whenever it is called, it doesn't care when. The timing and scheduling logic lives in an off-chain agent that reads active cycles, checks buffer and pool scores, and calls `agentRebalance()` only when needed. This keeps the contracts clean and gas-efficient.

### Why does FlowrollCredit not affect employer yield?

Salary advances are funded from a separate credit pool, not from the employer's deposited payroll. The employer's cycle continues unaffected. On payday, the outstanding debt is simply deducted from the employee's credited share before it hits their PayVault balance.

---

## Getting Started

> If you are running the full Flowroll stack, follow the root monorepo README instead. The instructions below are for working on the contracts or agent in isolation.

### Smart Contracts

#### Prerequisites

- [Foundry](https://getfoundry.sh/) — `curl -L https://foundry.paradigm.xyz | bash`
- [Git](https://git-scm.com/)
- [Weave](https://docs.weave.xyz) — for running a local Initia appchain

#### Installation

```bash
git clone https://github.com/LanreAkintayo/flowroll-contract
cd flowroll-contract
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
forge test --match-test test_createGroup_storesCorrectly
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

Wait until the appchain is fully running before proceeding.

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

Fill in the deployed addresses printed in step 2. See [Environment Variables](#environment-variables) for the full reference.

**4. Wire the contracts**

```bash
chmod +x scripts/sh/wire.sh
./scripts/sh/wire.sh
```

This sets all cross-contract references — YieldRouter, PayrollManager, PayrollDispatcher, PayVault, and FlowrollCredit — and registers the stable and volatile pool adapters.

**5. Seed the pools**

```bash
chmod +x scripts/sh/seed.sh
./scripts/sh/seed.sh
```

Mints MockUSDC, deposits initial TVL into both pools, and funds the Zapper with native token and USDC.

---

**Optional — Simulate yield (dev only)**

To inflate pool share prices and test the yield flow end to end, run these two scripts in order:

```bash
chmod +x scripts/sh/simulate-yield.sh
./scripts/sh/simulate-yield.sh
```

```bash
chmod +x scripts/sh/change-pool-apys.sh
./scripts/sh/change-pool-apys.sh
```

> Only use these in local or testnet environments.

---

### Agent

The off-chain rebalance agent is a TypeScript service that monitors active cycles and calls `agentRebalance()` on YieldRouter at the configured interval.

#### Prerequisites

- Node.js 20+
- npm

#### Setup

```bash
cd scripts/agent
npm install
cp .env.example .env
```

Fill in the values in `.env`. See [Agent Environment Variables](#agent-environment-variable) for the full reference.

#### Run

```bash
npm start
```

The agent reads its configuration from `config.ts`, maintains state in `agent-state.json`, and writes logs to `agent.log`. Webhook notifications (if configured) are handled by `webhook.ts`.

---

## Environment Variables

### Contracts

Copy `.env.example` to `.env` at the repo root and fill in the values:

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

> Deployed addresses are printed by `forge script script/Deploy.s.sol` — fill them in after step 2.

### Agent Environment Variable

Copy `.env.example` to `.env` inside `scripts/agent/` and fill in the values:

```bash
cp scripts/agent/.env.example scripts/agent/.env
```

| Variable | Description |
|---|---|
| `INITIA_EVM_RPC` | RPC endpoint the agent connects to |
| `YIELD_ROUTER_ADDRESS` | Deployed YieldRouter address |
| `AGENT_INTERVAL_MS` | How often the agent runs in milliseconds (default: `30000`) |
| `LOG_LEVEL` | Logging verbosity — `info`, `debug`, or `error` |
| `PRIVATE_KEY` | Private key of the agent operator wallet — never commit this |
| `AGENT_OPERATOR` | Wallet address of the agent operator |
| `FEE_RECIPIENT` | Wallet address that receives protocol fees |
| `HEALTH_PORT` | Port for the agent health check endpoint (default: `3001`) |
| `WEBHOOK_URL` | Discord or Telegram webhook URL for notifications (optional) |
| `WEBHOOK_TYPE` | Webhook platform — `discord` or `telegram` (optional) |
| `MAX_RETRIES` | Max retry attempts on failed transactions (default: `2`) |
| `RETRY_DELAY_MS` | Delay between retries in milliseconds (default: `2000`) |

---

## Project Structure

```
flowroll-contract/
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
│   ├── sh/
│   │   ├── wire.sh
│   │   ├── seed.sh
│   │   ├── simulate-yield.sh
│   │   └── change-pool-apys.sh
│   └── agent/
│       ├── abis/
│       │   └── YieldRouter.json
│       ├── .env.example
│       ├── config.ts
│       ├── discover.ts
│       ├── health.ts
│       ├── index.ts
│       ├── logger.ts
│       ├── package.json
│       ├── rebalance.ts
│       ├── state.ts
│       ├── tsconfig.json
│       ├── types.ts
│       └── webhook.ts
├── script/
│   └── Deploy.s.sol
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