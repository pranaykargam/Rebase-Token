// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {IRouterClient} from "@ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BridgeTokensScript is Script {
    function run(
        address receiverAddress,            // Address receiving tokens on the destination chain
        uint64 destinationChainSelector,    // CCIP selector for the destination chain
        address tokenToSendAddress,         // Address of the ERC20 token being bridged
        uint256 amountToSend,               // Amount of the token to bridge
        address linkTokenAddress,           // Address of the LINK token (for fees) on the source chain
        address routerAddress               // Address of the CCIP Router on the source chain
    ) public {
        // Prepare the token amount array
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: tokenToSendAddress, // The address of the token being sent
            amount: amountToSend       // The amount of the token to send
        });

        // Prepare the CCIP message
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encodePacked(receiverAddress), // abi.encode or abi.encodePacked (depending on CCIP version)
            data: "",                                    // Empty payload
            tokenAmounts: tokenAmounts,                  // The array of token transfers
            feeToken: linkTokenAddress,                  // Token used for fees (LINK)
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 0})
            )
        });

        // Start broadcasting (sign and send transactions)
        vm.startBroadcast();

        // Estimate the CCIP fee for this message
        uint256 ccipFee = IRouterClient(routerAddress).getFee(destinationChainSelector, message);

        // Approve the CCIP Router to spend the fee token (LINK)
        IERC20(linkTokenAddress).approve(routerAddress, ccipFee);

        // Approve the CCIP Router to spend the token being bridged
        IERC20(tokenToSendAddress).approve(routerAddress, amountToSend);

        // Call ccipSend on the router
        IRouterClient(routerAddress).ccipSend(destinationChainSelector, message);

        vm.stopBroadcast();
    }
}
