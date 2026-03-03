// src/Vault.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebaseToken} from "./Interfaces/IRebaseToken.sol";

contract Vault {
    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    error Vault_RedeemFailed();
    error Vault_DepositAmountIsZero();

    constructor(IRebaseToken _rebaseTokenAddress) {
        i_rebaseToken = _rebaseTokenAddress;
    }

    /**
     * @notice Fallback function to accept ETH rewards sent directly to the contract.
     */
    receive() external payable {}

    /**
     * @notice Allows a user to deposit ETH and receive an equivalent amount of RebaseTokens.
     */
    function deposit() external payable {
        uint256 amountToMint = msg.value;
        if (amountToMint == 0) {
            revert Vault_DepositAmountIsZero();
        }
        i_rebaseToken.mint(msg.sender, amountToMint);
        emit Deposit(msg.sender, amountToMint);
    }

    /**
     * @notice Allows a user to burn their RebaseTokens and receive a corresponding amount of ETH.
     * @param _amount The amount of RebaseTokens to redeem.
     * @dev Follows Checks-Effects-Interactions pattern. Uses low-level .call for ETH transfer.
     */
    function redeem(uint256 _amount) external {
        uint256 amountToRedeem = _amount;
        if (_amount == type(uint256).max) {
            amountToRedeem = i_rebaseToken.balanceOf(msg.sender);
        }

        i_rebaseToken.burn(msg.sender, amountToRedeem);

        (bool success, ) = payable(msg.sender).call{value: amountToRedeem}("");
        if (!success) {
            revert Vault_RedeemFailed();
        }

        emit Redeem(msg.sender, amountToRedeem);
    }

    /**
     * @notice Gets the address of the RebaseToken contract associated with this vault.
     * @return The address of the RebaseToken.
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
