// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IYieldRouter} from "./interfaces/IYieldRouter.sol";
import {IPayrollManager} from "./interfaces/IPayrollManager.sol";
import {IFlowrollCredit} from "./interfaces/IFlowrollCredit.sol";

/**
 * @title PayVault
 * @notice Employee balance and auto-save contract for Flowroll.
 */
contract PayVault is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- STRUCTS ---

    struct AutoSaveCycle {
        uint256 cycleId;
        uint256 amountSaved;
        uint256 startTime;
        uint256 duration;
        bool isActive;
    }

    // --- ERRORS ---

    error PayVault__NotDispatcher();
    error PayVault__NotYieldRouter();
    error PayVault__NotPayrollManager();
    error PayVault__NotFlowrollCredit();
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

    // --- EVENTS ---

    event Credited(address indexed employee, uint256 amount, uint256 actualCreditAmount, uint256 remainingDebt, uint256 timestamp);
    event Claimed(address indexed employee, uint256 amount, uint256 timestamp);
    event AutoSaveStarted(address indexed employee, uint256 indexed cycleId, uint256 amountSaved, uint256 amountClaimed, uint256 duration, uint256 timestamp);
    event AutoSaveSettled(address indexed employee, uint256 indexed cycleId, uint256 totalReceived, uint256 yieldEarned, uint256 fee, uint256 netCredited, uint256 timestamp);
    event FeeCollected(address indexed recipient, uint256 amount);
    event FundsTransferred(address indexed recipient, uint256 amount);
    event DispatcherSet(address indexed dispatcher);
    event YieldRouterSet(address indexed router);
    event PayrollManagerSet(address indexed manager);
    event FlowrollCreditSet(address indexed credit);
    event FeeRecipientUpdated(address indexed previous, address indexed updated);
    event FeeBpsUpdated(uint256 previous, uint256 updated);

    // --- STATE VARIABLES ---

    uint256 public constant SCALE = 10_000;
    uint256 public constant MAX_FEE_BPS = 2_000;
    uint256 public constant MAX_SAVE_PCT = 10_000;

    address public immutable USDC;
    address public dispatcher;
    address public yieldRouter;
    address public feeRecipient;
    address public payrollManager;
    address public flowrollCredit;
    uint256 public feeBps;

    uint256 public totalEmployeeBalances;

    mapping(address => uint256) private balances;
    mapping(address => AutoSaveCycle[]) private autoSaveCycles;
    mapping(address => mapping(uint256 => uint256)) private cycleIndex;
    mapping(address => mapping(uint256 => bool)) private cycleSettled;

    // --- MODIFIERS ---

    modifier onlyDispatcher() {
        _onlyDispatcher();
        _;
    }

    modifier onlyYieldRouter() {
        _onlyYieldRouter();
        _;
    }

    modifier onlyPayrollManager() {
        _onlyPayrollManager();
        _;
    }


    /**
     * @param _usdc USDC token address on EVM.
     * @param _feeRecipient Address that receives protocol fee from auto-save yield.
     * @param _feeBps Fee in basis points taken from auto-save yield.
     */
    constructor(
        address _usdc,
        address _feeRecipient,
        uint256 _feeBps
    ) Ownable(msg.sender) {
        if (_usdc == address(0) || _feeRecipient == address(0)) revert PayVault__ZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert PayVault__InvalidFeeBps();

        USDC = _usdc;
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;
    }

    // --- EXTERNAL ---

    function setDispatcher(address _dispatcher) external onlyOwner {
        if (_dispatcher == address(0)) revert PayVault__ZeroAddress();
        dispatcher = _dispatcher;
        emit DispatcherSet(_dispatcher);
    }

    function setYieldRouter(address _router) external onlyOwner {
        if (_router == address(0)) revert PayVault__ZeroAddress();
        yieldRouter = _router;
        emit YieldRouterSet(_router);
    }

    function setPayrollManager(address _manager) external onlyOwner {
        if (_manager == address(0)) revert PayVault__ZeroAddress();
        payrollManager = _manager;
        emit PayrollManagerSet(_manager);
    }

    function setFlowrollCredit(address _flowrollCredit) external onlyOwner {
        if (_flowrollCredit == address(0)) revert PayVault__ZeroAddress();
        flowrollCredit = _flowrollCredit;
        emit FlowrollCreditSet(_flowrollCredit);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) revert PayVault__ZeroAddress();
        emit FeeRecipientUpdated(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    function setFeeBps(uint256 _feeBps) external onlyOwner {
        if (_feeBps > MAX_FEE_BPS) revert PayVault__InvalidFeeBps();
        emit FeeBpsUpdated(feeBps, _feeBps);
        feeBps = _feeBps;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Credits an employee's balance, settling outstanding debt first.
     */
    function credit(
        address employee,
        uint256 amount
    ) external onlyDispatcher whenNotPaused nonReentrant {
        if (employee == address(0)) revert PayVault__ZeroAddress();
        if (amount == 0) revert PayVault__ZeroAmount();

        IERC20(USDC).safeTransferFrom(msg.sender, address(this), amount);

        (uint256 actualCreditAmount, uint256 remainingDebt) = _resolveEmployeeCredit(employee, amount);

        IPayrollManager(payrollManager).removeFromTotalPendingSalary(employee, amount);

        balances[employee] += actualCreditAmount;
        totalEmployeeBalances += actualCreditAmount;

        IFlowrollCredit(flowrollCredit).updateDebt(employee, remainingDebt);  

        uint256 amountToSend = amount - actualCreditAmount;
        if (amountToSend > 0) {
            IERC20(USDC).safeTransfer(flowrollCredit, amountToSend);
            emit FundsTransferred(flowrollCredit, amountToSend);
        }

        emit Credited(employee, amount, actualCreditAmount, remainingDebt, block.timestamp);
    }

    /**
     * @notice Withdraws USDC from balance directly to wallet.
     */
    function claim(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert PayVault__ZeroAmount();
        if (balances[msg.sender] < amount) revert PayVault__InsufficientBalance();

        balances[msg.sender] -= amount;
        totalEmployeeBalances -= amount;
        IERC20(USDC).safeTransfer(msg.sender, amount);

        emit Claimed(msg.sender, amount, block.timestamp);
    }

    /**
     * @notice Claims from balance while locking a portion into a yield cycle.
     */
    function claimAndSave(
        uint256 amount,
        uint256 savePct,
        uint256 duration
    ) external whenNotPaused nonReentrant {
        if (amount == 0) revert PayVault__ZeroAmount();
        if (savePct == 0 || savePct > MAX_SAVE_PCT) revert PayVault__InvalidSavePct();
        if (duration == 0) revert PayVault__ZeroDuration();
        if (balances[msg.sender] < amount) revert PayVault__InsufficientBalance();
        if (yieldRouter == address(0)) revert PayVault__RouterNotSet();

        balances[msg.sender] -= amount;
        totalEmployeeBalances -= amount;

        uint256 savedAmount = (amount * savePct) / SCALE;
        uint256 claimedAmount = amount - savedAmount;

        IERC20(USDC).approve(yieldRouter, savedAmount);

        uint256 cycleId = IYieldRouter(yieldRouter).startCycle(
            msg.sender,
            savedAmount,
            duration,
            address(this)
        );

        IERC20(USDC).approve(yieldRouter, 0);

        uint256 idx = autoSaveCycles[msg.sender].length;
        autoSaveCycles[msg.sender].push(AutoSaveCycle({
            cycleId: cycleId,
            amountSaved: savedAmount,
            startTime: block.timestamp,
            duration: duration,
            isActive: true
        }));

        cycleIndex[msg.sender][cycleId] = idx + 1;

        if (claimedAmount > 0) {
            IERC20(USDC).safeTransfer(msg.sender, claimedAmount);
            emit Claimed(msg.sender, claimedAmount, block.timestamp);
        }

        emit AutoSaveStarted(
            msg.sender,
            cycleId,
            savedAmount,
            claimedAmount,
            duration,
            block.timestamp
        );
    }

    /**
     * @notice Settles a matured auto-save cycle. Called by YieldRouter on payday.
     */
    function disburse(
        address employee,
        uint256 cycleId,
        uint256 amount
    ) external onlyYieldRouter whenNotPaused nonReentrant {
        if (amount == 0) revert PayVault__ZeroAmount();
        if (cycleSettled[employee][cycleId]) revert PayVault__AlreadyDisbursed();

        if (IERC20(USDC).balanceOf(address(this)) < amount) revert PayVault__InsufficientContractBalance();

        uint256 idxPlusOne = cycleIndex[employee][cycleId];
        if (idxPlusOne == 0) revert PayVault__CycleNotFound();

        AutoSaveCycle storage cycle = autoSaveCycles[employee][idxPlusOne - 1];
        if (!cycle.isActive) revert PayVault__CycleAlreadySettled();

        uint256 principal = cycle.amountSaved;
        uint256 yieldEarned = amount > principal ? amount - principal : 0;
        uint256 fee = (yieldEarned * feeBps) / SCALE;
        uint256 netCredited = amount - fee;

        if (fee > 0) {
            IERC20(USDC).safeTransfer(feeRecipient, fee);
            emit FeeCollected(feeRecipient, fee);
        }

        balances[employee] += netCredited;
        totalEmployeeBalances += netCredited;

        cycle.isActive = false;
        cycleSettled[employee][cycleId] = true;

        emit AutoSaveSettled(
            employee,
            cycleId,
            amount,
            yieldEarned,
            fee,
            netCredited,
            block.timestamp
        );
    }

    /**
     * @notice Recovers dust USDC from rounding errors.
     */
    function recoverDust() external onlyOwner {
        uint256 contractBalance = IERC20(USDC).balanceOf(address(this));
        uint256 dust = contractBalance > totalEmployeeBalances 
            ? contractBalance - totalEmployeeBalances 
            : 0;
        if (dust > 0) {
            IERC20(USDC).safeTransfer(feeRecipient, dust);
        }
    }

    // --- EXTERNAL VIEW ---

    function getBalance(address employee) external view returns (uint256) {
        return balances[employee];
    }

    function getAutoSaveCycles(address employee) external view returns (AutoSaveCycle[] memory) {
        return autoSaveCycles[employee];
    }

    function getAutoSaveCycle(address employee, uint256 index) external view returns (AutoSaveCycle memory) {
        return autoSaveCycles[employee][index];
    }

    function isCycleSettled(address employee, uint256 cycleId) external view returns (bool) {
        return cycleSettled[employee][cycleId];
    }

    // --- PUBLIC VIEW ---

    /**
     * @notice Calculates actual credit amount and remaining debt.
     */
    function _resolveEmployeeCredit(address _employee, uint256 _amount) public view returns (uint256 creditAmount, uint256 remainingDebt) {
        uint256 employeeDebt = IFlowrollCredit(flowrollCredit).getEmployeeDebt(_employee);        
        if (employeeDebt == 0) return (_amount, 0); 

        creditAmount = _amount > employeeDebt ? _amount - employeeDebt : 0;
        remainingDebt = _amount < employeeDebt ? employeeDebt - _amount : 0;    
    }

    // --- INTERNAL VIEW ---

    function _onlyDispatcher() internal view {
        if (msg.sender != dispatcher) revert PayVault__NotDispatcher();
    }

    function _onlyYieldRouter() internal view {
        if (msg.sender != yieldRouter) revert PayVault__NotYieldRouter();
    }

    function _onlyPayrollManager() internal view {
        if (msg.sender != payrollManager) revert PayVault__NotPayrollManager();
    }
}