// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolAdapter} from "../interfaces/IPoolAdapter.sol";

/**
 * @title BasePoolAdapter
 * @notice Abstract base contract for Flowroll pool adapters.
 * @dev Provides shared state, authorization, and safe token operations.
 */
abstract contract BasePoolAdapter is Ownable, IPoolAdapter {
    using SafeERC20 for IERC20;

    error Adapter__ZeroAddress();
    error Adapter__ZeroAmount();
    error Adapter__ZeroShares();
    error Adapter__InsufficientReceived(uint256 expected, uint256 received);
    error Adapter__PoolCallFailed();

    event PoolUpdated(address indexed previousPool, address indexed newPool);
    event Deposited(uint256 usdcAmount, uint256 sharesReceived);
    event Withdrawn(uint256 sharesReturned, uint256 usdcReceived);

    /// @notice USDC token address.
    address public immutable usdc;

    /// @notice Underlying pool address.
    address public pool;

    /**
     * @param _usdc USDC token address.
     * @param _pool Underlying pool address.
     */
    constructor(address _usdc, address _pool) Ownable(msg.sender) {
        if (_usdc == address(0)) revert Adapter__ZeroAddress();
        if (_pool == address(0)) revert Adapter__ZeroAddress();
        usdc = _usdc;
        pool = _pool;
    }

    /**
     * @notice Updates the underlying pool address.
     * @param _newPool New pool address.
     */
    function setPool(address _newPool) external onlyOwner {
        if (_newPool == address(0)) revert Adapter__ZeroAddress();
        emit PoolUpdated(pool, _newPool);
        pool = _newPool;
    }

    /// @inheritdoc IPoolAdapter
    function deposit(uint256 amount) external virtual override returns (uint256 shares);

    /// @inheritdoc IPoolAdapter
    function withdraw(uint256 shares) external virtual override returns (uint256 amountReceived);

    /// @inheritdoc IPoolAdapter
    function getApyBps() external view virtual override returns (uint256);

    /// @inheritdoc IPoolAdapter
    function getTvl() external view virtual override returns (uint256);

    /// @inheritdoc IPoolAdapter
    function isStablePair() external view virtual override returns (bool);

    /// @inheritdoc IPoolAdapter
    function getPositionValue(address holder) external view virtual override returns (uint256);

    /// @inheritdoc IPoolAdapter
    function sharesToValue(uint256 shares) external view virtual override returns (uint256);

    /**
     * @notice Approves the pool to spend USDC.
     * @param amount Amount to approve.
     */
    function _approvePool(uint256 amount) internal {
        IERC20(usdc).forceApprove(pool, amount);
    }

    /**
     * @notice Transfers USDC from the caller to this adapter.
     * @param amount Amount to pull.
     */
    function _pullUsdc(uint256 amount) internal {
        if (amount == 0) revert Adapter__ZeroAmount();
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Transfers USDC from this adapter to the caller.
     * @param amount Amount to push.
     */
    function _pushUsdc(uint256 amount) internal {
        if (amount == 0) revert Adapter__ZeroAmount();
        IERC20(usdc).safeTransfer(msg.sender, amount);
    }
}