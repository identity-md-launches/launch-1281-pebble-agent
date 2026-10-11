# Pebble Agent (PEBBLE)

An immutable ERC-20 with **1,000,000,000 PEBBLE**, **18 decimals**, and a fixed total supply of
**1,000,000,000,000,000,000,000,000,000 base units** (`10^27`).

## Contract and assumptions

`src/PebbleToken.sol:PebbleToken` extends the vendored OpenZeppelin Contracts v5.1.0 ERC-20.
The constructor mints the entire supply once to `msg.sender`. When a factory deploys it, the
factory receives everything; the originating wallet does not. The token has no owner or
administrative role, external mint or burn function, pause, blacklist, tax, rebase, proxy,
upgrade mechanism, or external calls. Supply remains constant throughout its lifetime.

Transfers deliver the exact amount and return `true`; invalid operations revert with
OpenZeppelin's ERC-6093 custom errors. Zero-value transfers and self-transfers are supported.
The zero address cannot send or receive tokens and cannot be an approval spender.
Approvals replace the previous amount and can be revoked by approving zero. Finite allowances
decrease on `transferFrom`; the ERC-20 convention of an unlimited `uint256.max` allowance is
supported without decrementing it. OpenZeppelin v5 does not emit an `Approval` event when
spending allowance; integrations should read `allowance()` to obtain the current value.

## Build and checks

Run these from the repository root with Foundry and Solidity 0.8.26 installed:

```sh
forge build
forge test
forge fmt --check
```

The compiler is pinned in `foundry.toml`, with Cancun EVM, optimization at 200 runs, and
`bytecode_hash = "none"`. Production and test dependencies are vendored as ordinary files
under `lib/`; no network downloads or submodules are required to build. Dependency versions,
upstream locations, licenses, and individual file SHA-256 hashes are recorded in
`DEPENDENCIES.json`. Neither FFI nor filesystem cheatcode permissions are enabled.

Tests cover metadata, constructor mint/event and factory deployment, exact distribution,
transfers, zero and self transfers, approvals/revocation, finite and unlimited allowances,
insufficient balances/allowances, zero addresses, rollback on failure, absence of privileged
entrypoints, and runtime opcode restrictions. Fuzz tests cover successful and failing
transfers; stateful invariants exercise sequences of transfers, approvals, and delegated
transfers while checking supply and balance conservation. Tests use no environment variables,
RPC endpoints, clock waits, or live chain state. The launch-flow unit test checks exact token
movements; the network's separate protected harness validates actual pool seeding and swaps.

## Deployment parameters

Deploy the creation bytecode for **PebbleToken** directly with **no constructor arguments**
and **zero native ETH value**. No initialization transaction or external contract dependency
is required. The intended launch is Ethereum, chain ID 1, which supports the pinned Cancun
target. Direct deployment mints to the deploying account; deployment through the launch factory
mints to that factory, allowing its ordinary distribution and pool transfers without exemptions.
The Solidity contract identifier is `PebbleToken`; token metadata remains `Pebble Agent` / `PEBBLE`.

For the specified launch, the factory handles the 10% swarm distribution, 80% pool allocation,
and 10% requester remainder. These are launch responsibilities, not token constructor
allocations or token-controlled economics. Pool settings and the launch manifest are handled
by the network's later launch step. This project does not create a manifest or broadcast a transaction.

## After launch and operational responsibilities

There are no owner settings or maintenance calls. The deployer must confirm the chain, bytecode,
metadata, total supply, constructor mint recipient, and subsequent distribution, then publish
and verify source on the block explorer. Holders are responsible for custody and approval
management. Use bounded allowances for spenders; when changing an existing allowance, revoke
it first and wait for confirmation to reduce the standard ERC-20 approval race risk.

Tokens sent to a wrong address or a contract unable to return them cannot be recovered by an
administrator. The token cannot accept ordinary ETH transfers; forced ETH or other assets
sent to its address have no recovery function. Local Foundry tests and source review are not
an independent security audit. Independent review and production deployment verification are
the launch operator's responsibilities. Slither and Mythril were not run.
