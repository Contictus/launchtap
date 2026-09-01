# Contracts

Foundry project for the launchpad contracts. V1 public interfaces, errors, events, storage
layouts, and the fixed-supply launch token are covered by local and CI drift gates.

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

Run the complete local gate from Windows PowerShell 5.1 or PowerShell 7:

```powershell
./contracts/scripts/check.ps1 all
```

Individual commands, run from `contracts/`, are:

```bash
forge fmt --check
forge build
./scripts/check-goldens.ps1
forge test
forge lint --severity high med low info -D warnings
forge build --sizes
```

The compiler configuration in `foundry.toml` is authoritative for local and CI builds.
`scripts/check-dependencies.ps1` rejects a different Foundry binary, dependency commit, or CI
toolchain pin. `scripts/check-goldens.ps1` rejects event ABI, storage layout, or compiler
pipeline drift. After an intentional reviewed ABI or layout change, regenerate the artifacts
from `contracts/` with:

```powershell
./scripts/check-goldens.ps1 -Write
```

`abi/v1/ILaunchEvents.json` is the authoritative V1 event artifact consumed by the backend.
`storage-layout/v1/LaunchToken.json` captures the composed ERC-20 implementation layout.
`LaunchFactoryStorageBase.json` is explicitly pre-composition until the factory implementation
lands.
