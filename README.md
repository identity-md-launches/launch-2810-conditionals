# Conditionals (COND)

Conditionals is a fixed-supply ERC-20 token. The entire supply is minted once,
in the constructor, to the immediate deployer (`msg.sender`).

| Property | Value |
| --- | --- |
| Solidity contract | `Conditionals` |
| Source | `src/Conditionals.sol` |
| Name | `Conditionals` |
| Symbol | `COND` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None |
| Native currency required by constructor | None; constructor is nonpayable |
| Initial recipient | Immediate deployer; the factory when factory-deployed |
| Administrative roles or configurable settings | None |

## Behavior and assumptions

The brief specifies metadata, supply, and initial allocation. Ordinary ERC-20
behavior is used for transfers and approvals. There are no transfer taxes,
rebases, transfer restrictions, public burns, further minting, ownership,
upgrade mechanism, pause, blacklist, seizure powers, or external dependencies
at runtime. The constructor makes no external calls. The internal mint helper
is reachable only from construction in this deployed contract.

Transfers deliver the exact amount and emit `Transfer`. Zero-amount transfers
are allowed between valid addresses and emit the same event. Self-transfers
require sufficient balance and preserve it. Transfers to the zero address
revert. `approve` sets an allowance and emits `Approval`; `transferFrom`
requires the caller's allowance and sufficient sender balance. Failed calls
revert atomically, including any allowance changes.

Allowances can exceed a balance, can be overwritten, and can be revoked by
approving zero. OpenZeppelin's standard maximum-`uint256` allowance is treated
as unlimited and is not reduced when spent. Spending a finite allowance
reduces it without emitting an additional `Approval` event; indexers should
read `allowance` rather than infer it solely from approval events. Holders
should approve only trusted spenders and the required amounts. When replacing
a live allowance, first revoke it and confirm that transaction to mitigate
the standard ERC-20 allowance replacement race.

## Build and checks

Foundry is required. Solidity is pinned to `0.8.26` in root `foundry.toml`.
The configuration targets Cancun, enables the optimizer with 200 runs, and
sets `bytecode_hash = "none"` for reproducible launch bytecode. Deploy only to
a chain supporting the configured EVM version (the intended chain is Ethereum).

All Solidity dependencies and their licenses are ordinary files under `lib/`;
no network, package installation, submodules, FFI, filesystem cheatcode access,
RPC endpoint, keys, or environment configuration are needed by the tests.
An offline verifier needs Foundry and the pinned compiler already installed.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x2ea7e1720a3ea5225f9cc1738201c0eeb25e147fe6e7f001f38ccbf3bacb03a0 forge test
forge fmt --check
```

The unit tests cover exact metadata and supply, the constructor's mint event,
contract/factory deployment, complete allocation and claim transfers, holder
transfers in both directions, self/zero transfers, approvals, finite/infinite
allowances, revocation, atomic failures, and absent privileged entrypoints.
The factory flow test models token movements; the independent launch checks
exercise actual pool integration.

Five fuzz tests exercise valid and invalid transfers, self-transfers, approvals,
and delegated spending (512 cases each). Stateful invariant tests execute
random sequences of transfers, approvals, and delegated transfers across four
actors (128 runs, up to 64 calls each), comparing balances and allowances
against an independent model and requiring constant supply and conservation.
Tests use isolated deployments and no environment reads or writes.

## Deployment and operational responsibilities

Deploy the creation bytecode for `src/Conditionals.sol:Conditionals` with no
constructor arguments, zero native value, and no initialization call. It is
a direct deployment, not a proxy. `new Conditionals()` is sufficient from a
factory. The factory receives all `10^27` base units; the transaction origin,
factory caller, and a separate owner address receive none automatically. The
launch factory is responsible for subsequent swarm, pool, and remainder
allocations. The token itself performs no distribution or pool initialization.

The launch operator should confirm compiler settings and artifact identity,
deploy through the intended factory, verify source on the target chain, and
check `name`, `symbol`, `decimals`, `totalSupply`, the constructor `Transfer`
event, and allocation balances. Launch orchestration and its manifest belong
to the separate launch process; no manifest or broadcast script is needed to
configure this token. This assignment does not execute transactions.

### After launch

There are no setters, privileged keys, initialization steps, external services,
or keeper responsibilities. Holders control transfers and approvals; the
deployer has the same rights as every other holder. Deployment and distribution
are irreversible. Operators cannot recover mistakenly sent tokens or assets
from this contract, reset allowances, freeze holders, or repair the deployed
code. In particular, users should not send COND, other tokens, or native
currency to the token contract itself. Ordinary native-currency sends revert.

## Security and dependencies

The token inherits the unmodified ERC-20 implementation from OpenZeppelin
Contracts `v5.1.0`; only its dependency closure is vendored. Tests use
forge-std `v1.9.7`. Each dependency directory contains its license and a
`VENDORED.md` recording the upstream URL, version, and archive SHA-256.
No dependency download is performed by the build.

The supplied security reference was considered for input validation, decimal
handling, access control, supply reachability, and external-call risks. The
token has no oracle, signature, randomness, external call, or upgrade path.
Foundry build, unit/fuzz/invariant tests, and formatting are the local
verification methods. Slither, Mythril, a production pool deployment, and an
independent security audit are not claimed by this project. Local tests do not
replace the separate independent adversarial review before release.
