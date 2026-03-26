// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPool
 * @notice Interface for InitiaDEX liquidity pools
 * @dev MockPool.sol implements this for testnet development.
 *      Replace with real InitiaDEX pool interface once testnet
 *      pool addresses are confirmed.
 */
interface IPool {
    function deposit(uint256 amount) external returns (uint256 shares);
    function withdraw(uint256 shares) external returns (uint256 amount);
    function getPositionValue(address user) external view returns (uint256);
    function getApyBps() external view returns (uint256);
    function getTvl() external view returns (uint256);
    function isStablePair() external view returns (bool);
    function shares(address user) external view returns (uint256);
}
