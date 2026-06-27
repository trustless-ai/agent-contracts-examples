# agent-contracts-examples

Runnable examples for the [trustless-ai](https://github.com/trustless-ai) verification stack.
Each example is zero-dependency and self-describing — the README explains what to run and why.

## verify/ — recompute and verify proofs yourself, trusting nothing

The core claim of the stack: every verdict is recomputable from public data.
These examples show you how to verify a single proof and how to re-derive the entire public ledger
without trusting the issuer's API.

```bash
# verify one proof (zero deps, stdlib only)
python verify/invinoveritas_verify.py verify/sample_proof.json

# recompute the entire live ledger from public Nostr relays
python verify/recompute_ledger.py

# machine-readable output
python verify/recompute_ledger.py --json
```

`invinoveritas_verify.py` is byte-compatible with `verifyProof` in
[@trustless-ai/agent-sdk](https://github.com/trustless-ai/agent-sdk) — both derive the
NIP-01 event id via `sha256(JSON [0, pubkey, created_at, kind, tags, content])` and
verify the BIP-340 schnorr signature against the published key. Run both on the same
proof to confirm they agree.

`recompute_ledger.py` fetches events from public Nostr relays (never the issuer's API),
recomputes ids and signatures, and reports which entries independently verified. Entries
older than relay retention can be verified via their Bitcoin OpenTimestamps anchor:
`ots verify -d <event_id> <event_id>.ots`.

### What these cover in the 5-layer stack

```
commitment  (ERC-8281)   — commit before outcome
identity    (ERC-8004)   — who signed it
authority   (ERC-8312)   — what it was permitted to do
witnessed   (ERC-8299/8274, OURS) — recomputable verdict ← verify/ examples live here
settle-once (ERC-8275)   — conditional escrow on the proof
```

The verify layer is the trust anchor everything above depends on: escrow releases on a
recomputable proof, not a claim.
