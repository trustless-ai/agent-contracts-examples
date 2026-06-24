/**
 * recovery-receipt quickstart — verify an agent receipt on-chain in ~5 minutes.
 *
 *   agent-sdk side, owned/reviewed by @babyblueviper1 (verify layer). DRAFT — wire-up by the escrow side.
 *
 * What it shows, end to end:
 *   1. build a commit-before-outcome receipt  (agent-sdk: normalizeSpec + buildCommitEvent + artifactHash)
 *   2. sign it with the agent's BIP-340 key    (@noble/curves schnorr — your key mgmt, the SDK never signs)
 *   3. pack it                                 (agent-sdk: packReceiptProof → exact calldata the verifier reads)
 *   4. verify ON-CHAIN                          (BIP340Verifier.verify → (valid, match))
 *   5. the SAME claim, two independent ways     (SDK verifyFullFlow  AND  a zero-dependency recompute)
 *
 * The point of (5): you never have to trust the SDK. The one-liner and the hand-rolled recompute agree,
 * so "audit the verifier itself" is the headline, not a footnote (trustless-ai CONTRIBUTING, the SDK rule).
 *
 *   # 1. local chain + deploy
 *   anvil &
 *   cd ../contracts && ISSUER_PUBKEY=<agent x-only> PRIVATE_KEY=<anvil key> \
 *     forge script script/Deploy.s.sol:Deploy --rpc-url http://127.0.0.1:8545 --broadcast
 *   # 2. run
 *   AGENT_PRIVKEY=<same agent key> VERIFIER=<deployed addr> bun run quickstart.ts
 */
import { ethers } from "ethers";
import { schnorr } from "@noble/curves/secp256k1";
import { sha256 } from "@noble/hashes/sha256";
import { buildCommitEvent, normalizeSpec, packReceiptProof } from "@trustless-ai/agent-sdk";

const RPC = process.env.RPC_URL ?? "http://127.0.0.1:8545";
const VERIFIER = process.env.VERIFIER ?? "";
const hex = (u: Uint8Array) => Buffer.from(u).toString("hex");

// zero-dependency artifact_hash: sha256 over canonical (sorted, recursive) JSON. No SDK in this path.
function canonical(v: any): string {
  if (Array.isArray(v)) return `[${v.map(canonical).join(",")}]`;
  if (v && typeof v === "object")
    return `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canonical(v[k])}`).join(",")}}`;
  return JSON.stringify(v);
}
const zeroDepArtifactHash = (spec: any) => hex(sha256(new TextEncoder().encode(canonical(spec))));

async function main() {
  if (!VERIFIER) throw new Error("set VERIFIER=<deployed BIP340Verifier address> (see header)");
  const priv = (process.env.AGENT_PRIVKEY ?? "").replace(/^0x/, "");
  if (!priv) throw new Error("set AGENT_PRIVKEY=<32-byte hex>");
  const pubkey = hex(schnorr.getPublicKey(priv)); // x-only; must equal the verifier's pinned issuer

  // 1. build the receipt spec (owner-bound: output_address is inside the hash)
  const spec = normalizeSpec({
    job_id: "quickstart-1",
    target_wallet: "0x000000000000000000000000000000000000dEaD",
    output_address: "0x000000000000000000000000000000000000bEEF",
    asset_set: { ens_name: "example.eth", token_id: "1", base_registrar: "0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85", registry: "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e" },
  });
  const { event, artifact_hash } = buildCommitEvent({ spec, pubkey, judgmentType: "recovery_receipt", schema: "trustless-ai.commit.v0" });

  // 2. sign the event id (BIP-340)
  const idBytes = ethers.getBytes("0x" + (event.id as string).replace(/^0x/, ""));
  event.sig = hex(schnorr.sign(idBytes, priv));

  // 3. pack → the exact bytes the on-chain verifier decodes
  const proof = packReceiptProof(event);
  const expect = "0x" + artifact_hash.replace(/^0x/, "");

  // 4. verify ON-CHAIN
  const verifier = new ethers.Contract(VERIFIER, ["function verify(bytes32,bytes) view returns (bool,bool)"], new ethers.JsonRpcProvider(RPC));
  const [valid, match] = await verifier.verify(expect, proof);

  // 5. same claim, zero-dependency recompute (no SDK)
  const recomputed = zeroDepArtifactHash(spec);
  const sdkHash = artifact_hash.replace(/^0x/, "");
  const recomputeOk = recomputed === sdkHash;

  console.log("agent x-only pubkey :", pubkey);
  console.log("artifact_hash (sdk) :", expect);
  console.log("artifact_hash (0-dep):", "0x" + recomputed, recomputeOk ? "✓ match" : "✗ DRIFT");
  console.log("on-chain verify     : valid =", valid, "| match =", match);
  // Recomputability is the whole thesis here: a zero-dep drift makes the "recomputable
  // without the SDK" claim false, so it MUST fail the run, not just print a line.
  if (!recomputeOk) throw new Error("zero-dep recompute DRIFTED from the SDK artifact_hash — recomputability claim is false; aborting.");
  console.log(valid && match ? "\n✅ a real agent receipt verified on-chain, no oracle — and recomputable without the SDK." : "\n✗ check the pinned issuer key matches AGENT_PRIVKEY.");
}

main().catch((e) => { console.error("\n✗", e instanceof Error ? e.message : e); process.exit(1); });
