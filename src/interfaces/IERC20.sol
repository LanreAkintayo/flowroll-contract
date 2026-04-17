// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IERC20
 * @notice Standard interface for ERC20 token interactions.
 * @dev Interface for USDC and other compatible assets within Flowroll.
 */
interface IERC20 {
    /**
     * @notice Transfers tokens to a specific recipient.
     * @param to The address of the recipient.
     * @param amount The number of tokens to transfer.
     * @return success Boolean indicating if the operation succeeded.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @notice Transfers tokens from one address to another using an allowance.
     * @param from The address holding the tokens.
     * @param to The address receiving the tokens.
     * @param amount The number of tokens to transfer.
     * @return success Boolean indicating if the operation succeeded.
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /**
     * @notice Sets an allowance for a spender over the caller's tokens.
     * @param spender The address authorized to spend the tokens.
     * @param amount The maximum number of tokens allowed.
     * @return success Boolean indicating if the operation succeeded.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @notice Returns the token balance of a specific account.
     * @param account The address to query.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Returns the remaining allowance a spender has for an owner.
     * @param owner The address providing the allowance.
     * @param spender The address authorized to spend.
     */
    function allowance(address owner, address spender) external view returns (uint256);
}