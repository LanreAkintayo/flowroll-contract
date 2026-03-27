// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockUSDC
 * @notice ERC20 mock token representing USDC for local development and testing.
 * @dev Overrides default decimals to 6 to mirror mainnet USDC behavior.
 */
contract MockUSDC is ERC20, Ownable {

    error MockUSDC__ZeroAddress();
    error MockUSDC__ZeroAmount();

    /**
     * @param initialSupply Initial token supply minted to the deployer.
     */
    constructor(uint256 initialSupply) ERC20("USD Coin", "USDC") Ownable(msg.sender) {
        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply);
        }
    }

    /// @notice Overrides default ERC20 decimals to 6.
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @notice Mints new MockUSDC tokens.
     * @param to Recipient address.
     * @param amount Amount to mint.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert MockUSDC__ZeroAddress();
        if (amount == 0) revert MockUSDC__ZeroAmount();
        _mint(to, amount);
    }
}