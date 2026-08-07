// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IReceiptVerifier} from "./IReceiptVerifier.sol";

interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @title MiniRecoveryEscrow — the minimal quickstart escrow (illustrative, not production).
/// @notice The smallest thing that shows the gate: release a fee ONLY when the agent's receipt is
///         (1) a genuine signed proof + (2) bound to this job (both via the verifier) AND (3) the asset
///         actually reached the owner-specified `output` on-chain. Never on `valid` alone. Nullifies the
///         artifact on release so a receipt can't be replayed.
///
///         The full, production version (refunds, events, expiry, reentrancy guard) lives in the project
///         repo: https://github.com/TMerlini/hack-ens-recovery. This file is deliberately tiny so the
///         flow is readable in one screen.
contract MiniRecoveryEscrow {
    IReceiptVerifier public immutable verifier;
    mapping(bytes32 => bool) public spent; // nullifier on artifact_hash

    struct Job { address agent; address output; address asset; uint256 tokenId; uint256 fee; bool open; }
    mapping(bytes32 => Job) public jobs;

    constructor(IReceiptVerifier verifier_) { verifier = verifier_; }

    /// Open + fund a job. `expectArtifactHash` = H(job_id, target_wallet, output, asset_set) from the SDK.
    function openJob(bytes32 expectArtifactHash, address output, address asset, uint256 tokenId, address agent)
        external payable
    {
        require(!spent[expectArtifactHash] && !jobs[expectArtifactHash].open, "exists/spent");
        require(msg.value > 0 && output != address(0), "bad args");
        jobs[expectArtifactHash] = Job(agent, output, asset, tokenId, msg.value, true);
    }

    /// Permissionless. Releases iff valid ∧ artifactHashMatches ∧ on-chain delivery; then nullifies.
    function release(bytes32 expectArtifactHash, bytes calldata receiptProof) external {
        Job storage j = jobs[expectArtifactHash];
        require(j.open && !spent[expectArtifactHash], "not open");

        (bool valid, bool matches) = verifier.verify(expectArtifactHash, receiptProof);
        require(valid, "receipt invalid");          // genuine signed proof
        require(matches, "artifact mismatch");      // bound to THIS job
        require(IERC721(j.asset).ownerOf(j.tokenId) == j.output, "not delivered"); // the trustless teeth

        j.open = false;
        spent[expectArtifactHash] = true;           // replay nullifier
        (bool ok,) = payable(j.agent).call{value: j.fee}("");
        require(ok, "pay failed");
    }
}
