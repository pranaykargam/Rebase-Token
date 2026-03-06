// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {TokenPool} from "@ccip/contracts/pools/TokenPool.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.3/token/ERC20/IERC20.sol";
import {IRebaseToken} from "./Interfaces/IRebaseToken.sol";
import {Pool} from "@ccip/contracts/libraries/Pool.sol"; 



contract RebaseTokenPool is TokenPool {

    // This pool fixes that by propagating each user's personal interest rate via CCIP messages.
    // Without this code: Interest lost on every bridge 
    // With this code: Interest preserved perfectly across chains

That's why `userInterestRate` travels in the CCIP message! 🚀

    constructor(
        IERC20 _token,
        address[] memory _allowlist,
        address _rnmProxy,
        address _router
    ) TokenPool(_token, 18, _allowlist, _rnmProxy, _router) {
     
    }

    function lockOrBurn(
        Pool.LockOrBurnInV1 calldata lockOrBurnIn
    ) public override returns (Pool.LockOrBurnOutV1 memory) {
        _validateLockOrBurn(lockOrBurnIn);

        address originalSender = lockOrBurnIn.originalSender;

        // Fetch the user's current interest rate from the rebase token
        uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(originalSender);

        // Burn the specified amount of tokens from this pool contract
        // CCIP transfers tokens to the pool before lockOrBurn is called
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        emit LockedOrBurned({
            remoteChainSelector: lockOrBurnIn.remoteChainSelector,
            token: address(i_token),
            sender: msg.sender,
            amount: lockOrBurnIn.amount
        });

        return Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
    }

        function releaseOrMint(
        Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
    ) public override returns (Pool.ReleaseOrMintOutV1 memory /* releaseOrMintOut */) { // Named return optional
        _validateReleaseOrMint(releaseOrMintIn, releaseOrMintIn.sourceDenominatedAmount);

        // Decode the user interest rate sent from the source pool
        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
        
        // The receiver address is directly available
        address receiver = releaseOrMintIn.receiver;

        // Mint tokens to the receiver, applying the propagated interest rate
        IRebaseToken(address(i_token)).mintWithInterestRate(
            receiver,
            releaseOrMintIn.sourceDenominatedAmount,
            userInterestRate
        );

        return Pool.ReleaseOrMintOutV1({
            destinationAmount: releaseOrMintIn.sourceDenominatedAmount
        });
    }
}


