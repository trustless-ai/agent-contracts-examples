// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/GenesisAgentRegistry.sol";

contract GenesisAgentRegistryTest is Test {
    GenesisAgentRegistry reg;

    address admin = address(0xAD);
    address payable treasury = payable(address(0x7E));
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA401);

    // A 2-leaf allowlist over {alice, bob}. leaf = keccak256(abi.encodePacked(addr)).
    bytes32 leafAlice;
    bytes32 leafBob;
    bytes32 root;

    function setUp() public {
        leafAlice = keccak256(abi.encodePacked(alice));
        leafBob = keccak256(abi.encodePacked(bob));
        // Sorted-pair root (OZ MerkleProof sorts each pair).
        root = _hashPair(leafAlice, leafBob);

        GenesisAgentRegistry.InitParams memory p = GenesisAgentRegistry.InitParams({
            name: "Genesis Agents",
            symbol: "GAGENT",
            baseAgentURI: "ipfs://base/{agentId}",
            initialAdmin: admin,
            treasury: treasury,
            royaltyReceiver: treasury,
            royaltyBps: 500,
            maxSupply: 0,
            allowlistPrice: 0,
            publicPrice: 0.001 ether
        });
        reg = new GenesisAgentRegistry(p);

        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(carol, 10 ether);
    }

    // ── helpers ─────────────────────────────────────────────────────────

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _emptyMeta() internal pure returns (GenesisAgentRegistry.MetadataEntry[] memory) {
        return new GenesisAgentRegistry.MetadataEntry[](0);
    }

    function _proofFor(bytes32 sibling) internal pure returns (bytes32[] memory p) {
        p = new bytes32[](1);
        p[0] = sibling;
    }

    // ── phase gating ────────────────────────────────────────────────────

    function test_ClosedPhase_RevertsBothPaths() public {
        // default phase is Closed
        vm.prank(alice);
        vm.expectRevert("Public phase not active");
        reg.mint{value: 0.001 ether}("ipfs://a", _emptyMeta());

        vm.prank(alice);
        vm.expectRevert("Allowlist phase not active");
        reg.mintAllowlist("ipfs://a", _emptyMeta(), _proofFor(leafBob));
    }

    // ── allowlist phase ─────────────────────────────────────────────────

    function test_Allowlist_ValidProof_Mints_Free() public {
        vm.startPrank(admin);
        reg.setAllowlistRoot(root);
        reg.setPhase(GenesisAgentRegistry.Phase.Allowlist);
        vm.stopPrank();

        vm.prank(alice);
        uint256 id = reg.mintAllowlist("ipfs://alice", _emptyMeta(), _proofFor(leafBob));
        assertEq(reg.ownerOf(id), alice);
        assertEq(id, 1);
        assertEq(reg.totalSupply(), 1);
    }

    function test_Allowlist_BadProof_Reverts() public {
        vm.startPrank(admin);
        reg.setAllowlistRoot(root);
        reg.setPhase(GenesisAgentRegistry.Phase.Allowlist);
        vm.stopPrank();

        // carol is not in the tree; her proof (any sibling) fails.
        vm.expectRevert("Not allowlisted");
        vm.prank(carol);
        reg.mintAllowlist("ipfs://carol", _emptyMeta(), _proofFor(leafBob));
    }

    function test_Allowlist_WrongPrice_Reverts() public {
        vm.startPrank(admin);
        reg.setAllowlistRoot(root);
        reg.setAllowlistPrice(0.002 ether);
        reg.setPhase(GenesisAgentRegistry.Phase.Allowlist);
        vm.stopPrank();

        vm.expectRevert("Incorrect mint price");
        vm.prank(alice);
        reg.mintAllowlist{value: 0.001 ether}("ipfs://a", _emptyMeta(), _proofFor(leafBob));
    }

    // ── public phase + treasury payout ──────────────────────────────────

    function test_Public_Mints_And_ForwardsToTreasury() public {
        vm.prank(admin);
        reg.setPhase(GenesisAgentRegistry.Phase.Public);

        uint256 before = treasury.balance;
        vm.prank(carol);
        uint256 id = reg.mint{value: 0.001 ether}("ipfs://carol", _emptyMeta());

        assertEq(reg.ownerOf(id), carol);
        assertEq(treasury.balance - before, 0.001 ether);
    }

    function test_Public_WrongValue_Reverts() public {
        vm.prank(admin);
        reg.setPhase(GenesisAgentRegistry.Phase.Public);

        vm.expectRevert("Incorrect mint price");
        vm.prank(carol);
        reg.mint{value: 0.005 ether}("ipfs://carol", _emptyMeta());
    }

    // ── maxSupply cap ───────────────────────────────────────────────────

    function test_MaxSupply_Caps() public {
        vm.startPrank(admin);
        reg.setPhase(GenesisAgentRegistry.Phase.Public);
        reg.setPublicPrice(0);
        reg.setMaxSupply(2);
        vm.stopPrank();

        vm.prank(alice);
        reg.mint("ipfs://1", _emptyMeta());
        vm.prank(bob);
        reg.mint("ipfs://2", _emptyMeta());

        vm.expectRevert("Max supply reached");
        vm.prank(carol);
        reg.mint("ipfs://3", _emptyMeta());
    }

    function test_SetMaxSupply_BelowCurrent_Reverts() public {
        vm.startPrank(admin);
        reg.setPhase(GenesisAgentRegistry.Phase.Public);
        reg.setPublicPrice(0);
        vm.stopPrank();

        vm.prank(alice);
        reg.mint("ipfs://1", _emptyMeta());
        vm.prank(bob);
        reg.mint("ipfs://2", _emptyMeta());

        vm.expectRevert("Below current supply");
        vm.prank(admin);
        reg.setMaxSupply(1);
    }

    // ── self-source + conformance ───────────────────────────────────────

    function test_SelfSource_And_Interfaces() public {
        vm.prank(admin);
        reg.setPhase(GenesisAgentRegistry.Phase.Public);
        vm.prank(alice);
        uint256 id = reg.mint{value: 0.001 ether}("ipfs://a", _emptyMeta());

        (address src, uint256 srcId) = reg.getSourceNFT(id);
        assertEq(src, address(reg));
        assertEq(srcId, id);
        assertTrue(reg.isSourceNFTOwnershipValid(id));
        assertTrue(reg.hasSourceNFT(id));

        // Honest ERC-165: advertises the query-only subset it implements, NOT the full interface.
        assertTrue(reg.supportsInterface(0x8b3597c9));  // IAgentSourceBindingView (getSourceNFT^hasSourceNFT^isSourceNFTOwnershipValid)
        assertFalse(reg.supportsInterface(0x27eba962)); // NOT full IAgentSourceBinding — no boundCollection/registerWithSource (Fede's finding)
        assertTrue(reg.supportsInterface(0x2a55205a));  // IERC2981
        assertTrue(reg.supportsInterface(0x80ac58cd));  // IERC721
    }

    function test_TokenURI_ResolvesPlaceholder() public {
        vm.prank(admin);
        reg.setPhase(GenesisAgentRegistry.Phase.Public);
        vm.prank(alice);
        uint256 id = reg.mint{value: 0.001 ether}("", _emptyMeta()); // falls back to baseAgentURI
        assertEq(reg.tokenURI(id), "ipfs://base/1");
    }

    // ── admin gating ────────────────────────────────────────────────────

    function test_OnlyOwner_Phase_And_Price() public {
        vm.expectRevert();
        vm.prank(alice);
        reg.setPhase(GenesisAgentRegistry.Phase.Public);

        vm.expectRevert();
        vm.prank(alice);
        reg.setPublicPrice(1 ether);

        vm.expectRevert();
        vm.prank(alice);
        reg.setAllowlistRoot(bytes32(uint256(1)));
    }

    function test_Paused_BlocksMint() public {
        vm.startPrank(admin);
        reg.setPhase(GenesisAgentRegistry.Phase.Public);
        reg.pause();
        vm.stopPrank();

        vm.expectRevert(); // Pausable: paused
        vm.prank(alice);
        reg.mint{value: 0.001 ether}("ipfs://a", _emptyMeta());
    }
}
