package postgres

import (
	"context"

	"github.com/Contictus/launchtap/backend/internal/ledger"
	"github.com/Contictus/launchtap/backend/internal/store/postgres/sqlc"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
)

// DBTX is implemented by pgx pools, connections, and transactions.
type DBTX interface {
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
	Query(context.Context, string, ...any) (pgx.Rows, error)
	QueryRow(context.Context, string, ...any) pgx.Row
}

// Store scalar types are aliases of the validated sqlc codec types. Callers
// depend on this adapter package, not on generated query code.
type (
	Address = sqlc.Address
	Hash    = sqlc.Hash
	Uint256 = sqlc.Uint256

	IndexedBlock     = ledger.IndexedBlock
	Trade            = ledger.Trade
	LaunchPauseEvent = ledger.LaunchPauseEvent
)

type SyncState struct {
	ChainID         int64
	DeploymentID    string
	ObservedNumber  pgtype.Int8
	ObservedHash    *Hash
	ObservedAt      pgtype.Timestamptz
	SafeNumber      pgtype.Int8
	SafeHash        *Hash
	SafeAt          pgtype.Timestamptz
	FinalizedNumber pgtype.Int8
	FinalizedHash   *Hash
	FinalizedAt     pgtype.Timestamptz
}

type DirtyClaim struct {
	ChainID           int64
	TokenAddress      Address
	ClaimedGeneration int64
}
