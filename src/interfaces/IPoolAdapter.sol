// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPoolAdapter
 * @notice Standard interface for all Flowroll pool adapters.
 * @dev Standardizes interactions between YieldRouter and underlying yield sources.
 */
interface IPoolAdapter {
    /**
     * @notice Deposits USDC into the underlying pool.
     * @param amount USDC amount to deposit (6 decimals).
     * @return shares Amount of shares or LP tokens minted.
     */
    function deposit(uint256 amount) external returns (uint256 shares);

    /**
     * @notice Withdraws USDC from the pool by burning shares.
     * @param shares Amount of shares or LP tokens to burn.
     * @return amountReceived Total USDC received including accrued yield.
     */
    function withdraw(uint256 shares) external returns (uint256 amountReceived);

    /// @notice Returns the current pool APY in basis points.
    function getApyBps() external view returns (uint256);

    /// @notice Returns the Total Value Locked (TVL) in the pool in USDC (6 decimals).
    function getTvl() external view returns (uint256);

    /// @notice Indicates if the pool is a stablecoin pair.
    function isStablePair() external view returns (bool);

    /**
     * @notice Returns the total USDC value of the position held by a specific address.
     * @param holder Address of the position owner.
     */
    function getPositionValue(address holder) external view returns (uint256);

    /**
     * @notice Calculates the USDC value for a specific amount of shares.
     * @param shares The number of shares to evaluate.
     */
    function sharesToValue(uint256 shares) external view returns (uint256);
}