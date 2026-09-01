# Contracts

Foundry scaffold for the launchpad contracts. Task 1 intentionally contains only a compile
probe; production interfaces and contracts begin in Task 2.

## Pinned toolchain

- Foundry `v1.8.1` (`982849d3140c01fd3b72905759581a132df7aa98`)
- Solidity `0.8.36`
- OpenZeppelin Contracts `v5.7.0`
- forge-std `v1.16.1`

Install the exact Foundry release from the official release page, then initialize the pinned
submodules from the repository root:

```bash
git submodule update --init --recursive
```

Run the complete local gate from PowerShell:

```powershell
./contracts/scripts/check.ps1 all
```

Individual commands, run from `contracts/`, are:

```bash
forge fmt --check
forge build
forge test
forge lint --severity high med low info -D warnings
forge build --sizes
```

The compiler configuration in `foundry.toml` is authoritative for local and CI builds.
`scripts/check-dependencies.ps1` rejects a different Foundry binary, dependency commit, or CI
toolchain pin.
