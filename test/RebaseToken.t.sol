

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/Interfaces/IRebaseToken.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IAccessControl} from "../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address private owner;
    address private user;
    address private user2;

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");
        user2 = makeAddr("user2");

        vm.deal(owner, 10 ether);

        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));

        (bool success, ) = payable(address(vault)).call{value: 1 ether}("");
        assertTrue(success);
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) internal {
        if (rewardAmount == 0) return;
        vm.deal(address(this), rewardAmount);
        (bool success, ) = payable(address(vault)).call{value: rewardAmount}("");
        assertTrue(success);
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.deal(user, amount);

        vm.startPrank(user);
        vault.deposit{value: amount}();

        uint256 startBalance = rebaseToken.balanceOf(user);
        assertApproxEqAbs(startBalance, amount, 1);

        // Use the cheatcode timestamp getter so `via_ir` optimizations don't treat `block.timestamp` as constant.
        uint256 t0 = vm.getBlockTimestamp();
        vm.warp(t0 + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startBalance);

        vm.warp(t0 + 2 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, middleBalance);
        vm.stopPrank();

        // Allow 1 wei rounding difference from integer division.
        assertApproxEqAbs(
            endBalance - middleBalance,
            middleBalance - startBalance,
            1
        );
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.deal(user, amount);

        vm.startPrank(user);
        vault.deposit{value: amount}();
        vault.redeem(type(uint256).max);
        vm.stopPrank();

        assertEq(rebaseToken.balanceOf(user), 0);
        assertApproxEqAbs(user.balance, amount, 1);
    }

    function testRedeemAfterTimePassed(
        uint256 depositAmount,
        uint256 time
    ) public {
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);
        // Ensure enough time passes for at least 1 wei of interest
        // even for the minimum depositAmount, despite integer truncation.
        time = bound(time, 1 hours, type(uint96).max);

        vm.deal(user, depositAmount);
        vm.startPrank(user);
        vault.deposit{value: depositAmount}();

        vm.warp(block.timestamp + time);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user);
        vm.stopPrank();

        // Rewards are funded/sent from the test contract (not the pranked user).
        addRewardsToVault(balanceAfterSomeTime - depositAmount);

        vm.startPrank(user);
        vault.redeem(type(uint256).max);
        vm.stopPrank();

        assertGt(user.balance, depositAmount);
        assertApproxEqAbs(user.balance, balanceAfterSomeTime, 1);
    }

    function testTransferInheritsInterestRate(
        uint256 amount,
        uint256 amountToSend
    ) public {
        amount = bound(amount, 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1, amount);

        vm.deal(user, amount);
        vm.startPrank(user);
        vault.deposit{value: amount}();
        uint256 userLockedRate = rebaseToken.getUserInterestRate(user);

        // Owner reduces the global rate after user's deposit.
        vm.stopPrank();
        vm.prank(owner);
        rebaseToken.setInterestRate(userLockedRate - 1);

        // Transfer via transferFrom (custom logic lives there).
        vm.startPrank(user);
        rebaseToken.approve(user, amountToSend);
        rebaseToken.transferFrom(user, user2, amountToSend);
        vm.stopPrank();

        assertEq(rebaseToken.getUserInterestRate(user2), userLockedRate);
    }

    function testPrincipleBalanceOfDoesNotChange(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.deal(user, amount);

        vm.startPrank(user);
        vault.deposit{value: amount}();
        vm.stopPrank();

        assertEq(rebaseToken.principleBalanceOf(user), amount);

        vm.warp(block.timestamp + 7 days);
        assertEq(rebaseToken.principleBalanceOf(user), amount);
    }

    function testCannotSetInterestRate(uint256 newInterestRate) public {
        vm.prank(user);
        vm.expectPartialRevert(
            bytes4(Ownable.OwnableUnauthorizedAccount.selector)
        );
        rebaseToken.setInterestRate(newInterestRate);
    }



       function testCannotCallMintAndBurn() public {
        vm.prank(user);
        vm.expectPartialRevert(
            bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector)
        );
        rebaseToken.mint(user, 1 ether);

        vm.prank(user);
        vm.expectPartialRevert(
            bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector)
        );
        rebaseToken.burn(user, 1 ether);
    }
}