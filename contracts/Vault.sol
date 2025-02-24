// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol"; 
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./interfaces/IVault.sol";
import "./interfaces/IChallenge.sol";
/**
 * @title Vault
 * @notice An upgradeable vault for holding bets. It supports ETH deposits by default
 * and can optionally support an ERC-20 token once the owner sets its address.
 */
contract Vault is 
    IVault,
    UUPSUpgradeable, 
    OwnableUpgradeable, 
    PausableUpgradeable, 
    ReentrancyGuardUpgradeable 
{
    /// @notice ERC-20 token used for bets. When unset (address(0)) only ETH bets are supported.
    IERC20 public token;

    /// @notice The challenge contract that is using the vault.
    IChallenge internal challengeContract;

    // ============================ //
    //           Errors             //
    // ============================ //

    error UnauthorizedCaller();

    /**
     * @notice Initializes the vault.
     * @dev The token remains unset (address(0)) so that bets default to ETH.
     */
    function initialize(address _challengeContract) external initializer {
        __Ownable_init(msg.sender);
        transferOwnership(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        
        challengeContract = IChallenge(_challengeContract);
    }

    /**
     * @notice Sets the ERC-20 token to be used for bets.
     * @dev Can only be called by the owner. It can only be set once.
     * @param tokenAddress The address of the ERC-20 token contract.
     */
    function setTokenAddress(address tokenAddress) external onlyOwner {
        require(address(token) == address(0), "Token already set");
        require(tokenAddress != address(0), "Token address cannot be zero");
        token = IERC20(tokenAddress);
        emit TokenAddressSet(tokenAddress);
    }

    /**
     * @notice Deposit ETH into the vault.
     */
    function depositETH() external payable nonReentrant whenNotPaused {
        require(msg.value > 0, "Must send ETH");
        emit Deposited(msg.sender, msg.value, false);
    }

    /**
     * @notice Deposit ERC-20 tokens into the vault.
     * @dev The token address must be set via setTokenAddress.
     * The sender must have approved the vault to transfer tokens.
     * @param amount The amount of tokens to deposit.
     */
    function depositToken(uint256 amount) external nonReentrant whenNotPaused {
        require(address(token) != address(0), "Token not set");
        require(amount > 0, "Amount must be > 0");
        bool success = token.transferFrom(msg.sender, address(this), amount);
        require(success, "Token transfer failed");
        emit Deposited(msg.sender, amount, true);
    }

    /**
     * @notice Withdraw funds from the vault.
     * @dev Only callable by the owner (e.g. from your Challenge contract logic).
     * @param recipient The address to receive the funds.
     * @param amount The amount to withdraw.
     * @param isToken If true, withdraw tokens; otherwise, withdraw ETH.
     */
    function withdrawFunds(address payable recipient, uint256 amount, bool isToken) external nonReentrant whenNotPaused {
        if (msg.sender != address(challengeContract)) {
            revert UnauthorizedCaller();
        }
        require(recipient != address(0), "Recipient cannot be zero");
        require(amount > 0, "Amount must be > 0");
        if (isToken) {
            require(address(token) != address(0), "Token not set");
            uint256 tokenBalance = token.balanceOf(address(this));
            require(amount <= tokenBalance, "Insufficient token balance");
            bool success = token.transfer(recipient, amount);
            require(success, "Token transfer failed");
        } else {
            uint256 ethBalance = address(this).balance;
            require(amount <= ethBalance, "Insufficient ETH balance");
            (bool success, ) = recipient.call{value: amount}("");
            require(success, "ETH transfer failed");
        }
        emit Withdrawn(recipient, amount, isToken);
    }

    /**
     * @notice Returns the vault balance.
     * @param isToken If true, returns the token balance; otherwise, returns the ETH balance.
     */
    function getBalance(bool isToken) external view returns (uint256) {
        if (isToken) {
            return (address(token) != address(0)) ? token.balanceOf(address(this)) : 0;
        } else {
            return address(this).balance;
        }
    }

    /**
     * @dev Authorizes upgrades of the contract.
     * Only the owner is allowed to upgrade.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
