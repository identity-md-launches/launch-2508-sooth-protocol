# Sooth Protocol (SOOTH)

`src/SoothToken.sol:SoothToken` is a fixed-supply ERC-20. Its constructor mints
1,000,000,000 SOOTH, with 18 decimals, entirely to the immediate deployer. On the
IdentityMD launch path that deployer is the factory. There are no constructor
arguments, initialization calls, application contracts, or external contract
dependencies at runtime.

## Scope and assumptions

The brief's additional description is only **“M”**. It does not define an
executable feature or transfer rule. This implementation treats it as an
unspecified description and implements the concrete name, symbol, supply, and
constructor allocation requirements as a standard ERC-20. It does not infer a
meaning such as mintability, a market, or a separate protocol from that letter.

Transfers deliver exactly the requested amount. There are no token taxes,
rebases, burns, pause controls, blacklists, ownership roles, upgrade paths, or
post-construction minting. Supply remains constant for the lifetime of this
deployment. The deployer has the same transfer and approval rights as any other
holder after construction.

The token uses the vendored
[OpenZeppelin Contracts v5.1.0 ERC-20 implementation](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.1.0/contracts/token/ERC20/ERC20.sol).
Successful transfers and approvals return `true`; invalid operations revert with
ERC-6093 custom errors. Zero-value transfers are supported, and zero-address
recipients and spenders are rejected. Approvals replace the existing allowance;
`type(uint256).max` denotes an allowance that spending does not decrease. Finite
allowances decrease on `transferFrom`. Transfers emit `Transfer`; explicit
approvals emit `Approval`. Spending an allowance does not emit an extra `Approval`
event, so clients should query `allowance` for its current value.

## Build and tests

Prerequisites are Foundry and Solidity **0.8.26**. All imported source files are
ordinary files under `lib/`; no package download, submodule initialization, RPC,
wallet, or environment configuration is required by the tests. The verifier
provides the pinned compiler offline.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x844885d1b156a9585143bfb759f05fe92cb29d52387a537fb48553a94780f0ce forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, enables the optimizer with 200 runs, uses the
Paris EVM target, and sets `bytecode_hash = "none"`. Paris avoids requiring newer
EVM opcodes for this simple token. No FFI or filesystem cheatcode permissions are
enabled. Each fuzz test runs 1,024 cases; no seed is pinned in configuration, so
the verifier's supplied seed remains effective.

Tests cover:

- Exact metadata, base-unit supply, initial allocation, and the single mint event.
- Exact transfers, full balances, one base unit, zero transfers, and self-transfers.
- Approval replacement/revocation, finite and unlimited spending, unauthorized
  callers, exhausted approvals, and rollback of allowances when a transfer fails.
- Invalid zero-address operations, overdrafts, unsupported administrative calls,
  native-currency rejection, and absence of public mint/burn/upgrade entry points.
- Factory CREATE2 deployment, exact 10%/80%/10% allocation, full distributor claims,
  transfers into and out of pool custody, and the factory's lack of holder privileges.
- Random transfer and approval sequences checked against an independent ledger
  after every action, including failures and self-transfers. `STEPS = 32` is the
  number of actions per model test case.

The launch test models token custody movements; it does not implement a pool or
claim to execute real Uniswap swaps. The supplied protected test source was read
to check compatibility. Its full v4 integration and ownership checks require the
network's separate launch harness, creation-code inputs, and resolved manifest;
they are not part of this standalone local test suite.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract | `SoothToken` |
| Artifact | `out/SoothToken.sol/SoothToken.json` |
| Constructor arguments | None (`[]`) |
| Name | `Sooth Protocol` |
| Symbol | `SOOTH` |
| Decimals | `18` |
| Initial and total supply, base units | `1000000000000000000000000000` |
| Mint recipient | Immediate constructor caller (`msg.sender`) |
| Target chain, as specified in the assignment | Robinhood Chain, chain ID `4663` |
| Owner / administrator | None |
| Application contracts | None |

The launch service deploys the compiled creation bytecode directly through its
factory. Do not deploy through a helper that retains the initial supply: the
actual immediate deploying contract receives it. The constructor makes no
external calls, requires no funded external accounts, and works on an empty
chain. No linked libraries or proxy deployment steps are required.

The following are the assignment's launch-system parameters. They are not
constructor arguments, token configuration, or values independently discovered
on-chain during this task:

- Pair currency: IMD at `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127`, 18 decimals.
- Pool fee: `12500` (1.25%); tick spacing: `60`.
- Reference `pool.initialPrice`: `79228162514264337593543950336`. The launch system
  derives the actual opening price from market cap, supply, and token ordering.
- Economics, preserved as supplied:

```json
{"poolBps":8000,"initialMarketCapWei":"4000000000000000000000","remainderTo":"0xd6302976e590b9b947da8774b7f1246164e0ce98"}
```

The initial market cap is 4,000 IMD for the entire supply. The factory handles
distribution: 100,000,000 SOOTH (10%) to its MerkleDistributor, 800,000,000 SOOTH
(80%) for pool seeding, and 100,000,000 SOOTH (10%) to the specified remainder
recipient. The token constructor allocates all tokens to the factory before any
of those transfers; it neither implements nor controls their destination rules.
The separate manifest step produces `launch.json` after acceptance.

## After launch

There are no owner-settable values, keeper jobs, subscriptions, oracle feeds,
allowlists, or initialization transactions. The launch operator is responsible
for deployment, distribution, pool initialization, and explorer verification
using the pinned build settings. Check the deployed metadata and supply, initial
mint log, and resulting balances against the accepted launch manifest.

Holders control their own balances and approvals. Wallets should display amounts
using 18 decimals, request only the allowance needed, and account for the
standard ERC-20 allowance replacement race when changing an existing approval
([ERC-20](https://eips.ethereum.org/EIPS/eip-20)). There is no administrator able
to recover mistaken token transfers or assets sent to this contract. Transfers
to the token contract itself are valid ERC-20 transfers but cannot be recovered.

The contract has no timing, oracle, randomness, bridge, or chain-specific
precompile logic. Transaction inclusion and finality still depend on the target
chain. Local testing and source review do not replace an independent security
review before release. Slither, Mythril, live-chain deployment, and full launch
integration were not run as part of this implementation.
