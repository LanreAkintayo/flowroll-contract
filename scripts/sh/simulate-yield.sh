#!/usr/bin/env bash
set -euo pipefail

# Load environment variables from root .env
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/.env"

echo "================================================"
echo "     Flowroll — Simulate Yield (Dev Only)       "
echo "================================================"
echo ""
echo "⚠️  This script is for local/testnet development only."
echo "   Do not run against mainnet."
echo ""

YIELD_AMOUNT=1000000000  # 1,000 USDC (6 decimals)

# ── Mint USDC for yield injection ─────────────────────
echo "Minting USDC for yield simulation..."
cast send $MOCK_USDC_ADDRESS \
  "mint(address,uint256)" $DEPLOYER $((YIELD_AMOUNT * 2)) \
  --rpc-url $RPC --private-key $PK

echo "USDC minted ✓"
echo ""

# ── Inject yield into stable pool ────────────────────
echo "Approving stable pool..."
cast send $MOCK_USDC_ADDRESS \
  "approve(address,uint256)" $STABLE_POOL_ADDRESS $YIELD_AMOUNT \
  --rpc-url $RPC --private-key $PK

echo "Simulating yield for stable pool..."
cast send $STABLE_POOL_ADDRESS \
  "simulateYield(uint256)" $YIELD_AMOUNT \
  --rpc-url $RPC --private-key $PK

echo "Stable pool yield injected ✓"
echo ""

# ── Inject yield into volatile pool ──────────────────
echo "Approving volatile pool..."
cast send $MOCK_USDC_ADDRESS \
  "approve(address,uint256)" $VOLATILE_POOL_ADDRESS $YIELD_AMOUNT \
  --rpc-url $RPC --private-key $PK

echo "Simulating yield for volatile pool..."
cast send $VOLATILE_POOL_ADDRESS \
  "simulateYield(uint256)" $YIELD_AMOUNT \
  --rpc-url $RPC --private-key $PK

echo "Volatile pool yield injected ✓"
echo ""

echo "================================================"
echo "         Yield simulation complete ✓            "
echo "================================================"