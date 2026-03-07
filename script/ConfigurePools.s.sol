// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TokenPool} from "@ccip/contracts/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/libraries/RateLimiter.sol";

/// @notice Configures a RebaseTokenPool for cross-chain with a single remote chain.
/// Run with --sig "run(address,uint64,address,address)" <POOL_ADDRESS> <REMOTE_CHAIN_SELECTOR> <REMOTE_POOL_ADDRESS> <REMOTE_TOKEN_ADDRESS>
contract ConfigurePoolScript is Script {
    function run(
        address poolAddress,
        uint64 remoteChainSelector,
        address remotePoolAddress,
        address remoteTokenAddress
    ) public {
        uint64[] memory chainSelectorsToRemove = new uint64[](0);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePoolAddress);

        RateLimiter.Config memory rateLimitOff = RateLimiter.Config({
            isEnabled: false,
            capacity: 0,
            rate: 0
        });

        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: rateLimitOff,
            inboundRateLimiterConfig: rateLimitOff
        });

        vm.startBroadcast();
        TokenPool(poolAddress).applyChainUpdates(chainSelectorsToRemove, chainsToAdd);
        vm.stopBroadcast();

        console.log("Pool", poolAddress, "configured for remote chain", remoteChainSelector);
    }
}
