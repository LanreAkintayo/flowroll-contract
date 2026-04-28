// "lastScannedBlock": 12746, for appchain
{
  "lastScannedBlock": 17294722,
  "knownEmployers": [
    "0x96a9b1F84b40ADd32bCd1FE1D8C04A995b2bDC6d",
    "0xc3235B99Bdf0F12e793BcA9B83A8BAD88E06C8B3",
    "0x6AeCa04B7208d65B35aAa53061Bd3d6b348fe72f",
    "0x74cFd9B6fF483441eD156980828846d880C988c3",
    "0xbe989468B3E8C3ACEE46AEf04ADD906222e25A92",
    "0x7525B4B10451B021e58EAdB20Aa7Ca92368BA2DF",
    "0xec2B1547294a4dd62C0aE651aEb01493f8e4cD74",
    "0xADEe03eF7C97c0541D8c90F6c263C3a015339F1b",
    "0xd0333948C3198dde12D5950250Cebb9f678Ea8fa",
    "0x23Af6F5cd25278Db501e05054820a0D278a3F8ce",
    "0x4c1E3C8178c19BA9c9fDb6c79391A3b4DFAD9F86"
  ]
}


// Another flow;
Deploy the contract first;
forge script script/Deploy.s.sol   --rpc-url $RPC   --broadcast   --private-key $TESTNET_PRIVATE_KEY 

// Create Group
cast send $PAYROLL_MANAGER_ADDRESS "createGroup(string, uint256)" "Core Engineering" 60 --rpc-url $RPC --private-key $PK

// Approve to spend funds
cast send $MOCK_USDC_ADDRESS "approve(address, uint256)" $PAYROLL_MANAGER_ADDRESS 5000000000 --rpc-url $RPC --private-key $PK

cast send $PAYROLL_MANAGER_ADDRESS \
  "setUpPayroll(uint256,address[],uint256[])" \
  1 \
  "[0xc3235B99Bdf0F12e793BcA9B83A8BAD88E06C8B3]" \
  "[5000000000]" \
  --rpc-url $RPC --private-key $PK



cast send $YIELD_ROUTER_ADDRESS \
  "agentRebalance(address,uint256)" \
  $DEPLOYER 1 \
  --rpc-url $RPC \
  --private-key $PK




// To get getPools
cast call $YIELD_ROUTER_ADDRESS "getPool(uint256)((address,address,bool,bool,uint256))" 0 --rpc-url $RPC

To setup payroll


cast send $PAYROLL_MANAGER_ADDRESS \
  "setUpPayroll(uint256,address[],uint256[])" \
  1 \
  "[0xc3235B99Bdf0F12e793BcA9B83A8BAD88E06C8B3]" \
  "[5000000000]" \
  --rpc-url $RPC --private-key $PK

------------------------------------------------------------------------------------------------------------------------
// To set apys
echo "Setting stable pool APY to 5%..."
cast send $STABLE_POOL_ADDRESS \
  "setApyBps(uint256)" 3000 \
  --rpc-url $RPC --private-key $PK

echo "Setting volatile pool APY to 20%..."
cast send $VOLATILE_POOL_ADDRESS \
  "setApyBps(uint256)" 500 \
  --rpc-url $RPC --private-key $PK




---------------------------------------------------------------------------------------------------------------------


// TO simulate yield
echo "Minting USDC for yield simulation..."
cast send $MOCK_USDC_ADDRESS \
  "mint(address,uint256)" $DEPLOYER 2000000000 \
  --rpc-url $RPC --private-key $PK

echo "Approving stable pool..."
cast send $MOCK_USDC_ADDRESS \
  "approve(address,uint256)" $STABLE_POOL_ADDRESS 1000000000 \
  --rpc-url $RPC --private-key $PK

echo "Approving volatile pool..."
cast send $MOCK_USDC_ADDRESS \
  "approve(address,uint256)" $VOLATILE_POOL_ADDRESS 1000000000 \
  --rpc-url $RPC --private-key $PK

echo "Simulating yield for stable..."
cast send $STABLE_POOL_ADDRESS \
  "simulateYield(uint256)" 1000000000 \
  --rpc-url $RPC --private-key $PK

echo "Simulating yield for volatile..."
cast send $VOLATILE_POOL_ADDRESS \
  "simulateYield(uint256)" 1000000000 \
  --rpc-url $RPC --private-key $PK




--------------------------------------------------------------------------------------------------------------------------


// To deploy script;
forge script script/Deploy.s.sol   --rpc-url $RPC   --broadcast   --private-key $TESTNET_PRIVATE_KEY 


To wire the contract;
echo "=== Step 1: Wiring contracts ==="

echo "Setting up YieldRouter..."
cast send $YIELD_ROUTER_ADDRESS \
  "setPayrollManager(address)" $PAYROLL_MANAGER_ADDRESS \
  --rpc-url $RPC --private-key $PK

cast send $YIELD_ROUTER_ADDRESS \
  "setPayVault(address)" $PAY_VAULT_ADDRESS \
  --rpc-url $RPC --private-key $PK

echo "Router configured ✓"



echo "Setting up PayrollManager..."
cast send $PAYROLL_MANAGER_ADDRESS \
  "setYieldRouter(address)" $YIELD_ROUTER_ADDRESS \
  --rpc-url $RPC --private-key $PK

cast send $PAYROLL_MANAGER_ADDRESS \
  "setPayrollDispatcher(address)" $PAYROLL_DISPATCHER_ADDRESS \
  --rpc-url $RPC --private-key $PK

cast send $PAYROLL_MANAGER_ADDRESS \
  "setPayVault(address)" $PAY_VAULT_ADDRESS \
  --rpc-url $RPC --private-key $PK

echo "Manager configured ✓"


echo "Setting up Dispatcher..."
cast send $PAYROLL_DISPATCHER_ADDRESS \
  "setYieldRouter(address)" $YIELD_ROUTER_ADDRESS \
  --rpc-url $RPC --private-key $PK

cast send $PAYROLL_DISPATCHER_ADDRESS \
  "setPayrollManager(address)" $PAYROLL_MANAGER_ADDRESS \
  --rpc-url $RPC --private-key $PK

cast send $PAYROLL_DISPATCHER_ADDRESS \
  "setPayVault(address)" $PAY_VAULT_ADDRESS \
  --rpc-url $RPC --private-key $PK

echo "Dispatcher configured ✓"


echo "Setting up PayVault..."
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

echo "Vault configured ✓"

echo "Setting up FlowrollCredit..."
cast send $FLOWROLL_CREDIT_ADDRESS \
  "setPayrollManager(address)" $PAYROLL_MANAGER_ADDRESS \
  --rpc-url $RPC --private-key $PK

cast send $FLOWROLL_CREDIT_ADDRESS \
  "setPayVault(address)" $PAY_VAULT_ADDRESS \
  --rpc-url $RPC --private-key $PK

echo "FlowrollCredit configured ✓"



echo "===Adding Pools ==="
echo "Adding stable pool to Router..."
cast send $YIELD_ROUTER_ADDRESS \
  "addPool(address,address,bool,uint256)" \
  $STABLE_ADAPTER_ADDRESS $STABLE_POOL_ADDRESS true 500 \
  --rpc-url $RPC --private-key $PK

echo "Adding volatile pool to Router..."
cast send $YIELD_ROUTER_ADDRESS \
  "addPool(address,address,bool,uint256)" \
  $VOLATILE_ADAPTER_ADDRESS $VOLATILE_POOL_ADDRESS false 500 \
  --rpc-url $RPC --private-key $PK


echo "=== Wiring complete ==="

STEP 2 -------------------------------------------------------------------------------------------
To seed pools;

echo "=== Step 2: Seeding pools ==="
echo "Deployer: $DEPLOYER"

echo "Minting USDC..."
cast send $MOCK_USDC_ADDRESS \
  "mint(address,uint256)" $DEPLOYER $((INITIAL_TVL * 2)) \
  --rpc-url $RPC --private-key $PK

echo "Minting USDC into Flowroll Credit..."
cast send $MOCK_USDC_ADDRESS \
  "mint(address,uint256)" $FLOWROLL_CREDIT_ADDRESS $((INITIAL_TVL * 2)) \
  --rpc-url $RPC --private-key $PK

echo "Approving stable pool..."
cast send $MOCK_USDC_ADDRESS \
  "approve(address,uint256)" $STABLE_POOL_ADDRESS $INITIAL_TVL \
  --rpc-url $RPC --private-key $PK

echo "Depositing into stable pool..."
cast send $STABLE_POOL_ADDRESS \
  "deposit(uint256,address)" $INITIAL_TVL $DEPLOYER \
  --rpc-url $RPC --private-key $PK

echo "Stable pool seeded ✓"

echo "Approving volatile pool..."
cast send $MOCK_USDC_ADDRESS \
  "approve(address,uint256)" $VOLATILE_POOL_ADDRESS $INITIAL_TVL \
  --rpc-url $RPC --private-key $PK

echo "Depositing into volatile pool..."
cast send $VOLATILE_POOL_ADDRESS \
  "deposit(uint256,address)" $INITIAL_TVL $DEPLOYER \
  --rpc-url $RPC --private-key $PK

echo "Volatile pool seeded ✓"


echo "Funding Zapper with native token..."
cast send $FLOWROLL_ZAPPER_ADDRESS \
  --value $(cast to-wei 1000) \
  --rpc-url $RPC --private-key $PK

echo "Minting USDC into Zapper..."
cast send $MOCK_USDC_ADDRESS \
  "mint(address,uint256)" $FLOWROLL_ZAPPER_ADDRESS $(cast to-wei 5000000000000) \
  --rpc-url $RPC --private-key $PK

echo "Zapper funded ✓"

echo "=== Pools seeded ==="