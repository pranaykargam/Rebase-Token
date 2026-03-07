// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Vault} from "../src/Vault.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {IRebaseToken} from "../src/Interfaces/IRebaseToken.sol";
import {IERC20} from "@openzeppelin/contracts@4.8.3/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";
import {CCIPLocalSimulatorFork} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {Register} from "@chainlink-local/src/ccip/Register.sol";

contract TokenAndPoolDeployer is Script {
    /// @notice Ethereum Sepolia chain ID (used when broadcasting to testnet without fork)
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;

    /// @notice Ethereum Sepolia CCIP addresses (from Chainlink's Register / official deployment)
    function getSepoliaNetworkDetails() internal pure returns (Register.NetworkDetails memory) {
        return Register.NetworkDetails({
            chainSelector: 16015286601757825753,
            routerAddress: 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59,
            linkAddress: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            wrappedNativeAddress: 0x097D90c9d3E0B50Ca60e1ae45F6A81010f9FB534,
            ccipBnMAddress: 0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05,
            ccipLnMAddress: 0x466D489b6d36E7E3b824ef491C225F5830E81cC1,
            rmnProxyAddress: 0xba3f6251de62dED61Ff98590cB2fDf6871FbB991,
            registryModuleOwnerCustomAddress: 0x62e731218d0D47305aba2BE3751E7EE9E5520790,
            tokenAdminRegistryAddress: 0x95F29FEE11c5C55d26cCcf1DB6772DE953B37B82
        });
    }

    function _getNetworkDetails() internal returns (Register.NetworkDetails memory) {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            return getSepoliaNetworkDetails();
        }
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        return ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
    }

    function run() public returns (RebaseToken token, RebaseTokenPool pool) {
        Register.NetworkDetails memory networkDetails = _getNetworkDetails();

        vm.startBroadcast();

        token = new RebaseToken();
        pool = new RebaseTokenPool(
            IERC20(address(token)),
            new address[](0),
            networkDetails.rmnProxyAddress,
            networkDetails.routerAddress
        );
        token.grantMintAndBurnRole(address(pool));

        vm.stopBroadcast();

        console.log("RebaseToken deployed at:", address(token));
        console.log("RebaseTokenPool deployed at:", address(pool));
    }
}

contract VaultDeployer is Script {
    function run(address _rebaseToken) public returns (Vault vault) {
        vm.startBroadcast();
        vault = new Vault(IRebaseToken(_rebaseToken));
        IRebaseToken(_rebaseToken).grantMintAndBurnRole(address(vault));
        vm.stopBroadcast();

        console.log("Vault deployed at:", address(vault));
    }
}

/// @notice Split into separate functions so each can be run as its own forge script call,
///         avoiding "future transaction tries to replace pending" nonce issues on Sepolia.
contract SetPermissions is Script {
    /// @notice Sepolia CCIP registry addresses (must match chain when using setAdminAndPool(address,address)).
    address internal constant SEPOLIA_REGISTRY_MODULE_OWNER_CUSTOM = 0x62e731218d0D47305aba2BE3751E7EE9E5520790;
    address internal constant SEPOLIA_TOKEN_ADMIN_REGISTRY = 0x95F29FEE11c5C55d26cCcf1DB6772DE953B37B82;

    /// @notice Grants MINT_AND_BURN_ROLE on the RebaseToken to the pool. Call first.
    function grantRole(address token, address pool) public {
        vm.startBroadcast();
        IRebaseToken(token).grantMintAndBurnRole(pool);
        vm.stopBroadcast();
    }

    /// @notice Registers the token as admin and sets the pool on Ethereum Sepolia. Call after grantRole.
    /// Uses hardcoded Sepolia CCIP registry addresses. For other chains use setAdminAndPool(address,address,address,address).
    function setAdminAndPool(address token, address pool) public {
        setAdminAndPool(token, pool, SEPOLIA_REGISTRY_MODULE_OWNER_CUSTOM, SEPOLIA_TOKEN_ADMIN_REGISTRY);
    }

    /// @notice Registers the token as admin and sets the pool in TokenAdminRegistry (explicit registry addresses).
    function setAdminAndPool(
        address token,
        address pool,
        address registryModuleOwnerCustom,
        address tokenAdminRegistry
    ) public {
        vm.startBroadcast();
        RegistryModuleOwnerCustom(registryModuleOwnerCustom).registerAdminViaOwner(token);
        TokenAdminRegistry(tokenAdminRegistry).acceptAdminRole(token);
        TokenAdminRegistry(tokenAdminRegistry).setPool(token, pool);
        vm.stopBroadcast();
    }
}
