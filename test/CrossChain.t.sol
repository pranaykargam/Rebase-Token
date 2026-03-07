// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

// Import your project-specific contracts
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/Interfaces/IRebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.3/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "@ccip/contracts/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/libraries/RateLimiter.sol";
import {Client} from "@ccip/contracts/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/interfaces/IRouterClient.sol";

// Chainlink Local simulator
import {CCIPLocalSimulatorFork} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {Register} from "@chainlink-local/src/ccip/Register.sol";

contract CrossChainTest is Test {
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;
    Vault vault; // Only on Sepolia

    RebaseTokenPool sepoliaPool;
    RebaseTokenPool arbSepoliaPool;

    address owner;
    address user;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    function setUp() public {
        // 1. Create owner and user
        owner = address(0x1234);
        user = vm.addr(1);

        // 2. Create forks
        sepoliaFork = vm.createSelectFork("sepolia");
        arbSepoliaFork = vm.createFork("arb-sepolia");

        // 3. Deploy CCIP Local Simulator
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // 4. Get network details for both chains
        vm.selectFork(sepoliaFork);
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        // 5. Deploy contracts on Sepolia
        vm.selectFork(sepoliaFork);
        vm.startPrank(owner);
        
        sepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );

        // Register admin and accept admin role
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress)
            .acceptAdminRole(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(sepoliaToken), address(sepoliaPool));

        // Grant roles to vault and pool
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));
        
        vm.stopPrank();

        // 6. Deploy contracts on Arbitrum Sepolia
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);

        arbSepoliaToken = new RebaseToken();
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );

        // Register admin and accept admin role
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .acceptAdminRole(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(arbSepoliaToken), address(arbSepoliaPool));

        // Grant roles to pool
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));
        
        vm.stopPrank();

        // 7. Configure token pools for cross-chain communication
        configureTokenPool(
            sepoliaFork,                            // Local chain: Sepolia
            address(sepoliaPool),                   // Local pool: Sepolia's TokenPool
            arbSepoliaNetworkDetails.chainSelector, // Remote chain selector: Arbitrum Sepolia
            address(arbSepoliaPool),                // Remote pool address
            address(arbSepoliaToken)                // Remote token address
        );

        configureTokenPool(
            arbSepoliaFork,                         // Local chain: Arbitrum Sepolia
            address(arbSepoliaPool),                // Local pool: Arbitrum Sepolia's TokenPool
            sepoliaNetworkDetails.chainSelector,    // Remote chain selector: Sepolia
            address(sepoliaPool),                   // Remote pool address
            address(sepoliaToken)                   // Remote token address
        );
    }

    function configureTokenPool(
        uint256 forkId,
        address localPoolAddress,
        uint64 remoteChainSelector,
        address remotePoolAddress,
        address remoteTokenAddress
    ) internal {
        // Select the correct fork (local chain context)
        vm.selectFork(forkId);

        // Prepare arguments for applyChainUpdates
        uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        // ABI-encode remote pool addresses array
        bytes[] memory remotePoolAddressesBytesArray = new bytes[](1);
        remotePoolAddressesBytesArray[0] = abi.encode(remotePoolAddress);
        
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddressesBytesArray,
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false,
                capacity: 0,
                rate: 0
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false,
                capacity: 0,
                rate: 0
            })
        });

        // Execute applyChainUpdates as owner
        vm.prank(owner);
        TokenPool(localPoolAddress).applyChainUpdates(
            remoteChainSelectorsToRemove,
            chainsToAdd
        );
    }

    function testSepoliaVaultHasCorrectToken() public {
        vm.selectFork(sepoliaFork);
        assertEq(vault.getRebaseTokenAddress(), address(sepoliaToken));
    }

    function testSepoliaPoolHasCorrectToken() public {
        vm.selectFork(sepoliaFork);
        assertEq(address(sepoliaPool.getToken()), address(sepoliaToken));
    }

    function testArbSepoliaPoolHasCorrectToken() public {
        vm.selectFork(arbSepoliaFork);
        assertEq(address(arbSepoliaPool.getToken()), address(arbSepoliaToken));
    }

    function testPoolsConfigured() public {
        // Test Sepolia pool configuration
        vm.selectFork(sepoliaFork);
        // Add specific assertions for pool configuration if needed
        
        // Test Arbitrum Sepolia pool configuration
        vm.selectFork(arbSepoliaFork);
        // Add specific assertions for pool configuration if needed
    }

    /*//////////////////////////////////////////////////////////////
                            BRIDGE FUNCTION 
    //////////////////////////////////////////////////////////////*/

    function bridgeTokens(
        address fromUser,
        uint256 amountToBridge,
        uint256 localFork, // Source chain fork ID
        uint256 remoteFork, // Destination chain fork ID
        Register.NetworkDetails memory localNetworkDetails, // Struct with source chain info
        Register.NetworkDetails memory remoteNetworkDetails, // Struct with dest. chain info
        RebaseToken localToken, // Source token contract instance
        RebaseToken remoteToken // Destination token contract instance
    ) internal {
        // -- On localFork, pranking as user --
        vm.selectFork(localFork);

        // 1. Initialize tokenAmounts array
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(localToken), // Token address on the local chain
            amount: amountToBridge      // Amount to transfer
        });

        // 2. Construct the EVM2AnyMessage
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(fromUser), // Receiver on the destination chain
            data: "",                   // No additional data payload in this example
            tokenAmounts: tokenAmounts, // The tokens and amounts to transfer
            feeToken: localNetworkDetails.linkAddress, // Using LINK as the fee token
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 0}) // Use default gas limit
            )
        });

        // 3. Get the CCIP fee
        uint256 fee = IRouterClient(localNetworkDetails.routerAddress).getFee(
            remoteNetworkDetails.chainSelector,
            message
        );

        // 4. Fund the user with LINK (for testing via CCIPLocalSimulatorFork)
        ccipLocalSimulatorFork.requestLinkFromFaucet(fromUser, fee);

        // 5. Approve LINK for the Router
        vm.prank(fromUser);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);

        // 6. Approve the actual token to be bridged
        vm.prank(fromUser);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);

        // 7. Get user's balance on the local chain BEFORE sending
        uint256 localBalanceBefore = localToken.balanceOf(fromUser);

        // 8. Send the CCIP message
        vm.prank(fromUser);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(
            remoteNetworkDetails.chainSelector, // Destination chain ID
            message
        );

          // 9. Assert user's balance on the local chain decreased by amountToBridge
        assertEq(localToken.balanceOf(fromUser), localBalanceBefore - amountToBridge, "Local balance incorrect after send");

        // 10. Simulate message propagation to the remote chain
        vm.warp(block.timestamp + 20 minutes); // Fast-forward time

        // 11. Get user's balance on the remote chain BEFORE message processing
        vm.selectFork(remoteFork);
        uint256 remoteBalanceBefore = remoteToken.balanceOf(fromUser);

        // 12. Process the message on the remote chain (using CCIPLocalSimulatorFork)
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        // 13. Assert user's balance on the remote chain increased by amountToBridge
        assertEq(remoteToken.balanceOf(fromUser), remoteBalanceBefore + amountToBridge, "Remote balance incorrect after receive");

    }

    function testBridgeAllTokens() public {
        uint256 DEPOSIT_AMOUNT = 1e5; // Using a small, fixed amount for clarity

        // 1. Deposit into Vault on Sepolia
        vm.selectFork(sepoliaFork);
        vm.deal(user, DEPOSIT_AMOUNT); // Give user some ETH to deposit

        vm.prank(user);
        Vault(payable(address(vault))).deposit{value: DEPOSIT_AMOUNT}();

        assertEq(sepoliaToken.balanceOf(user), DEPOSIT_AMOUNT, "User Sepolia token balance after deposit incorrect");

        // 2. Bridge Tokens: Sepolia -> Arbitrum Sepolia
        bridgeTokens(
            user,
            DEPOSIT_AMOUNT,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );

        // 3. Bridge All Tokens Back: Arbitrum Sepolia -> Sepolia
        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 20 minutes); // Advance time on Arbitrum Sepolia before bridging back

        uint256 arbBalanceToBridgeBack = arbSepoliaToken.balanceOf(user);
        assertTrue(arbBalanceToBridgeBack > 0, "User Arbitrum balance should be non-zero before bridging back");

        bridgeTokens(
            user,
            arbBalanceToBridgeBack,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            arbSepoliaToken,
            sepoliaToken
        );

        // Final state check: User on Sepolia should have their initial deposit back
        vm.selectFork(sepoliaFork);
        assertEq(sepoliaToken.balanceOf(user), DEPOSIT_AMOUNT, "User Sepolia token balance after bridging back incorrect");
    }
}
