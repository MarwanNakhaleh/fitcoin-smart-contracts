// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

/**
 * @title Vault contract interface
 * @author Branson Solutions LLC
 * @notice Interface for storing user bets
 */
interface IVault {
    /// @notice Emitted when a user deposits funds.
    /// @param user The address depositing funds.
    /// @param amount The amount deposited.
    /// @param isToken True if the deposit was in tokens, false for ETH.
    event Deposited(address indexed user, uint256 amount, bool isToken);

    /// @notice Emitted when funds are withdrawn/distributed from the vault.
    /// @param recipient The address that received funds.
    /// @param amount The amount withdrawn.
    /// @param isToken True if the withdrawal was in tokens, false for ETH.
    event Withdrawn(address indexed recipient, uint256 amount, bool isToken);

    /// @notice Emitted when an ERC-20 token address is set.
    event TokenAddressSet(address tokenAddress);

    /*
    * @notice Deposit ETH into the vault. 
    */
    function depositETH() external payable;

    /*
    * @notice Withdraw funds from the vault.
    * @param recipient The address to receive the funds.
    * @param amount The amount to withdraw.
    * @param isToken True if the withdrawal was in tokens, false for ETH.
    */
    function withdrawFunds(address payable recipient, uint256 amount, bool isToken) external;
}