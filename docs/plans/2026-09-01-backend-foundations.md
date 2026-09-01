# Backend Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the substrate every later backend plan depends on — a tested pure-Go bonding-curve math library, a migrated Postgres schema with typed access and a Unit-of-Work, and config loading with a compiled-in chain registry.

**Architecture:** Modular monolith, one Go module at `backend/`. This plan delivers three shared packages (`internal/curve`, `internal/config`, `internal/store/postgres`) plus repo scaffolding. No process (`cmd/api`, `cmd/indexer`) is wired up yet; those come in Plans 2 and 3. `curve/` has zero dependencies and is verified byte-for-byte against a vector table (the Solidity contract, authored in a separate plan, will generate the full vector set later). `store/` uses pgx + sqlc + goose and is tested against a real Postgres via testcontainers.

**Tech Stack:** Go 1.23, `github.com/jackc/pgx/v5`, `sqlc` (v1.27+), `github.com/pressly/goose/v3`, `github.com/shopspring/decimal`, `github.com/ethereum/go-ethereum` (common value types only in this plan), `github.com/testcontainers/testcontainers-go`, `golangci-lint`.

**Spec:** `docs/specs/2026-09-01-backend-core-design.md`

## Global Constraints

- **Language/runtime:** Go 1.23. Single module `backend/` (path: `github.com/pons/launchpad/backend` — adjust the org segment once, everywhere, if it differs).
- **Zero-cost:** no paid services. Dev Postgres runs in Docker / testcontainers only.
- **Precision:** all curve arithmetic uses `*big.Int`. No `float64`, no `big.Float` anywhere a value must match on-chain state. `shopspring/decimal` is permitted **only** in API DTO code (not in this plan).
- **DIP line:** application/domain code must not import `pgx`, `sqlc`-generated packages, or `ethclient`. It **may** use go-ethereum value types (`common.Address`, `common.Hash`, `*big.Int`) as domain primitives.
- **Dependency rule (enforced by `depguard`):** `internal/curve` imports only stdlib + `math/big`. `internal/config` imports only stdlib + `go-ethereum/common`. `internal/store/postgres` may import `pgx` and sqlc output; nothing outside `store/` may.
- **Canonical vs derived:** canonical tables are the chain projection and are never recomputed from derived data. Derived tables are always rebuildable from canonical.
- **Idempotency:** every event-derived (canonical) table carries `block_number BIGINT`, `tx_hash BYTEA`, `log_index INT`, with a UNIQUE constraint on `(tx_hash, log_index)`.
- **Rounding convention for `curve/`:** every division that determines an amount *leaving the pool* rounds **up** (ceil), favouring the pool; fee splits round **down**. This is the documented default; the differential test against the contract is the final authority and Go yields if they differ.

---

## File Structure

Created by this plan:

```
.gitattributes                              LF enforcement for Go/SQL
backend/go.mod                              module definition
backend/go.sum
backend/.golangci.yml                       linter config incl. depguard rules
backend/Taskfile.yml                        dev commands (build, test, lint, migrate, sqlc)
backend/sqlc.yaml                           sqlc codegen config
backend/.env.example                        documented env template
backend/cmd/migrate/main.go                 goose migration runner
backend/internal/config/config.go           Config struct, Load(), env parsing
backend/internal/config/chains.go           ChainConfig + compiled-in registry
backend/internal/config/config_test.go
backend/internal/curve/curve.go             State, NewState, invariant helpers
backend/internal/curve/price.go             SpotPriceWad, TokensSold, IsGraduated
backend/internal/curve/quote.go             QuoteBuy, QuoteSell
backend/internal/curve/mathutil.go          ceilDiv, mulDiv helpers
backend/internal/curve/curve_test.go
backend/internal/curve/quote_test.go
backend/internal/curve/vectors_test.go      differential vector-table test
backend/internal/curve/testdata/curve_vectors.json
backend/internal/store/postgres/migrations/00001_sync_and_tokens.sql
backend/internal/store/postgres/migrations/00002_canonical_events.sql
backend/internal/store/postgres/migrations/00003_derived_and_views.sql
backend/internal/store/postgres/migrations/embed.go
backend/internal/store/postgres/db.go       pool ctor, DBTX type alias
backend/internal/store/postgres/queries/sync_state.sql
backend/internal/store/postgres/queries/tokens.sql
backend/internal/store/postgres/gen/            (sqlc output — generated, committed)
backend/internal/store/postgres/uow.go      Repositories struct, WithinTx
backend/internal/store/postgres/migrate_test.go
backend/internal/store/postgres/uow_test.go
backend/internal/store/postgres/testsupport.go  testcontainers Postgres helper
.github/workflows/backend.yml               lint + test CI job
```

---

## Task 1: Repo scaffold and Go module

**Files:**
- Create: `.gitattributes`
- Create: `backend/go.mod`
- Create: `backend/.golangci.yml`
- Create: `backend/Taskfile.yml`
- Create: `backend/.env.example`
- Create: `.github/workflows/backend.yml`
- Create: `backend/internal/curve/doc.go` (temporary package anchor so `go build ./...` has a package)

**Interfaces:**
- Consumes: nothing.
- Produces: a buildable module. Module path `github.com/pons/launchpad/backend`. Task runner commands: `task build`, `task test`, `task lint`, `task sqlc`, `task migrate`.

- [ ] **Step 1: Create `.gitattributes`**

```gitattributes
* text=auto eol=lf
*.go text eol=lf
*.sql text eol=lf
*.md text eol=lf
```

- [ ] **Step 2: Initialise the module**

Run from repo root:

```bash
mkdir -p backend/internal/curve
cd backend
go mod init github.com/pons/launchpad/backend
go mod edit -go=1.23
```

- [ ] **Step 3: Add the temporary package anchor**

Create `backend/internal/curve/doc.go`:

```go
// Package curve implements the off-chain mirror of the bonding-curve math.
// It has zero dependencies beyond the standard library and math/big.
package curve
```

- [ ] **Step 4: Create `backend/.golangci.yml`**

```yaml
run:
  timeout: 3m
linters:
  enable:
    - depguard
    - errcheck
    - gosimple
    - govet
    - ineffassign
    - staticcheck
    - unused
    - revive
linters-settings:
  depguard:
    rules:
      curve:
        files: ["**/internal/curve/**"]
        allow: ["$gostd", "math/big"]
      config:
        files: ["**/internal/config/**"]
        allow: ["$gostd", "github.com/ethereum/go-ethereum/common"]
      no-infra-in-domain:
        files: ["**/internal/**", "!**/internal/store/**", "!**/cmd/**"]
        deny:
          - pkg: "github.com/jackc/pgx"
            desc: "infra driver must not be imported by domain/application code"
          - pkg: "github.com/ethereum/go-ethereum/ethclient"
            desc: "RPC client must not be imported by domain/application code"
```

- [ ] **Step 5: Create `backend/Taskfile.yml`**

```yaml
version: "3"
tasks:
  build:
    cmds: ["go build ./..."]
  test:
    cmds: ["go test ./... -race -count=1"]
  lint:
    cmds: ["golangci-lint run"]
  sqlc:
    cmds: ["sqlc generate"]
  migrate:
    cmds: ["go run ./cmd/migrate up"]
```

- [ ] **Step 6: Create `backend/.env.example`**

```bash
# Active chain: 31337 (anvil) | 46630 (robinhood testnet) | 4663 (robinhood mainnet)
CHAIN_ID=31337
# JSON-RPC endpoint for the active chain
RPC_URL=http://127.0.0.1:8545
# Postgres DSN
DATABASE_URL=postgres://launchpad:launchpad@127.0.0.1:5432/launchpad?sslmode=disable
# Log level: debug | info | warn | error
LOG_LEVEL=info
```

- [ ] **Step 7: Create `.github/workflows/backend.yml`**

```yaml
name: backend
on:
  push: { paths: ["backend/**", ".github/workflows/backend.yml"] }
  pull_request: { paths: ["backend/**", ".github/workflows/backend.yml"] }
jobs:
  test:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: backend } }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version: "1.23" }
      - run: go build ./...
      - run: go test ./... -race -count=1
      - uses: golangci/golangci-lint-action@v6
        with: { working-directory: backend, version: v1.61 }
```

- [ ] **Step 8: Verify the module builds**

Run: `cd backend && go build ./...`
Expected: exit 0, no output.

- [ ] **Step 9: Commit**

```bash
git add .gitattributes backend/go.mod backend/.golangci.yml backend/Taskfile.yml backend/.env.example backend/internal/curve/doc.go .github/workflows/backend.yml
git commit -m "chore(backend): scaffold Go module, linter, task runner, CI"
```

---

## Task 2: Config package — Config struct and Load()

**Files:**
- Create: `backend/internal/config/config.go`
- Test: `backend/internal/config/config_test.go`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `type Config struct { ChainID uint64; RPCURL string; DatabaseURL string; LogLevel string; Chain ChainConfig }`
  - `func Load(getenv func(string) string) (Config, error)` — pure; caller passes `os.Getenv`. Returns an error if `CHAIN_ID`, `RPC_URL`, or `DATABASE_URL` is empty, if `CHAIN_ID` is not a uint64, or if `CHAIN_ID` is not in the registry (registry lookup added in Task 3; until then `Chain` is left zero and only the presence/parse checks are tested).

- [ ] **Step 1: Write the failing test**

Create `backend/internal/config/config_test.go`:

```go
package config

import "testing"

func env(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

func TestLoad_OK(t *testing.T) {
	c, err := Load(env(map[string]string{
		"CHAIN_ID":     "31337",
		"RPC_URL":      "http://localhost:8545",
		"DATABASE_URL": "postgres://x",
		"LOG_LEVEL":    "debug",
	}))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if c.ChainID != 31337 || c.RPCURL != "http://localhost:8545" || c.LogLevel != "debug" {
		t.Fatalf("bad config: %+v", c)
	}
}

func TestLoad_MissingRequired(t *testing.T) {
	_, err := Load(env(map[string]string{"CHAIN_ID": "31337"}))
	if err == nil {
		t.Fatal("expected error for missing RPC_URL/DATABASE_URL")
	}
}

func TestLoad_BadChainID(t *testing.T) {
	_, err := Load(env(map[string]string{
		"CHAIN_ID": "notanumber", "RPC_URL": "x", "DATABASE_URL": "y",
	}))
	if err == nil {
		t.Fatal("expected parse error for CHAIN_ID")
	}
}

func TestLoad_LogLevelDefault(t *testing.T) {
	c, _ := Load(env(map[string]string{
		"CHAIN_ID": "31337", "RPC_URL": "x", "DATABASE_URL": "y",
	}))
	if c.LogLevel != "info" {
		t.Fatalf("want default info, got %q", c.LogLevel)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/config/ -run TestLoad -v`
Expected: FAIL — `undefined: Load`.

- [ ] **Step 3: Write minimal implementation**

Create `backend/internal/config/config.go`:

```go
package config

import (
	"fmt"
	"strconv"
	"strings"
)

type Config struct {
	ChainID     uint64
	RPCURL      string
	DatabaseURL string
	LogLevel    string
	Chain       ChainConfig
}

func Load(getenv func(string) string) (Config, error) {
	var c Config

	rawChain := strings.TrimSpace(getenv("CHAIN_ID"))
	if rawChain == "" {
		return c, fmt.Errorf("config: CHAIN_ID is required")
	}
	id, err := strconv.ParseUint(rawChain, 10, 64)
	if err != nil {
		return c, fmt.Errorf("config: CHAIN_ID %q: %w", rawChain, err)
	}
	c.ChainID = id

	c.RPCURL = strings.TrimSpace(getenv("RPC_URL"))
	if c.RPCURL == "" {
		return c, fmt.Errorf("config: RPC_URL is required")
	}
	c.DatabaseURL = strings.TrimSpace(getenv("DATABASE_URL"))
	if c.DatabaseURL == "" {
		return c, fmt.Errorf("config: DATABASE_URL is required")
	}

	c.LogLevel = strings.TrimSpace(getenv("LOG_LEVEL"))
	if c.LogLevel == "" {
		c.LogLevel = "info"
	}
	return c, nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/config/ -run TestLoad -v`
Expected: PASS (all four).

- [ ] **Step 5: Commit**

```bash
git add backend/internal/config/
git commit -m "feat(config): Config struct and Load() with env validation"
```

---

## Task 3: Config package — chain registry

**Files:**
- Create: `backend/internal/config/chains.go`
- Modify: `backend/internal/config/config.go` (wire registry lookup into `Load`)
- Modify: `backend/internal/config/config_test.go` (add registry cases)

**Interfaces:**
- Consumes: `Config`, `Load` from Task 2.
- Produces:
  - `type ChainConfig struct { ChainID uint64; Name string; FactoryAddr common.Address; StartBlock uint64; Confirmations uint64; UniV2Factory common.Address; UniV2Router common.Address; WETH common.Address; ExplorerBase string }`
  - `func ChainByID(id uint64) (ChainConfig, bool)` — registry lookup.
  - `Load` now sets `c.Chain` from the registry and errors on unknown id.

- [ ] **Step 1: Write the failing test — add to `config_test.go`**

```go
func TestChainByID_Known(t *testing.T) {
	cc, ok := ChainByID(31337)
	if !ok || cc.Name != "anvil" {
		t.Fatalf("want anvil, got %+v ok=%v", cc, ok)
	}
}

func TestChainByID_Unknown(t *testing.T) {
	if _, ok := ChainByID(999999); ok {
		t.Fatal("want ok=false for unknown chain id")
	}
}

func TestLoad_UnknownChainErrors(t *testing.T) {
	_, err := Load(env(map[string]string{
		"CHAIN_ID": "999999", "RPC_URL": "x", "DATABASE_URL": "y",
	}))
	if err == nil {
		t.Fatal("expected error for unknown CHAIN_ID")
	}
}

func TestLoad_SetsChain(t *testing.T) {
	c, err := Load(env(map[string]string{
		"CHAIN_ID": "31337", "RPC_URL": "x", "DATABASE_URL": "y",
	}))
	if err != nil || c.Chain.ChainID != 31337 || c.Chain.Name != "anvil" {
		t.Fatalf("chain not wired: %+v err=%v", c.Chain, err)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/config/ -v`
Expected: FAIL — `undefined: ChainByID`.

- [ ] **Step 3: Write `backend/internal/config/chains.go`**

```go
package config

import "github.com/ethereum/go-ethereum/common"

type ChainConfig struct {
	ChainID       uint64
	Name          string
	FactoryAddr   common.Address
	StartBlock    uint64
	Confirmations uint64
	UniV2Factory  common.Address
	UniV2Router   common.Address
	WETH          common.Address
	ExplorerBase  string
}

// registry is compiled in. Secrets (RPC URLs) come from env, not here.
// FactoryAddr / StartBlock are filled once our factory is deployed per chain;
// zero values are acceptable until Plan 2 needs them.
var registry = map[uint64]ChainConfig{
	31337: {
		ChainID: 31337, Name: "anvil",
		Confirmations: 0,
	},
	46630: {
		ChainID: 46630, Name: "robinhood-testnet",
		Confirmations: 5,
		UniV2Factory:  common.HexToAddress("0x8bceaa40b9acdfaedf85adf4ff01f5ad6517937f"),
		UniV2Router:   common.HexToAddress("0x89e5db8b5aa49aa85ac63f691524311aeb649eba"),
		ExplorerBase:  "https://explorer.testnet.chain.robinhood.com",
	},
	4663: {
		ChainID: 4663, Name: "robinhood-mainnet",
		Confirmations: 5,
		UniV2Factory:  common.HexToAddress("0x8bceaa40b9acdfaedf85adf4ff01f5ad6517937f"),
		UniV2Router:   common.HexToAddress("0x89e5db8b5aa49aa85ac63f691524311aeb649eba"),
		ExplorerBase:  "https://robinhoodchain.blockscout.com",
	},
}

func ChainByID(id uint64) (ChainConfig, bool) {
	cc, ok := registry[id]
	return cc, ok
}
```

> Note: the Uniswap v2 addresses above are the deployment values recorded in the spec. The mainnet/testnet WETH address is still unverified in the spec (open question 13.1-adjacent); leave `WETH` zero until confirmed, and do not block on it in this plan.

- [ ] **Step 4: Wire the registry into `Load` — modify `config.go`**

Replace the `return c, nil` at the end of `Load` with:

```go
	cc, ok := ChainByID(c.ChainID)
	if !ok {
		return c, fmt.Errorf("config: no chain registered for CHAIN_ID %d", c.ChainID)
	}
	c.Chain = cc
	return c, nil
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd backend && go test ./internal/config/ -v`
Expected: PASS (all cases incl. the Task 2 ones).

- [ ] **Step 6: Run the linter to confirm depguard is happy**

Run: `cd backend && golangci-lint run ./internal/config/...`
Expected: exit 0 (config may import `go-ethereum/common`, nothing else).

- [ ] **Step 7: Commit**

```bash
git add backend/internal/config/
git commit -m "feat(config): compiled-in chain registry (anvil, robinhood testnet/mainnet)"
```

---

## Task 4: curve — math helpers and State

**Files:**
- Create: `backend/internal/curve/mathutil.go`
- Create: `backend/internal/curve/curve.go`
- Delete: `backend/internal/curve/doc.go` (its package doc moves into `curve.go`)
- Test: `backend/internal/curve/curve_test.go`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `func ceilDiv(a, b *big.Int) *big.Int` — `⌈a/b⌉` for non-negative `a`, positive `b`; panics on `b <= 0`.
  - `func mulDiv(a, b, denom *big.Int) *big.Int` — `⌊a*b/denom⌋`, no intermediate overflow (big.Int is arbitrary precision, so this is just `a*b/denom`); panics on `denom <= 0`.
  - `type State struct { X, Y, K *big.Int }` — X = ETH reserve (wei), Y = token reserve (base units), K = X·Y invariant fixed at launch.
  - `func NewState(x0, y0 *big.Int) State` — sets `K = x0·y0`; clones inputs (no aliasing).
  - `func (s State) Clone() State`
  - `func (s State) Invariant() *big.Int` — returns `X·Y` (for tests/asserts; may differ from K by rounding after trades).

- [ ] **Step 1: Write the failing test**

Create `backend/internal/curve/curve_test.go`:

```go
package curve

import (
	"math/big"
	"testing"
)

func bi(s string) *big.Int { n, _ := new(big.Int).SetString(s, 10); return n }

func TestCeilDiv(t *testing.T) {
	cases := []struct{ a, b, want string }{
		{"10", "3", "4"},
		{"9", "3", "3"},
		{"0", "7", "0"},
		{"1", "1000000", "1"},
	}
	for _, c := range cases {
		got := ceilDiv(bi(c.a), bi(c.b))
		if got.Cmp(bi(c.want)) != 0 {
			t.Fatalf("ceilDiv(%s,%s)=%s want %s", c.a, c.b, got, c.want)
		}
	}
}

func TestMulDiv(t *testing.T) {
	got := mulDiv(bi("1000000000000000000"), bi("100"), bi("10000"))
	if got.Cmp(bi("10000000000000000")) != 0 {
		t.Fatalf("mulDiv = %s", got)
	}
}

func TestNewStateSetsK(t *testing.T) {
	s := NewState(bi("1400000000000000000"), bi("1066666667000000000000000000"))
	want := new(big.Int).Mul(bi("1400000000000000000"), bi("1066666667000000000000000000"))
	if s.K.Cmp(want) != 0 {
		t.Fatalf("K = %s want %s", s.K, want)
	}
}

func TestNewStateNoAliasing(t *testing.T) {
	x0 := bi("100")
	s := NewState(x0, bi("200"))
	x0.SetInt64(999)
	if s.X.Cmp(bi("100")) != 0 {
		t.Fatalf("State.X aliases caller input: %s", s.X)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/curve/ -v`
Expected: FAIL — `undefined: ceilDiv` etc.

- [ ] **Step 3: Write `backend/internal/curve/mathutil.go`**

```go
package curve

import "math/big"

func ceilDiv(a, b *big.Int) *big.Int {
	if b.Sign() <= 0 {
		panic("curve: ceilDiv by non-positive divisor")
	}
	q, r := new(big.Int).QuoRem(a, b, new(big.Int))
	if r.Sign() > 0 {
		q.Add(q, big.NewInt(1))
	}
	return q
}

func mulDiv(a, b, denom *big.Int) *big.Int {
	if denom.Sign() <= 0 {
		panic("curve: mulDiv by non-positive denominator")
	}
	return new(big.Int).Quo(new(big.Int).Mul(a, b), denom)
}
```

- [ ] **Step 4: Write `backend/internal/curve/curve.go`**

```go
// Package curve implements the off-chain mirror of the bonding-curve math.
// It has zero dependencies beyond the standard library and math/big.
//
// Rounding convention: divisions that determine an amount leaving the pool
// round up (ceil); fee splits round down. The differential test against the
// Solidity contract is the final authority.
package curve

import "math/big"

type State struct {
	X *big.Int // ETH reserve (wei)
	Y *big.Int // token reserve (base units)
	K *big.Int // X*Y invariant, fixed at launch
}

func NewState(x0, y0 *big.Int) State {
	x := new(big.Int).Set(x0)
	y := new(big.Int).Set(y0)
	return State{X: x, Y: y, K: new(big.Int).Mul(x, y)}
}

func (s State) Clone() State {
	return State{
		X: new(big.Int).Set(s.X),
		Y: new(big.Int).Set(s.Y),
		K: new(big.Int).Set(s.K),
	}
}

func (s State) Invariant() *big.Int { return new(big.Int).Mul(s.X, s.Y) }
```

- [ ] **Step 5: Delete the anchor file**

```bash
rm backend/internal/curve/doc.go
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd backend && go test ./internal/curve/ -v`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A backend/internal/curve/
git commit -m "feat(curve): State type and big.Int math helpers"
```

---

## Task 5: curve — SpotPriceWad, TokensSold, IsGraduated

**Files:**
- Create: `backend/internal/curve/price.go`
- Test: `backend/internal/curve/price_test.go`

**Interfaces:**
- Consumes: `State` (Task 4).
- Produces:
  - `func SpotPriceWad(s State) *big.Int` — `⌊X·1e18/Y⌋`, ETH-per-token in wad (1e18) fixed point.
  - `func TokensSold(s State, y0 *big.Int) *big.Int` — `y0 − Y`.
  - `func IsGraduated(s State, y0, curveTokens *big.Int) bool` — `TokensSold(s,y0) >= curveTokens`.

- [ ] **Step 1: Write the failing test**

Create `backend/internal/curve/price_test.go`:

```go
package curve

import (
	"math/big"
	"testing"
)

var wad = bi("1000000000000000000")

func TestSpotPriceWad_AtLaunch(t *testing.T) {
	// x0 = 1.4 ETH, y0 = 1,066,666,667 tokens (18 dp)
	x0 := bi("1400000000000000000")
	y0 := bi("1066666667000000000000000000")
	s := NewState(x0, y0)
	got := SpotPriceWad(s)
	// 1.4e18 * 1e18 / 1.066666667e27 = 1_312_500_000 (≈1.3125e-9 ETH, in wad)
	want := bi("1312499999")
	if got.Cmp(want) != 0 {
		t.Fatalf("SpotPriceWad = %s want %s", got, want)
	}
}

func TestTokensSold(t *testing.T) {
	y0 := bi("1000")
	s := State{X: bi("1"), Y: bi("600"), K: bi("600")}
	if TokensSold(s, y0).Cmp(bi("400")) != 0 {
		t.Fatalf("TokensSold = %s", TokensSold(s, y0))
	}
}

func TestIsGraduated(t *testing.T) {
	y0 := bi("1000")
	curveTokens := bi("800")
	if IsGraduated(State{Y: bi("300")}, y0, curveTokens) != false {
		t.Fatal("300 sold < 800 -> not graduated")
	}
	if IsGraduated(State{Y: bi("200")}, y0, curveTokens) != true {
		t.Fatal("800 sold >= 800 -> graduated")
	}
	if IsGraduated(State{Y: bi("150")}, y0, curveTokens) != true {
		t.Fatal("850 sold >= 800 -> graduated")
	}
}
```

> The `want` value `1312499999` in the first test is `⌊1.4e18 · 1e18 / 1.066666667e27⌋`. Compute it exactly when writing the test; if your arithmetic yields a different floor, use that — the assertion must match the documented round-down rule, not a guess.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/curve/ -run 'SpotPrice|TokensSold|IsGraduated' -v`
Expected: FAIL — `undefined: SpotPriceWad`.

- [ ] **Step 3: Write `backend/internal/curve/price.go`**

```go
package curve

import "math/big"

var wad1e18 = new(big.Int).Exp(big.NewInt(10), big.NewInt(18), nil)

func SpotPriceWad(s State) *big.Int {
	return mulDiv(s.X, wad1e18, s.Y)
}

func TokensSold(s State, y0 *big.Int) *big.Int {
	return new(big.Int).Sub(y0, s.Y)
}

func IsGraduated(s State, y0, curveTokens *big.Int) bool {
	return TokensSold(s, y0).Cmp(curveTokens) >= 0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && go test ./internal/curve/ -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/curve/price.go backend/internal/curve/price_test.go
git commit -m "feat(curve): spot price, tokens sold, graduation check"
```

---

## Task 6: curve — QuoteBuy

**Files:**
- Create: `backend/internal/curve/quote.go`
- Test: `backend/internal/curve/quote_test.go`

**Interfaces:**
- Consumes: `State`, `ceilDiv`, `mulDiv` (Tasks 4-5).
- Produces:
  - `type Quote struct { AmountOut *big.Int; ProtocolFee *big.Int; CreatorFee *big.Int; Next State }`
  - `func QuoteBuy(s State, ethGross *big.Int, feeBps, protoShareBps uint16) Quote`
    - `totalFee = ⌊ethGross·feeBps/10000⌋`; `protocolFee = ⌊totalFee·protoShareBps/10000⌋`; `creatorFee = totalFee − protocolFee`.
    - `dxEff = ethGross − totalFee`; `newX = X + dxEff`; `newY = ⌈K/newX⌉`; `AmountOut = Y − newY`.
    - `Next = State{X: newX, Y: newY, K: K}`.
    - Panics if `ethGross <= 0`.

- [ ] **Step 1: Write the failing test**

Create `backend/internal/curve/quote_test.go`:

```go
package curve

import (
	"math/big"
	"testing"
)

// launch state from the spec: x0 = 1.4 ETH, y0 = 1,066,666,667e18
func launchState() State {
	return NewState(bi("1400000000000000000"), bi("1066666667000000000000000000"))
}

func TestQuoteBuy_FeeSplit(t *testing.T) {
	s := launchState()
	// buy with 1 ETH, 1% fee, 50/50 split
	q := QuoteBuy(s, bi("1000000000000000000"), 100, 5000)
	if q.ProtocolFee.Cmp(bi("5000000000000000")) != 0 { // 0.005 ETH
		t.Fatalf("protocolFee = %s want 5e15", q.ProtocolFee)
	}
	if q.CreatorFee.Cmp(bi("5000000000000000")) != 0 {
		t.Fatalf("creatorFee = %s want 5e15", q.CreatorFee)
	}
}

func TestQuoteBuy_MovesReservesAlongCurve(t *testing.T) {
	s := launchState()
	q := QuoteBuy(s, bi("1000000000000000000"), 100, 5000)
	// dxEff = 1 ETH - 0.01 ETH = 0.99 ETH
	wantNewX := new(big.Int).Add(s.X, bi("990000000000000000"))
	if q.Next.X.Cmp(wantNewX) != 0 {
		t.Fatalf("Next.X = %s want %s", q.Next.X, wantNewX)
	}
	// newY = ceil(K / newX); AmountOut = Y - newY
	wantNewY := ceilDiv(s.K, wantNewX)
	if q.Next.Y.Cmp(wantNewY) != 0 {
		t.Fatalf("Next.Y = %s want %s", q.Next.Y, wantNewY)
	}
	wantOut := new(big.Int).Sub(s.Y, wantNewY)
	if q.AmountOut.Cmp(wantOut) != 0 {
		t.Fatalf("AmountOut = %s want %s", q.AmountOut, wantOut)
	}
	if q.AmountOut.Sign() <= 0 {
		t.Fatal("AmountOut must be positive")
	}
}

func TestQuoteBuy_PriceIncreasesAfterBuy(t *testing.T) {
	s := launchState()
	before := SpotPriceWad(s)
	q := QuoteBuy(s, bi("1000000000000000000"), 100, 5000)
	after := SpotPriceWad(q.Next)
	if after.Cmp(before) <= 0 {
		t.Fatalf("price did not increase: before=%s after=%s", before, after)
	}
}

func TestQuoteBuy_PanicsOnNonPositive(t *testing.T) {
	defer func() {
		if recover() == nil {
			t.Fatal("expected panic")
		}
	}()
	QuoteBuy(launchState(), big.NewInt(0), 100, 5000)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/curve/ -run QuoteBuy -v`
Expected: FAIL — `undefined: QuoteBuy`.

- [ ] **Step 3: Write `backend/internal/curve/quote.go`**

```go
package curve

import "math/big"

type Quote struct {
	AmountOut   *big.Int
	ProtocolFee *big.Int
	CreatorFee  *big.Int
	Next        State
}

var bpsDenom = big.NewInt(10000)

func splitFee(gross *big.Int, feeBps, protoShareBps uint16) (total, proto, creator *big.Int) {
	total = mulDiv(gross, big.NewInt(int64(feeBps)), bpsDenom)
	proto = mulDiv(total, big.NewInt(int64(protoShareBps)), bpsDenom)
	creator = new(big.Int).Sub(total, proto)
	return
}

func QuoteBuy(s State, ethGross *big.Int, feeBps, protoShareBps uint16) Quote {
	if ethGross.Sign() <= 0 {
		panic("curve: QuoteBuy ethGross must be positive")
	}
	totalFee, protoFee, creatorFee := splitFee(ethGross, feeBps, protoShareBps)

	dxEff := new(big.Int).Sub(ethGross, totalFee)
	newX := new(big.Int).Add(s.X, dxEff)
	newY := ceilDiv(s.K, newX)
	out := new(big.Int).Sub(s.Y, newY)

	return Quote{
		AmountOut:   out,
		ProtocolFee: protoFee,
		CreatorFee:  creatorFee,
		Next:        State{X: newX, Y: newY, K: new(big.Int).Set(s.K)},
	}
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && go test ./internal/curve/ -run QuoteBuy -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/curve/quote.go backend/internal/curve/quote_test.go
git commit -m "feat(curve): QuoteBuy with fee split and pool-favouring rounding"
```

---

## Task 7: curve — QuoteSell

**Files:**
- Modify: `backend/internal/curve/quote.go`
- Modify: `backend/internal/curve/quote_test.go`

**Interfaces:**
- Consumes: everything from Task 6.
- Produces:
  - `func QuoteSell(s State, tokensIn *big.Int, feeBps, protoShareBps uint16) Quote`
    - `newY = Y + tokensIn`; `newX = ⌈K/newY⌉`; `ethGross = X − newX`.
    - fees are taken from `ethGross`: `totalFee = ⌊ethGross·feeBps/10000⌋`; `protocolFee = ⌊totalFee·protoShareBps/10000⌋`; `creatorFee = totalFee − protocolFee`.
    - `AmountOut = ethGross − totalFee` (ETH to the seller).
    - `Next = State{X: newX, Y: newY, K: K}`.
    - Panics if `tokensIn <= 0` or if `tokensIn >= Y` (cannot drain the reserve).

- [ ] **Step 1: Write the failing test — add to `quote_test.go`**

```go
func TestQuoteSell_RoundTripApprox(t *testing.T) {
	s := launchState()
	buy := QuoteBuy(s, bi("1000000000000000000"), 100, 5000)
	// sell the tokens we just bought, back into the post-buy state
	sell := QuoteSell(buy.Next, buy.AmountOut, 100, 5000)
	// seller gets less than they paid (fees on both legs + rounding)
	if sell.AmountOut.Cmp(bi("1000000000000000000")) >= 0 {
		t.Fatalf("round trip should lose value, got %s", sell.AmountOut)
	}
	// state returns close to launch X (within fees taken); Y within 1 unit
	diffY := new(big.Int).Abs(new(big.Int).Sub(sell.Next.Y, s.Y))
	if diffY.Cmp(bi("2")) > 0 {
		t.Fatalf("Y did not return near launch: diff=%s", diffY)
	}
}

func TestQuoteSell_FeesFromProceeds(t *testing.T) {
	s := launchState()
	buy := QuoteBuy(s, bi("2000000000000000000"), 100, 5000)
	sell := QuoteSell(buy.Next, buy.AmountOut, 100, 5000)
	gross := new(big.Int).Add(sell.AmountOut, new(big.Int).Add(sell.ProtocolFee, sell.CreatorFee))
	// gross = X_before - newX
	wantGross := new(big.Int).Sub(buy.Next.X, sell.Next.X)
	if gross.Cmp(wantGross) != 0 {
		t.Fatalf("gross mismatch: %s vs %s", gross, wantGross)
	}
}

func TestQuoteSell_PanicsOnDrain(t *testing.T) {
	defer func() {
		if recover() == nil {
			t.Fatal("expected panic")
		}
	}()
	s := launchState()
	QuoteSell(s, new(big.Int).Set(s.Y), 100, 5000)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/curve/ -run QuoteSell -v`
Expected: FAIL — `undefined: QuoteSell`.

- [ ] **Step 3: Add `QuoteSell` to `quote.go`**

```go
func QuoteSell(s State, tokensIn *big.Int, feeBps, protoShareBps uint16) Quote {
	if tokensIn.Sign() <= 0 {
		panic("curve: QuoteSell tokensIn must be positive")
	}
	if tokensIn.Cmp(s.Y) >= 0 {
		panic("curve: QuoteSell cannot drain token reserve")
	}
	newY := new(big.Int).Add(s.Y, tokensIn)
	newX := ceilDiv(s.K, newY)
	ethGross := new(big.Int).Sub(s.X, newX)

	totalFee, protoFee, creatorFee := splitFee(ethGross, feeBps, protoShareBps)
	out := new(big.Int).Sub(ethGross, totalFee)

	return Quote{
		AmountOut:   out,
		ProtocolFee: protoFee,
		CreatorFee:  creatorFee,
		Next:        State{X: newX, Y: newY, K: new(big.Int).Set(s.K)},
	}
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && go test ./internal/curve/ -v`
Expected: PASS (all curve tests).

- [ ] **Step 5: Commit**

```bash
git add backend/internal/curve/quote.go backend/internal/curve/quote_test.go
git commit -m "feat(curve): QuoteSell with proceeds-side fees"
```

---

## Task 8: curve — differential vector-table test

**Files:**
- Create: `backend/internal/curve/testdata/curve_vectors.json`
- Create: `backend/internal/curve/vectors_test.go`

**Interfaces:**
- Consumes: `QuoteBuy`, `QuoteSell`, `SpotPriceWad` (Tasks 5-7).
- Produces: a table-driven test that reads `testdata/curve_vectors.json` and asserts byte-identical `*big.Int` outputs. The JSON schema below is the contract that the Solidity plan's vector generator must emit.

- [ ] **Step 1: Define the vector file — create `testdata/curve_vectors.json`**

Seed it with hand-computed vectors now (compute each field exactly with the documented rounding; do not approximate). The generator in the contracts plan will replace/extend this file.

```json
{
  "schema": 1,
  "vectors": [
    {
      "name": "buy 1 ETH at launch",
      "op": "buy",
      "state": { "x": "1400000000000000000", "y": "1066666667000000000000000000" },
      "amountIn": "1000000000000000000",
      "feeBps": 100,
      "protoShareBps": 5000,
      "expect": {
        "amountOut": "FILL_EXACT",
        "protocolFee": "5000000000000000",
        "creatorFee": "5000000000000000",
        "nextX": "2390000000000000000",
        "nextY": "FILL_EXACT"
      }
    },
    {
      "name": "sell back the bought tokens",
      "op": "sell",
      "state": { "x": "2390000000000000000", "y": "FILL_EXACT" },
      "amountIn": "FILL_EXACT",
      "feeBps": 100,
      "protoShareBps": 5000,
      "expect": {
        "amountOut": "FILL_EXACT",
        "protocolFee": "FILL_EXACT",
        "creatorFee": "FILL_EXACT",
        "nextX": "FILL_EXACT",
        "nextY": "1066666667000000000000000000"
      }
    }
  ]
}
```

Replace every `FILL_EXACT` with the exact decimal string your Task 6/7 implementation produces (run a scratch `go test` that prints them, then paste). The point of the file is to freeze those values so a contract mismatch is caught later.

- [ ] **Step 2: Write the test — create `vectors_test.go`**

```go
package curve

import (
	"encoding/json"
	"math/big"
	"os"
	"testing"
)

type vecFile struct {
	Schema  int `json:"schema"`
	Vectors []struct {
		Name          string `json:"name"`
		Op            string `json:"op"`
		State         struct{ X, Y string } `json:"state"`
		AmountIn      string `json:"amountIn"`
		FeeBps        uint16 `json:"feeBps"`
		ProtoShareBps uint16 `json:"protoShareBps"`
		Expect        struct {
			AmountOut, ProtocolFee, CreatorFee, NextX, NextY string
		} `json:"expect"`
	} `json:"vectors"`
}

func TestCurveVectors(t *testing.T) {
	raw, err := os.ReadFile("testdata/curve_vectors.json")
	if err != nil {
		t.Fatalf("read vectors: %v", err)
	}
	var f vecFile
	if err := json.Unmarshal(raw, &f); err != nil {
		t.Fatalf("parse vectors: %v", err)
	}
	if f.Schema != 1 {
		t.Fatalf("unsupported vector schema %d", f.Schema)
	}
	eq := func(t *testing.T, label, got, want string) {
		t.Helper()
		if want == "FILL_EXACT" {
			t.Fatalf("%s: vector file still contains FILL_EXACT", label)
		}
		if got != want {
			t.Fatalf("%s: got %s want %s", label, got, want)
		}
	}
	for _, v := range f.Vectors {
		t.Run(v.Name, func(t *testing.T) {
			s := NewState(bi(v.State.X), bi(v.State.Y))
			var q Quote
			switch v.Op {
			case "buy":
				q = QuoteBuy(s, bi(v.AmountIn), v.FeeBps, v.ProtoShareBps)
			case "sell":
				q = QuoteSell(s, bi(v.AmountIn), v.FeeBps, v.ProtoShareBps)
			default:
				t.Fatalf("unknown op %q", v.Op)
			}
			eq(t, "amountOut", q.AmountOut.String(), v.Expect.AmountOut)
			eq(t, "protocolFee", q.ProtocolFee.String(), v.Expect.ProtocolFee)
			eq(t, "creatorFee", q.CreatorFee.String(), v.Expect.CreatorFee)
			eq(t, "nextX", q.Next.X.String(), v.Expect.NextX)
			eq(t, "nextY", q.Next.Y.String(), v.Expect.NextY)
		})
	}
}
```

- [ ] **Step 3: Fill the vectors and run**

Run: `cd backend && go test ./internal/curve/ -run TestCurveVectors -v`
Expected: initially FAIL with "still contains FILL_EXACT". Fill every value from your implementation's actual output, re-run, expect PASS.

- [ ] **Step 4: Add a fuzz test for monotonicity — append to `vectors_test.go`**

```go
func FuzzQuoteBuyMonotonic(f *testing.F) {
	f.Add(uint64(1_000_000_000_000_000_000))
	f.Fuzz(func(t *testing.T, ethIn uint64) {
		if ethIn == 0 {
			t.Skip()
		}
		s := NewState(bi("1400000000000000000"), bi("1066666667000000000000000000"))
		before := SpotPriceWad(s)
		q := QuoteBuy(s, new(big.Int).SetUint64(ethIn), 100, 5000)
		if q.AmountOut.Sign() < 0 {
			t.Fatalf("negative amountOut for ethIn=%d", ethIn)
		}
		if SpotPriceWad(q.Next).Cmp(before) < 0 {
			t.Fatalf("price decreased after buy, ethIn=%d", ethIn)
		}
	})
}
```

- [ ] **Step 5: Run the fuzz test briefly**

Run: `cd backend && go test ./internal/curve/ -run x -fuzz FuzzQuoteBuyMonotonic -fuzztime 20s`
Expected: `PASS`, no new corpus failures.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/curve/testdata backend/internal/curve/vectors_test.go
git commit -m "test(curve): differential vector table + monotonicity fuzz"
```

---

## Task 9: store — migration tooling and canonical schema (part 1)

**Files:**
- Create: `backend/internal/store/postgres/migrations/00001_sync_and_tokens.sql`
- Create: `backend/internal/store/postgres/migrations/embed.go`
- Create: `backend/cmd/migrate/main.go`
- Create: `backend/internal/store/postgres/testsupport.go`
- Test: `backend/internal/store/postgres/migrate_test.go`

**Interfaces:**
- Consumes: `config` (Task 3) for `DATABASE_URL` (via env in `cmd/migrate`).
- Produces:
  - `migrations.FS` — an `embed.FS` with all goose SQL files.
  - `func RunMigrations(ctx context.Context, dsn string) error` — applies all up migrations (used by `cmd/migrate` and tests).
  - `func StartTestPostgres(t *testing.T) string` — spins a throwaway Postgres via testcontainers, runs migrations, returns the DSN. Skips the test if Docker is unavailable.
  - Tables after 00001: `goose_db_version`, `sync_state`, `tokens`.

- [ ] **Step 1: Add dependencies**

```bash
cd backend
go get github.com/jackc/pgx/v5@latest
go get github.com/pressly/goose/v3@latest
go get github.com/testcontainers/testcontainers-go@latest
go get github.com/testcontainers/testcontainers-go/modules/postgres@latest
```

- [ ] **Step 2: Write migration `00001_sync_and_tokens.sql`**

```sql
-- +goose Up
CREATE TABLE sync_state (
    id               SMALLINT PRIMARY KEY DEFAULT 1,
    chain_id         BIGINT      NOT NULL,
    last_block       BIGINT      NOT NULL,
    last_block_hash  BYTEA       NOT NULL,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT sync_state_singleton CHECK (id = 1)
);

CREATE TABLE tokens (
    address             BYTEA PRIMARY KEY,
    curve_address       BYTEA       NOT NULL,
    creator             BYTEA       NOT NULL,
    name                TEXT        NOT NULL,
    symbol              TEXT        NOT NULL,
    total_supply        NUMERIC(78,0) NOT NULL,
    x0                  NUMERIC(78,0) NOT NULL,
    y0                  NUMERIC(78,0) NOT NULL,
    k                   NUMERIC(156,0) NOT NULL,
    curve_tokens        NUMERIC(78,0) NOT NULL,
    lp_tokens           NUMERIC(78,0) NOT NULL,
    graduation_eth      NUMERIC(78,0) NOT NULL,
    trade_fee_bps       INT         NOT NULL,
    protocol_share_bps  INT         NOT NULL,
    phase               TEXT        NOT NULL DEFAULT 'curve'
                          CHECK (phase IN ('curve','graduated')),
    lp_pair             BYTEA,
    token_is_token0     BOOLEAN,
    launched_at         TIMESTAMPTZ NOT NULL,
    launch_block        BIGINT      NOT NULL,
    launch_tx           BYTEA       NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX tokens_phase_idx        ON tokens (phase);
CREATE INDEX tokens_creator_idx      ON tokens (creator);
CREATE INDEX tokens_launched_at_idx  ON tokens (launched_at DESC);
CREATE INDEX tokens_name_symbol_fts  ON tokens
    USING GIN (to_tsvector('simple', name || ' ' || symbol));

-- +goose Down
DROP TABLE tokens;
DROP TABLE sync_state;
```

- [ ] **Step 3: Write `migrations/embed.go`**

```go
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS
```

- [ ] **Step 4: Write `db.go` with `RunMigrations` — create `backend/internal/store/postgres/db.go`**

```go
package postgres

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"

	"github.com/pons/launchpad/backend/internal/store/postgres/migrations"
)

// DBTX is satisfied by both *pgxpool.Pool and pgx.Tx; sqlc-generated code targets it.
// (Full definition lands in Task 11 alongside sqlc output.)

func NewPool(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
	return pgxpool.New(ctx, dsn)
}

func RunMigrations(ctx context.Context, dsn string) error {
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		return fmt.Errorf("open: %w", err)
	}
	defer db.Close()

	goose.SetBaseFS(migrations.FS)
	if err := goose.SetDialect("postgres"); err != nil {
		return err
	}
	if err := goose.UpContext(ctx, db, "."); err != nil {
		return fmt.Errorf("goose up: %w", err)
	}
	return nil
}
```

- [ ] **Step 5: Write `cmd/migrate/main.go`**

```go
package main

import (
	"context"
	"log"
	"os"

	"github.com/pons/launchpad/backend/internal/store/postgres"
)

func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("DATABASE_URL is required")
	}
	cmd := "up"
	if len(os.Args) > 1 {
		cmd = os.Args[1]
	}
	if cmd != "up" {
		log.Fatalf("only 'up' is supported, got %q", cmd)
	}
	if err := postgres.RunMigrations(context.Background(), dsn); err != nil {
		log.Fatalf("migrate: %v", err)
	}
	log.Println("migrations applied")
}
```

- [ ] **Step 6: Write `testsupport.go`**

```go
package postgres

import (
	"context"
	"testing"
	"time"

	"github.com/testcontainers/testcontainers-go"
	tcpg "github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"
)

func StartTestPostgres(t *testing.T) string {
	t.Helper()
	ctx := context.Background()
	ctr, err := tcpg.Run(ctx, "postgres:16-alpine",
		tcpg.WithDatabase("launchpad"),
		tcpg.WithUsername("launchpad"),
		tcpg.WithPassword("launchpad"),
		testcontainers.WithWaitStrategy(
			wait.ForLog("database system is ready to accept connections").
				WithOccurrence(2).WithStartupTimeout(60*time.Second)),
	)
	if err != nil {
		t.Skipf("cannot start postgres container (docker unavailable?): %v", err)
	}
	t.Cleanup(func() { _ = ctr.Terminate(ctx) })

	dsn, err := ctr.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatalf("connection string: %v", err)
	}
	if err := RunMigrations(ctx, dsn); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return dsn
}
```

- [ ] **Step 7: Write the failing test — `migrate_test.go`**

```go
package postgres

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5"
)

func TestMigrations_CreateCoreTables(t *testing.T) {
	dsn := StartTestPostgres(t)
	conn, err := pgx.Connect(context.Background(), dsn)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	defer conn.Close(context.Background())

	for _, tbl := range []string{"sync_state", "tokens"} {
		var exists bool
		err := conn.QueryRow(context.Background(),
			`SELECT EXISTS (SELECT 1 FROM information_schema.tables
			  WHERE table_schema='public' AND table_name=$1)`, tbl).Scan(&exists)
		if err != nil || !exists {
			t.Fatalf("table %q missing (err=%v)", tbl, err)
		}
	}
}

func TestSyncState_Singleton(t *testing.T) {
	dsn := StartTestPostgres(t)
	conn, _ := pgx.Connect(context.Background(), dsn)
	defer conn.Close(context.Background())

	_, err := conn.Exec(context.Background(),
		`INSERT INTO sync_state (id, chain_id, last_block, last_block_hash)
		 VALUES (2, 1, 0, '\x00')`)
	if err == nil {
		t.Fatal("expected CHECK violation for id <> 1")
	}
}
```

- [ ] **Step 8: Run tests**

Run: `cd backend && go test ./internal/store/postgres/ -run 'Migrations|SyncState' -v`
Expected: PASS (or SKIP if Docker is unavailable locally — CI has Docker).

- [ ] **Step 9: Commit**

```bash
git add backend/internal/store backend/cmd/migrate backend/go.mod backend/go.sum
git commit -m "feat(store): goose migration tooling + sync_state/tokens schema"
```

---

## Task 10: store — canonical event schema (part 2)

**Files:**
- Create: `backend/internal/store/postgres/migrations/00002_canonical_events.sql`
- Modify: `backend/internal/store/postgres/migrate_test.go`

**Interfaces:**
- Consumes: 00001.
- Produces tables: `trades`, `graduations`, `creator_fee_claims`, `transfers`, `pool_swaps`. Every one has `block_number BIGINT`, `block_time TIMESTAMPTZ`, `tx_hash BYTEA`, `log_index INT`, and `UNIQUE (tx_hash, log_index)`.

- [ ] **Step 1: Write migration `00002_canonical_events.sql`**

```sql
-- +goose Up
CREATE TABLE trades (
    id                 BIGGENERATED, -- placeholder line, replaced below
    token_address      BYTEA        NOT NULL REFERENCES tokens(address),
    trader             BYTEA        NOT NULL,
    is_buy             BOOLEAN      NOT NULL,
    eth_amount         NUMERIC(78,0) NOT NULL,
    token_amount       NUMERIC(78,0) NOT NULL,
    protocol_fee       NUMERIC(78,0) NOT NULL,
    creator_fee        NUMERIC(78,0) NOT NULL,
    new_eth_reserve    NUMERIC(78,0) NOT NULL,
    new_token_reserve  NUMERIC(78,0) NOT NULL,
    price_wad          NUMERIC(78,0) NOT NULL,
    block_number       BIGINT       NOT NULL,
    block_time         TIMESTAMPTZ  NOT NULL,
    tx_hash            BYTEA        NOT NULL,
    log_index          INT          NOT NULL,
    UNIQUE (tx_hash, log_index)
);
```

> The `id BIGGENERATED` line above is intentionally wrong so you notice this note: use
> `id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY` for `trades`, `creator_fee_claims`,
> `transfers`, and `pool_swaps`. `graduations` uses `token_address` as its PK (one per token).
> Write the corrected file in full:

```sql
-- +goose Up
CREATE TABLE trades (
    id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    token_address      BYTEA        NOT NULL REFERENCES tokens(address),
    trader             BYTEA        NOT NULL,
    is_buy             BOOLEAN      NOT NULL,
    eth_amount         NUMERIC(78,0) NOT NULL,
    token_amount       NUMERIC(78,0) NOT NULL,
    protocol_fee       NUMERIC(78,0) NOT NULL,
    creator_fee        NUMERIC(78,0) NOT NULL,
    new_eth_reserve    NUMERIC(78,0) NOT NULL,
    new_token_reserve  NUMERIC(78,0) NOT NULL,
    price_wad          NUMERIC(78,0) NOT NULL,
    block_number       BIGINT       NOT NULL,
    block_time         TIMESTAMPTZ  NOT NULL,
    tx_hash            BYTEA        NOT NULL,
    log_index          INT          NOT NULL,
    UNIQUE (tx_hash, log_index)
);
CREATE INDEX trades_token_block_idx ON trades (token_address, block_number, log_index);
CREATE INDEX trades_token_time_idx  ON trades (token_address, block_time DESC);

CREATE TABLE graduations (
    token_address    BYTEA PRIMARY KEY REFERENCES tokens(address),
    eth_to_pool      NUMERIC(78,0) NOT NULL,
    tokens_to_pool   NUMERIC(78,0) NOT NULL,
    lp_pair          BYTEA        NOT NULL,
    graduation_fee   NUMERIC(78,0) NOT NULL,
    block_number     BIGINT       NOT NULL,
    block_time       TIMESTAMPTZ  NOT NULL,
    tx_hash          BYTEA        NOT NULL,
    log_index        INT          NOT NULL,
    UNIQUE (tx_hash, log_index)
);

CREATE TABLE creator_fee_claims (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    token_address  BYTEA        NOT NULL REFERENCES tokens(address),
    creator        BYTEA        NOT NULL,
    amount         NUMERIC(78,0) NOT NULL,
    block_number   BIGINT       NOT NULL,
    block_time     TIMESTAMPTZ  NOT NULL,
    tx_hash        BYTEA        NOT NULL,
    log_index      INT          NOT NULL,
    UNIQUE (tx_hash, log_index)
);

CREATE TABLE transfers (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    token_address  BYTEA        NOT NULL REFERENCES tokens(address),
    from_addr      BYTEA        NOT NULL,
    to_addr        BYTEA        NOT NULL,
    value          NUMERIC(78,0) NOT NULL,
    block_number   BIGINT       NOT NULL,
    block_time     TIMESTAMPTZ  NOT NULL,
    tx_hash        BYTEA        NOT NULL,
    log_index      INT          NOT NULL,
    UNIQUE (tx_hash, log_index)
);
CREATE INDEX transfers_token_idx ON transfers (token_address, block_number);

CREATE TABLE pool_swaps (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    token_address  BYTEA        NOT NULL REFERENCES tokens(address),
    pair           BYTEA        NOT NULL,
    amount0_in     NUMERIC(78,0) NOT NULL,
    amount1_in     NUMERIC(78,0) NOT NULL,
    amount0_out    NUMERIC(78,0) NOT NULL,
    amount1_out    NUMERIC(78,0) NOT NULL,
    price_wad      NUMERIC(78,0) NOT NULL,
    block_number   BIGINT       NOT NULL,
    block_time     TIMESTAMPTZ  NOT NULL,
    tx_hash        BYTEA        NOT NULL,
    log_index      INT          NOT NULL,
    UNIQUE (tx_hash, log_index)
);
CREATE INDEX pool_swaps_token_time_idx ON pool_swaps (token_address, block_time DESC);

-- +goose Down
DROP TABLE pool_swaps;
DROP TABLE transfers;
DROP TABLE creator_fee_claims;
DROP TABLE graduations;
DROP TABLE trades;
```

- [ ] **Step 2: Write the failing test — add to `migrate_test.go`**

```go
func TestMigrations_CanonicalTablesAndUnique(t *testing.T) {
	dsn := StartTestPostgres(t)
	conn, _ := pgx.Connect(context.Background(), dsn)
	defer conn.Close(context.Background())
	ctx := context.Background()

	for _, tbl := range []string{"trades", "graduations", "creator_fee_claims", "transfers", "pool_swaps"} {
		var ok bool
		conn.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM information_schema.tables
			WHERE table_name=$1)`, tbl).Scan(&ok)
		if !ok {
			t.Fatalf("missing table %q", tbl)
		}
	}

	// seed a token to satisfy the FK
	_, err := conn.Exec(ctx, `INSERT INTO tokens
		(address, curve_address, creator, name, symbol, total_supply, x0, y0, k,
		 curve_tokens, lp_tokens, graduation_eth, trade_fee_bps, protocol_share_bps,
		 launched_at, launch_block, launch_tx)
		VALUES ('\x01','\x02','\x03','T','TKN',1,1,1,1,1,1,1,100,5000, now(), 1, '\xaa')`)
	if err != nil {
		t.Fatalf("seed token: %v", err)
	}
	ins := `INSERT INTO transfers
		(token_address, from_addr, to_addr, value, block_number, block_time, tx_hash, log_index)
		VALUES ('\x01','\x00','\x03', 5, 10, now(), '\xdead', 0)`
	if _, err := conn.Exec(ctx, ins); err != nil {
		t.Fatalf("first insert: %v", err)
	}
	if _, err := conn.Exec(ctx, ins); err == nil {
		t.Fatal("expected UNIQUE (tx_hash, log_index) violation on duplicate")
	}
}
```

- [ ] **Step 3: Run tests**

Run: `cd backend && go test ./internal/store/postgres/ -run Migrations -v`
Expected: PASS (or SKIP without Docker).

- [ ] **Step 4: Commit**

```bash
git add backend/internal/store/postgres/migrations backend/internal/store/postgres/migrate_test.go
git commit -m "feat(store): canonical event tables with (tx_hash, log_index) uniqueness"
```

---

## Task 11: store — derived schema, market_trades view, sqlc setup

**Files:**
- Create: `backend/internal/store/postgres/migrations/00003_derived_and_views.sql`
- Create: `backend/sqlc.yaml`
- Create: `backend/internal/store/postgres/queries/sync_state.sql`
- Create: `backend/internal/store/postgres/queries/tokens.sql`
- Create: `backend/internal/store/postgres/gen/` (generated by sqlc; commit the output)
- Modify: `backend/internal/store/postgres/db.go` (add `DBTX` alias re-export)
- Test: `backend/internal/store/postgres/migrate_test.go` (view shape assertion)

**Interfaces:**
- Consumes: 00001-00002.
- Produces:
  - Derived tables: `holder_balances`, `candles`, `token_stats`, `protocol_daily`, `protocol_stats`.
  - View: `market_trades (token_address, ts, price_wad, eth_volume, token_volume, side_buy, trader, tx_hash, log_index, source)`.
  - `gen.Queries` with methods `GetSyncState`, `UpsertSyncState`, `UpsertToken`, `GetToken` (exact signatures determined by sqlc from the query files below).
  - `postgres.DBTX = gen.DBTX` (type alias) so callers outside `gen` refer to `postgres.DBTX`.

- [ ] **Step 1: Write migration `00003_derived_and_views.sql`**

```sql
-- +goose Up
CREATE TABLE holder_balances (
    token_address        BYTEA        NOT NULL REFERENCES tokens(address),
    holder               BYTEA        NOT NULL,
    balance              NUMERIC(78,0) NOT NULL,
    first_acquired_block  BIGINT      NOT NULL,
    updated_block        BIGINT       NOT NULL,
    PRIMARY KEY (token_address, holder)
);
CREATE INDEX holder_balances_token_bal_idx
    ON holder_balances (token_address, balance DESC);

CREATE TABLE candles (
    token_address  BYTEA        NOT NULL REFERENCES tokens(address),
    interval       TEXT         NOT NULL CHECK (interval IN ('1m','5m','1h','1d')),
    bucket_start   TIMESTAMPTZ  NOT NULL,
    open           NUMERIC(78,0) NOT NULL,
    high           NUMERIC(78,0) NOT NULL,
    low            NUMERIC(78,0) NOT NULL,
    close          NUMERIC(78,0) NOT NULL,
    volume_eth     NUMERIC(78,0) NOT NULL,
    volume_token   NUMERIC(78,0) NOT NULL,
    trade_count    INT          NOT NULL,
    PRIMARY KEY (token_address, interval, bucket_start)
);

CREATE TABLE token_stats (
    token_address     BYTEA PRIMARY KEY REFERENCES tokens(address),
    price_wad         NUMERIC(78,0) NOT NULL DEFAULT 0,
    price_usd         NUMERIC(38,18) NOT NULL DEFAULT 0,
    fdv_usd           NUMERIC(38,2) NOT NULL DEFAULT 0,
    circ_mc_usd       NUMERIC(38,2) NOT NULL DEFAULT 0,
    liquidity_usd     NUMERIC(38,2) NOT NULL DEFAULT 0,
    ath_price_wad     NUMERIC(78,0) NOT NULL DEFAULT 0,
    vol_24h_usd       NUMERIC(38,2) NOT NULL DEFAULT 0,
    price_change_24h  NUMERIC(10,4) NOT NULL DEFAULT 0,
    holder_count      INT          NOT NULL DEFAULT 0,
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE protocol_daily (
    day          DATE PRIMARY KEY,
    volume_eth   NUMERIC(78,0) NOT NULL DEFAULT 0,
    volume_usd   NUMERIC(38,2) NOT NULL DEFAULT 0,
    launches     INT NOT NULL DEFAULT 0,
    trades       INT NOT NULL DEFAULT 0,
    graduations  INT NOT NULL DEFAULT 0
);

CREATE TABLE protocol_stats (
    id            SMALLINT PRIMARY KEY DEFAULT 1,
    vol_24h_usd   NUMERIC(38,2) NOT NULL DEFAULT 0,
    launches_24h  INT NOT NULL DEFAULT 0,
    trades_24h    INT NOT NULL DEFAULT 0,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT protocol_stats_singleton CHECK (id = 1)
);

CREATE VIEW market_trades AS
    SELECT token_address,
           block_time AS ts,
           price_wad,
           eth_amount   AS eth_volume,
           token_amount AS token_volume,
           is_buy       AS side_buy,
           trader,
           tx_hash,
           log_index,
           'curve'::text AS source
    FROM trades
    UNION ALL
    SELECT ps.token_address,
           ps.block_time AS ts,
           ps.price_wad,
           CASE WHEN t.token_is_token0
                THEN ps.amount1_in + ps.amount1_out
                ELSE ps.amount0_in + ps.amount0_out END AS eth_volume,
           CASE WHEN t.token_is_token0
                THEN ps.amount0_in + ps.amount0_out
                ELSE ps.amount1_in + ps.amount1_out END AS token_volume,
           CASE WHEN t.token_is_token0
                THEN ps.amount0_out > 0
                ELSE ps.amount1_out > 0 END AS side_buy,
           NULL::bytea AS trader,
           ps.tx_hash,
           ps.log_index,
           'dex'::text AS source
    FROM pool_swaps ps
    JOIN tokens t ON t.address = ps.token_address;

-- +goose Down
DROP VIEW market_trades;
DROP TABLE protocol_stats;
DROP TABLE protocol_daily;
DROP TABLE token_stats;
DROP TABLE candles;
DROP TABLE holder_balances;
```

- [ ] **Step 2: Write `backend/sqlc.yaml`**

```yaml
version: "2"
sql:
  - engine: "postgresql"
    schema: "internal/store/postgres/migrations"
    queries: "internal/store/postgres/queries"
    gen:
      go:
        package: "gen"
        out: "internal/store/postgres/gen"
        sql_package: "pgx/v5"
        emit_pointers_for_null_types: true
        overrides:
          - db_type: "bytea"
            go_type: "[]byte"
```

- [ ] **Step 3: Write `queries/sync_state.sql`**

```sql
-- name: GetSyncState :one
SELECT chain_id, last_block, last_block_hash, updated_at
FROM sync_state WHERE id = 1;

-- name: UpsertSyncState :exec
INSERT INTO sync_state (id, chain_id, last_block, last_block_hash, updated_at)
VALUES (1, @chain_id, @last_block, @last_block_hash, now())
ON CONFLICT (id) DO UPDATE
SET chain_id = EXCLUDED.chain_id,
    last_block = EXCLUDED.last_block,
    last_block_hash = EXCLUDED.last_block_hash,
    updated_at = now();
```

- [ ] **Step 4: Write `queries/tokens.sql`**

```sql
-- name: UpsertToken :exec
INSERT INTO tokens (
    address, curve_address, creator, name, symbol, total_supply,
    x0, y0, k, curve_tokens, lp_tokens, graduation_eth,
    trade_fee_bps, protocol_share_bps, launched_at, launch_block, launch_tx
) VALUES (
    @address, @curve_address, @creator, @name, @symbol, @total_supply,
    @x0, @y0, @k, @curve_tokens, @lp_tokens, @graduation_eth,
    @trade_fee_bps, @protocol_share_bps, @launched_at, @launch_block, @launch_tx
)
ON CONFLICT (address) DO NOTHING;

-- name: GetToken :one
SELECT * FROM tokens WHERE address = @address;

-- name: SetTokenGraduated :exec
UPDATE tokens
SET phase = 'graduated', lp_pair = @lp_pair, token_is_token0 = @token_is_token0
WHERE address = @address;
```

- [ ] **Step 5: Generate and wire `DBTX`**

Run: `cd backend && sqlc generate`
Then append to `db.go`:

```go
import gen "github.com/pons/launchpad/backend/internal/store/postgres/gen"

// DBTX is the query surface shared by *pgxpool.Pool and pgx.Tx.
type DBTX = gen.DBTX
```

- [ ] **Step 6: Write the failing test — add to `migrate_test.go`**

```go
func TestMigrations_MarketTradesViewShape(t *testing.T) {
	dsn := StartTestPostgres(t)
	conn, _ := pgx.Connect(context.Background(), dsn)
	defer conn.Close(context.Background())

	rows, err := conn.Query(context.Background(), `SELECT * FROM market_trades LIMIT 0`)
	if err != nil {
		t.Fatalf("select from view: %v", err)
	}
	defer rows.Close()
	got := map[string]bool{}
	for _, fd := range rows.FieldDescriptions() {
		got[string(fd.Name)] = true
	}
	for _, col := range []string{"token_address", "ts", "price_wad", "eth_volume",
		"token_volume", "side_buy", "trader", "tx_hash", "log_index", "source"} {
		if !got[col] {
			t.Fatalf("market_trades view missing column %q", col)
		}
	}
}
```

- [ ] **Step 7: Run tests + lint + build**

Run:
```bash
cd backend && go test ./internal/store/postgres/ -run Migrations -v && go build ./... && golangci-lint run
```
Expected: PASS / exit 0 (store tests SKIP without Docker).

- [ ] **Step 8: Commit**

```bash
git add backend/sqlc.yaml backend/internal/store/postgres backend/go.mod backend/go.sum
git commit -m "feat(store): derived schema, market_trades view, sqlc codegen"
```

---

## Task 12: store — Unit of Work

**Files:**
- Create: `backend/internal/store/postgres/uow.go`
- Test: `backend/internal/store/postgres/uow_test.go`

**Interfaces:**
- Consumes: `gen.Queries`, `gen.New`, `*pgxpool.Pool`, `DBTX` (Task 11).
- Produces:
  - `type Repositories struct { Q *gen.Queries }` — for this plan the bundle just carries the sqlc `*gen.Queries` bound to the active tx. Later plans add typed feature-repository fields that wrap `Q`.
  - `type UnitOfWork interface { WithinTx(ctx context.Context, fn func(r Repositories) error) error }`
  - `func NewUnitOfWork(pool *pgxpool.Pool) UnitOfWork`
  - Semantics: `WithinTx` opens a `pgx.Tx`, builds `Repositories{Q: gen.New(tx)}`, runs `fn`, commits if `fn` returns nil, otherwise rolls back and returns `fn`'s error. A panic in `fn` rolls back and re-panics.

- [ ] **Step 1: Write the failing test — `uow_test.go`**

```go
package postgres

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	gen "github.com/pons/launchpad/backend/internal/store/postgres/gen"
)

func pool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := StartTestPostgres(t)
	p, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatalf("pool: %v", err)
	}
	t.Cleanup(p.Close)
	return p
}

func TestUoW_CommitsOnNil(t *testing.T) {
	p := pool(t)
	uow := NewUnitOfWork(p)
	err := uow.WithinTx(context.Background(), func(r Repositories) error {
		return r.Q.UpsertSyncState(context.Background(), gen.UpsertSyncStateParams{
			ChainID: 31337, LastBlock: 42, LastBlockHash: []byte{0x01},
		})
	})
	if err != nil {
		t.Fatalf("WithinTx: %v", err)
	}
	q := gen.New(p)
	got, err := q.GetSyncState(context.Background())
	if err != nil || got.LastBlock != 42 {
		t.Fatalf("state not committed: %+v err=%v", got, err)
	}
}

func TestUoW_RollsBackOnError(t *testing.T) {
	p := pool(t)
	uow := NewUnitOfWork(p)
	sentinel := errors.New("boom")
	err := uow.WithinTx(context.Background(), func(r Repositories) error {
		_ = r.Q.UpsertSyncState(context.Background(), gen.UpsertSyncStateParams{
			ChainID: 31337, LastBlock: 99, LastBlockHash: []byte{0x02},
		})
		return sentinel
	})
	if !errors.Is(err, sentinel) {
		t.Fatalf("want sentinel, got %v", err)
	}
	q := gen.New(p)
	if _, err := q.GetSyncState(context.Background()); !errors.Is(err, pgx.ErrNoRows) {
		t.Fatalf("row should not exist after rollback, err=%v", err)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/store/postgres/ -run TestUoW -v`
Expected: FAIL — `undefined: NewUnitOfWork`.

- [ ] **Step 3: Write `uow.go`**

```go
package postgres

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	gen "github.com/pons/launchpad/backend/internal/store/postgres/gen"
)

type Repositories struct {
	Q *gen.Queries
}

type UnitOfWork interface {
	WithinTx(ctx context.Context, fn func(r Repositories) error) error
}

type uow struct{ pool *pgxpool.Pool }

func NewUnitOfWork(pool *pgxpool.Pool) UnitOfWork { return &uow{pool: pool} }

func (u *uow) WithinTx(ctx context.Context, fn func(r Repositories) error) (err error) {
	tx, err := u.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() {
		if p := recover(); p != nil {
			_ = tx.Rollback(ctx)
			panic(p)
		}
		if err != nil {
			_ = tx.Rollback(ctx)
			return
		}
		err = tx.Commit(ctx)
	}()

	return fn(Repositories{Q: gen.New(tx)})
}

var _ = pgx.ErrNoRows // keep pgx imported for callers of this package's tests
```

> Remove the trailing `var _ = pgx.ErrNoRows` line if `golangci-lint` flags it as unused
> in non-test builds; it is only there to document the dependency. Prefer deleting it and
> letting the test file import `pgx` directly (it already does).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && go test ./internal/store/postgres/ -run TestUoW -v`
Expected: PASS (SKIP without Docker).

- [ ] **Step 5: Full check**

Run:
```bash
cd backend && go build ./... && go test ./... -race -count=1 && golangci-lint run
```
Expected: all green (store tests SKIP locally if Docker is absent; they run in CI).

- [ ] **Step 6: Commit**

```bash
git add backend/internal/store/postgres/uow.go backend/internal/store/postgres/uow_test.go
git commit -m "feat(store): Unit of Work (WithinTx) over pgx transactions"
```

---

## Self-Review

**1. Spec coverage (this plan's slice):**
- §4.2 package layout → Tasks 1, 4-12 create `internal/curve`, `internal/config`, `internal/store/postgres`, `cmd/migrate`. `apiserver/indexer/chain/feature modules` are explicitly Plans 2-3.
- §4.3 dependency rules → Task 1 `depguard` config; Task 3 Step 6 verifies.
- §4.5 Unit of Work → Task 12.
- §6 curve math (precision, surface, differential test) → Tasks 4-8. `QuoteBuy/QuoteSell/SpotPriceWad/TokensSold/IsGraduated` all covered; vector-table harness in Task 8.
- §7.1 canonical tables → Tasks 9-10; §7.2 `market_trades` view → Task 11; §7.3 derived tables → Task 11.
- §7.4 tooling (pgx, sqlc, goose, tsvector search index) → Tasks 9, 11.
- §10 config env + chain registry → Tasks 2-3.
- §11 testing (curve vectors+fuzz, store via testcontainers) → Tasks 8, 9-12.
- Deferred to later plans (not gaps): RPC client, sync loop, reorg, aggregation, API, auth, SSE, `ETH_USD` source, WETH address confirmation.

**2. Placeholder scan:** Two intentional "wrong line" teaching notes (Task 10 Step 1 `BIGGENERATED`, Task 12 Step 3 trailing var) are immediately followed by the corrected full code and an instruction — not left as TODOs. `FILL_EXACT` in Task 8 is a deliberate, enforced-by-test marker with explicit instructions to replace it from real output. No "add error handling" / "similar to Task N" placeholders.

**3. Type consistency:** `Quote{AmountOut, ProtocolFee, CreatorFee, Next}` used identically in Tasks 6-8. `State{X,Y,K}` consistent Tasks 4-8. `Repositories{Q *gen.Queries}` defined Task 12, referenced only there. `RunMigrations(ctx, dsn)` / `StartTestPostgres(t)` / `NewUnitOfWork(pool)` signatures match across Tasks 9-12. `DBTX = gen.DBTX` alias introduced Task 11, no earlier use. sqlc method names (`GetSyncState`, `UpsertSyncState`, `UpsertToken`, `GetToken`, `SetTokenGraduated`) match between `queries/*.sql` and the test call sites.

---

## Execution Handoff

Plan complete and saved to `docs/plans/2026-09-01-backend-foundations.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
