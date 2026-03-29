// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPayVault {
    struct EmployeeRouting {
        address evmAddress;      // explicit EVM address — priority 1
        string  initUsername;    // .init username — priority 2
        bool    isCrossChain;    // true = route via IBC
        string  channel;         // IBC channel e.g. "channel-0"
        string  cosmosAddress;   // bech32 destination address for cross-chain
    }

    function credit(address employee, uint256 amount) external;
    function getRouting(address employee) external view returns (EmployeeRouting memory);
}