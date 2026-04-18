// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title FlowrollZapper
 * @notice Facilitates appchain onboarding by swapping bridged INIT for test USDC and native gas.
 * @dev Implements fixed-rate swaps with anti-sybil limits. Uses custom errors for gas optimization.
 */
contract FlowrollZapper is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- STATE VARIABLES ---

    IERC20 public immutable bridgedInit;
    IERC20 public immutable testUsdc;

    uint256 public immutable initUnit; 

    uint256 public usdcRate; 
    uint256 public gasRate;  
    
    uint256 public maxZapPerWallet;
    mapping(address => uint256) public totalZapped;

    // --- EVENTS ---

    event Zapped(address indexed user, uint256 initDeposited, uint256 usdcReceived, uint256 gasReceived);
    event RatesUpdated(uint256 newUsdcRate, uint256 newGasRate);
    event MaxZapUpdated(uint256 newMaxZap);

    // --- ERRORS ---

    error FlowrollZapper__AmountTooLow();
    error FlowrollZapper__ExceedsMaxZapLimit();
    error FlowrollZapper__InsufficientTreasuryBalance();
    error FlowrollZapper__NativeTransferFailed();

    // --- CONSTRUCTOR ---

    /**
     * @param _bridgedInit Address of the bridged INIT token on L2.
     * @param _testUsdc Address of the test USDC token.
     * @param _rawUsdcPerInit Whole number of USDC given per 1 whole INIT.
     * @param _rawGasPerInit Whole number of Native Gas given per 1 whole INIT.
     * @param _maxZapPerWallet Maximum base units of INIT a single address can zap.
     */
    constructor(
        address _bridgedInit,
        address _testUsdc,
        uint256 _rawUsdcPerInit,
        uint256 _rawGasPerInit,
        uint256 _maxZapPerWallet
    ) Ownable(msg.sender) {
        bridgedInit = IERC20(_bridgedInit);
        testUsdc = IERC20(_testUsdc);
        
        uint8 initDecimals = IERC20Metadata(_bridgedInit).decimals();
        uint8 usdcDecimals = IERC20Metadata(_testUsdc).decimals();
        
        initUnit = 10 ** initDecimals;
        usdcRate = _rawUsdcPerInit * (10 ** usdcDecimals);
        gasRate = _rawGasPerInit * 1e18;

        maxZapPerWallet = _maxZapPerWallet;
    }

    // --- RECEIVE ---

    receive() external payable {}

    // --- EXTERNAL ---

    /**
     * @notice Swaps deposited INIT for USDC and Native Gas based on fixed rates.
     * @param initAmount The amount of INIT to deposit in base units.
     */
    function zap(uint256 initAmount) external whenNotPaused nonReentrant {
        if (initAmount == 0) revert FlowrollZapper__AmountTooLow();
        if (totalZapped[msg.sender] + initAmount > maxZapPerWallet) revert FlowrollZapper__ExceedsMaxZapLimit();

        (uint256 usdcOut, uint256 gasOut) = getQuote(initAmount);

        if (testUsdc.balanceOf(address(this)) < usdcOut || address(this).balance < gasOut) {
            revert FlowrollZapper__InsufficientTreasuryBalance();
        }

        totalZapped[msg.sender] += initAmount;

        bridgedInit.safeTransferFrom(msg.sender, address(this), initAmount);
        testUsdc.safeTransfer(msg.sender, usdcOut);

        (bool success, ) = payable(msg.sender).call{value: gasOut}("");
        if (!success) revert FlowrollZapper__NativeTransferFailed();

        emit Zapped(msg.sender, initAmount, usdcOut, gasOut);
    }

    /**
     * @notice Updates the internal exchange rates.
     */
    function updateRates(uint256 _rawUsdcPerInit, uint256 _rawGasPerInit) external onlyOwner {
        uint8 usdcDecimals = IERC20Metadata(address(testUsdc)).decimals();
        usdcRate = _rawUsdcPerInit * (10 ** usdcDecimals);
        gasRate = _rawGasPerInit * 1e18;
        
        emit RatesUpdated(usdcRate, gasRate);
    }

    /**
     * @notice Updates the anti-sybil deposit limit.
     */
    function updateMaxZap(uint256 _maxZap) external onlyOwner {
        maxZapPerWallet = _maxZap;
        emit MaxZapUpdated(_maxZap);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Allows the owner to recover all tokens and native gas from the contract.
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 initBal = bridgedInit.balanceOf(address(this));
        if (initBal > 0) bridgedInit.safeTransfer(owner(), initBal);

        uint256 usdcBal = testUsdc.balanceOf(address(this));
        if (usdcBal > 0) testUsdc.safeTransfer(owner(), usdcBal);

        uint256 gasBal = address(this).balance;
        if (gasBal > 0) {
            (bool success, ) = payable(owner()).call{value: gasBal}("");
            if (!success) revert FlowrollZapper__NativeTransferFailed();
        }
    }

    // --- PUBLIC VIEW ---

    /**
     * @notice Calculates the expected output for a given INIT input.
     * @param initAmount The amount of INIT to query.
     * @return usdcOut Expected USDC output in base units.
     * @return gasOut Expected Native Gas output in base units.
     */
    function getQuote(uint256 initAmount) public view returns (uint256 usdcOut, uint256 gasOut) {
        usdcOut = (initAmount * usdcRate) / initUnit;
        gasOut = (initAmount * gasRate) / initUnit;
    }
}