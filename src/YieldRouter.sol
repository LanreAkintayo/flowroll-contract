// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPoolAdapter.sol";
import "./interfaces/IPayrollDispatcher.sol";

/**
 * @title YieldRouter
 * @notice Core yield agent contract for Flowroll
 *
 * @dev Design principles:
 *
 *   MULTI-CYCLE: Each caller (employer or EscrowVault) can run multiple
 *   concurrent cycles simultaneously — one per department, team, or schedule.
 *   No single-active-cycle restriction. Agent discovers active cycles off-chain
 *   via getCycleHistory() and calls agentRebalance(caller, cycleId) per cycle.
 *
 *   ADAPTER PATTERN: YieldRouter never talks to real pools directly. Every pool
 *   has a deployed adapter contract implementing IPoolAdapter. Adding a new pool
 *   = write adapter + call addPool(adapterAddress). No YieldRouter changes ever.
 *
 *   PAYDAY HANDOFF: On payday, funds go to PayrollDispatcher via IPayrollDispatcher
 *   interface — not back to caller directly. Dispatcher handles .init username
 *   resolution, cross-chain routing, and employee Auto-Save.
 *
 *   TREASURY ENTRY POINT: In the final design, employers interact with Treasury.sol
 *   which calls into YieldRouter. YieldRouter access control is built with this
 *   in mind — Treasury address is authorised as a caller.
 *
 *   ESCROW VAULT: EscrowVault is treated as a regular caller — no special casing.
 *   It calls startCycle() and agentRebalance() like any employer.
 *
 *   OPENZEPPELIN: Uses Ownable, Pausable, ReentrancyGuard, SafeERC20.
 *
 *   EVENTS-ONLY LOGGING: Agent actions emitted as AgentAction events, never
 *   written to storage. Frontend queries events to reconstruct history.
 *
 *   NO viaIR: Stack depth managed via scoped blocks and lean locals.
 */
contract YieldRouter is Ownable, Pausable, ReentrancyGuard {

    using SafeERC20 for IERC20;

    // ─── Enums ───────────────────────────────────────────────────────────────

    enum ActionType {
        CycleStarted,               // 0: New cycle initiated
        Rebalanced,                 // 1: Funds moved to higher-scoring pool
        BufferAdjusted,             // 2: Buffer increased, funds withdrawn from pools
        MovedToReserve,             // 3: Idle funds moved to reserve (buffer 100%+)
        PoolBelowMinAPY,            // 4: No pool cleared minimum APY floor
        EarlyWithdrawalTriggered,   // 5: Early withdrawal safety trigger fired
        PaydayTriggered,            // 6: Payday — funds sent to PayrollDispatcher
        NoActionNeeded              // 7: Current allocation already optimal
    }

    // ─── Structs ─────────────────────────────────────────────────────────────

    struct PoolEntry {
        address adapterAddress; // IPoolAdapter implementation for this pool
        string  name;
        bool    isStablePair;   // true = no IL risk, false = volatile pair
        bool    isActive;
        uint256 minApyBps;      // Per-pool APY floor override
    }

    struct PayrollCycle {
        uint256 cycleId;            // 1-indexed per caller
        uint256 totalDeposited;     // Original USDC deposit (6 decimals)
        uint256 cycleStartTime;     // Unix timestamp of deposit
        uint256 payDay;             // Unix timestamp of scheduled payday
        uint256 currentAllocation;  // Total shares currently in pools
        uint256 yieldEarned;        // Cumulative yield this cycle (6 decimals)
        bool    isActive;
    }

    // ─── Custom Errors ───────────────────────────────────────────────────────

    error YieldRouter__NotAgent();
    error YieldRouter__NotAuthorizedCaller();
    error YieldRouter__CycleNotFound();
    error YieldRouter__CycleNotActive();
    error YieldRouter__ZeroDeposit();
    error YieldRouter__ZeroDuration();
    error YieldRouter__InvalidPoolIndex();
    error YieldRouter__PoolAlreadyInactive();
    error YieldRouter__ZeroAddress();
    error YieldRouter__InsufficientPoolBalance();
    error YieldRouter__NothingToWithdraw();
    error YieldRouter__DispatcherNotSet();

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant SCALE                 = 10_000;
    uint256 public constant IL_RISK_STABLE        = 10_000; // 1.0 — no IL risk
    uint256 public constant IL_RISK_VOLATILE      = 7_000;  // 0.7 — IL risk present
    uint256 public constant RISK_MULT_HIGH        = 10_000; // 1.0 — >= 20 days left
    uint256 public constant RISK_MULT_MED         = 8_000;  // 0.8 — >= 10 days left
    uint256 public constant RISK_MULT_LOW         = 6_000;  // 0.6 — < 10 days left
    uint256 public constant REBALANCE_THRESHOLD   = 30;     // min score improvement to rebalance
    uint256 public constant MIN_APY_BPS           = 200;    // 2% global APY floor
    uint256 public constant ONE_DAY               = 1 days;
    uint256 public constant EARLY_WITHDRAWAL_DAYS = 1;      // act N days before buffer threshold
    uint256 public constant NO_POOL               = type(uint256).max; // sentinel: no pool

    // ─── Buffer Ladder ───────────────────────────────────────────────────────

    // Days-left thresholds (descending), index-aligned with BUFFER_BPS
    uint256[4] private BUFFER_DAYS = [25, 15, 5, 0];

    // Buffer percentages in basis points
    // Index 0: >= 25 days → 10%  | Index 1: >= 15 days → 40%
    // Index 2: >= 5  days → 105% | Index 3: payday     → 105%
    // 105% is capped at totalDeposited — no revert
    uint256[4] private BUFFER_BPS = [1_000, 4_000, 10_500, 10_500];

    // ─── State ───────────────────────────────────────────────────────────────

    address public immutable usdc;
    address public agentOperator;
    address public payrollDispatcher;
    address public treasury;            // Treasury.sol — authorised caller

    PoolEntry[] public pools;

    // Full cycle history per caller — never overwritten, append-only
    // caller → array of all cycles (active and historical)
    mapping(address => PayrollCycle[]) public cycles;

    // caller → cycleId → poolIndex → shares held in that pool
    // cycleId is 1-indexed so we use cycleId directly (not array index)
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public poolAllocations;

    // ─── Events ──────────────────────────────────────────────────────────────

    event AgentOperatorUpdated(address indexed previous, address indexed updated);
    event PayrollDispatcherSet(address indexed dispatcher);
    event TreasurySet(address indexed treasury);
    event PoolAdded(uint256 indexed poolIndex, address adapterAddress, string name);
    event PoolDeactivated(uint256 indexed poolIndex);

    event CycleStarted(
        address indexed caller,
        uint256 indexed cycleId,
        uint256         totalDeposited,
        uint256         payDay
    );

    event PaydaySettled(
        address indexed caller,
        uint256 indexed cycleId,
        uint256         totalDisbursed,
        uint256         yieldEarned
    );

    /**
     * @notice Emitted on every agent action — single source of truth for history
     * @dev Frontend queries: contract.queryFilter(contract.filters.AgentAction(caller))
     *      Filter by cycleId to get history for a specific cycle.
     */
    event AgentAction(
        address indexed caller,
        uint256 indexed cycleId,
        uint256         cycleDay,
        ActionType      actionType,
        uint256         fromPoolIndex,  // NO_POOL if N/A
        uint256         toPoolIndex,    // NO_POOL if N/A
        uint256         amountMoved,    // 0 if N/A
        uint256         scoreBefore,    // 0 if N/A
        uint256         scoreAfter      // 0 if N/A
    );

    // ─── Modifiers ───────────────────────────────────────────────────────────

    modifier onlyAgent() {
        if (msg.sender != agentOperator && msg.sender != owner())
            revert YieldRouter__NotAgent();
        _;
    }

    /**
     * @notice Restricts direct calls to authorised callers only
     * @dev In final design: Treasury.sol and EscrowVault call startCycle.
     *      Direct employer calls are blocked — they go through Treasury.
     *      During hackathon MVP: owner is also authorised for testing.
     */
    modifier onlyAuthorizedCaller() {
        if (
            msg.sender != treasury &&
            msg.sender != owner()
        ) revert YieldRouter__NotAuthorizedCaller();
        _;
    }

    modifier cycleExists(address caller, uint256 cycleId) {
        if (cycleId == 0 || cycleId > cycles[caller].length)
            revert YieldRouter__CycleNotFound();
        _;
    }

    modifier cycleIsActive(address caller, uint256 cycleId) {
        if (cycleId == 0 || cycleId > cycles[caller].length)
            revert YieldRouter__CycleNotFound();
        if (!cycles[caller][cycleId - 1].isActive)
            revert YieldRouter__CycleNotActive();
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────────

    /**
     * @param _agentOperator Backend agent wallet address
     * @param _usdc          USDC token for this environment
     *                       (MockUSDC locally, real USDC on testnet/mainnet)
     */
    constructor(address _agentOperator, address _usdc) Ownable(msg.sender) {
        if (_agentOperator == address(0)) revert YieldRouter__ZeroAddress();
        if (_usdc          == address(0)) revert YieldRouter__ZeroAddress();
        agentOperator = _agentOperator;
        usdc          = _usdc;
    }

    // ─── Admin ───────────────────────────────────────────────────────────────

    function setAgentOperator(address _agent) external onlyOwner {
        if (_agent == address(0)) revert YieldRouter__ZeroAddress();
        emit AgentOperatorUpdated(agentOperator, _agent);
        agentOperator = _agent;
    }

    /**
     * @notice Set the PayrollDispatcher address
     * @dev Must be set before any cycle can reach payday
     */
    function setPayrollDispatcher(address _dispatcher) external onlyOwner {
        if (_dispatcher == address(0)) revert YieldRouter__ZeroAddress();
        payrollDispatcher = _dispatcher;
        emit PayrollDispatcherSet(_dispatcher);
    }

    /**
     * @notice Set Treasury.sol as the authorised employer-facing entry point
     */
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert YieldRouter__ZeroAddress();
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ─── Pool Management ─────────────────────────────────────────────────────

    /**
     * @notice Register a pool adapter in the whitelist
     * @dev adapterAddress must implement IPoolAdapter.
     *      Environment switching is purely via adapter addresses:
     *        Local    → MockPoolAdapter (wraps MockPool.sol)
     *        Testnet  → real InitiaDEX adapter
     *        Mainnet  → real InitiaDEX adapter
     *      Adding a new pool: write adapter + call addPool(). No router changes.
     */
    function addPool(
        address adapterAddress,
        string calldata name,
        bool isStablePair,
        uint256 minApyBps
    ) external onlyOwner {
        if (adapterAddress == address(0)) revert YieldRouter__ZeroAddress();
        uint256 idx = pools.length;
        pools.push(PoolEntry({
            adapterAddress: adapterAddress,
            name:           name,
            isStablePair:   isStablePair,
            isActive:       true,
            minApyBps:      minApyBps
        }));
        emit PoolAdded(idx, adapterAddress, name);
    }

    function deactivatePool(uint256 poolIndex) external onlyOwner {
        if (poolIndex >= pools.length)   revert YieldRouter__InvalidPoolIndex();
        if (!pools[poolIndex].isActive)  revert YieldRouter__PoolAlreadyInactive();
        pools[poolIndex].isActive = false;
        emit PoolDeactivated(poolIndex);
    }

    function getPoolCount() external view returns (uint256) { return pools.length; }

    function getPool(uint256 poolIndex) external view returns (PoolEntry memory) {
        if (poolIndex >= pools.length) revert YieldRouter__InvalidPoolIndex();
        return pools[poolIndex];
    }

    // ─── Cycle Management ────────────────────────────────────────────────────

    /**
     * @notice Start a new payroll cycle
     * @dev Multiple concurrent cycles allowed per caller — no restriction.
     *      Called by Treasury.sol on behalf of employers, or by EscrowVault directly.
     *      Real USDC pulled from caller into this contract.
     *
     *      Stack safety: scoped blocks keep live locals ≤ 5 at any point.
     *
     * @param employer          The employer address this cycle belongs to
     *                          (Treasury passes the actual employer, not itself)
     * @param totalDeposited    USDC amount to deposit (6 decimals)
     * @param cycleDurationDays Cycle duration in days (typically 30)
     */
    function startCycle(
        address employer,
        uint256 totalDeposited,
        uint256 cycleDurationDays
    ) external onlyAuthorizedCaller whenNotPaused {
        if (totalDeposited    == 0) revert YieldRouter__ZeroDeposit();
        if (cycleDurationDays == 0) revert YieldRouter__ZeroDuration();

        // Block 1: pull USDC from caller (Treasury or EscrowVault)
        {
            IERC20(usdc).safeTransferFrom(msg.sender, address(this), totalDeposited);
        }

        // Block 2: push new cycle — newCycleId and payday survive for emit
        uint256 newCycleId;
        uint256 payday;
        {
            newCycleId = cycles[employer].length + 1;
            payday     = block.timestamp + (cycleDurationDays * ONE_DAY);

            cycles[employer].push(PayrollCycle({
                cycleId:           newCycleId,
                totalDeposited:    totalDeposited,
                cycleStartTime:    block.timestamp,
                payDay:            payday,
                currentAllocation: 0,
                yieldEarned:       0,
                isActive:          true
            }));
        }

        emit CycleStarted(employer, newCycleId, totalDeposited, payday);
        emit AgentAction(
            employer, newCycleId, 1,
            ActionType.CycleStarted,
            NO_POOL, NO_POOL, 0, 0, 0
        );
    }

    // ─── Cycle Getters ───────────────────────────────────────────────────────

    /// @notice Get a specific cycle by cycleId (1-indexed)
    function getCycle(address caller, uint256 cycleId)
        external view cycleExists(caller, cycleId)
        returns (PayrollCycle memory)
    {
        return cycles[caller][cycleId - 1];
    }

    /// @notice Get full cycle history for a caller
    function getCycleHistory(address caller) external view returns (PayrollCycle[] memory) {
        return cycles[caller];
    }

    /// @notice Total cycles ever started by a caller (active + historical)
    function getCycleCount(address caller) external view returns (uint256) {
        return cycles[caller].length;
    }

    /**
     * @notice Get all currently active cycles for a caller
     * @dev Used by the frontend dashboard. Agent uses getCycleHistory() off-chain.
     */
    function getActiveCycles(address caller) external view returns (PayrollCycle[] memory) {
        PayrollCycle[] memory all = cycles[caller];
        uint256 count = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (all[i].isActive) count++;
        }
        PayrollCycle[] memory active = new PayrollCycle[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < all.length; i++) {
            if (all[i].isActive) active[j++] = all[i];
        }
        return active;
    }

    // ─── Buffer Calculation ──────────────────────────────────────────────────

    /**
     * @notice Calculate required buffer for a specific cycle
     * @param caller  Employer or EscrowVault address
     * @param cycleId The specific cycle to calculate buffer for
     * @return bufferAmount Minimum USDC that must stay liquid
     * @return bufferBps    Buffer percentage in basis points
     * @return daysLeft     Days remaining until payday
     */
    function calculateBuffer(address caller, uint256 cycleId)
        public view cycleIsActive(caller, cycleId)
        returns (uint256 bufferAmount, uint256 bufferBps, uint256 daysLeft)
    {
        PayrollCycle memory cycle = cycles[caller][cycleId - 1];

        if (block.timestamp >= cycle.payDay) {
            daysLeft  = 0;
            bufferBps = BUFFER_BPS[3];
        } else {
            daysLeft = (cycle.payDay - block.timestamp) / ONE_DAY;

            // Early withdrawal: behave as if N days closer to payday
            uint256 effective = daysLeft > EARLY_WITHDRAWAL_DAYS
                ? daysLeft - EARLY_WITHDRAWAL_DAYS : 0;

            bufferBps = BUFFER_BPS[3]; // default: max buffer
            for (uint256 i = 0; i < BUFFER_DAYS.length; i++) {
                if (effective >= BUFFER_DAYS[i]) { bufferBps = BUFFER_BPS[i]; break; }
            }
        }

        // Cap at totalDeposited — 105% case handled gracefully
        bufferAmount = (cycle.totalDeposited * bufferBps) / SCALE;
        if (bufferAmount > cycle.totalDeposited) bufferAmount = cycle.totalDeposited;
    }

    /// @notice Calculate idle amount available for yield farming in a specific cycle
    function calculateIdleAmount(address caller, uint256 cycleId)
        public view cycleIsActive(caller, cycleId)
        returns (uint256)
    {
        (uint256 bufferAmount,,) = calculateBuffer(caller, cycleId);
        uint256 total = cycles[caller][cycleId - 1].totalDeposited;
        return total > bufferAmount ? total - bufferAmount : 0;
    }

    // ─── Scoring Formula ─────────────────────────────────────────────────────

    /**
     * @notice Score a pool: APY × LiquidityFactor × RiskMultiplier × ILRiskFactor
     * @dev Stack safety: external adapter reads isolated in Block 1.
     *      APY floor gate in Block 2. Score computation in Block 3.
     */
    function scorePool(uint256 poolIndex, uint256 idleAmount, uint256 daysLeft)
        public view returns (uint256 score)
    {
        if (poolIndex >= pools.length) revert YieldRouter__InvalidPoolIndex();
        PoolEntry memory pool = pools[poolIndex];
        if (!pool.isActive) return 0;

        // Block 1: read from adapter — frees adapter reference before Block 2
        uint256 apyBps;
        uint256 poolTvl;
        {
            IPoolAdapter adapter = IPoolAdapter(pool.adapterAddress);
            apyBps  = adapter.getApyBps();
            poolTvl = adapter.getTvl();
        }

        // Block 2: APY floor gate
        {
            uint256 minApy = pool.minApyBps > MIN_APY_BPS ? pool.minApyBps : MIN_APY_BPS;
            if (apyBps < minApy) return 0;
        }

        // Block 3: compute score — all factors scaled by SCALE (10_000)
        uint256 liqFactor  = (idleAmount == 0 || poolTvl >= idleAmount)
            ? SCALE : (poolTvl * SCALE) / idleAmount;

        uint256 ilFactor   = pool.isStablePair ? IL_RISK_STABLE : IL_RISK_VOLATILE;
        uint256 riskMult   = _getRiskMultiplier(daysLeft);

        score = (apyBps * liqFactor / SCALE * riskMult / SCALE * ilFactor) / SCALE;
    }

    function findBestPool(uint256 idleAmount, uint256 daysLeft)
        public view returns (uint256 bestIdx, uint256 bestScore)
    {
        bestIdx   = NO_POOL;
        bestScore = 0;
        for (uint256 i = 0; i < pools.length; i++) {
            uint256 s = scorePool(i, idleAmount, daysLeft);
            if (s > bestScore) { bestScore = s; bestIdx = i; }
        }
    }

    function findWorstAllocatedPool(address caller, uint256 cycleId, uint256 idleAmount, uint256 daysLeft)
        public view returns (uint256 worstIdx, uint256 worstScore)
    {
        worstIdx   = NO_POOL;
        worstScore = type(uint256).max;
        for (uint256 i = 0; i < pools.length; i++) {
            if (poolAllocations[caller][cycleId][i] == 0) continue;
            uint256 s = scorePool(i, idleAmount, daysLeft);
            if (s < worstScore) { worstScore = s; worstIdx = i; }
        }
    }

    // ─── Agent: Main Rebalance ───────────────────────────────────────────────

    /**
     * @notice Called by agent backend every 6-12 hours for a specific cycle
     *
     * @dev Agent discovery pattern (off-chain, free):
     *      Order of operations (safety always before optimization):
     *        1. Payday     → withdraw all, send to PayrollDispatcher, close cycle
     *        2. Buffer     → cascading withdrawal from worst pools until needed covered
     *        3. No idle    → log MovedToReserve and exit
     *        4. APY floor  → log PoolBelowMinAPY and exit if nothing qualifies
     *        5. Rebalance  → two sub-cases:
     *                        a. Fresh deployment (nothing in pools yet) → deploy directly
     *                        b. Existing allocation → calculate delta, cascade withdraw,
     *                           deploy actual received amount (not assumed amount)
     *
     * @param caller  Employer or EscrowVault whose cycle to rebalance
     * @param cycleId The specific cycle to rebalance
     */
    function agentRebalance(address caller, uint256 cycleId)
        external
        onlyAgent
        whenNotPaused
        nonReentrant
        cycleIsActive(caller, cycleId)
    {
        // Read cycle reference once — used across all steps
        PayrollCycle storage cycle = cycles[caller][cycleId - 1];
        uint256 cycleDay = _getCycleDay(cycle.cycleStartTime);

        // Calculate buffer for this specific cycle
        uint256 bufferAmount;
        uint256 bufferBps;
        uint256 daysLeft;
        (bufferAmount, bufferBps, daysLeft) = calculateBuffer(caller, cycleId);

        uint256 idleAmount = cycle.totalDeposited > bufferAmount
            ? cycle.totalDeposited - bufferAmount : 0;

        // ── Step 1: Payday ───────────────────────────────────────────────────
        if (daysLeft == 0) {
            if (payrollDispatcher == address(0)) revert YieldRouter__DispatcherNotSet();

            _withdrawAllFromPools(caller, cycleId);

            uint256 disbursed   = cycle.totalDeposited;
            uint256 earned      = cycle.yieldEarned;
            cycle.isActive      = false;

            // Transfer to PayrollDispatcher and trigger disbursement
            IERC20(usdc).safeTransfer(payrollDispatcher, disbursed);
            IPayrollDispatcher(payrollDispatcher).disburse(caller, cycleId, disbursed);

            emit PaydaySettled(caller, cycleId, disbursed, earned);
            emit AgentAction(
                caller, cycleId, cycleDay,
                ActionType.PaydayTriggered,
                NO_POOL, NO_POOL, disbursed, 0, 0
            );
            return;
        }

        // ── Step 2: Buffer adjustment — cascading withdrawal ─────────────────
        // Withdraw exactly what's needed from worst pools, one at a time,
        // until the full needed amount is covered. Never withdraw more than needed.
        {
            uint256 deployed = _getTotalDeployed(caller, cycleId);
            if (deployed > idleAmount) {
                uint256 needed    = deployed - idleAmount;
                bool    isEarly   = _isEarlyWithdrawalTrigger(daysLeft);
                ActionType act    = isEarly
                    ? ActionType.EarlyWithdrawalTriggered
                    : ActionType.BufferAdjusted;

                uint256 withdrawn = _cascadeWithdraw(caller, cycleId, needed, idleAmount, daysLeft);

                emit AgentAction(
                    caller, cycleId, cycleDay,
                    act, NO_POOL, NO_POOL, withdrawn, 0, 0
                );
            }
        }

        // ── Step 3: No idle money ────────────────────────────────────────────
        if (idleAmount == 0) {
            emit AgentAction(
                caller, cycleId, cycleDay,
                ActionType.MovedToReserve,
                NO_POOL, NO_POOL, 0, 0, 0
            );
            return;
        }

        // ── Step 4: APY floor check ──────────────────────────────────────────
        uint256 bestIdx;
        uint256 bestScore;
        {
            (bestIdx, bestScore) = findBestPool(idleAmount, daysLeft);
        }

        if (bestIdx == NO_POOL || bestScore == 0) {
            emit AgentAction(
                caller, cycleId, cycleDay,
                ActionType.PoolBelowMinAPY,
                NO_POOL, NO_POOL, idleAmount, 0, 0
            );
            return;
        }

        // ── Step 5: Rebalance or hold ────────────────────────────────────────
        _handleRebalanceOrHold(caller, cycleId, cycleDay, idleAmount, daysLeft, bestIdx, bestScore);
    }

    // ─── Internal: Rebalance Logic ────────────────────────────────────────────

    /**
     * @notice Handles Step 5 — rebalance or hold decision
     * @dev Extracted to keep agentRebalance stack lean.
     *      Two distinct sub-cases:
     *        a. Fresh: no existing allocation → deploy idleAmount directly
     *        b. Existing: already deployed → calculate delta, cascade withdraw,
     *           deploy ACTUAL received amount (not assumed)
     */
    function _handleRebalanceOrHold(
        address caller,
        uint256 cycleId,
        uint256 cycleDay,
        uint256 idleAmount,
        uint256 daysLeft,
        uint256 bestIdx,
        uint256 bestScore
    ) internal {
        uint256 currentScore = _getCurrentAllocationScore(caller, cycleId, idleAmount, daysLeft);

        if (bestScore <= currentScore + REBALANCE_THRESHOLD) {
            // Current allocation is already optimal — hold
            emit AgentAction(
                caller, cycleId, cycleDay,
                ActionType.NoActionNeeded,
                NO_POOL, NO_POOL, 0, currentScore, bestScore
            );
            return;
        }

        uint256 deployed = _getTotalDeployed(caller, cycleId);

        if (deployed == 0) {
            // ── Sub-case A: Fresh deployment ─────────────────────────────────
            // Nothing in pools yet — deploy idle funds directly, no withdrawal needed
            _deployToPool(caller, cycleId, bestIdx, idleAmount);

            emit AgentAction(
                caller, cycleId, cycleDay,
                ActionType.Rebalanced,
                NO_POOL, bestIdx, idleAmount, currentScore, bestScore
            );
        } else {
            // ── Sub-case B: Existing allocation — rebalance ──────────────────
            // Only move the DELTA between current best pool and new best pool.
            // Use actual received amount from withdrawal — never assumed amount.
            uint256 worstIdx;
            uint256 received;
            {
                // Find current worst allocated pool
                (worstIdx,) = findWorstAllocatedPool(caller, cycleId, idleAmount, daysLeft);

                // Only rebalance if worst and best are different pools
                if (worstIdx != NO_POOL && worstIdx != bestIdx) {
                    // Withdraw entire worst position — actual received may differ from shares
                    uint256 shares = poolAllocations[caller][cycleId][worstIdx];
                    if (shares > 0) {
                        received = _withdrawFromPool(caller, cycleId, worstIdx, shares);
                    }
                }
            }

            // Deploy actual received amount to best pool
            // If nothing was received (worst == best or no position), skip
            if (received > 0) {
                _deployToPool(caller, cycleId, bestIdx, received);

                emit AgentAction(
                    caller, cycleId, cycleDay,
                    ActionType.Rebalanced,
                    worstIdx, bestIdx, received, currentScore, bestScore
                );
            } else {
                // Worst and best are same pool — already optimal
                emit AgentAction(
                    caller, cycleId, cycleDay,
                    ActionType.NoActionNeeded,
                    NO_POOL, NO_POOL, 0, currentScore, bestScore
                );
            }
        }
    }

    // ─── Internal: Pool Interactions (Production-Grade) ──────────────────────

    /**
     * @notice Deploy USDC to a pool via its adapter
     * @dev SafeERC20.safeApprove used — works identically with MockPoolAdapter
     *      and real InitiaDEX adapters. Adapter handles all pool-specific logic.
     */
    function _deployToPool(
        address caller,
        uint256 cycleId,
        uint256 poolIndex,
        uint256 amount
    ) internal {
        address adapter = pools[poolIndex].adapterAddress;
        IERC20(usdc).approve(adapter, amount);

        uint256 shares = IPoolAdapter(adapter).deposit(amount);
        poolAllocations[caller][cycleId][poolIndex] += shares;
        cycles[caller][cycleId - 1].currentAllocation += amount;
    }

    /**
     * @notice Withdraw from a pool via its adapter
     * @dev Returns actual amount received — may differ from deposited due to
     *      yield accrual or slippage. Caller must use this value, not assume.
     */
    function _withdrawFromPool(
        address caller,
        uint256 cycleId,
        uint256 poolIndex,
        uint256 shares
    ) internal returns (uint256 received) {
        if (poolAllocations[caller][cycleId][poolIndex] < shares)
            revert YieldRouter__InsufficientPoolBalance();

        received = IPoolAdapter(pools[poolIndex].adapterAddress).withdraw(shares);
        poolAllocations[caller][cycleId][poolIndex] -= shares;

        // Track yield: amount above original allocation is profit
        PayrollCycle storage cycle = cycles[caller][cycleId - 1];
        if (received > cycle.currentAllocation) {
            cycle.yieldEarned      += received - cycle.currentAllocation;
            cycle.currentAllocation = 0;
        } else {
            cycle.currentAllocation -= received;
        }
    }

    /**
     * @notice Cascading withdrawal — withdraw exactly `needed` from worst pools
     * @dev Cuts weakest positions first. Moves to next worst if one pool
     *      doesn't have enough. Stops as soon as `needed` is fully covered.
     *      Never over-withdraws.
     * @return totalWithdrawn Actual total amount withdrawn across all pools
     */
    function _cascadeWithdraw(
        address caller,
        uint256 cycleId,
        uint256 needed,
        uint256 idleAmount,
        uint256 daysLeft
    ) internal returns (uint256 totalWithdrawn) {
        uint256 remaining = needed;

        while (remaining > 0) {
            // Find current worst pool with allocation
            (uint256 worstIdx,) = findWorstAllocatedPool(caller, cycleId, idleAmount, daysLeft);
            if (worstIdx == NO_POOL) break; // nothing left to withdraw

            uint256 shares = poolAllocations[caller][cycleId][worstIdx];
            if (shares == 0) break;

            // Calculate how many shares we need to cover `remaining`
            // Use position value to estimate shares needed
            uint256 positionValue = IPoolAdapter(pools[worstIdx].adapterAddress)
            .sharesToValue(shares);

            uint256 sharesToWithdraw;
            if (positionValue <= remaining) {
                // This pool can't fully cover remaining — withdraw entire position
                sharesToWithdraw = shares;
            } else {
                // This pool has more than enough — withdraw proportional shares
                sharesToWithdraw = (shares * remaining) / positionValue;
                if (sharesToWithdraw == 0) sharesToWithdraw = 1; // avoid dust
            }

            uint256 received = _withdrawFromPool(caller, cycleId, worstIdx, sharesToWithdraw);
            totalWithdrawn  += received;

            if (received >= remaining) {
                remaining = 0;
            } else {
                remaining -= received;
            }
        }
    }

    /// @notice Withdraw all positions across all pools for a cycle
    function _withdrawAllFromPools(address caller, uint256 cycleId) internal {
        for (uint256 i = 0; i < pools.length; i++) {
            uint256 shares = poolAllocations[caller][cycleId][i];
            if (shares > 0) _withdrawFromPool(caller, cycleId, i, shares);
        }
    }

    // ─── Internal: Pure Helpers ───────────────────────────────────────────────

    function _getRiskMultiplier(uint256 daysLeft) internal pure returns (uint256) {
        if (daysLeft >= 20) return RISK_MULT_HIGH;
        if (daysLeft >= 10) return RISK_MULT_MED;
        return RISK_MULT_LOW;
    }

    function _getCycleDay(uint256 cycleStartTime) internal view returns (uint256) {
        return (block.timestamp - cycleStartTime) / ONE_DAY + 1;
    }

    function _getTotalDeployed(address caller, uint256 cycleId)
        internal view returns (uint256 total)
    {
        for (uint256 i = 0; i < pools.length; i++) {
            total += poolAllocations[caller][cycleId][i];
        }
    }

    function _getCurrentAllocationScore(
        address caller,
        uint256 cycleId,
        uint256 idleAmount,
        uint256 daysLeft
    ) internal view returns (uint256 best) {
        for (uint256 i = 0; i < pools.length; i++) {
            if (!pools[i].isActive) continue;
            if (poolAllocations[caller][cycleId][i] > 0) {
                uint256 s = scorePool(i, idleAmount, daysLeft);
                if (s > best) best = s;
            }
        }
    }

    function _isEarlyWithdrawalTrigger(uint256 daysLeft) internal view returns (bool) {
        uint256 adjusted = daysLeft + EARLY_WITHDRAWAL_DAYS;
        for (uint256 i = 0; i < 3; i++) {
            if (adjusted == BUFFER_DAYS[i]) return true;
        }
        return false;
    }
}
