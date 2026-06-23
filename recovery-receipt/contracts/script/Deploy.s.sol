// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {BIP340Verifier} from "../src/BIP340Verifier.sol";
import {MiniRecoveryEscrow} from "../src/MiniRecoveryEscrow.sol";

/// Quickstart deploy: BIP340Verifier(issuer) -> MiniRecoveryEscrow(verifier).
/// env: PRIVATE_KEY, ISSUER_PUBKEY (x-only 32-byte = the agent's key).
contract Deploy is Script {
    function run() external returns (BIP340Verifier verifier, MiniRecoveryEscrow escrow) {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        verifier = new BIP340Verifier(vm.envBytes32("ISSUER_PUBKEY"));
        escrow = new MiniRecoveryEscrow(verifier);
        vm.stopBroadcast();
        console2.log("BIP340Verifier:", address(verifier));
        console2.log("MiniRecoveryEscrow:", address(escrow));
    }
}
