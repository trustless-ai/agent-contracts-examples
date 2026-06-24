// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MiniRecoveryEscrow} from "../src/MiniRecoveryEscrow.sol";
import {IReceiptVerifier} from "../src/IReceiptVerifier.sol";

// Mock verifier: receiptProof = abi.encode(bool valid, bytes32 artifactHash).
// (The REAL on-chain path — BIP340Verifier over a genuine signed receipt — is proven in
// BIP340Verifier.t.sol + BIP340Vectors.t.sol. Here we isolate the escrow gate.)
contract MockVerifier is IReceiptVerifier {
    function verify(bytes32 expect, bytes calldata p) external pure returns (bool, bool) {
        (bool v, bytes32 h) = abi.decode(p, (bool, bytes32));
        return (v, h == expect);
    }
}

contract MockERC721 {
    mapping(uint256 => address) public owners;
    function setOwner(uint256 id, address o) external { owners[id] = o; }
    function ownerOf(uint256 id) external view returns (address) { return owners[id]; }
}

contract MiniRecoveryEscrowTest is Test {
    MiniRecoveryEscrow escrow;
    MockERC721 asset;
    address agent = makeAddr("agent");
    address owner = makeAddr("output");
    bytes32 constant H = keccak256("artifact");
    uint256 constant TID = 7;

    function setUp() public {
        escrow = new MiniRecoveryEscrow(new MockVerifier());
        asset = new MockERC721();
        vm.deal(address(this), 10 ether);
        escrow.openJob{value: 1 ether}(H, owner, address(asset), TID, agent);
    }

    function _proof(bool v, bytes32 h) internal pure returns (bytes memory) { return abi.encode(v, h); }

    function test_release_happyPath() public {
        asset.setOwner(TID, owner); // delivered
        escrow.release(H, _proof(true, H));
        assertEq(agent.balance, 1 ether);
        assertTrue(escrow.spent(H));
    }

    function test_neverOnValidAlone() public {
        asset.setOwner(TID, agent); // valid+match but NOT delivered to owner
        vm.expectRevert(bytes("not delivered"));
        escrow.release(H, _proof(true, H));
    }

    function test_revertsOnInvalid() public {
        asset.setOwner(TID, owner);
        vm.expectRevert(bytes("receipt invalid"));
        escrow.release(H, _proof(false, H));
    }

    function test_revertsOnArtifactMismatch() public {
        asset.setOwner(TID, owner);
        vm.expectRevert(bytes("artifact mismatch"));
        escrow.release(H, _proof(true, keccak256("other")));
    }

    function test_replayBlocked() public {
        asset.setOwner(TID, owner);
        escrow.release(H, _proof(true, H));
        vm.expectRevert(bytes("not open"));
        escrow.release(H, _proof(true, H));
    }
}
