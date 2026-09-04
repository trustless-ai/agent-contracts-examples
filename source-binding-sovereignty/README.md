# source-binding-sovereignty — why "bare owner-equality" is non-conformant, as a runnable walk

**Recompute this claim in one command:**

```bash
cd source-binding-sovereignty/contracts
forge test -vv     # 8 passing — states 3 and 4 are the point
```

The output you're checking:

```
STATE 1: still held (direct holder)
   conformant (3-case rule): true
   naive  (ownerOf equality): true
STATE 2: diverged (source sold to a stranger)
   conformant (3-case rule): false
   naive  (ownerOf equality): false
STATE 3: re-converged via canonical TBA (sovereignty)
   conformant (3-case rule): true
   naive  (ownerOf equality): false      <-- the bug
STATE 4: re-converged via binding-contract escrow
   conformant (3-case rule): true
   naive  (ownerOf equality): false      <-- the bug
```

## What this shows

[ERC-8323](https://github.com/ethereum/ERCs/pull/1851) (Source-Token Agent Binding) says
`isSourceNFTOwnershipValid` MUST return true when `ownerOf(sourceToken)` is **any** of:

- **(a)** the current owner of `agentId` — direct, non-custodial holding
- **(b)** the agent's **canonical** [ERC-6551](https://eips.ethereum.org/EIPS/eip-6551) token-bound account — *the agent holds its own source* (sovereignty)
- **(c)** the binding contract itself — source escrowed under the binding (sovereignty)

and that a literal `ownerOf(sourceToken) == ownerOf(agentId)` check is **non-conformant**,
because it "reports every TBA- or binding-custody binding as permanently lapsed."

That sentence is a claim about behavior, so this example makes it a test. One agent, one source
token, four states, both rules evaluated at every state. In states 1 and 2 they agree — which is
exactly why the bug survives review: a naive implementation looks correct until an agent becomes
sovereign. In states 3 and 4 they disagree, and the naive rule refuses an agent that holds its
own provenance.

## The other clauses, also executable

| test | spec clause |
|---|---|
| `test_canonicalAccountIsPinned_notAnyTBA` | case (b) MUST pin **one** account — a different implementation *or* salt is a different address, and a source parked in a non-canonical TBA of the same agent is **not** valid ("any TBA of the agent" is not a checkable rule) |
| `test_nonexistentAgentReverts_burnedSourceReturnsFalse` | non-existent **agent** reverts (ERC-721 `ownerOf` semantics); burned **source** returns false, never reverts |
| `test_erc165_advertisesViewIdOnly` | honest ERC-165: a read-only registry advertises `IAgentSourceBindingView` (`0x8b3597c9`) and MUST NOT claim the full `IAgentSourceBinding` (`0x27eba962`) |
| `test_recheckAtActionTime_notApprovalTime` | a verdict attests the identity premise *as of* its timestamp; the premise does not carry forward, so consumers re-check at **action** time |

## How the TBA is derived

`ERC6551Registry.sol` reproduces the canonical `account()` CREATE2 derivation exactly, and the test
`vm.etch`es it at the canonical registry address `0x000000006551c19487814612e58FE06813775758` — so the
account this example computes is the same one a mainnet consumer computes. `SourceBoundAgentRegistry`
declares its `tbaImplementation` and `TBA_SALT` publicly, satisfying the spec's requirement that a
conformant registry make the pinned account determinable.

## Files

```
contracts/src/
  IAgentSourceBindingView.sol   the ERC-8323 read side (0x8b3597c9)
  SourceBoundAgentRegistry.sol  conformant 3-case rule + the naive check, side by side on purpose
  ERC6551Registry.sol           canonical account() derivation
  MiniERC721.sol / MiniAccount.sol   the smallest source collection + TBA that make the walk real
contracts/test/
  SovereigntyWalk.t.sol         the four states and the four spec clauses
```

Zero dependencies beyond `forge-std`. Nothing here needs a network, an RPC, or a deployment.
