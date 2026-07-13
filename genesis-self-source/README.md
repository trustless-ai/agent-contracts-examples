# genesis-self-source — a self-sourced ERC-8004 agent registry

A worked reference for the **self-source** case of [Source-Token Agent Binding](https://github.com/ethereum/ERCs/pull/1851)
(ERC-8323): an agent whose provenance source **is the agent itself**.

Most source-bound agents are bridged from a *pre-existing* NFT — you own a PFP, you mint an agent
that points back at it (`getSourceNFT(id) → (someCollection, tokenId)`). A **genesis** agent has no
external collection: it is minted from scratch, and its source is its own contract —
`getSourceNFT(id) → (address(this), id)`. Anyone can mint a self-sovereign agent from an image +
metadata, no pre-existing token required.

## The point of this example: honest ERC-165

Because a self-sourced agent has no external collection, it **cannot** implement the full
`IAgentSourceBinding` interface — there is nothing to `boundCollection()`, and `registerWithSource()`
has no meaning. It implements only the **read side** of source binding.

Advertising the full interface id would be a *false* ERC-165 positive — a verifier calling
`supportsInterface` would trust a claim the contract can't honor. So this contract advertises the
**query-only subset** instead:

| interface | id | this contract |
|---|---|---|
| `IAgentSourceBinding` (full: 5 selectors) | `0x27eba962` | **false** — no `boundCollection` / `registerWithSource` |
| `IAgentSourceBindingView` (read side: 3 selectors) | `0x8b3597c9` | **true** — `getSourceNFT ^ hasSourceNFT ^ isSourceNFTOwnershipValid` |
| `IERC2981` | `0x2a55205a` | true |
| `IERC721` | `0x80ac58cd` | true |

`test_SelfSource_And_Interfaces` asserts **both** directions (`0x8b3597c9` true, `0x27eba962` false),
so the honest claim can't silently regress. The id is derived via
`type(IAgentSourceBindingView).interfaceId`, not a hardcoded constant, so it can't drift from the
functions the interface declares.

> An implementation MUST advertise only the interface it implements. `IAgentSourceBindingView` is not
> "a smaller interface for lesser contracts" — it is the honest boundary of what a self-sourced agent
> can attest. Whether a source exists and is still owned is universal; registration presumes an
> external collection.

## What the contract does

- **Self-sourced mint** — `mint()` / `mintAllowlist(proof)`; each agent's source is `(address(this), agentId)`.
- **Phased** — `Closed → Allowlist → Public`, admin-toggled; per-phase price; Merkle allowlist
  (leaf = `keccak256(abi.encodePacked(addr))`, sorted-pair).
- **Supply + economics** — `maxSupply` cap (0 = unlimited), treasury forwarding, ERC-2981 royalties, `Pausable`.
- **ERC-8004 identity** — each agent is an ERC-721 with an `{agentId}` tokenURI template and an
  EIP-712 `setAgentWallet` flow.

## Run it

```bash
cd genesis-self-source
git submodule update --init --recursive   # OpenZeppelin v5.6.1 + forge-std
forge test -vv
```

Expect **12 passing**. Compiled with solc 0.8.24, `via_ir = true`, optimizer 200 runs.

## Live reference

Deployed + verified on Ethereum mainnet: [`0xe91934aB1f6A40cc1Bb4cD530FEFF56dFE524963`](https://etherscan.io/address/0xe91934aB1f6A40cc1Bb4cD530FEFF56dFE524963).
Verify the honest claim yourself with a single `eth_call`:

```bash
cast call 0xe91934aB1f6A40cc1Bb4cD530FEFF56dFE524963 "supportsInterface(bytes4)(bool)" 0x8b3597c9  # true
cast call 0xe91934aB1f6A40cc1Bb4cD530FEFF56dFE524963 "supportsInterface(bytes4)(bool)" 0x27eba962  # false
cast call 0xe91934aB1f6A40cc1Bb4cD530FEFF56dFE524963 "getSourceNFT(uint256)(address,uint256)" 1     # (self, 1)
```

Canonical source lives in [`ens-dynamic-kit`](https://github.com/Echo-Merlini/ens-dynamic-kit);
this is the trimmed, standalone reference.
