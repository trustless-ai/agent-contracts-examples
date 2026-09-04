// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/// @notice The smallest ERC-721 that supports this example: mint, transfer, ownerOf.
///         Deliberately dependency-free — the example must be readable end to end.
contract MiniERC721 {
    mapping(uint256 => address) internal _ownerOf;
    uint256 public nextId = 1;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    error NonexistentToken(uint256 tokenId);
    error NotOwner();

    function mint(address to) external returns (uint256 id) {
        id = nextId++;
        _ownerOf[id] = to;
        emit Transfer(address(0), to, id);
    }

    /// @dev ERC-721 semantics: reverts for a non-existent token.
    function ownerOf(uint256 tokenId) public view returns (address) {
        address o = _ownerOf[tokenId];
        if (o == address(0)) revert NonexistentToken(tokenId);
        return o;
    }

    function exists(uint256 tokenId) external view returns (bool) {
        return _ownerOf[tokenId] != address(0);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        if (ownerOf(tokenId) != from || msg.sender != from) revert NotOwner();
        _ownerOf[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function burn(uint256 tokenId) external {
        address o = ownerOf(tokenId);
        if (msg.sender != o) revert NotOwner();
        delete _ownerOf[tokenId];
        emit Transfer(o, address(0), tokenId);
    }
}
