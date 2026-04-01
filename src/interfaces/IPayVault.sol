// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPayVault
 * @notice Interface for the PayVault contract.
 */
interface IPayVault {
    // ─── Structs ─────────────────────────────────────────────────────────────

    struct AutoSaveCycle {
        uint256 cycleId;
        uint256 amountSaved;
        uint256 startTime;
        uint256 duration;
        bool isActive;
    }

    // ─── Custom Errors ───────────────────────────────────────────────────────

    error PayVault__NotDispatcher();
    error PayVault__NotYieldRouter();
    error PayVault__ZeroAddress();
    error PayVault__ZeroAmount();
    error PayVault__ZeroDuration();
    error PayVault__InvalidFeeBps();
    error PayVault__InvalidSavePct();
    error PayVault__InsufficientBalance();
    error PayVault__InsufficientContractBalance();
    error PayVault__RouterNotSet();
    error PayVault__DispatcherNotSet();
    error PayVault__CycleNotFound();
    error PayVault__CycleAlreadySettled();
    error PayVault__AlreadyDisbursed();

    // ─── Events ──────────────────────────────────────────────────────────────

    event Credited(address indexed employee, uint256 amount, uint256 timestamp);
    event Claimed(address indexed employee, uint256 amount, uint256 timestamp);
    
    event AutoSaveStarted(
        address indexed employee,
        uint256 indexed cycleId,
        uint256 amountSaved,
        uint256 amountClaimed,
        uint256 duration,
        uint256 timestamp
    );

    event AutoSaveSettled(
        address indexed employee,
        uint256 indexed cycleId,
        uint256 totalReceived,
        uint256 yieldEarned,
        uint256 fee,
        uint256 netCredited,
        uint256 timestamp
    );

    event FeeCollected(address indexed recipient, uint256 amount);
    event DispatcherSet(address indexed dispatcher);
    event YieldRouterSet(address indexed router);
    event FeeRecipientUpdated(address indexed previous, address indexed updated);
    event FeeBpsUpdated(uint256 previous, uint256 updated);

    // ─── State Variable Getters ──────────────────────────────────────────────

    function SCALE() external view returns (uint256);
    function MAX_FEE_BPS() external view returns (uint256);
    function MAX_SAVE_PCT() external view returns (uint256);
    function usdc() external view returns (address);
    function dispatcher() external view returns (address);
    function yieldRouter() external view returns (address);
    function feeRecipient() external view returns (address);
    function feeBps() external view returns (uint256);
    function totalEmployeeBalances() external view returns (uint256);

    // ─── Core Functions ──────────────────────────────────────────────────────

    /**
     * @notice Credit an employee's balance. Called by PayrollDispatcher.
     */
    function credit(address employee, uint256 amount) external;

    /**
     * @notice Withdraw USDC from balance to wallet.
     */
    function claim(uint256 amount) external;

    /**
     * @notice Claim from balance while putting a portion into a new yield cycle.
     */
    function claimAndSave(uint256 amount, uint256 savePct, uint256 duration) external;

    /**
     * @notice Settle a matured auto-save cycle. Called by YieldRouter.
     */
    function disburse(address employee, uint256 cycleId, uint256 amount) external;

    // ─── View Functions ───────────────────────────────────────────────────────

    function getBalance(address employee) external view returns (uint256);
    function getAutoSaveCycles(address employee) external view returns (AutoSaveCycle[] memory);
    function getAutoSaveCycle(address employee, uint256 index) external view returns (AutoSaveCycle memory);
    function isCycleSettled(address employee, uint256 cycleId) external view returns (bool);

    // ─── Admin & Recovery Functions ──────────────────────────────────────────

    function setDispatcher(address _dispatcher) external;
    function setYieldRouter(address _router) external;
    function setFeeRecipient(address _feeRecipient) external;
    function setFeeBps(uint256 _feeBps) external;
    function pause() external;
    function unpause() external;
    function recoverDust() external;
}