// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice ERC-8323 query-only companion interface — the read side of source binding.
///         ERC-165 id 0x8b3597c9 = getSourceNFT ^ hasSourceNFT ^ isSourceNFTOwnershipValid.
interface IAgentSourceBindingView {
    function getSourceNFT(uint256 agentId) external view returns (address collection, uint256 tokenId);
    function hasSourceNFT(uint256 agentId) external view returns (bool);
    function isSourceNFTOwnershipValid(uint256 agentId) external view returns (bool);
}
