
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address private owner;
    address private user;

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");

        vm.deal(owner, 10 ether);

        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));

        (bool success, ) = payable(address(vault)).call{value: 1 ether}("");
        assertTrue(success);
        vm.stopPrank();
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.deal(user, amount);

        vm.startPrank(user);
        vault.deposit{value: amount}();

        uint256 initialBalance = rebaseToken.balanceOf(user);

        uint256 timeDelta = 1 days;
        vm.warp(block.timestamp + timeDelta);
        uint256 balanceAfterFirstWarp = rebaseToken.balanceOf(user);
        uint256 interestFirstPeriod = balanceAfterFirstWarp - initialBalance;

        vm.warp(block.timestamp + timeDelta);
        uint256 balanceAfterSecondWarp = rebaseToken.balanceOf(user);
        uint256 interestSecondPeriod = balanceAfterSecondWarp - balanceAfterFirstWarp;
        vm.stopPrank();

        // Allow 1 wei rounding difference from integer division.
        assertApproxEqAbs(interestFirstPeriod, interestSecondPeriod, 1);
    }
}