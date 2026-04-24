#!/usr/bin/env bash
set -euo pipefail

# Load environment variables from root .env
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/.env"

echo ROOT_DIR: $ROOT_DIR

echo "================================================"
echo "         Flowroll — Contract Wiring             "
echo "================================================"
echo ""

# ── YieldRouter ──────────────────────────────────────
echo "Configuring YieldRouter..."

cast send $YIELD_ROUTER_ADDRESS \
  "setPayrollManager(address)" $PAYROLL_MANAGER_ADDRESS \
  --rpc-url $RPC --private-key $PK

cast send $YIELD_ROUTER_ADDRESS \
  "setPayVault(address)" $PAY_VAULT_ADDRESS \
  --rpc-url $RPC --private-key $PK

echo "YieldRouter configured ✓"
echo ""

# ── PayrollManager ────────────────────────────────────
echo "Configuring PayrollManager..."

cast send $PAYROLL_MANAGER_ADDRESS \
  "setYieldRouter(address)" $YIELD_ROUTER_ADDRESS \
  --rpc-url $RPC --private-key $PK

cast send $PAYROLL_MANAGER_ADDRESS \
  "setPayrollDispatcher(address)" $PAYROLL_DISPATCHER_ADDRESS \
  --rpc-url $RPC --private-key $PK

cast send $PAYROLL_MANAGER_ADDRESS \
  "setPayVault(address)" $PAY_VAULT_ADDRESS \
  --rpc-url $RPC --private-key $PK

echo "PayrollManager configured ✓"
echo ""

# ── PayrollDispatcher ─────────────────────────────────
echo "Configuring PayrollDispatcher..."

cast send $PAYROLL_DISPATCHER_ADDRESS \
  "setYieldRouter(address)" $YIELD_ROUTER_ADDRESS \
  --rpc-url $RPC --private-key $PK

cast send $PAYROLL_DISPATCHER_ADDRESS \
  "setPayrollManager(address)" $PAYROLL_MANAGER_ADDRESS \
  --rpc-url $RPC --private-key $PK

cast send $PAYROLL_DISPATCHER_ADDRESS \
  "setPayVault(address)" $PAY_VAULT_ADDRESS \
  --rpc-url $RPC --private-key $PK

echo "PayrollDispatcher configured ✓"
echo ""

# ── PayVault ──────────────────────────────────────────
echo "Configuring PayVault..."

cast send $PAY_VAULT_ADDRESS \
  "setDispatcher(address)" $PAYROLL_DISPATCHER_ADDRESS \
  --rpc-url $RPC --private-key $PK

cast send $PAY_VAULT_ADDRESS \
  "setYieldRouter(address)" $YIELD_ROUTER_ADDRESS \
  --rpc-url $RPC --private-key $PK

cast send $PAY_VAULT_ADDRESS \
  "setPayrollManager(address)" $PAYROLL_MANAGER_ADDRESS \
  --rpc-url $RPC --private-key $PK

cast send $PAY_VAULT_ADDRESS \
  "setFlowrollCredit(address)" $FLOWROLL_CREDIT_ADDRESS \
  --rpc-url $RPC --private-key $PK

echo "PayVault configured ✓"
echo ""

# ── FlowrollCredit ────────────────────────────────────
echo "Configuring FlowrollCredit..."

cast send $FLOWROLL_CREDIT_ADDRESS \
  "setPayrollManager(address)" $PAYROLL_MANAGER_ADDRESS \
  --rpc-url $RPC --private-key $PK

cast send $FLOWROLL_CREDIT_ADDRESS \
  "setPayVault(address)" $PAY_VAULT_ADDRESS \
  --rpc-url $RPC --private-key $PK

echo "FlowrollCredit configured ✓"
echo ""

# ── Pools ─────────────────────────────────────────────
echo "Registering pools..."

cast send $YIELD_ROUTER_ADDRESS \
  "addPool(address,address,bool,uint256)" \
  $STABLE_ADAPTER_ADDRESS $STABLE_POOL_ADDRESS true 500 \
  --rpc-url $RPC --private-key $PK

echo "Stable pool registered ✓"

cast send $YIELD_ROUTER_ADDRESS \
  "addPool(address,address,bool,uint256)" \
  $VOLATILE_ADAPTER_ADDRESS $VOLATILE_POOL_ADDRESS false 500 \
  --rpc-url $RPC --private-key $PK

echo "Volatile pool registered ✓"
echo ""

echo "================================================"
echo "           Wiring complete ✓                    "
echo "================================================"