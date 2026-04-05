simple on-chain app: an `AMM-based` market
For a production, high-volume prediction venue like `Polymarket`: a CLOB is often better


Onchain = happens on the blockchain;
 offchain = happens outside it and maybe settles onchain later.


`Checkpoint 1`:
🔭 `Understanding the protocol` 📺

our prediction market has three essential parts:

🪙 Tokens (like ERC20s) to represent outcomes

💧 Trading mechanism (AMM or order book) to let users buy/sell shares

🔮 An oracle to settle the final outcome

     This contract extends the standard ERC20 spec with custom minting and burning logic. 




## Deploy

Set your environment variables in `.env`:

```sh
PRIVATE_KEY=your_private_key
RPC_URL=your_rpc_url
ETHERSCAN_API_KEY=your_etherscan_api_key
```

Run the deployment script:

```sh
forge script script/DeployPredictionMarket.s.sol:DeployPredictionMarket \
  --rpc-url $RPC_URL \
  --broadcast
```

Verify the deployed contract:

```sh
forge verify-contract <DEPLOYED_CONTRACT_ADDRESS> src/PredictionMarket.sol:PredictionMarket \
  --chain <CHAIN_ID> \
  --etherscan-api-key $ETHERSCAN_API_KEY
```