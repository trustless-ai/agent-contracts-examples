// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {MiniERC721} from "../src/MiniERC721.sol";
import {MiniAccount} from "../src/MiniAccount.sol";
import {ERC6551Registry} from "../src/ERC6551Registry.sol";
import {SourceBoundAgentRegistry} from "../src/SourceBoundAgentRegistry.sol";

/// @notice ERC-8323 §"Valid ownership is not bare owner-equality" — as an executable walk.
///
///         One agent, one source token, four states. At every state both checks run:
///         the conformant three-case rule and the bare-equality anti-pattern. Where they
///         DISAGREE is the carve-out the spec exists to protect.
contract SovereigntyWalkTest is Test {
    /// @dev The canonical ERC-6551 registry address named by the spec.
    address constant CANONICAL_6551 = 0x000000006551c19487814612e58FE06813775758;

    MiniERC721 sourceCollection;
    SourceBoundAgentRegistry registry;
    address tbaImpl;

    address alice = address(0xA11CE);
    address stranger = address(0x57A);

    uint256 agentId;
    uint256 sourceId;

    function setUp() public {
        // Put the real ERC-6551 registry derivation at its canonical address, so the account
        // this example computes is the same one a mainnet consumer would compute.
        vm.etch(CANONICAL_6551, address(new ERC6551Registry()).code);

        sourceCollection = new MiniERC721();
        tbaImpl = address(new MiniAccount());
        registry = new SourceBoundAgentRegistry(tbaImpl);

        vm.prank(alice);
        sourceId = sourceCollection.mint(alice);
        agentId = registry.mintWithSource(alice, address(sourceCollection), sourceId);
    }

    function _report(string memory state) internal view returns (bool conformant, bool naive) {
        conformant = registry.isSourceNFTOwnershipValid(agentId);
        naive = registry.naiveIsOwnershipValid(agentId);
        console2.log(state);
        console2.log("   conformant (3-case rule):", conformant);
        console2.log("   naive  (ownerOf equality):", naive);
    }

    /// @notice STATE 1 — still held. Source sits with the agent owner: case (a).
    ///         Both checks agree. This is the only state a naive implementation gets right.
    function test_state1_stillHeld_bothAgree() public view {
        (bool conformant, bool naive) = _report("STATE 1: still held (direct holder)");
        assertTrue(conformant, "case (a): direct holding must be valid");
        assertTrue(naive, "naive happens to agree here");
    }

    /// @notice STATE 2 — diverged. Source sold to a stranger: the binding genuinely lapsed.
    ///         Both checks agree again — a lapsed binding must read false either way.
    function test_state2_diverged_bothAgree() public {
        vm.prank(alice);
        sourceCollection.transferFrom(alice, stranger, sourceId);

        (bool conformant, bool naive) = _report("STATE 2: diverged (source sold to a stranger)");
        assertFalse(conformant, "a genuinely lapsed binding must be false");
        assertFalse(naive, "naive agrees here too");
    }

    /// @notice STATE 3 — RE-CONVERGED VIA TBA. The source is moved into the agent's own
    ///         canonical ERC-6551 account: case (b), the sovereignty pattern.
    ///
    ///         THE DIVERGENCE. The conformant rule says valid — the agent holds its own source.
    ///         Bare equality says lapsed, because ownerOf(source) is the TBA, not the agent owner.
    ///         A consumer running the naive check would refuse a perfectly sovereign agent.
    function test_state3_reconvergedViaTBA_naiveIsWrong() public {
        vm.prank(alice);
        sourceCollection.transferFrom(alice, stranger, sourceId);

        address tba = registry.canonicalAccount(agentId);
        vm.prank(stranger);
        sourceCollection.transferFrom(stranger, tba, sourceId);

        (bool conformant, bool naive) = _report("STATE 3: re-converged via canonical TBA (sovereignty)");
        assertTrue(conformant, "case (b): the agent holds its own source -> VALID");
        assertFalse(naive, "bare equality force-fails the sovereignty pattern: the bug");
        assertTrue(conformant != naive, "the two rules DISAGREE here: this is the carve-out");
    }

    /// @notice STATE 4 — re-converged via binding-contract escrow: case (c).
    ///         Second divergence, same shape: sovereign custody, naive says lapsed.
    function test_state4_reconvergedViaEscrow_naiveIsWrong() public {
        vm.prank(alice);
        sourceCollection.transferFrom(alice, address(registry), sourceId);

        (bool conformant, bool naive) = _report("STATE 4: re-converged via binding-contract escrow");
        assertTrue(conformant, "case (c): source escrowed under the binding -> VALID");
        assertFalse(naive, "bare equality force-fails escrow custody too");
    }

    /// @notice The canonical account is PINNED (spec: case (b) MUST pin a single account).
    ///         A different implementation or salt yields a different address — so "any TBA of
    ///         the agent" is not a checkable rule, and a registry must declare which one it means.
    function test_canonicalAccountIsPinned_notAnyTBA() public {
        address pinned = registry.canonicalAccount(agentId);
        address otherImpl = address(new MiniAccount());
        address otherAccount = ERC6551Registry(CANONICAL_6551).account(
            otherImpl, bytes32(0), block.chainid, address(registry), agentId
        );
        address otherSalt = ERC6551Registry(CANONICAL_6551).account(
            registry.tbaImplementation(), bytes32(uint256(1)), block.chainid, address(registry), agentId
        );
        assertTrue(pinned != otherAccount, "a different implementation is a different account");
        assertTrue(pinned != otherSalt, "a different salt is a different account");

        // And a source parked in a NON-canonical TBA of the same agent is NOT valid.
        vm.prank(alice);
        sourceCollection.transferFrom(alice, otherAccount, sourceId);
        assertFalse(
            registry.isSourceNFTOwnershipValid(agentId),
            "only the PINNED canonical account counts, not any TBA of the agent"
        );
    }

    /// @notice Spec: nonexistent AGENT reverts; burned SOURCE returns false, never reverts.
    function test_nonexistentAgentReverts_burnedSourceReturnsFalse() public {
        vm.expectRevert();
        registry.isSourceNFTOwnershipValid(9_999);

        vm.prank(alice);
        sourceCollection.burn(sourceId);
        assertFalse(registry.isSourceNFTOwnershipValid(agentId), "burned source -> false, not revert");
    }

    /// @notice Honest ERC-165: the view id only — this registry has no write side.
    function test_erc165_advertisesViewIdOnly() public view {
        assertTrue(registry.supportsInterface(0x8b3597c9), "must advertise IAgentSourceBindingView");
        assertFalse(registry.supportsInterface(0x27eba962), "must NOT claim the full IAgentSourceBinding");
    }

    /// @notice Spec §"Re-check at action time": a verdict issued while the binding held does not
    ///         carry forward. Same agent, same verdict, two different execution moments.
    function test_recheckAtActionTime_notApprovalTime() public {
        bool atVerdictTime = registry.isSourceNFTOwnershipValid(agentId);
        assertTrue(atVerdictTime, "premise held when the verdict was issued");

        vm.prank(alice);
        sourceCollection.transferFrom(alice, stranger, sourceId); // binding lapses AFTER the verdict

        bool atActionTime = registry.isSourceNFTOwnershipValid(agentId);
        assertFalse(atActionTime, "the premise does not carry forward: re-check blocks execution");
    }
}
