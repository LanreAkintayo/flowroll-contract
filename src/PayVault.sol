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
 *
 * @dev Key architectural decisions:
 *
 *   BALANCE MODEL: Each employee has a flat USDC balance. PayrollDispatcher
 *   credits this balance on payday. Employees claim from it at any time.
 *   Per-payday breakdown is reconstructed from Credited events off-chain.
 *
 *   CREDIT: credit() is callable only by PayrollDispatcher. It pulls USDC
 *   from the dispatcher (via transferFrom) and adds to the employee's balance.
 *   No auto-save logic runs here — credit is pure accounting.
 *
 *   CLAIM: claim() is a pure withdrawal — employee specifies amount, receives
 *   it directly to their wallet. No auto-save applied.
 *
 *   CLAIM AND SAVE: claimAndSave() lets employees simultaneously withdraw and
 *   put a portion to work in yield. Employee specifies amount, savePct, and
 *   duration. The saved portion starts a new YieldRouter cycle owned by the
 *   employee with PayVault as dispatcher. The remainder transfers to wallet.
 *
 *   AUTO-SAVE PAYDAY: When an auto-save cycle matures, YieldRouter calls
 *   disburse() on this contract (PayVault is set as per-cycle dispatcher).
 *   PayVault receives principal + yield, takes protocol fee from yield only,
 *   and credits net amount back to employee's balance.
 *
 *   FEE MODEL: Fee is taken from yield only — never from principal. Same
 *   pattern as PayrollDispatcher. feeBps and feeRecipient are independently
 *   configurable from PayrollDispatcher's fee settings.
 *
 *   BALANCE ASSERTION: disburse() verifies actual USDC balance >= amount
 *   before proceeding, same as PayrollDispatcher.
 *
 *   CYCLE TRACKING: Each claimAndSave() pushes an AutoSaveCycle entry to
 *   the employee's array. disburse() marks the cycle inactive by cycleId.
 *   Frontend reads AutoSaveCycle array for savings history and status.
 */
contract PayVault is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Structs ─────────────────────────────────────────────────────────────

    struct AutoSaveCycle {
        uint256 cycleId;
        uint256 amountSaved;
        uint256 startTime;
        uint256 duration;
        bool    isActive;
    }

    // ─── Custom Errors ───────────────────────────────────────────────────────

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

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant SCALE       = 10_000;
    uint256 public constant MAX_FEE_BPS = 2_000; // 20% max fee on yield
    uint256 public constant MAX_SAVE_PCT = 10_000; // 100% max save — full claim can be saved

    // ─── State ───────────────────────────────────────────────────────────────

    address public immutable usdc;
    address public dispatcher;   // PayrollDispatcher — authorized to call credit()
    address public yieldRouter;  // YieldRouter — authorized to call disburse()
    address public feeRecipient;
    address public payrollManager;
    address public flowrollCredit;
    uint256 public feeBps;

    uint256 public totalEmployeeBalances;

    // employee → USDC balance
    mapping(address => uint256) private balances;

    // employee → auto-save cycles array
    mapping(address => AutoSaveCycle[]) private autoSaveCycles;

    // employee → cycleId → index+1 in autoSaveCycles (0 = not found)
    // Used for O(1) lookup in disburse()
    mapping(address => mapping(uint256 => uint256)) private cycleIndex;

    // employee → cycleId → disbursed flag (double-settlement protection)
    mapping(address => mapping(uint256 => bool)) private cycleSettled;

    // ─── Events ──────────────────────────────────────────────────────────────

    event Credited(
        address indexed employee,
        uint256 amount,
        uint256 actualCreditAmount,
        uint256 remainingDebt,
        uint256 timestamp
    );

    event Claimed(
        address indexed employee,
        uint256 amount,
        uint256 timestamp
    );

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

    event FeeCollected(
        address indexed recipient,
        uint256 amount
    );

    event FundsTransferred(
        address indexed recipient,
        uint256 amount
    );


    event DispatcherSet(address indexed dispatcher);
    event YieldRouterSet(address indexed router);
    event PayrollManagerSet(address indexed manager);
    event FlowrollCreditSet(address indexed credit);
    event FeeRecipientUpdated(address indexed previous, address indexed updated);
    event FeeBpsUpdated(uint256 previous, uint256 updated);

    // ─── Modifiers ───────────────────────────────────────────────────────────

    modifier onlyDispatcher() {
        if (msg.sender != dispatcher) revert PayVault__NotDispatcher();
        _;
    }

    modifier onlyYieldRouter() {
        if (msg.sender != yieldRouter) revert PayVault__NotYieldRouter();
        _;
    }

    modifier onlyPayrollManager() {
        if (msg.sender != payrollManager) revert PayVault__NotPayrollManager();
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────────

    /**
     * @param _usdc         USDC token address on evm-1
     * @param _feeRecipient Address that receives protocol fee from auto-save yield
     * @param _feeBps       Fee in basis points taken from auto-save yield
     */
    constructor(
        address _usdc,
        address _feeRecipient,
        uint256 _feeBps
    ) Ownable(msg.sender) {
        if (_usdc == address(0))        revert PayVault__ZeroAddress();
        if (_feeRecipient == address(0)) revert PayVault__ZeroAddress();
        if (_feeBps > MAX_FEE_BPS)      revert PayVault__InvalidFeeBps();

        usdc         = _usdc;
        feeRecipient = _feeRecipient;
        feeBps       = _feeBps;
    }

    // ─── Admin ───────────────────────────────────────────────────────────────

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

    // ─── Core: Credit ────────────────────────────────────────────────────────

    /**
     * @notice Credit an employee's balance. Called by PayrollDispatcher on payday.
     * @dev Pulls USDC from dispatcher via transferFrom. Pure accounting — no
     *      auto-save logic runs here. Auto-save is employee's choice at claim time.
     *
     * @param employee  Employee wallet address
     * @param amount    USDC amount to credit (6 decimals)
     */
    function credit(
        address employee,
        uint256 amount
    ) external onlyDispatcher whenNotPaused nonReentrant {
        if (employee == address(0)) revert PayVault__ZeroAddress();
        if (amount == 0)            revert PayVault__ZeroAmount();

        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);

        // Before we add the balance of the employee we have to resolve the actual amount;
        (uint256 actualCreditAmount, uint256 remainingDebt) = _resolveEmployeeCredit(employee, amount);

        // Update total pending salary
        IPayrollManager(payrollManager).removeFromTotalPendingSalary(employee, amount);

        balances[employee] += actualCreditAmount;
        totalEmployeeBalances += actualCreditAmount;

         // Update debt;
        IFlowrollCredit(flowrollCredit).updateDebt(employee, remainingDebt);  

        // Send the requested salary back to flowroll credit;
        uint256 amountToSend = amount - actualCreditAmount;
        IERC20(usdc).safeTransfer(flowrollCredit, amountToSend);

        emit FundsTransferred(flowrollCredit, amountToSend);
        emit Credited(employee, amount, actualCreditAmount, remainingDebt, block.timestamp);
    }

    function _resolveEmployeeCredit(address _employee, uint256 _amount) public view returns (uint256 creditAmount, uint256 remainingDebt) {
        // Check if they have debt;
        uint256 employeeDebt = IFlowrollCredit(flowrollCredit).getEmployeeDebt(_employee);        
        if (employeeDebt == 0) return (_amount, 0); 

        creditAmount = _amount > employeeDebt ? _amount - employeeDebt : 0;
        remainingDebt = _amount < employeeDebt ? employeeDebt - _amount : 0;    
    }


    // ─── Core: Claim ─────────────────────────────────────────────────────────

    /**
     * @notice Withdraw USDC from balance to wallet. No auto-save applied.
     * @dev Employee specifies exact amount. Reverts if balance insufficient.
     *
     * @param amount USDC amount to withdraw (6 decimals)
     */
    function claim(
        uint256 amount
    ) external whenNotPaused nonReentrant {
        if (amount == 0)                    revert PayVault__ZeroAmount();
        if (balances[msg.sender] < amount)  revert PayVault__InsufficientBalance();

        balances[msg.sender] -= amount;
        totalEmployeeBalances -= amount;
        IERC20(usdc).safeTransfer(msg.sender, amount);

        emit Claimed(msg.sender, amount, block.timestamp);
    }

    // ─── Core: Claim And Save ────────────────────────────────────────────────

    /**
     * @notice Claim from balance while putting a portion into yield.
     * @dev Deducts full amount from balance. Saves savePct portion into a new
     *      YieldRouter cycle owned by msg.sender with PayVault as dispatcher.
     *      Remainder transfers directly to employee wallet.
     *
     *      Auto-save cycle is tracked in autoSaveCycles[msg.sender].
     *      On payday, YieldRouter calls disburse() on this contract with
     *      employee address as the "employer" key.
     *
     * @param amount    Total USDC to claim from balance (6 decimals)
     * @param savePct   Portion to save in basis points (e.g. 2000 = 20%)
     * @param duration  Auto-save cycle duration in seconds
     */
    function claimAndSave(
        uint256 amount,
        uint256 savePct,
        uint256 duration
    ) external whenNotPaused nonReentrant {
        if (amount == 0)                    revert PayVault__ZeroAmount();
        if (savePct == 0 || savePct > MAX_SAVE_PCT) revert PayVault__InvalidSavePct();
        if (duration == 0)                  revert PayVault__ZeroDuration();
        if (balances[msg.sender] < amount)  revert PayVault__InsufficientBalance();
        if (yieldRouter == address(0))      revert PayVault__RouterNotSet();

        // ── Deduct full amount from balance ───────────────────────────────────
        balances[msg.sender] -= amount;
        totalEmployeeBalances -= amount;

        // ── Calculate split ───────────────────────────────────────────────────
        uint256 savedAmount   = (amount * savePct) / SCALE;
        uint256 claimedAmount = amount - savedAmount;

        // ── Start YieldRouter cycle for saved portion ─────────────────────────
        // employee is the cycle owner key, PayVault is the per-cycle dispatcher
        IERC20(usdc).approve(yieldRouter, savedAmount);

        uint256 cycleId = IYieldRouter(yieldRouter).startCycle(
            msg.sender,      // cycle owner — employee address
            savedAmount,
            duration,
            address(this)    // per-cycle dispatcher — PayVault handles payday
        );

        IERC20(usdc).approve(yieldRouter, 0);

        // ── Track auto-save cycle ─────────────────────────────────────────────
        uint256 idx = autoSaveCycles[msg.sender].length;
        autoSaveCycles[msg.sender].push(AutoSaveCycle({
            cycleId:     cycleId,
            amountSaved: savedAmount,
            startTime:   block.timestamp,
            duration:    duration,
            isActive:    true
        }));

        // Store index+1 for O(1) lookup in disburse()
        cycleIndex[msg.sender][cycleId] = idx + 1;

        // ── Transfer remainder to employee wallet ─────────────────────────────
        if (claimedAmount > 0) {
            IERC20(usdc).safeTransfer(msg.sender, claimedAmount);
        }

        emit AutoSaveStarted(
            msg.sender,
            cycleId,
            savedAmount,
            claimedAmount,
            duration,
            block.timestamp
        );

        if (claimedAmount > 0) {
            emit Claimed(msg.sender, claimedAmount, block.timestamp);
        }
    }

    // ─── Core: Disburse (Auto-Save Payday) ───────────────────────────────────

    /**
     * @notice Settle a matured auto-save cycle. Called by YieldRouter on payday.
     * @dev YieldRouter transfers principal + yield to this contract before calling.
     *      Fee is taken from yield only. Net amount credited to employee balance.
     *      Marks AutoSaveCycle as inactive.
     *
     *      Note: "employer" parameter from YieldRouter's perspective is the
     *      employee address — employees own their auto-save cycles directly.
     *
     * @param employee  Employee whose auto-save cycle matured (passed as "employer" by YieldRouter)
     * @param cycleId   YieldRouter cycle ID
     * @param amount    Total USDC transferred — principal + yield
     */
    function disburse(
        address employee,
        uint256 cycleId,
        uint256 amount
    ) external onlyYieldRouter whenNotPaused nonReentrant {
        if (amount == 0)  revert PayVault__ZeroAmount();
        if (cycleSettled[employee][cycleId]) revert PayVault__AlreadyDisbursed();

        // ── Verify balance ────────────────────────────────────────────────────
        if (IERC20(usdc).balanceOf(address(this)) < amount)
            revert PayVault__InsufficientContractBalance();

        // ── Look up cycle ─────────────────────────────────────────────────────
        uint256 idxPlusOne = cycleIndex[employee][cycleId];
        if (idxPlusOne == 0) revert PayVault__CycleNotFound();

        AutoSaveCycle storage cycle = autoSaveCycles[employee][idxPlusOne - 1];
        if (!cycle.isActive) revert PayVault__CycleAlreadySettled();

        // ── Calculate yield and fee ───────────────────────────────────────────
        uint256 principal  = cycle.amountSaved;
        uint256 yieldEarned = amount > principal ? amount - principal : 0;
        uint256 fee         = (yieldEarned * feeBps) / SCALE;
        uint256 netCredited = amount - fee;

        // ── Collect protocol fee ──────────────────────────────────────────────
        if (fee > 0) {
            IERC20(usdc).safeTransfer(feeRecipient, fee);
            emit FeeCollected(feeRecipient, fee);
        }

        // ── Credit net amount to employee balance ─────────────────────────────
        balances[employee] += netCredited;
        totalEmployeeBalances += netCredited;

        // ── Mark cycle settled ────────────────────────────────────────────────
        cycle.isActive            = false;
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

    // ─── View Functions ───────────────────────────────────────────────────────

    function getBalance(address employee) external view returns (uint256) {
        return balances[employee];
    }

    function getAutoSaveCycles(
        address employee
    ) external view returns (AutoSaveCycle[] memory) {
        return autoSaveCycles[employee];
    }

    function getAutoSaveCycle(
        address employee,
        uint256 index
    ) external view returns (AutoSaveCycle memory) {
        return autoSaveCycles[employee][index];
    }

    function isCycleSettled(
        address employee,
        uint256 cycleId
    ) external view returns (bool) {
        return cycleSettled[employee][cycleId];
    }

    // ─── Recovery ────────────────────────────────────────────────────────────

    /**
     * @notice Recover dust USDC from rounding.
     * @dev Should rarely be needed — included for safety.
     *      Only recovers amounts above total employee balances.
     *      Funds go to feeRecipient.
     */
    function recoverDust() external onlyOwner {
    uint256 contractBalance = IERC20(usdc).balanceOf(address(this));
    uint256 dust = contractBalance > totalEmployeeBalances 
        ? contractBalance - totalEmployeeBalances 
        : 0;
    if (dust > 0) {
        IERC20(usdc).safeTransfer(feeRecipient, dust);
    }
}
}
