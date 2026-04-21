#!/usr/bin/env bash
set -euo pipefail

# Load environment variables from root .env
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/.env"

echo "================================================"
echo "      Flowroll — Change Pool APYs (Dev Only)    "
echo "================================================"
echo ""
echo "⚠️  This script is for local/testnet development only."
echo "   Do not run against mainnet."
echo ""

# ── Set APYs ──────────────────────────────────────────
# Values are in basis points (bps): 100 bps = 1%
# e.g. 3000 = 30%, 500 = 5%

echo "Setting stable pool APY to 30% (3000 bps)..."
cast send $STABLE_POOL_ADDRESS \
  "setApyBps(uint256)" 3000 \
  --rpc-url $RPC --private-key $PK

echo "Stable pool APY set ✓"
echo ""

echo "Setting volatile pool APY to 5% (500 bps)..."
cast send $VOLATILE_POOL_ADDRESS \
  "setApyBps(uint256)" 500 \
  --rpc-url $RPC --private-key $PK

echo "Volatile pool APY set ✓"
echo ""

echo "================================================"
echo "           Pool APYs updated ✓                  "
echo "================================================"