// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IYieldRouter
 * @notice Interface for the YieldRouter core agent.
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
        uint256 cycleDuration; // in seconds
        uint256[] tierThresholds; // absolute second thresholds, descending
        uint256[] snapshotTierBps; // buffer bps per tier, snapshotted
        uint256 highRiskThreshold; // snapshotted in seconds
        uint256 medRiskThreshold; // snapshotted in seconds
        uint256 idleBalance;
        bool isActive;
        address dispatcher;
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
    error YieldRouter__CycleNotCancellable();

    // ─── Events ──────────────────────────────────────────────────────────────

    event AgentOperatorUpdated(
        address indexed previous,
        address indexed updated
    );
    event PayrollDispatcherSet(address indexed dispatcher);
    event TreasurySet(address indexed treasury);
    event PayVaultSet(address indexed vault);
    event PayrollManagerSet(address indexed payrollManager);
    event BufferConfigUpdated();
    event RiskConfigUpdated(uint256 indexed highPct, uint256 indexed medPct);

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
    event CycleCancelled(
        address indexed caller,
        uint256 indexed cycleId,
        uint256 amountReturned
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

    // ─── State Variable Getters ──────────────────────────────────────────────

    function SCALE() external view returns (uint256);
    function IL_RISK_STABLE() external view returns (uint256);
    function IL_RISK_VOLATILE() external view returns (uint256);
    function RISK_MULT_HIGH() external view returns (uint256);
    function RISK_MULT_MED() external view returns (uint256);
    function RISK_MULT_LOW() external view returns (uint256);
    function REBALANCE_THRESHOLD() external view returns (uint256);
    function MIN_APY_BPS() external view returns (uint256);
    function NO_POOL() external view returns (uint256);

    function usdc() external view returns (address);
    function agentOperator() external view returns (address);
    function payVault() external view returns (address);
    function payrollManager() external view returns (address);

    function pools(
        uint256 index
    )
        external
        view
        returns (
            address adapterAddress,
            address pool,
            bool isStablePair,
            bool isActive,
            uint256 minApyBps
        );

    function poolAllocations(
        address caller,
        uint256 cycleId,
        uint256 poolIndex
    ) external view returns (uint256);

    // ─── Core Cycle Management ───────────────────────────────────────────────

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

    function agentRebalance(address caller, uint256 cycleId) external;

    // ─── View & Query Functions ──────────────────────────────────────────────

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

    function getPoolCount() external view returns (uint256);
    function getPool(
        uint256 poolIndex
    ) external view returns (PoolEntry memory);

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

    function scorePool(
        uint256 poolIndex,
        uint256 idleAmount,
        uint256 timeLeft,
        uint256 highRiskThreshold,
        uint256 medRiskThreshold
    ) external view returns (uint256 score);

    // ─── Admin Functions ──────────────────────────────────────────────────────

    function setAgentOperator(address _agent) external;
    function setPayVault(address _payVault) external;
    function setPayrollManager(address _payrollManager) external;
    function setBufferConfig(
        uint256[] calldata tierPcts,
        uint256[] calldata tierBps
    ) external;
    function setRiskConfig(uint256 highPct, uint256 medPct) external;

    function addPool(
        address adapterAddress,
        address pool,
        bool isStablePair,
        uint256 minApyBps
    ) external;
    function deactivatePool(uint256 poolIndex) external;

    function pause() external;
    function unpause() external;
}
