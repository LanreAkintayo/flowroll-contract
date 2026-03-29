// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IYieldRouter
 * @notice Standard interface for the core yield agent contract in Flowroll.
 */
interface IYieldRouter {
    // ─── Enums ───────────────────────────────────────────────────────────────

    enum ActionType {
        CycleStarted,
        Rebalanced,
        BufferAdjusted,
        MovedToReserve,
        PoolBelowMinAPY,
        PaydayTriggered,
        NoActionNeeded
    }

    // ─── Structs ─────────────────────────────────────────────────────────────

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
        uint256 currentAllocation;
        uint256 yieldEarned;
        bool isActive;
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
    error YieldRouter__DispatcherNotSet();
    error YieldRouter__InvalidBufferConfig();
    error YieldRouter__InvalidRiskConfig();

    // ─── Events ──────────────────────────────────────────────────────────────

    event AgentOperatorUpdated(
        address indexed previous,
        address indexed updated
    );
    event PayrollDispatcherSet(address indexed dispatcher);
    event TreasurySet(address indexed treasury);
    event BufferConfigUpdated();
    event PoolAdded(
        uint256 indexed poolIndex,
        address adapterAddress,
        address poolAddress
    );
    event PoolDeactivated(uint256 indexed poolIndex);
    event CycleStarted(
        address indexed caller,
        uint256 indexed cycleId,
        uint256 totalDeposited,
        uint256 payDay
    );
    event PaydaySettled(
        address indexed caller,
        uint256 indexed cycleId,
        uint256 totalDisbursed,
        uint256 yieldEarned
    );
    event AgentAction(
        address indexed caller,
        uint256 indexed cycleId,
        uint256 timeIntoCycle,
        ActionType actionType,
        uint256 fromPoolIndex,
        uint256 toPoolIndex,
        uint256 amountMoved,
        uint256 scoreBefore,
        uint256 scoreAfter
    );
    event RiskConfigUpdated(uint256 indexed highPct, uint256 indexed medPct);

    // ─── Admin Functions ─────────────────────────────────────────────────────

    function setAgentOperator(address _agent) external;

    function setPayrollDispatcher(address _dispatcher) external;

    function setTreasury(address _treasury) external;

    function setBufferConfig(
        uint256[] calldata tierPcts,
        uint256[] calldata tierBps
    ) external;

    function setRiskConfig(uint256 highPct, uint256 medPct) external;

    function pause() external;

    function unpause() external;

    // ─── Pool Management ─────────────────────────────────────────────────────

    function addPool(
        address adapterAddress,
        address pool,
        bool isStablePair,
        uint256 minApyBps
    ) external;

    function deactivatePool(uint256 poolIndex) external;

    function getPoolCount() external view returns (uint256);

    function getPool(
        uint256 poolIndex
    ) external view returns (PoolEntry memory);

    // ─── Cycle Management ────────────────────────────────────────────────────

    function startCycle(
        address employer,
        uint256 totalDeposited,
        uint256 cycleDuration,
        address dispatcher
    ) external returns (uint256 cycleId);

    function cancelCycle(
        address employer,
        uint256 cycleId
    ) external returns (uint256 amountReturned);

    // ─── Cycle Getters ───────────────────────────────────────────────────────

    function getCycle(
        address caller,
        uint256 cycleId
    ) external view returns (PayrollCycle memory);

    function getCycleHistory(
        address caller
    ) external view returns (PayrollCycle[] memory);

    function getCycleCount(address caller) external view returns (uint256);

    function getActiveCycles(
        address caller
    ) external view returns (PayrollCycle[] memory);

    // ─── Math & Buffer Calculation ───────────────────────────────────────────

    function calculateBuffer(
        address caller,
        uint256 cycleId
    )
        external
        view
        returns (uint256 bufferAmount, uint256 bufferBps, uint256 timeLeft);

    function calculateIdleAmount(
        address caller,
        uint256 cycleId
    ) external view returns (uint256);

    // ─── Scoring & Pool Discovery ────────────────────────────────────────────

    function scorePool(
        uint256 poolIndex,
        uint256 idleAmount,
        uint256 timeLeft,
        uint256 highRiskThreshold,
        uint256 medRiskThreshold
    ) external view returns (uint256 score);

    function findBestPool(
        uint256 idleAmount,
        uint256 timeLeft,
        uint256 highRiskThreshold,
        uint256 medRiskThreshold
    ) external view returns (uint256 bestIdx, uint256 bestScore);

    function findWorstAllocatedPool(
        address caller,
        uint256 cycleId,
        uint256 idleAmount,
        uint256 timeLeft,
        uint256 highRiskThreshold,
        uint256 medRiskThreshold
    ) external view returns (uint256 worstIdx, uint256 worstScore);

    // ─── Agent Rebalance ─────────────────────────────────────────────────────

    function agentRebalance(address caller, uint256 cycleId) external;
}
