// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockERC20} from "../../../src/mocks/MockERC20.sol";
import {FlowrollZapper} from "../../../src/FlowrollZapper.sol";

/**
 * @title FlowrollZapperTest
 * @notice Comprehensive Foundry test suite for the Flowroll Onboarding Zapper.
 */
contract FlowrollZapperTest is Test {
    FlowrollZapper public zapper;
    MockERC20 public bridgedInit;
    MockERC20 public testUsdc;

    address public owner = address(this);
    address public lanre = address(0x123);

    uint256 constant INIT_DECIMALS = 18;
    uint256 constant USDC_DECIMALS = 6;
    
    uint256 constant INIT_UNIT = 10 ** INIT_DECIMALS;
    uint256 constant USDC_UNIT = 10 ** USDC_DECIMALS;
    uint256 constant GAS_UNIT = 10 ** 18;

    uint256 constant USDC_PER_INIT = 500;
    uint256 constant GAS_PER_INIT = 10;
    uint256 constant MAX_ZAP = 100 * INIT_UNIT;

    function setUp() public {
        bridgedInit = new MockERC20("Bridged INIT", "INIT", uint8(INIT_DECIMALS));
        testUsdc = new MockERC20("Test USDC", "USDC", uint8(USDC_DECIMALS));

        zapper = new FlowrollZapper(
            address(bridgedInit),
            address(testUsdc),
            USDC_PER_INIT,
            GAS_PER_INIT,
            MAX_ZAP
        );

        testUsdc.mint(address(zapper), 100_000 * USDC_UNIT);
        vm.deal(address(zapper), 1000 ether);

        bridgedInit.mint(lanre, 50 * INIT_UNIT);
    }

    /* ========================================== */
    /* STATE TESTS                                */
    /* ========================================== */

    function test_InitialState() public view {
        assertEq(address(zapper.bridgedInit()), address(bridgedInit));
        assertEq(address(zapper.testUsdc()), address(testUsdc));
        assertEq(zapper.initUnit(), INIT_UNIT);
        assertEq(zapper.usdcRate(), USDC_PER_INIT * USDC_UNIT);
        assertEq(zapper.gasRate(), GAS_PER_INIT * GAS_UNIT);
        assertEq(zapper.maxZapPerWallet(), MAX_ZAP);
    }

    function test_GetQuote() public view {
        uint256 zapAmount = 2 * INIT_UNIT;
        (uint256 usdcOut, uint256 gasOut) = zapper.getQuote(zapAmount);

        assertEq(usdcOut, 2 * USDC_PER_INIT * USDC_UNIT);
        assertEq(gasOut, 2 * GAS_PER_INIT *  GAS_UNIT);
    }

    /* ========================================== */
    /* ZAP TESTS                                  */
    /* ========================================== */

    function test_Zap_Success() public {
        uint256 zapAmount = 5 * INIT_UNIT;

        vm.startPrank(lanre);
        bridgedInit.approve(address(zapper), zapAmount);

        uint256 lanreInitBefore = bridgedInit.balanceOf(lanre);
        uint256 lanreUsdcBefore = testUsdc.balanceOf(lanre);
        uint256 lanreGasBefore = lanre.balance;

        zapper.zap(zapAmount);
        vm.stopPrank();

        assertEq(bridgedInit.balanceOf(lanre), lanreInitBefore - zapAmount);
        assertEq(testUsdc.balanceOf(lanre), lanreUsdcBefore + (2500 * USDC_UNIT));
        assertEq(lanre.balance, lanreGasBefore + (50 * GAS_UNIT));
        
        assertEq(zapper.totalZapped(lanre), zapAmount);
    }

    function test_Zap_RevertIfAmountZero() public {
        vm.prank(lanre);
        vm.expectRevert(FlowrollZapper.FlowrollZapper__AmountTooLow.selector);
        zapper.zap(0);
    }

    function test_Zap_RevertIfExceedsMaxLimit() public {
        uint256 zapAmount = 101 * INIT_UNIT;
        bridgedInit.mint(lanre, zapAmount);

        vm.startPrank(lanre);
        bridgedInit.approve(address(zapper), zapAmount);
        
        vm.expectRevert(FlowrollZapper.FlowrollZapper__ExceedsMaxZapLimit.selector);
        zapper.zap(zapAmount);
        vm.stopPrank();
    }

    function test_Zap_RevertIfTreasuryEmpty() public {
        zapper.emergencyWithdraw();

        uint256 zapAmount = 1 * INIT_UNIT;
        vm.startPrank(lanre);
        bridgedInit.approve(address(zapper), zapAmount);

        vm.expectRevert(FlowrollZapper.FlowrollZapper__InsufficientTreasuryBalance.selector);
        zapper.zap(zapAmount);
        vm.stopPrank();
    }

    /* ========================================== */
    /* ADMIN TESTS                                */
    /* ========================================== */

    function test_EmergencyWithdraw() public {
        uint256 zapAmount = 1 * INIT_UNIT;
        vm.startPrank(lanre);
        bridgedInit.approve(address(zapper), zapAmount);
        zapper.zap(zapAmount);
        vm.stopPrank();

        uint256 contractInit = bridgedInit.balanceOf(address(zapper));
        uint256 contractUsdc = testUsdc.balanceOf(address(zapper));
        uint256 contractGas = address(zapper).balance;

        uint256 ownerInitBefore = bridgedInit.balanceOf(owner);
        uint256 ownerUsdcBefore = testUsdc.balanceOf(owner);
        uint256 ownerGasBefore = owner.balance;

        zapper.emergencyWithdraw();

        assertEq(bridgedInit.balanceOf(owner), ownerInitBefore + contractInit);
        assertEq(testUsdc.balanceOf(owner), ownerUsdcBefore + contractUsdc);
        assertEq(owner.balance, ownerGasBefore + contractGas);

        assertEq(bridgedInit.balanceOf(address(zapper)), 0);
        assertEq(testUsdc.balanceOf(address(zapper)), 0);
        assertEq(address(zapper).balance, 0);
    }

    receive() external payable {}
}