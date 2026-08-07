// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/// @notice Minimal token-bound account implementation. It only needs to EXIST as an address
///         that can hold a token — this example is about who `ownerOf` reports, not about
///         what the account can execute.
contract MiniAccount {
    receive() external payable {}
}
