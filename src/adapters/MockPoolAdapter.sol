// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {BasePoolAdapter} from "./BasePoolAdapter.sol";
import {IPoolAdapter} from "../interfaces/IPoolAdapter.sol";

/**
 * @title MockPoolAdapter
 * @notice Stateless routing adapter for the MockPool ERC4626 vault.
 * @dev Facilitates deposits and withdrawals between YieldRouter and the vault.
 * Mints shares to this adapter and routes assets seamlessly to maintain a zero balance.
 */
contract MockPoolAdapter is BasePoolAdapter {

    /**
     * @param _usdc MockUSDC token address.
     * @param _mockPool MockPool (ERC4626) vault address.
     */
    constructor(
        address _usdc,
        address _mockPool
    ) BasePoolAdapter(_usdc, _mockPool) {}

    /**
     * @notice Deposits USDC into the vault and mints ERC4626 shares.
     * @dev Pulls USDC from the caller, approves the vault, and executes the deposit.
     * @param amount The amount of USDC to deposit (6 decimals).
     * @return shares The number of ERC4626 share tokens minted.
     */
    function deposit(uint256 amount) external override returns (uint256 shares) {
        if (amount == 0) revert Adapter__ZeroAmount();

        _pullUsdc(amount);
        _approvePool(amount);

        shares = IERC4626(pool).deposit(amount, address(this));
        if (shares == 0) revert Adapter__PoolCallFailed();

        emit Deposited(amount, shares);
    }

    /**
     * @notice Redeems vault shares and routes USDC back to the YieldRouter.
     * @dev Approves the vault to burn shares and routes withdrawn assets directly to msg.sender.
     * @param shares The number of shares to redeem.
     * @return amountReceived The exact USDC amount received (principal + yield).
     */
    function withdraw(uint256 shares) external override returns (uint256 amountReceived) {
        if (shares == 0) revert Adapter__ZeroShares();

        IERC20(pool).approve(pool, shares);

        amountReceived = IERC4626(pool).redeem(shares, msg.sender, address(this));
        if (amountReceived == 0) revert Adapter__PoolCallFailed();

        emit Withdrawn(shares, amountReceived);
    }

    /// @notice Returns current APY in basis points.
    function getApyBps() external view override returns (uint256) {
        return IPoolAdapter(pool).getApyBps();
    }

    /// @notice Returns total assets currently locked in the vault.
    function getTvl() external view override returns (uint256) {
        return IPoolAdapter(pool).getTvl();
    }

    /// @notice Returns whether the pool is a stable pair.
    function isStablePair() external view override returns (bool) {
        return IPoolAdapter(pool).isStablePair();
    }

    /**
     * @notice Returns the total USDC value of a specific holder's position.
     * @param holder The address of the position owner.
     */
    function getPositionValue(address holder) external view override returns (uint256) {
        return IPoolAdapter(pool).getPositionValue(holder);
    }

    /**
     * @notice Calculates the USDC value for a given amount of shares.
     * @param shares The number of shares to value.
     */
    function sharesToValue(uint256 shares) external view override returns (uint256) {
        return IPoolAdapter(pool).sharesToValue(shares);
    }
}