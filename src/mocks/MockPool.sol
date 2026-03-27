// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockPool
 * @notice Simulated ERC4626 yield vault for local development and testing.
 * @dev Facilitates yield simulation by allowing direct asset injection to appreciate share value.
 */
contract MockPool is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    error MockPool__ZeroAmount();

    event YieldSimulated(uint256 amount, uint256 newTotalAssets);
    event ApyUpdated(uint256 previousApyBps, uint256 newApyBps);

    /// @notice Human-readable pool name.
    string public poolName;

    /// @notice Indicates if the pool is a stablecoin pair.
    bool public immutable STABLE_PAIR;

    /// @notice Reported APY in basis points.
    uint256 public apyBps;

    /**
     * @param _asset Underlying ERC20 asset address.
     * @param _poolName Human-readable pool identifier.
     * @param _apyBps Initial APY in basis points.
     * @param _stablePair True if the pool carries no impermanent loss risk.
     * @param _shareName ERC20 name for the vault share token.
     * @param _shareSymbol ERC20 symbol for the vault share token.
     */
    constructor(
        address _asset,
        string memory _poolName,
        uint256 _apyBps,
        bool _stablePair,
        string memory _shareName,
        string memory _shareSymbol
    )
        ERC4626(IERC20(_asset))
        ERC20(_shareName, _shareSymbol)
        Ownable(msg.sender)
    {
        poolName = _poolName;
        apyBps = _apyBps;
        STABLE_PAIR = _stablePair;
    }

    /**
     * @notice Simulates yield by injecting assets directly into the vault.
     * @dev Increases totalAssets without minting new shares, appreciating the exchange rate.
     * @param amount The amount of underlying assets to inject (6 decimals).
     */
    function simulateYield(uint256 amount) external onlyOwner {
        if (amount == 0) revert MockPool__ZeroAmount();

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        emit YieldSimulated(amount, totalAssets());
    }

    /**
     * @notice Updates the reported APY.
     * @param _apyBps New APY in basis points.
     */
    function setApyBps(uint256 _apyBps) external onlyOwner {
        emit ApyUpdated(apyBps, _apyBps);
        apyBps = _apyBps;
    }

    /// @notice Returns current APY in basis points.
    function getApyBps() external view returns (uint256) {
        return apyBps;
    }

    /// @notice Returns total assets currently locked in the vault.
    function getTvl() external view returns (uint256) {
        return totalAssets();
    }

    /// @notice Returns whether the pool is a stable pair.
    function isStablePair() external view returns (bool) {
        return STABLE_PAIR;
    }

    /**
     * @notice Returns the total USDC value of a specific holder's position.
     * @param holder The address of the position owner.
     */
    function getPositionValue(address holder) external view returns (uint256) {
        return convertToAssets(balanceOf(holder));
    }

    /**
     * @notice Calculates the underlying asset value for a specific amount of shares.
     * @param shares The number of shares to evaluate.
     */
    function sharesToValue(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }
}