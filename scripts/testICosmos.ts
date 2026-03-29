import { ethers } from "ethers";
import * as dotenv from "dotenv";
dotenv.config();

const COSMOS_ADDRESS = "0x00000000000000000000000000000000000000f1";

const COSMOS_ABI = [
    "function to_cosmos_address(address evm_address) external returns (string)",
    "function to_denom(address erc20_address) external returns (string)",
    "function query_cosmos(string path, string req) external returns (string)",
    "function execute_cosmos(string msg) external returns (bool)"
];

async function main() {
    const provider = new ethers.JsonRpcProvider(process.env.INITIA_RPC);
    const signer   = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);
    const cosmos   = new ethers.Contract(COSMOS_ADDRESS, COSMOS_ABI, signer);

    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log("  Flowroll — ICosmos Precompile Tests  ");
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

    // ── Test 1: to_cosmos_address ─────────────────────────────────────────
    console.log("▶ Test 1: to_cosmos_address");
    try {
        const cosmosAddr = await cosmos.to_cosmos_address.staticCall(signer.address);
        console.log(`  EVM address:    ${signer.address}`);
        console.log(`  Cosmos address: ${cosmosAddr}`);
        console.log("  ✅ PASSED\n");
    } catch (e) {
        console.log(`  ❌ FAILED: ${e}\n`);
        process.exit(1); // No point continuing if this fails
    }

    // ── Test 2: to_denom ─────────────────────────────────────────────────
    console.log("▶ Test 2: to_denom (MockUSDC)");
    const mockUSDC = process.env.MOCK_USDC!;
    try {
        const denom = await cosmos.to_denom.staticCall(mockUSDC);
        console.log(`  MockUSDC address: ${mockUSDC}`);
        console.log(`  Cosmos denom:     ${denom}`);
        console.log("  ✅ PASSED\n");
    } catch (e) {
        console.log(`  ❌ FAILED: ${e}\n`);
    }

    // ── Test 3: execute_cosmos MsgSend smoke test ─────────────────────────
    console.log("▶ Test 3: execute_cosmos (MsgSend smoke test)");
    try {
        const cosmosAddr = await cosmos.to_cosmos_address.staticCall(signer.address);
        const msgSend = JSON.stringify({
            "@type": "/cosmos.bank.v1beta1.MsgSend",
            "from_address": cosmosAddr,
            "to_address": cosmosAddr,
            "amount": []
        });

        const tx = await cosmos.execute_cosmos(msgSend);
        await tx.wait();
        console.log(`  Transaction: ${tx.hash}`);
        console.log("  ✅ PASSED\n");
    } catch (e) {
        console.log(`  ❌ FAILED: ${e}\n`);
    }

    // ── Test 4: query_cosmos .init username ───────────────────────────────
    console.log("▶ Test 4: query_cosmos (.init username resolution)");
    try {
        const result = await cosmos.query_cosmos.staticCall(
            "/initia.registry.v1.Query/GetAddress",
            JSON.stringify({ username: "test.init" })
        );
        console.log(`  Resolution result: ${result}`);
        console.log("  ✅ PASSED\n");
    } catch (e) {
        console.log(`  ❌ FAILED — path may be wrong: ${e}\n`);
    }

    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log("  Tests complete");
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
}

main().catch(console.error);