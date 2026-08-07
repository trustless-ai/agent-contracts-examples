// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/// @notice The ERC-6551 registry's canonical `account()` derivation, reproduced exactly.
///         Deployed in tests at the canonical address 0x000000006551c19487814612e58FE06813775758
///         (via vm.etch) so the example computes the SAME account a mainnet consumer would.
///
///         A token-bound account is CREATE2-derived from
///         (registry, implementation, chainId, tokenContract, tokenId, salt) — which is exactly
///         why ERC-8323 §"Case (b) MUST pin a single account" exists: one agent token is the base
///         of unboundedly many candidate TBAs, so "any TBA of the agent" is not a checkable rule.
contract ERC6551Registry {
    event ERC6551AccountCreated(
        address account,
        address indexed implementation,
        bytes32 salt,
        uint256 chainId,
        address indexed tokenContract,
        uint256 indexed tokenId
    );

    function account(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) public view returns (address) {
        bytes32 bytecodeHash = keccak256(_creationCode(implementation, salt, chainId, tokenContract, tokenId));
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash)))));
    }

    function createAccount(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external returns (address addr) {
        bytes memory code = _creationCode(implementation, salt, chainId, tokenContract, tokenId);
        addr = account(implementation, salt, chainId, tokenContract, tokenId);
        if (addr.code.length != 0) return addr;
        assembly {
            addr := create2(0, add(code, 0x20), mload(code), salt)
        }
        require(addr != address(0), "create2 failed");
        emit ERC6551AccountCreated(addr, implementation, salt, chainId, tokenContract, tokenId);
    }

    /// @dev ERC-1167 minimal proxy + the immutable (salt, chainId, tokenContract, tokenId) footer.
    function _creationCode(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            hex"3d60ad80600a3d3981f3363d3d373d3d3d363d73",
            implementation,
            hex"5af43d82803e903d91602b57fd5bf3",
            abi.encode(salt, chainId, tokenContract, tokenId)
        );
    }
}
