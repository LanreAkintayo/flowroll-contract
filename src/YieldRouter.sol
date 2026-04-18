// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolAdapter} from "./interfaces/IPoolAdapter.sol";
import {IPayrollDispatcher} from "./interfaces/IPayrollDispatcher.sol";

/**
 * @title YieldRouter
 * @notice Core yield agent contract for Flowroll.
 * @dev Manages independent payroll cycles, pool allocations via adapters, and agent-driven rebalancing.
 */
contract YieldRouter is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- ENUMS ---

    enum ActionType {
        CycleStarted,
        Rebalanced,
        BufferAdjusted,
        MovedToReserve,
        PoolBelowMinAPY,
        PaydayTriggered,
        NoActionNeeded
    }

    // --- STRUCTS ---

    struct BufferConfig {
        uint256[] tierPcts;
        uint256[] tierBps;
    }

    struct RiskConfig {
        uint256 highThresholdPct;
        uint256 medThresholdPct;
    }

    struct PoolEntry {
        address adapterAddress;
        address pool;
        bool isStablePair;
        bool isActive;
        uint256 minApyBps;
    }

    struct PayrollCycle {
        uint256 cycleId;
        uint256 totalDeposited;
        uint256 cycleStartTime;
        uint256 payDay;
        uint256 cycleDuration;
        uint256[] tierThresholds;
        uint256[] snapshotTierBps;
        uint256 highRiskThreshold;
        uint256 medRiskThreshold;
        uint256 idleBalance;
        bool isActive;
        address dispatcher;
    }

    // --- ERRORS ---

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
    error YieldRouter__DispatcherNotSet();
    error YieldRouter__InvalidBufferConfig();
    error YieldRouter__InvalidRiskConfig();
    error YieldRouter__CycleNotCancellable();
    error YieldRouter__PoolAlreadyExists();

    // --- EVENTS ---

    event AgentOperatorUpdated(address indexed previous, address indexed updated);
    event PayrollDispatcherSet(address indexed dispatcher);
    event TreasurySet(address indexed treasury);
    event PayVaultSet(address indexed vault);
    event PayrollManagerSet(address indexed payrollManager);
    event BufferConfigUpdated();
    event PoolAdded(uint256 indexed poolIndex, address adapterAddress, address poolAddress);
    event PoolDeactivated(uint256 indexed poolIndex);
    event CycleStarted(address indexed caller, uint256 indexed cycleId, uint256 totalDeposited, uint256 payDay);
    event PaydaySettled(address indexed caller, uint256 indexed cycleId, uint256 totalDisbursed, uint256 yieldEarned);
    event AgentAction(address indexed caller, uint256 indexed cycleId, uint256 timeIntoCycle, ActionType indexed actionType, uint256 fromPoolIndex, uint256 toPoolIndex, uint256 amountMoved, uint256 scoreBefore, uint256 scoreAfter);
    event RiskConfigUpdated(uint256 indexed highPct, uint256 indexed medPct);
    event CycleCancelled(address indexed caller, uint256 indexed cycleId, uint256 amountReturned);

    // --- STATE VARIABLES ---

    uint256 public constant SCALE = 10_000;
    uint256 public constant IL_RISK_STABLE = 10_000;
    uint256 public constant IL_RISK_VOLATILE = 7_000;
    uint256 public constant RISK_MULT_HIGH = 10_000;
    uint256 public constant RISK_MULT_MED = 8_000;
    uint256 public constant RISK_MULT_LOW = 6_000;
    uint256 public constant REBALANCE_THRESHOLD = 30;
    uint256 public constant MIN_APY_BPS = 200;
    uint256 public constant NO_POOL = type(uint256).max;

    address public immutable USDC;
    address public agentOperator;
    address public payVault;
    address public payrollManager;

    PoolEntry[] public pools;
    BufferConfig bufferConfig;
    RiskConfig riskConfig;

    mapping(address => PayrollCycle[]) public cycles;
    mapping(address caller => mapping(uint256 cycleId => mapping(uint256 poolIndex => uint256))) public poolAllocations;
    mapping(address => bool) public poolExists;

    // --- MODIFIERS ---

    modifier onlyAgent() {
        _onlyAgent();
        _;
    }

    modifier onlyAuthorizedCaller() {
        _onlyAuthorizedCaller();
        _;
    }

    modifier cycleExists(address caller, uint256 cycleId) {
        _cycleExists(caller, cycleId);
        _;
    }

    modifier cycleIsActive(address caller, uint256 cycleId) {
        _cycleIsActive(caller, cycleId);
        _;
    }

    // --- CONSTRUCTOR ---

    /**
     * @param _agentOperator Backend agent wallet.
     * @param _usdc USDC token address for this environment.
     */
    constructor(address _agentOperator, address _usdc) Ownable(msg.sender) {
        if (_agentOperator == address(0) || _usdc == address(0)) revert YieldRouter__ZeroAddress();

        agentOperator = _agentOperator;
        USDC = _usdc;

        uint256[] memory defaultPcts = new uint256[](6);
        defaultPcts[0] = 7_000;
        defaultPcts[1] = 5_000;
        defaultPcts[2] = 3_000;
        defaultPcts[3] = 2_500;
        defaultPcts[4] = 1_000;
        defaultPcts[5] = 0;

        uint256[] memory defaultBps = new uint256[](6);
        defaultBps[0] = 500;
        defaultBps[1] = 1_000;
        defaultBps[2] = 1_500;
        defaultBps[3] = 4_000;
        defaultBps[4] = 10_000;
        defaultBps[5] = 10_500;

        bufferConfig = BufferConfig({
            tierPcts: defaultPcts,
            tierBps: defaultBps
        });

        riskConfig = RiskConfig({
            highThresholdPct: 6_000,
            medThresholdPct: 3_000
        });
    }

    // --- EXTERNAL ---

    function setAgentOperator(address _agent) external onlyOwner {
        if (_agent == address(0)) revert YieldRouter__ZeroAddress();
        emit AgentOperatorUpdated(agentOperator, _agent);
        agentOperator = _agent;
    }

    function setPayVault(address _payVault) external onlyOwner {
        if (_payVault == address(0)) revert YieldRouter__ZeroAddress();
        payVault = _payVault;
        emit PayVaultSet(_payVault);
    }

    function setPayrollManager(address _payrollManager) external onlyOwner {
        if (_payrollManager == address(0)) revert YieldRouter__ZeroAddress();
        payrollManager = _payrollManager;
        emit PayrollManagerSet(_payrollManager);
    }

    /**
     * @notice Updates the global buffer configuration.
     * @dev Does not affect actively running cycles.
     */
    function setBufferConfig(
        uint256[] calldata tierPcts,
        uint256[] calldata tierBps
    ) external onlyOwner {
        if (tierPcts.length == 0) revert YieldRouter__InvalidBufferConfig();
        if (tierBps.length != tierPcts.length) revert YieldRouter__InvalidBufferConfig();
        if (tierPcts[tierPcts.length - 1] != 0) revert YieldRouter__InvalidBufferConfig();

        for (uint256 i = 1; i < tierPcts.length; i++) {
            if (tierPcts[i] >= tierPcts[i - 1]) revert YieldRouter__InvalidBufferConfig();
        }
        for (uint256 i = 1; i < tierBps.length; i++) {
            if (tierBps[i] <= tierBps[i - 1]) revert YieldRouter__InvalidBufferConfig();
        }

        bufferConfig.tierPcts = tierPcts;
        bufferConfig.tierBps = tierBps;

        emit BufferConfigUpdated();
    }

    function setRiskConfig(uint256 highPct, uint256 medPct) external onlyOwner {
        if (highPct <= medPct) revert YieldRouter__InvalidRiskConfig();
        if (medPct == 0) revert YieldRouter__InvalidRiskConfig();
        riskConfig.highThresholdPct = highPct;
        riskConfig.medThresholdPct = medPct;
        emit RiskConfigUpdated(highPct, medPct);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function addPool(
        address adapterAddress,
        address pool,
        bool isStablePair,
        uint256 minApyBps
    ) external onlyOwner {
        if (adapterAddress == address(0) || pool == address(0)) revert YieldRouter__ZeroAddress();
        if (poolExists[pool]) revert YieldRouter__PoolAlreadyExists();

        uint256 idx = pools.length;
        pools.push(
            PoolEntry({
                adapterAddress: adapterAddress,
                pool: pool,
                isStablePair: isStablePair,
                isActive: true,
                minApyBps: minApyBps
            })
        );

        poolExists[pool] = true;
        emit PoolAdded(idx, adapterAddress, pool);
    }

    function deactivatePool(uint256 poolIndex) external onlyOwner {
        if (poolIndex >= pools.length) revert YieldRouter__InvalidPoolIndex();
        if (!pools[poolIndex].isActive) revert YieldRouter__PoolAlreadyInactive();
        
        pools[poolIndex].isActive = false;
        emit PoolDeactivated(poolIndex);
    }

    /**
     * @notice Starts a new payroll cycle and snapshots the active configuration.
     */
    function startCycle(
        address employer,
        uint256 totalDeposited,
        uint256 cycleDuration,
        address dispatcher
    ) external onlyAuthorizedCaller whenNotPaused returns (uint256 cycleId) {
        if (totalDeposited == 0) revert YieldRouter__ZeroDeposit();
        if (cycleDuration == 0) revert YieldRouter__ZeroDuration();

        IERC20(USDC).safeTransferFrom(msg.sender, address(this), totalDeposited);

        BufferConfig storage config = bufferConfig;
        uint256 tierCount = config.tierPcts.length;

        uint256[] memory tierThresholds = new uint256[](tierCount);
        for (uint256 i = 0; i < tierCount; i++) {
            tierThresholds[i] = (cycleDuration * config.tierPcts[i]) / SCALE;
        }

        uint256[] memory snapshotTierBps = new uint256[](config.tierBps.length);
        for (uint256 i = 0; i < config.tierBps.length; i++) {
            snapshotTierBps[i] = config.tierBps[i];
        }

        uint256 newCycleId = cycles[employer].length + 1;
        uint256 payday = block.timestamp + cycleDuration;

        uint256 highRiskThreshold = (cycleDuration * riskConfig.highThresholdPct) / SCALE;
        uint256 medRiskThreshold = (cycleDuration * riskConfig.medThresholdPct) / SCALE;

        cycles[employer].push(
            PayrollCycle({
                cycleId: newCycleId,
                totalDeposited: totalDeposited,
                cycleStartTime: block.timestamp,
                payDay: payday,
                cycleDuration: cycleDuration,
                tierThresholds: tierThresholds,
                highRiskThreshold: highRiskThreshold,
                medRiskThreshold: medRiskThreshold,
                snapshotTierBps: snapshotTierBps,
                idleBalance: totalDeposited,
                isActive: true,
                dispatcher: dispatcher
            })
        );

        cycleId = newCycleId;

        emit CycleStarted(employer, newCycleId, totalDeposited, payday);
        emit AgentAction(
            employer,
            newCycleId,
            0,
            ActionType.CycleStarted,
            NO_POOL,
            NO_POOL,
            0,
            0,
            0
        );
    }

    function cancelCycle(
        address employer,
        uint256 cycleId
    )
        external
        onlyAuthorizedCaller
        nonReentrant
        cycleIsActive(employer, cycleId)
        returns (uint256 amountReturned)
    {
        PayrollCycle storage cycle = cycles[employer][cycleId - 1];

        if (cycle.idleBalance < cycle.totalDeposited) revert YieldRouter__CycleNotCancellable();

        amountReturned = cycle.totalDeposited;
        cycle.isActive = false;

        IERC20(USDC).safeTransfer(msg.sender, amountReturned);

        emit CycleCancelled(employer, cycleId, amountReturned);
    }

    /**
     * @notice Main entry point for the off-chain agent to execute yield strategies.
     */
    function agentRebalance(
        address caller,
        uint256 cycleId
    )
        external
        onlyAgent
        whenNotPaused
        nonReentrant
        cycleIsActive(caller, cycleId)
    {
        PayrollCycle storage cycle = cycles[caller][cycleId - 1];
        uint256 timeIntoCycle = block.timestamp - cycle.cycleStartTime;

        uint256 bufferAmount;
        uint256 timeLeft;
        (bufferAmount, , timeLeft) = calculateBuffer(caller, cycleId);

        uint256 idleAmount = cycle.totalDeposited > bufferAmount
            ? cycle.totalDeposited - bufferAmount
            : 0;

        // --- Payday ---
        if (timeLeft == 0) {
            if (cycle.dispatcher == address(0)) revert YieldRouter__DispatcherNotSet();

            _withdrawAllFromPools(caller, cycleId);

            uint256 disbursed = cycle.idleBalance;

            cycle.isActive = false;

            IERC20(USDC).safeTransfer(cycle.dispatcher, disbursed);
            IPayrollDispatcher(cycle.dispatcher).disburse(caller, cycleId, disbursed);

            uint256 earned = disbursed > cycle.totalDeposited 
                ? disbursed - cycle.totalDeposited 
                : 0;

            emit PaydaySettled(caller, cycleId, disbursed, earned);
            emit AgentAction(
                caller,
                cycleId,
                timeIntoCycle,
                ActionType.PaydayTriggered,
                NO_POOL,
                NO_POOL,
                disbursed,
                0,
                0
            );
            return;
        }

        // --- Buffer adjustment ---
        {
            uint256 deployed = _getTotalDeployedValue(caller, cycleId);
            
            if (deployed > idleAmount) {
                uint256 needed = deployed - idleAmount;
                uint256 withdrawn = _cascadeWithdraw(
                    caller,
                    cycleId,
                    needed,
                    idleAmount,
                    timeLeft,
                    cycle.highRiskThreshold,
                    cycle.medRiskThreshold
                );
                emit AgentAction(
                    caller,
                    cycleId,
                    timeIntoCycle,
                    ActionType.BufferAdjusted,
                    NO_POOL,
                    NO_POOL,
                    withdrawn,
                    0,
                    0
                );
            }
        }

        // --- No idle capital ---
        if (idleAmount == 0) {
            emit AgentAction(
                caller,
                cycleId,
                timeIntoCycle,
                ActionType.MovedToReserve,
                NO_POOL,
                NO_POOL,
                0,
                0,
                0
            );
            return;
        }

        // --- APY floor check ---
        uint256 bestIdx;
        uint256 bestScore;
        (bestIdx, bestScore) = findBestPool(
            idleAmount,
            timeLeft,
            cycle.highRiskThreshold,
            cycle.medRiskThreshold
        );

        if (bestIdx == NO_POOL || bestScore == 0) {
            emit AgentAction(
                caller,
                cycleId,
                timeIntoCycle,
                ActionType.PoolBelowMinAPY,
                NO_POOL,
                NO_POOL,
                idleAmount,
                0,
                0
            );
            return;
        }

        // --- Rebalance or hold ---
        _handleRebalanceOrHold(
            caller,
            cycleId,
            timeIntoCycle,
            idleAmount,
            timeLeft,
            bestIdx,
            bestScore,
            cycle.highRiskThreshold,
            cycle.medRiskThreshold
        );
    }

    // --- EXTERNAL VIEW ---

    function getPoolCount() external view returns (uint256) {
        return pools.length;
    }

    function getPool(uint256 poolIndex) external view returns (PoolEntry memory) {
        if (poolIndex >= pools.length) revert YieldRouter__InvalidPoolIndex();
        return pools[poolIndex];
    }

    function getCycle(address caller, uint256 cycleId) external view cycleExists(caller, cycleId) returns (PayrollCycle memory) {
        return cycles[caller][cycleId - 1];
    }

    function getCycleHistory(address caller) external view returns (PayrollCycle[] memory) {
        return cycles[caller];
    }

    function getCycleCount(address caller) external view returns (uint256) {
        return cycles[caller].length;
    }

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

    function getLiveYield(address caller, uint256 cycleId) external view returns (
        uint256 totalValue, 
        uint256 netYield, 
        bool isLoss
    ) {
        if (cycleId == 0 || cycleId > cycles[caller].length) revert YieldRouter__CycleNotFound();

        PayrollCycle storage cycle = cycles[caller][cycleId - 1];
        
        uint256 deployedValue = _getTotalDeployedValue(caller, cycleId);

        totalValue = cycle.idleBalance + deployedValue;

        if (totalValue >= cycle.totalDeposited) {
            netYield = totalValue - cycle.totalDeposited;
            isLoss = false;
        } else {
            netYield = cycle.totalDeposited - totalValue; 
            isLoss = true;
        }
    }

    // --- PUBLIC VIEW ---

    /**
     * @notice Calculates the required liquid buffer based on time remaining.
     */
    function calculateBuffer(
        address caller,
        uint256 cycleId
    )
        public
        view
        returns (uint256 bufferAmount, uint256 bufferBps, uint256 timeLeft)
    {
        if (cycleId == 0 || cycleId > cycles[caller].length) revert YieldRouter__CycleNotFound();

        PayrollCycle memory cycle = cycles[caller][cycleId - 1];

        if (block.timestamp >= cycle.payDay) {
            timeLeft = 0;
            bufferBps = cycle.snapshotTierBps[cycle.snapshotTierBps.length - 1];
        } else {
            timeLeft = cycle.payDay - block.timestamp;

            bufferBps = cycle.snapshotTierBps[cycle.snapshotTierBps.length - 1];
            for (uint256 i = 0; i < cycle.tierThresholds.length; i++) {
                if (timeLeft >= cycle.tierThresholds[i]) {
                    bufferBps = cycle.snapshotTierBps[i];
                    break;
                }
            }
        }

        bufferAmount = (cycle.totalDeposited * bufferBps) / SCALE;
        if (bufferAmount > cycle.totalDeposited) bufferAmount = cycle.totalDeposited;
    }

    function calculateIdleAmount(
        address caller,
        uint256 cycleId
    ) public view cycleIsActive(caller, cycleId) returns (uint256) {
        (uint256 bufferAmount, , ) = calculateBuffer(caller, cycleId);
        uint256 total = cycles[caller][cycleId - 1].totalDeposited;
        return total > bufferAmount ? total - bufferAmount : 0;
    }

    function scorePool(
        uint256 poolIndex,
        uint256 idleAmount,
        uint256 timeLeft,
        uint256 highRiskThreshold,
        uint256 medRiskThreshold
    ) public view returns (uint256 score) {
        if (poolIndex >= pools.length) revert YieldRouter__InvalidPoolIndex();
        PoolEntry memory pool = pools[poolIndex];
        if (!pool.isActive) return 0;

        uint256 apyBps;
        uint256 poolTvl;
        {
            IPoolAdapter adapter = IPoolAdapter(pool.adapterAddress);
            apyBps = adapter.getApyBps();
            poolTvl = adapter.getTvl();
        }

        {
            uint256 minApy = pool.minApyBps > MIN_APY_BPS ? pool.minApyBps : MIN_APY_BPS;
            if (apyBps < minApy) return 0;
        }

        uint256 liqFactor = (idleAmount == 0 || poolTvl >= idleAmount)
            ? SCALE
            : (poolTvl * SCALE) / idleAmount;

        uint256 ilFactor = pool.isStablePair ? IL_RISK_STABLE : IL_RISK_VOLATILE;
        uint256 riskMult = _getRiskMultiplier(timeLeft, highRiskThreshold, medRiskThreshold);

        score = (((((apyBps * liqFactor) / SCALE) * riskMult) / SCALE) * ilFactor) / SCALE;
    }

    function findBestPool(
        uint256 idleAmount,
        uint256 timeLeft,
        uint256 highRiskThreshold,
        uint256 medRiskThreshold
    ) public view returns (uint256 bestIdx, uint256 bestScore) {
        bestIdx = NO_POOL;
        bestScore = 0;
        for (uint256 i = 0; i < pools.length; i++) {
            uint256 s = scorePool(i, idleAmount, timeLeft, highRiskThreshold, medRiskThreshold);
            if (s > bestScore) {
                bestScore = s;
                bestIdx = i;
            }
        }
    }

    function findWorstAllocatedPool(
        address caller,
        uint256 cycleId,
        uint256 idleAmount,
        uint256 timeLeft,
        uint256 highRiskThreshold,
        uint256 medRiskThreshold
    ) public view returns (uint256 worstIdx, uint256 worstScore) {
        worstIdx = NO_POOL;
        worstScore = type(uint256).max;
        for (uint256 i = 0; i < pools.length; i++) {
            if (poolAllocations[caller][cycleId][i] == 0) continue;
            uint256 s = scorePool(i, idleAmount, timeLeft, highRiskThreshold, medRiskThreshold);
            if (s < worstScore) {
                worstScore = s;
                worstIdx = i;
            }
        }
    }

    // --- INTERNAL ---

    function _handleRebalanceOrHold(
        address caller,
        uint256 cycleId,
        uint256 timeIntoCycle,
        uint256 idleAmount,
        uint256 timeLeft,
        uint256 bestIdx,
        uint256 bestScore,
        uint256 highRiskThreshold,
        uint256 medRiskThreshold
    ) internal {
        uint256 currentScore = _getCurrentAllocationScore(
            caller,
            cycleId,
            idleAmount,
            timeLeft,
            highRiskThreshold,
            medRiskThreshold
        );

        if (bestScore <= currentScore + REBALANCE_THRESHOLD) {
            emit AgentAction(caller, cycleId, timeIntoCycle, ActionType.NoActionNeeded, NO_POOL, NO_POOL, 0, currentScore, bestScore);
            return;
        }

        uint256 deployed = _getTotalDeployedValue(caller, cycleId);

        if (deployed == 0) {
            _deployToPool(caller, cycleId, bestIdx, idleAmount);
            emit AgentAction(caller, cycleId, timeIntoCycle, ActionType.Rebalanced, NO_POOL, bestIdx, idleAmount, currentScore, bestScore);
        } else {
            uint256 worstIdx;
            uint256 received;
            {
                (worstIdx, ) = findWorstAllocatedPool(caller, cycleId, idleAmount, timeLeft, highRiskThreshold, medRiskThreshold);
                if (worstIdx != NO_POOL && worstIdx != bestIdx) {
                    uint256 shares = poolAllocations[caller][cycleId][worstIdx];
                    if (shares > 0) {
                        received = _withdrawFromPool(caller, cycleId, worstIdx, shares);
                    }
                }
            }

            if (received > 0) {
                _deployToPool(caller, cycleId, bestIdx, received);
                emit AgentAction(caller, cycleId, timeIntoCycle, ActionType.Rebalanced, worstIdx, bestIdx, received, currentScore, bestScore);
            } else {
                emit AgentAction(caller, cycleId, timeIntoCycle, ActionType.NoActionNeeded, NO_POOL, NO_POOL, 0, currentScore, bestScore);
            }
        }
    }

    function _deployToPool(
        address caller,
        uint256 cycleId,
        uint256 poolIndex,
        uint256 amount
    ) internal {
        address adapter = pools[poolIndex].adapterAddress;
        IERC20(USDC).approve(adapter, amount);
        uint256 shares = IPoolAdapter(adapter).deposit(amount);

        poolAllocations[caller][cycleId][poolIndex] += shares;

        cycles[caller][cycleId - 1].idleBalance -= amount;
    }

    function _withdrawFromPool(
        address caller,
        uint256 cycleId,
        uint256 poolIndex,
        uint256 shares
    ) internal returns (uint256 received) {
        if (poolAllocations[caller][cycleId][poolIndex] < shares) revert YieldRouter__InsufficientPoolBalance();

        poolAllocations[caller][cycleId][poolIndex] -= shares;

        received = IPoolAdapter(pools[poolIndex].adapterAddress).withdraw(shares);
        
        cycles[caller][cycleId - 1].idleBalance += received;
    }

    function _cascadeWithdraw(
        address caller,
        uint256 cycleId,
        uint256 needed,
        uint256 idleAmount,
        uint256 timeLeft,
        uint256 highRiskThreshold,
        uint256 medRiskThreshold
    ) internal returns (uint256 totalWithdrawn) {
        uint256 remaining = needed;

        while (remaining > 0) {
            (uint256 worstIdx, ) = findWorstAllocatedPool(
                caller,
                cycleId,
                idleAmount,
                timeLeft,
                highRiskThreshold,
                medRiskThreshold
            );
            if (worstIdx == NO_POOL) break;

            uint256 shares = poolAllocations[caller][cycleId][worstIdx];
            if (shares == 0) break;

            uint256 positionValue = IPoolAdapter(pools[worstIdx].adapterAddress).sharesToValue(shares);

            uint256 sharesToWithdraw;
            if (positionValue <= remaining) {
                sharesToWithdraw = shares;
            } else {
                sharesToWithdraw = (shares * remaining) / positionValue;
                if (sharesToWithdraw == 0) sharesToWithdraw = 1;
            }

            uint256 received = _withdrawFromPool(caller, cycleId, worstIdx, sharesToWithdraw);
            totalWithdrawn += received;

            if (received >= remaining) {
                remaining = 0;
            } else {
                remaining -= received;
            }
        }
    }

    function _withdrawAllFromPools(address caller, uint256 cycleId) internal {
        for (uint256 i = 0; i < pools.length; i++) {
            uint256 shares = poolAllocations[caller][cycleId][i];
            if (shares > 0) _withdrawFromPool(caller, cycleId, i, shares);
        }
    }

    // --- INTERNAL VIEW ---

    function _onlyAgent() internal view {
        if (msg.sender != agentOperator && msg.sender != owner()) revert YieldRouter__NotAgent();
    }

    function _onlyAuthorizedCaller() internal view {
        if (msg.sender != owner() && msg.sender != payVault && msg.sender != payrollManager) revert YieldRouter__NotAuthorizedCaller();
    }

    function _cycleExists(address caller, uint256 cycleId) internal view {
        if (cycleId == 0 || cycleId > cycles[caller].length) revert YieldRouter__CycleNotFound();
    }

    function _cycleIsActive(address caller, uint256 cycleId) internal view {
        if (cycleId == 0 || cycleId > cycles[caller].length) revert YieldRouter__CycleNotFound();
        if (!cycles[caller][cycleId - 1].isActive) revert YieldRouter__CycleNotActive();
    }

    function _getTotalDeployedValue(
        address caller,
        uint256 cycleId
    ) internal view returns (uint256 totalValue) {
        for (uint256 i = 0; i < pools.length; i++) {
            uint256 shares = poolAllocations[caller][cycleId][i];
            if (shares > 0) {
                totalValue += IPoolAdapter(pools[i].adapterAddress).sharesToValue(shares);
            }
        }
    }

    function _getCurrentAllocationScore(
        address caller,
        uint256 cycleId,
        uint256 idleAmount,
        uint256 timeLeft,
        uint256 highRiskThreshold,
        uint256 medRiskThreshold
    ) internal view returns (uint256 best) {
        for (uint256 i = 0; i < pools.length; i++) {
            if (!pools[i].isActive) continue;
            if (poolAllocations[caller][cycleId][i] > 0) {
                uint256 s = scorePool(i, idleAmount, timeLeft, highRiskThreshold, medRiskThreshold);
                if (s > best) best = s;
            }
        }
    }

    // --- INTERNAL PURE ---

    function _getRiskMultiplier(
        uint256 timeLeft,
        uint256 highThreshold,
        uint256 medThreshold
    ) internal pure returns (uint256) {
        if (timeLeft >= highThreshold) return RISK_MULT_HIGH;
        if (timeLeft >= medThreshold) return RISK_MULT_MED;
        return RISK_MULT_LOW;
    }
}