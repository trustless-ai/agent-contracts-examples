# recovery-receipt — quickstart

**Verify an AI-agent receipt on-chain in ~5 minutes, trusting no one.** A clone-and-run example over the
two shared deps: `@trustless-ai/agent-sdk` (off-chain commit/sign/pack) + the BIP-340 verify primitive
(on-chain). Distilled from the production [hack-ens-recovery](https://github.com/TMerlini/hack-ens-recovery).

## Verify it yourself (the one rule)

The whole point is that you don't trust this code — you re-derive its claim from public data:

```bash
anvil &                                                    # local chain
cd contracts && forge test                                 # 19/19: incl. all 15 official BIP-340 vectors
ISSUER_PUBKEY=<agent x-only> PRIVATE_KEY=<anvil key> \
  forge script script/Deploy.s.sol:Deploy --rpc-url http://127.0.0.1:8545 --broadcast
cd ../app && bun install
AGENT_PRIVKEY=<same agent key> VERIFIER=<deployed addr> bun run quickstart.ts
```

`quickstart.ts` builds a signed receipt, verifies it **on-chain** (`BIP340Verifier.verify → (valid, match)`),
and recomputes the same `artifact_hash` **two independent ways** — the SDK *and* a zero-dependency
hand-rolled recompute — so the verifier is never a black box.

## What it shows

```
commitPreAction → sign (BIP-340) → packReceiptProof   [agent-sdk, off-chain]
        → BIP340Verifier.verify()                     [shared primitive, on-chain]
        → MiniRecoveryEscrow.release()                [gated on valid ∧ match ∧ on-chain delivery]
```

- **owner-bound by construction** — `output_address` is inside `artifact_hash`; the escrow re-checks
  `ownerOf(tokenId) == output_address` on-chain. Never releases on `valid` alone.
- **replay-safe** — the artifact is nullified on release.
- **no oracle** — the signature is checked in the contract (secp256k1 Schnorr via the `ecrecover` trick).

## Assurance ⚠️ pre-audit

`src/BIP340.sol` is **vendored pre-audit** for this example — crypto-critical and not yet independently
reviewed. Two tiers, labeled straight:
- **Tier 1 (interim):** a cred-based public-good review + reference cross-check (vs Chronicle `Schnorr.sol`
  + `crysol`) — being sourced.
- **Tier 2 (mainnet gate):** a grant-funded formal audit. Required before any mainnet value.

On promotion (post-audit) the vendored `src/{BIP340,IReceiptVerifier,BIP340Verifier}.sol` switch to an
import from `@trustless-ai/agent-ercs`. **Do not put mainnet value behind this copy.**

## Layout
- `contracts/src/` — the verify primitive (vendored, pre-audit) + `MiniRecoveryEscrow.sol` (illustrative).
- `contracts/test/` — 19 tests: the BIP-340 suite (incl. 15 official vectors) + the escrow gate.
- `app/quickstart.ts` — the off-chain runnable (agent-sdk side).

License: Apache-2.0.
