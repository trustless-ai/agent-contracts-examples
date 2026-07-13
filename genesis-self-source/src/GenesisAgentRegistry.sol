// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @notice Query-only subset of `IAgentSourceBinding` that a *self-sourced* agent honestly
///         implements. ERC-165 id `0x8b3597c9` = `getSourceNFT ^ hasSourceNFT ^ isSourceNFTOwnershipValid`.
///         A genesis agent implements the READ side of source-binding but NOT the bridge side
///         (`boundCollection` / `registerWithSource`), so it must advertise THIS id — not the full
///         `IAgentSourceBinding` (`0x27eba962`), which would be a false ERC-165 positive for the two
///         bridge methods it does not implement.
interface IAgentSourceBindingView {
    function getSourceNFT(uint256 agentId) external view returns (address sourceContract, uint256 sourceTokenId);
    function hasSourceNFT(uint256 agentId) external view returns (bool);
    function isSourceNFTOwnershipValid(uint256 agentId) external view returns (bool);
}

/**
 * @title GenesisAgentRegistry
 * @notice ERC-8004 Identity Registry for **self-sovereign ("genesis") agents** —
 *         anyone can mint an agent directly, without owning a pre-existing NFT.
 *         Unlike `AgentIdentityRegistry` (bound to an external source collection),
 *         a genesis agent's source is the agent itself: `getSourceNFT(id)` returns
 *         `(address(this), id)`. It advertises `IAgentSourceBindingView` (`0x8b3597c9`,
 *         the query-only subset it actually implements) + ERC-2981 — NOT the full
 *         `IAgentSourceBinding` (`0x27eba962`), whose `boundCollection`/`registerWithSource`
 *         bridge methods a genesis agent has no reason to implement.
 *
 *         One shared registry serves all minters (open-edition style); `agentId`
 *         increments per mint.
 *
 *         Minting is phased and admin-controlled:
 *           - `Closed`    : no public minting (deploy default).
 *           - `Allowlist` : only addresses in `allowlistRoot` may mint, at
 *                           `allowlistPrice` (may be 0 = free).
 *           - `Public`    : anyone may mint at `publicPrice`.
 *
 *         Economics (admin-configurable):
 *           - `allowlistPrice` / `publicPrice` : native ETH per mint, per phase.
 *           - `treasury`                       : receives mint proceeds.
 *           - `royaltyReceiver` / `royaltyBps` : ERC-2981 secondary royalty.
 *           - `maxSupply`                      : hard cap (0 = unlimited).
 *
 *         Platform usage credits are metered off-chain per-wallet by the gateway
 *         (a free-trial grant is issued at mint); nothing credit-related lives here.
 */
contract GenesisAgentRegistry is ERC721URIStorage, EIP712, Ownable2Step, Pausable, IERC2981 {
    using ECDSA for bytes32;

    // ── Types ───────────────────────────────────────────────────────────

    enum Phase { Closed, Allowlist, Public }

    struct MetadataEntry {
        string metadataKey;
        bytes metadataValue;
    }

    /// @notice Bundle of constructor parameters.
    struct InitParams {
        string name;
        string symbol;
        string baseAgentURI;
        address initialAdmin;
        address payable treasury;
        address royaltyReceiver;
        uint96 royaltyBps;
        uint256 maxSupply;
        uint256 allowlistPrice;
        uint256 publicPrice;
    }

    // ── Events ──────────────────────────────────────────────────────────

    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);
    event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy);
    event MetadataSet(
        uint256 indexed agentId,
        string indexed indexedMetadataKey,
        string metadataKey,
        bytes metadataValue
    );
    event SourceNFTLinked(
        uint256 indexed agentId,
        address indexed sourceContract,
        uint256 sourceTokenId
    );
    event BaseAgentURIUpdated(string oldURI, string newURI);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event RoyaltyUpdated(address oldReceiver, uint96 oldBps, address newReceiver, uint96 newBps);
    event MintProceedsForwarded(uint256 indexed agentId, address indexed treasury, uint256 amount);
    event PhaseChanged(Phase oldPhase, Phase newPhase);
    event PriceUpdated(Phase indexed phase, uint256 oldPrice, uint256 newPrice);
    event AllowlistRootUpdated(bytes32 oldRoot, bytes32 newRoot);
    event MaxSupplyUpdated(uint256 oldMax, uint256 newMax);

    // ── Constants ───────────────────────────────────────────────────────

    /// @notice Hard cap on royalties — 10%.
    uint96 public constant MAX_ROYALTY_BPS = 1000;

    /// @dev EIP-712 typehash for wallet verification.
    bytes32 private constant WALLET_TYPEHASH =
        keccak256("SetAgentWallet(uint256 agentId,address newWallet,uint256 deadline)");

    // ── Config ──────────────────────────────────────────────────────────

    Phase public phase;

    string public baseAgentURI;

    uint256 public allowlistPrice;
    uint256 public publicPrice;
    bytes32 public allowlistRoot;

    /// @notice Hard cap on total genesis agents. 0 = unlimited.
    uint256 public maxSupply;

    address payable public treasury;
    address public royaltyReceiver;
    uint96 public royaltyBps;

    // ── Storage ─────────────────────────────────────────────────────────

    uint256 private _nextId = 1;

    mapping(uint256 => mapping(string => bytes)) private _metadata;
    mapping(uint256 => address) private _agentWallets;

    // ── Constructor ─────────────────────────────────────────────────────

    constructor(InitParams memory p)
        ERC721(p.name, p.symbol)
        EIP712("GenesisAgentRegistry", "1")
        Ownable(p.initialAdmin)
    {
        require(p.royaltyBps <= MAX_ROYALTY_BPS, "Royalty too high");
        if (p.royaltyBps > 0) require(p.royaltyReceiver != address(0), "Royalty receiver required");
        if (p.allowlistPrice > 0 || p.publicPrice > 0) require(p.treasury != address(0), "Treasury required");

        baseAgentURI = p.baseAgentURI;
        treasury = p.treasury;
        royaltyReceiver = p.royaltyReceiver;
        royaltyBps = p.royaltyBps;
        maxSupply = p.maxSupply;
        allowlistPrice = p.allowlistPrice;
        publicPrice = p.publicPrice;
        // phase starts at Closed (0) — opened live via setPhase.
    }

    // ── Minting ─────────────────────────────────────────────────────────

    /// @notice Public-phase mint. Send exactly `publicPrice`.
    function mint(string calldata agentURI, MetadataEntry[] calldata metadata)
        external
        payable
        whenNotPaused
        returns (uint256 agentId)
    {
        require(phase == Phase.Public, "Public phase not active");
        require(msg.value == publicPrice, "Incorrect mint price");
        return _mintGenesis(agentURI, metadata);
    }

    /// @notice Allowlist-phase mint. Caller must present a valid Merkle proof for
    ///         their address against `allowlistRoot`, and send exactly `allowlistPrice`.
    function mintAllowlist(
        string calldata agentURI,
        MetadataEntry[] calldata metadata,
        bytes32[] calldata proof
    ) external payable whenNotPaused returns (uint256 agentId) {
        require(phase == Phase.Allowlist, "Allowlist phase not active");
        require(msg.value == allowlistPrice, "Incorrect mint price");
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(proof, allowlistRoot, leaf), "Not allowlisted");
        return _mintGenesis(agentURI, metadata);
    }

    function _mintGenesis(
        string calldata agentURI,
        MetadataEntry[] calldata metadata
    ) private returns (uint256 agentId) {
        require(maxSupply == 0 || _nextId - 1 < maxSupply, "Max supply reached");

        agentId = _registerInternal(agentURI, metadata, msg.sender);

        // Self-source: the agent IS its own source token.
        _metadata[agentId]["sourceNFT"] = abi.encode(address(this), agentId);
        emit MetadataSet(agentId, "sourceNFT", "sourceNFT", abi.encode(address(this), agentId));
        emit SourceNFTLinked(agentId, address(this), agentId);

        if (msg.value > 0) {
            (bool ok, ) = treasury.call{value: msg.value}("");
            require(ok, "Treasury transfer failed");
            emit MintProceedsForwarded(agentId, treasury, msg.value);
        }
    }

    // ── Agent URI ───────────────────────────────────────────────────────

    function setAgentURI(uint256 agentId, string calldata newURI) external {
        require(_isAuthorized(ownerOf(agentId), msg.sender, agentId), "Not authorized");
        _setTokenURI(agentId, newURI);
        emit URIUpdated(agentId, newURI, msg.sender);
    }

    // ── Metadata ────────────────────────────────────────────────────────

    function getMetadata(uint256 agentId, string memory metadataKey)
        external
        view
        returns (bytes memory)
    {
        _requireOwned(agentId);
        return _metadata[agentId][metadataKey];
    }

    function setMetadata(uint256 agentId, string memory metadataKey, bytes memory metadataValue)
        external
    {
        require(_isAuthorized(ownerOf(agentId), msg.sender, agentId), "Not authorized");
        require(
            keccak256(bytes(metadataKey)) != keccak256(bytes("agentWallet")),
            "Use setAgentWallet()"
        );
        _metadata[agentId][metadataKey] = metadataValue;
        emit MetadataSet(agentId, metadataKey, metadataKey, metadataValue);
    }

    // ── Agent Wallet (EIP-712 verified) ─────────────────────────────────

    function getAgentWallet(uint256 agentId) external view returns (address) {
        _requireOwned(agentId);
        address wallet = _agentWallets[agentId];
        return wallet == address(0) ? ownerOf(agentId) : wallet;
    }

    function setAgentWallet(
        uint256 agentId,
        address newWallet,
        uint256 deadline,
        bytes calldata signature
    ) external {
        require(_isAuthorized(ownerOf(agentId), msg.sender, agentId), "Not authorized");
        require(block.timestamp <= deadline, "Signature expired");
        require(newWallet != address(0), "Invalid wallet");

        bytes32 structHash = keccak256(abi.encode(WALLET_TYPEHASH, agentId, newWallet, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);

        address recovered = digest.recover(signature);
        if (recovered != newWallet) {
            try IERC1271(newWallet).isValidSignature(digest, signature) returns (bytes4 magicValue) {
                require(magicValue == IERC1271.isValidSignature.selector, "Invalid smart wallet sig");
            } catch {
                revert("Invalid wallet signature");
            }
        }

        _agentWallets[agentId] = newWallet;
        _metadata[agentId]["agentWallet"] = abi.encode(newWallet);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encode(newWallet));
    }

    function unsetAgentWallet(uint256 agentId) external {
        require(_isAuthorized(ownerOf(agentId), msg.sender, agentId), "Not authorized");
        delete _agentWallets[agentId];
        _metadata[agentId]["agentWallet"] = abi.encode(address(0));
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encode(address(0)));
    }

    // ── Source NFT Queries (self-source) ────────────────────────────────

    /// @notice A genesis agent is its own source: `(address(this), agentId)`.
    function getSourceNFT(uint256 agentId)
        external
        view
        returns (address sourceContract, uint256 sourceTokenId)
    {
        _requireOwned(agentId);
        return (address(this), agentId);
    }

    function hasSourceNFT(uint256 agentId) external view returns (bool) {
        _requireOwned(agentId);
        return true;
    }

    /// @notice Self-sourced ownership is valid as long as the agent token is owned.
    function isSourceNFTOwnershipValid(uint256 agentId) external view returns (bool) {
        _requireOwned(agentId);
        return true;
    }

    // ── ERC-2981 Royalties ──────────────────────────────────────────────

    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        _requireOwned(tokenId);
        if (royaltyReceiver == address(0) || royaltyBps == 0) {
            return (address(0), 0);
        }
        return (royaltyReceiver, (salePrice * royaltyBps) / 10_000);
    }

    // ── Admin ───────────────────────────────────────────────────────────

    function setPhase(Phase newPhase) external onlyOwner {
        Phase old = phase;
        phase = newPhase;
        emit PhaseChanged(old, newPhase);
    }

    function setAllowlistRoot(bytes32 newRoot) external onlyOwner {
        bytes32 old = allowlistRoot;
        allowlistRoot = newRoot;
        emit AllowlistRootUpdated(old, newRoot);
    }

    function setAllowlistPrice(uint256 newPrice) external onlyOwner {
        if (newPrice > 0) require(treasury != address(0), "Set treasury first");
        uint256 old = allowlistPrice;
        allowlistPrice = newPrice;
        emit PriceUpdated(Phase.Allowlist, old, newPrice);
    }

    function setPublicPrice(uint256 newPrice) external onlyOwner {
        if (newPrice > 0) require(treasury != address(0), "Set treasury first");
        uint256 old = publicPrice;
        publicPrice = newPrice;
        emit PriceUpdated(Phase.Public, old, newPrice);
    }

    function setMaxSupply(uint256 newMax) external onlyOwner {
        require(newMax == 0 || newMax >= _nextId - 1, "Below current supply");
        uint256 old = maxSupply;
        maxSupply = newMax;
        emit MaxSupplyUpdated(old, newMax);
    }

    function setBaseAgentURI(string calldata newBaseURI) external onlyOwner {
        string memory old = baseAgentURI;
        baseAgentURI = newBaseURI;
        emit BaseAgentURIUpdated(old, newBaseURI);
    }

    function setTreasury(address payable newTreasury) external onlyOwner {
        if (allowlistPrice > 0 || publicPrice > 0) {
            require(newTreasury != address(0), "Treasury required when price > 0");
        }
        address old = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(old, newTreasury);
    }

    function setRoyalty(address newReceiver, uint96 newBps) external onlyOwner {
        require(newBps <= MAX_ROYALTY_BPS, "Royalty too high");
        if (newBps > 0) require(newReceiver != address(0), "Receiver required when bps > 0");
        address oldReceiver = royaltyReceiver;
        uint96 oldBps = royaltyBps;
        royaltyReceiver = newReceiver;
        royaltyBps = newBps;
        emit RoyaltyUpdated(oldReceiver, oldBps, newReceiver, newBps);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ── View Helpers ────────────────────────────────────────────────────

    function totalSupply() public view returns (uint256) {
        return _nextId - 1;
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // ── Overrides ───────────────────────────────────────────────────────

    /// Clear agentWallet on transfer per ERC-8004 spec.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = super._update(to, tokenId, auth);
        if (from != address(0) && to != address(0)) {
            delete _agentWallets[tokenId];
            _metadata[tokenId]["agentWallet"] = abi.encode(address(0));
            emit MetadataSet(tokenId, "agentWallet", "agentWallet", abi.encode(address(0)));
        }
        return from;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721URIStorage, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(IAgentSourceBindingView).interfaceId ||  // 0x8b3597c9 — the query-only
                // subset a self-sourced agent implements. NOT 0x27eba962 (full IAgentSourceBinding):
                // this contract has no boundCollection/registerWithSource, so claiming the full id
                // would be a false ERC-165 positive. (Fede's finding, 2026-07-13.)
            interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // ── Internal ────────────────────────────────────────────────────────

    function _registerInternal(
        string calldata agentURI,
        MetadataEntry[] calldata metadata,
        address owner_
    ) private returns (uint256 agentId) {
        agentId = _nextId++;
        _mint(owner_, agentId);

        if (bytes(agentURI).length > 0) {
            string memory resolved = _resolveAgentIdPlaceholder(agentURI, agentId);
            _setTokenURI(agentId, resolved);
        } else if (bytes(baseAgentURI).length > 0) {
            _setTokenURI(agentId, _resolveAgentIdPlaceholder(baseAgentURI, agentId));
        }

        _agentWallets[agentId] = owner_;
        _metadata[agentId]["agentWallet"] = abi.encode(owner_);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encode(owner_));

        for (uint256 i = 0; i < metadata.length; i++) {
            require(
                keccak256(bytes(metadata[i].metadataKey)) != keccak256(bytes("agentWallet")),
                "Cannot set agentWallet in metadata array"
            );
            _metadata[agentId][metadata[i].metadataKey] = metadata[i].metadataValue;
            emit MetadataSet(agentId, metadata[i].metadataKey, metadata[i].metadataKey, metadata[i].metadataValue);
        }

        emit Registered(agentId, agentURI, owner_);
    }

    /// @dev Replace the first occurrence of `{agentId}` in `uri` with the decimal
    /// string of `agentId`. Returns `uri` unchanged if the placeholder is absent.
    function _resolveAgentIdPlaceholder(string memory uri, uint256 agentId)
        private
        pure
        returns (string memory)
    {
        bytes memory uriBytes = bytes(uri);
        bytes memory needle = bytes("{agentId}");
        if (uriBytes.length < needle.length) return uri;

        uint256 matchIdx = type(uint256).max;
        for (uint256 i = 0; i + needle.length <= uriBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (uriBytes[i + j] != needle[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                matchIdx = i;
                break;
            }
        }
        if (matchIdx == type(uint256).max) return uri;

        bytes memory idBytes = bytes(Strings.toString(agentId));
        bytes memory result = new bytes(uriBytes.length - needle.length + idBytes.length);

        for (uint256 k = 0; k < matchIdx; k++) {
            result[k] = uriBytes[k];
        }
        for (uint256 k = 0; k < idBytes.length; k++) {
            result[matchIdx + k] = idBytes[k];
        }
        uint256 tailStart = matchIdx + needle.length;
        for (uint256 k = 0; tailStart + k < uriBytes.length; k++) {
            result[matchIdx + idBytes.length + k] = uriBytes[tailStart + k];
        }
        return string(result);
    }
}
