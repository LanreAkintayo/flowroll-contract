// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";

abstract contract SharedBase is Test {

    // ─── Actors ──────────────────────────────────────────────────────────────

    address internal owner        = makeAddr("owner");
    address internal agentOperator = makeAddr("agentOperator");
    address internal treasury     = makeAddr("treasury");
    address internal employer     = makeAddr("employer");
    address internal stranger     = makeAddr("stranger");
    address internal employee     = makeAddr("employee");

    // ─── Tokens ──────────────────────────────────────────────────────────────

    MockUSDC internal usdc;

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 internal constant INITIAL_SUPPLY  = 10_000_000e6; // 10M USDC
    uint256 internal constant DEPOSIT_AMOUNT  = 50_000e6;     // 50k USDC
    uint256 internal constant CYCLE_DURATION  = 30 days;
    uint256 internal constant SCALE           = 10_000;

    // ─── Setup ───────────────────────────────────────────────────────────────

    function setUp() public virtual {
        vm.startPrank(owner);
        usdc = new MockUSDC(INITIAL_SUPPLY);
        usdc.mint(treasury,  DEPOSIT_AMOUNT * 10);
        usdc.mint(employer,  DEPOSIT_AMOUNT * 10);
        usdc.mint(employee,  DEPOSIT_AMOUNT * 10);
        vm.stopPrank();
    }
}