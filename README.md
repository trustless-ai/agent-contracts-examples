# agent-contracts-examples

Minimal, **clone-and-run** quickstarts over the two shared [onchain-ai](https://github.com/onchain-ai)
dependencies — `agent-ercs` (on-chain primitives) + [`agent-sdk`](https://github.com/onchain-ai/agent-sdk)
(off-chain verify/recompute). Not production code; the smallest thing that gets a newcomer from zero to
*"I verified an agent claim myself, trusting no one"*.

## The one rule

Every example ships a **verify / recompute step near the top of its README** — a newcomer re-derives the
example's central claim from public data in one command. (See the org [CONTRIBUTING](https://github.com/onchain-ai/.github/blob/main/CONTRIBUTING.md).)

## Examples

| | shows | shared deps |
|---|---|---|
| [`recovery-receipt`](./recovery-receipt) | verify an agent's commit-before-outcome receipt **on-chain** (no oracle) → owner-bound escrow release | `agent-sdk` + the BIP-340 verify primitive |

## License

Apache-2.0 (code) — matching `agent-sdk` and the org standard (Apache-2.0 code / CC0 specs).
