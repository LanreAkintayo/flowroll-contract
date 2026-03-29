// SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// /**
//  * @title MockPayVault
//  * @notice Stub PayVault for PayrollDispatcher tests.
//  *         Records credits, never reverts, pulls USDC on credit().
//  */
// contract MockPayVault {
//     address public usdc;

//     mapping(address => uint256) public credited;
//     address[] public creditedEmployees;
//     uint256 public creditCallCount;

//     constructor(address _usdc) {
//         usdc = _usdc;
//     }

//     function credit(address employee, uint256 amount) external {
//         IERC20(usdc).transferFrom(msg.sender, address(this), amount);
//         if (credited[employee] == 0) {
//             creditedEmployees.push(employee);
//         }
//         credited[employee] += amount;
//         creditCallCount++;
//     }

//     function getCreditedEmployees() external view returns (address[] memory) {
//         return creditedEmployees;
//     }

//     function reset() external {
//         for (uint256 i = 0; i < creditedEmployees.length; i++) {
//             credited[creditedEmployees[i]] = 0;
//         }
//         delete creditedEmployees;
//         creditCallCount = 0;
//     }
// }








pragma solidity ^0.8.24;

/**
 * @title MockPayVault
 * @notice Stub implementation of IPayVault for testing PayrollDispatcher.
 * @dev Tracks credits per employee. Replace with real PayVault in integration tests.
 */
contract MockPayVault {

    // ─── Events ──────────────────────────────────────────────────────────────

    event Credited(address indexed employee, uint256 amount);

    // ─── State ───────────────────────────────────────────────────────────────

    mapping(address => uint256) public balances;
    mapping(address => uint256) public creditCount;
    uint256 public totalCredited;

    // ─── Interface ───────────────────────────────────────────────────────────

    function credit(address employee, uint256 amount) external {
        balances[employee]    += amount;
        creditCount[employee] += 1;
        totalCredited         += amount;
        emit Credited(employee, amount);
    }
}
