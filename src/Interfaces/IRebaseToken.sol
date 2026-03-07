// src/interfaces/IRebaseToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRebaseToken {
    /**
     * @notice Mints new tokens to a specified address.
     * @param _to The address to mint tokens to.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) external;

    /**
     * @notice Mints new tokens to a specified address with a preserved interest rate (e.g. when bridging from another chain).
     * @param _to The address to mint tokens to.
     * @param _amount The amount of tokens to mint.
     * @param _userInterestRate The interest rate to apply for the recipient (from source chain).
     */
    function mintWithInterestRate(address _to, uint256 _amount, uint256 _userInterestRate) external;

    /**
     * @notice Burns tokens from a specified address.
     * @param _from The address to burn tokens from.
     * @param _amount The amount of tokens to burn.
     */
    function burn(address _from, uint256 _amount) external;

    /**
     * @notice Returns the balance of an account, including accrued interest if applicable.
     * @param _user The address to query.
     */
    function balanceOf(address _user) external view returns (uint256);

    /**
     * @notice Returns the current interest rate for a user (used when bridging to preserve rate on destination).
     * @param _user The address to query.
     */
    function getUserInterestRate(address _user) external view returns (uint256);

      function grantMintAndBurnRole(address _account) external;
}


