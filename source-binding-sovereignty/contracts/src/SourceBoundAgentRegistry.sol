// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {MiniERC721} from "./MiniERC721.sol";
import {IAgentSourceBindingView} from "./IAgentSourceBindingView.sol";

interface IERC6551Registry {
    function account(address implementation, bytes32 salt, uint256 chainId, address tokenContract, uint256 tokenId)
        external
        view
        returns (address);
}

interface IERC721Min {
    function ownerOf(uint256 tokenId) external view returns (address);
    function exists(uint256 tokenId) external view returns (bool);
}

/// @title SourceBoundAgentRegistry — an ERC-8323 conformant read side, next to the naive check it replaces
/// @notice Agent tokens whose provenance is a source NFT. `isSourceNFTOwnershipValid` implements the
///         FULL three-case live-ownership rule; `naiveIsOwnershipValid` implements the bare
///         `ownerOf(source) == ownerOf(agent)` equality the spec calls NON-CONFORMANT. Both are
///         exposed on purpose: the example's whole point is that they disagree on real states.
contract SourceBoundAgentRegistry is MiniERC721, IAgentSourceBindingView {
    /// @dev The canonical ERC-6551 registry address named by ERC-8323 §"Case (b)".
    IERC6551Registry public constant ERC6551_REGISTRY =
        IERC6551Registry(0x000000006551c19487814612e58FE06813775758);

    /// @dev Case (b) requires a registry to PIN one account — so the implementation and salt it
    ///      derives with are fixed here and readable, per "a conformant registry MUST make that
    ///      implementation and salt determinable".
    address public immutable tbaImplementation;
    bytes32 public constant TBA_SALT = bytes32(0);

    struct Source {
        address collection;
        uint256 tokenId;
        bool set;
    }

    mapping(uint256 => Source) internal _source;

    event SourceNFTLinked(uint256 indexed agentId, address indexed collection, uint256 indexed tokenId);

    error AlreadyBound();

    constructor(address tbaImplementation_) {
        tbaImplementation = tbaImplementation_;
    }

    /// @notice Mint an agent whose provenance is (collection, tokenId). Provenance is immutable.
    function mintWithSource(address to, address collection, uint256 tokenId) external returns (uint256 agentId) {
        agentId = this.mint(to);
        if (_source[agentId].set) revert AlreadyBound();
        _source[agentId] = Source({collection: collection, tokenId: tokenId, set: true});
        emit SourceNFTLinked(agentId, collection, tokenId);
    }

    // ---------------------------------------------------------------- ERC-8323 view

    /// @inheritdoc IAgentSourceBindingView
    /// @dev Immutable provenance — cacheable indefinitely (spec §Caching).
    function getSourceNFT(uint256 agentId) public view returns (address, uint256) {
        ownerOf(agentId); // ERC-721 semantics: revert for a non-existent agent
        Source memory s = _source[agentId];
        return (s.collection, s.tokenId);
    }

    /// @inheritdoc IAgentSourceBindingView
    function hasSourceNFT(uint256 agentId) public view returns (bool) {
        ownerOf(agentId);
        return _source[agentId].set;
    }

    /// @notice The canonical TBA of this agent — pinned, per spec case (b).
    function canonicalAccount(uint256 agentId) public view returns (address) {
        return ERC6551_REGISTRY.account(tbaImplementation, TBA_SALT, block.chainid, address(this), agentId);
    }

    /// @inheritdoc IAgentSourceBindingView
    /// @dev THE conformant rule. True when ownerOf(source) is any of:
    ///      (a) the current owner of agentId          — direct holding
    ///      (b) the agent's CANONICAL ERC-6551 TBA    — the agent holds its own source (sovereignty)
    ///      (c) this binding contract                 — source escrowed under the binding (sovereignty)
    ///      Reverts for a non-existent agent; returns false (never reverts) for a burned source.
    function isSourceNFTOwnershipValid(uint256 agentId) public view returns (bool) {
        address agentOwner = ownerOf(agentId); // reverts if the AGENT doesn't exist
        Source memory s = _source[agentId];
        if (!s.set) return false;
        if (!IERC721Min(s.collection).exists(s.tokenId)) return false; // burned source -> false, not revert
        address srcOwner = IERC721Min(s.collection).ownerOf(s.tokenId);
        return srcOwner == agentOwner // (a)
            || srcOwner == canonicalAccount(agentId) // (b)
            || srcOwner == address(this); // (c)
    }

    // ---------------------------------------------------------------- the anti-pattern

    /// @notice NON-CONFORMANT bare equality, kept here only so the tests can prove it diverges.
    ///         ERC-8323: "A literal ownerOf(sourceToken) == ownerOf(agentId) check is non-conformant:
    ///         it reports every TBA- or binding-custody binding as permanently lapsed."
    function naiveIsOwnershipValid(uint256 agentId) external view returns (bool) {
        address agentOwner = ownerOf(agentId);
        Source memory s = _source[agentId];
        if (!s.set || !IERC721Min(s.collection).exists(s.tokenId)) return false;
        return IERC721Min(s.collection).ownerOf(s.tokenId) == agentOwner;
    }

    // ---------------------------------------------------------------- ERC-165

    /// @dev Honest advertisement: the VIEW id only. This registry has no boundCollection /
    ///      registerWithSource, so claiming the full IAgentSourceBinding id would be a false positive.
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x8b3597c9 // IAgentSourceBindingView
            || interfaceId == 0x01ffc9a7; // ERC-165
    }
}
