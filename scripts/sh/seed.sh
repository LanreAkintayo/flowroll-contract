#!/usr/bin/env bash
set -euo pipefail

# Load environment variables from root .env
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/.env"

echo "================================================"
echo "           Flowroll — Seed Pools                "
echo "================================================"
echo ""
echo "Deployer: $DEPLOYER"
echo "Initial TVL per pool: $INITIAL_TVL"
echo ""

# ── Mint USDC ─────────────────────────────────────────
echo "Minting USDC to deployer..."
cast send $MOCK_USDC_ADDRESS \
  "mint(address,uint256)" $DEPLOYER $((INITIAL_TVL * 2)) \
  --rpc-url $RPC --private-key $PK

echo "Minting USDC into FlowrollCredit..."
cast send $MOCK_USDC_ADDRESS \
  "mint(address,uint256)" $FLOWROLL_CREDIT_ADDRESS $((INITIAL_TVL * 2)) \
  --rpc-url $RPC --private-key $PK

echo "USDC minted ✓"
echo ""

# ── Seed Stable Pool ──────────────────────────────────
echo "Seeding stable pool..."

cast send $MOCK_USDC_ADDRESS \
  "approve(address,uint256)" $STABLE_POOL_ADDRESS $INITIAL_TVL \
  --rpc-url $RPC --private-key $PK

cast send $STABLE_POOL_ADDRESS \
  "deposit(uint256,address)" $INITIAL_TVL $DEPLOYER \
  --rpc-url $RPC --private-key $PK

echo "Stable pool seeded ✓"
echo ""

# ── Seed Volatile Pool ────────────────────────────────
echo "Seeding volatile pool..."

cast send $MOCK_USDC_ADDRESS \
  "approve(address,uint256)" $VOLATILE_POOL_ADDRESS $INITIAL_TVL \
  --rpc-url $RPC --private-key $PK

cast send $VOLATILE_POOL_ADDRESS \
  "deposit(uint256,address)" $INITIAL_TVL $DEPLOYER \
  --rpc-url $RPC --private-key $PK

echo "Volatile pool seeded ✓"
echo ""

# ── Fund Zapper ───────────────────────────────────────
echo "Funding Zapper with native token..."
cast send $FLOWROLL_ZAPPER_ADDRESS \
  --value $(cast to-wei 1000) \
  --rpc-url $RPC --private-key $PK

echo "Minting USDC into Zapper..."
cast send $MOCK_USDC_ADDRESS \
  "mint(address,uint256)" $FLOWROLL_ZAPPER_ADDRESS $(cast to-wei 5000000000000) \
  --rpc-url $RPC --private-key $PK

echo "Zapper funded ✓"
echo ""

echo "================================================"
echo "           Pools seeded ✓                       "
echo "================================================"