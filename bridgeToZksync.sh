#!/usr/bin/env bash
# bridgeToZksync.sh — Deploy cross-chain app to Ethereum Sepolia and ZKsync Sepolia.
# Uses forge script for Sepolia and forge create / cast send for ZKsync (--legacy --zksync).
# Requires: .env with ZKSYNC_SEPOLIA_RPC_URL, SEPOLIA_RPC_URL; Foundry keystore account (e.g. updraft).

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

# -----------------------------------------------------------------------------
# Load environment
# -----------------------------------------------------------------------------
if [ -f .env ]; then
  set -a
  source .env
  set +a
else
  echo "Missing .env. Create from .env.example and set ZKSYNC_SEPOLIA_RPC_URL, SEPOLIA_RPC_URL."
  exit 1
fi

: "${ZKSYNC_SEPOLIA_RPC_URL:?Set ZKSYNC_SEPOLIA_RPC_URL in .env (e.g. https://sepolia.era.zksync.dev)}"
: "${SEPOLIA_RPC_URL:?Set SEPOLIA_RPC_URL in .env}"
ACCOUNT="${DEPLOYER_ACCOUNT:-updraft}"

# CCIP chain selectors (from Chainlink)
ETHEREUM_SEPOLIA_CHAIN_SELECTOR=16015286601757825753
ZKSYNC_SEPOLIA_CHAIN_SELECTOR=6898391096552792247

# ZKsync Sepolia CCIP addresses (from chainlink-local Register)
ZKSYNC_RMN_PROXY=0x3DA20FD3D8a8f8c1f1A5fD03648147143608C467
ZKSYNC_ROUTER=0xA1fdA8aa9A8C4b945C45aD30647b01f07D7A0B16
ZKSYNC_REGISTRY_MODULE_OWNER_CUSTOM=0x3139687Ee9938422F57933C3CDB3E21EE43c4d0F
ZKSYNC_TOKEN_ADMIN_REGISTRY=0xc7777f12258014866c677Bdb679D0b007405b7DF

echo "=============================================="
echo "Step 0: Update Foundry for ZKsync (optional)"
echo "=============================================="
# Uncomment to ensure ZKsync support:
# foundryup -zksync

echo "=============================================="
echo "Step 1: Compile for ZKsync"
echo "=============================================="
forge build --zksync

echo "=============================================="
echo "Step 2: Deploy on ZKsync Sepolia"
echo "=============================================="
# Deploy RebaseToken
ZKSYNC_TOKEN=$(forge create src/RebaseToken.sol:RebaseToken \
  --rpc-url "$ZKSYNC_SEPOLIA_RPC_URL" \
  --account "$ACCOUNT" \
  --legacy --zksync \
  --json | jq -r '.deployedTo')
echo "ZKsync RebaseToken: $ZKSYNC_TOKEN"

# Deploy RebaseTokenPool (token, allowlist, rmnProxy, router)
ZKSYNC_POOL=$(forge create src/RebaseTokenPool.sol:RebaseTokenPool \
  --rpc-url "$ZKSYNC_SEPOLIA_RPC_URL" \
  --account "$ACCOUNT" \
  --legacy --zksync \
  --constructor-args "$(cast abi-encode 'constructor(address,address[],address,address)' "$ZKSYNC_TOKEN" '[]' "$ZKSYNC_RMN_PROXY" "$ZKSYNC_ROUTER")" \
  --json | jq -r '.deployedTo')
echo "ZKsync RebaseTokenPool: $ZKSYNC_POOL"

echo "=============================================="
echo "Step 3: Set permissions on ZKsync contracts"
echo "=============================================="
cast send "$ZKSYNC_TOKEN" "grantMintAndBurnRole(address)" "$ZKSYNC_POOL" \
  --rpc-url "$ZKSYNC_SEPOLIA_RPC_URL" \
  --account "$ACCOUNT" \
  --legacy --zksync

cast send "$ZKSYNC_REGISTRY_MODULE_OWNER_CUSTOM" "registerAdminViaOwner(address)" "$ZKSYNC_TOKEN" \
  --rpc-url "$ZKSYNC_SEPOLIA_RPC_URL" \
  --account "$ACCOUNT" \
  --legacy --zksync

cast send "$ZKSYNC_TOKEN_ADMIN_REGISTRY" "acceptAdminRole(address)" "$ZKSYNC_TOKEN" \
  --rpc-url "$ZKSYNC_SEPOLIA_RPC_URL" \
  --account "$ACCOUNT" \
  --legacy --zksync

cast send "$ZKSYNC_TOKEN_ADMIN_REGISTRY" "setPool(address,address)" "$ZKSYNC_TOKEN" "$ZKSYNC_POOL" \
  --rpc-url "$ZKSYNC_SEPOLIA_RPC_URL" \
  --account "$ACCOUNT" \
  --legacy --zksync

echo "=============================================="
echo "Step 4: Deploy on Ethereum Sepolia"
echo "=============================================="
# Token + Pool (and grant pool role)
forge script script/Deployer.s.sol:TokenAndPoolDeployer \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --account "$ACCOUNT" \
  --broadcast

# Parse deployed addresses from broadcast (latest run). Alternatively set them manually.
BROADCAST_JSON="broadcast/Deployer.s.sol/11155111/run-latest.json"
if [ -f "$BROADCAST_JSON" ]; then
  SEPOLIA_TOKEN=$(jq -r '[.transactions[] | select(.contractName == "RebaseToken") | .contractAddress] | first // empty' "$BROADCAST_JSON")
  SEPOLIA_POOL=$(jq -r '[.transactions[] | select(.contractName == "RebaseTokenPool") | .contractAddress] | first // empty' "$BROADCAST_JSON")
fi
if [ -z "$SEPOLIA_TOKEN" ] || [ -z "$SEPOLIA_POOL" ]; then
  echo "Could not parse addresses. Set and export then re-run from Step 5:"
  echo "  export SEPOLIA_TOKEN=0x..."
  echo "  export SEPOLIA_POOL=0x..."
  exit 1
fi
echo "Sepolia RebaseToken: $SEPOLIA_TOKEN"
echo "Sepolia RebaseTokenPool: $SEPOLIA_POOL"

# Vault
forge script script/Deployer.s.sol:VaultDeployer \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --account "$ACCOUNT" \
  --broadcast \
  --sig "run(address)" "$SEPOLIA_TOKEN"

VAULT_BROADCAST="broadcast/Deployer.s.sol/11155111/run-latest.json"
if [ -f "$VAULT_BROADCAST" ]; then
  SEPOLIA_VAULT=$(jq -r '[.transactions[] | select(.contractName == "Vault") | .contractAddress] | first // empty' "$VAULT_BROADCAST")
fi
if [ -z "$SEPOLIA_VAULT" ]; then
  echo "Set SEPOLIA_VAULT from broadcast output above and continue."
fi
echo "Sepolia Vault: $SEPOLIA_VAULT"

echo "=============================================="
echo "Step 5: Set permissions on Sepolia (split calls to avoid nonce issues)"
echo "=============================================="
# Grant pool mint/burn role (if not already done in deployer)
forge script script/Deployer.s.sol:SetPermissions \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --account "$ACCOUNT" \
  --broadcast \
  --sig "grantRole(address,address)" "$SEPOLIA_TOKEN" "$SEPOLIA_POOL"

# Register admin and set pool (separate tx)
forge script script/Deployer.s.sol:SetPermissions \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --account "$ACCOUNT" \
  --broadcast \
  --sig "setAdminAndPool(address,address)" "$SEPOLIA_TOKEN" "$SEPOLIA_POOL"

echo "=============================================="
echo "Step 6: Configure Sepolia pool for ZKsync"
echo "=============================================="
forge script script/ConfigurePools.s.sol:ConfigurePoolScript \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --account "$ACCOUNT" \
  --broadcast \
  --sig "run(address,uint64,address,address)" "$SEPOLIA_POOL" "$ZKSYNC_SEPOLIA_CHAIN_SELECTOR" "$ZKSYNC_POOL" "$ZKSYNC_TOKEN"

echo "=============================================="
echo "Step 7: Configure ZKsync pool for Sepolia"
echo "=============================================="
# applyChainUpdates(remoteChainSelectorsToRemove, chainsToAdd) — encoding is complex; use a script or cast with abi-encode.
# Option A: Use a small Solidity script that calls applyChainUpdates (ZKsync may not support forge script; then use cast).
# Option B: Run a ConfigurePoolScript-equivalent for ZKsync via cast (requires encoding ChainUpdate).
# For ZKsync we use cast send with --legacy --zksync. Encoding bytes[] and structs in bash is tedious; consider running
# a one-off forge script that targets ZKsync if/when forge script supports it, or encode offline.
echo "Configure ZKsync pool manually or via a script that calls applyChainUpdates with:"
echo "  remoteChainSelector=$ETHEREUM_SEPOLIA_CHAIN_SELECTOR remotePool=$SEPOLIA_POOL remoteToken=$SEPOLIA_TOKEN"

echo "=============================================="
echo "Step 8: Deposit into Sepolia Vault (optional)"
echo "=============================================="
# AMOUNT="${DEPOSIT_AMOUNT_WEI:-1000000000000000000}"  # 1 ETH in wei
# cast send "$SEPOLIA_VAULT" "deposit()" --value "$AMOUNT" --rpc-url "$SEPOLIA_RPC_URL" --account "$ACCOUNT"
echo "To deposit: cast send $SEPOLIA_VAULT 'deposit()' --value <AMOUNT_WEI> --rpc-url \$SEPOLIA_RPC_URL --account $ACCOUNT"

echo "=============================================="
echo "Step 9: Bridge tokens (run BridgeTokens script)"
echo "=============================================="
echo "Run BridgeTokens.s.sol:BridgeTokensScript with receiver, destinationChainSelector (e.g. $ZKSYNC_SEPOLIA_CHAIN_SELECTOR), token, amount, LINK, router."

echo ""
echo "Done. Summary:"
echo "  ZKsync Token: $ZKSYNC_TOKEN  Pool: $ZKSYNC_POOL"
echo "  Sepolia Token: $SEPOLIA_TOKEN  Pool: $SEPOLIA_POOL  Vault: $SEPOLIA_VAULT"
