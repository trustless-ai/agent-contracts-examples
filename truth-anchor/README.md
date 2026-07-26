# truth-anchor/ — the ERC-8281 commitment anchor

The concrete **commitment** layer of the stack (`commit before outcome`). [`src/TruthAnchor.sol`](src/TruthAnchor.sol) is a permissionless, storage-less, ownerless contract whose only job is to emit a commitment.

```solidity
event Recorded(bytes32 indexed digest, address indexed committer);
function record(bytes32 digest) external { emit Recorded(digest, msg.sender); }
```

*"The log is the ledger."* An agent action's attestation digest is committed with `record(digest)`; anyone reads the `Recorded` event back and **recomputes** the digest from public data. Nothing about this contract, its deployer, or any server has to be trusted — the event either matches the recomputed hash or it doesn't. The same digest may be recorded any number of times (every identical action re-commits it), and each call is an independent, valid anchor.

- `topic0(Recorded)` = `0xdca60c2087041cbb12d9a57628c6cad28ecbd0437e47c7ab6c3aa6e162bf4497`
- The test asserts that canonical topic0, and fuzzes `record()` over arbitrary digests.

```bash
cd truth-anchor
forge test
forge script script/Deploy.s.sol:Deploy --rpc-url $RPC --private-key $PK --broadcast
```

## Deployments

The **same** contract, deployed unchanged to three chains — one action can be committed on more than one, giving independent commitments a verifier cross-checks. It's the anchor read live by the [Recomputable Agents](https://github.com/Echo-Merlini/verifiable-agents) `/verify` page ([demo.verticecriativo.pt](https://demo.verticecriativo.pt)).

| Chain | Address | Role |
|---|---|---|
| **Ethereum mainnet** (1) | [`0x1e2A118a2bf1C240aE6fDe187c07f905D360f094`](https://etherscan.io/address/0x1e2A118a2bf1C240aE6fDe187c07f905D360f094) | Showcase anchor — `/verify` reads mainnet |
| **Base Sepolia** (84532) | [`0x0963Fd33DF80c94360F2DC22e5c09517AeE7ED5c`](https://sepolia.basescan.org/address/0x0963Fd33DF80c94360F2DC22e5c09517AeE7ED5c) | Live per-action anchors (cheap, high-frequency) |
| **0G Galileo testnet** (16602) | [`0x29A45029DE2439925f2525E01Be6b6631fC9DD85`](https://chainscan-galileo.0g.ai/address/0x29A45029DE2439925f2525E01Be6b6631fC9DD85) | Second, independent commitment |

Committer / attestor across all three: `0x85Fa13511D170FBe173761b63D7f8DD4A6f6Bf1A`.

## Indexed by The Graph

Two subgraphs index the `Recorded` events so a commitment isn't just on-chain but **queryable** — its answer must agree with the raw RPC log read. Manifests + mappings live in the app repo: [`subgraph/`](https://github.com/Echo-Merlini/verifiable-agents/tree/main/subgraph) (mainnet, slug `recomputable-agents-anchor`, start block 25548334) · [`subgraph-base/`](https://github.com/Echo-Merlini/verifiable-agents/tree/main/subgraph-base) (Base Sepolia, slug `recomputable-agents-anchor-base`, start block 41658338).
