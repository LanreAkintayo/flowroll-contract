// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPayrollManager {
    function cycleToGroup(address employer, uint256 cycleId) external view returns (uint256);
    function getGroupEmployees(address employer, uint256 groupId) external view returns (address[] memory);
    function getSalary(address employer, uint256 groupId, address employee) external view returns (uint256);
    function getTotalPayroll(address employer, uint256 groupId) external view returns (uint256);
}