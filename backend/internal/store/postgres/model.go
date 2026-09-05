package postgres

import (
	"context"

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
)

type IndexedBlock struct {
	ChainID        int64
	BlockNumber    int64
	BlockHash      Hash
	ParentHash     Hash
	BlockTime      pgtype.Timestamptz
	FinalityStatus string
}

type Trade struct {
	ChainID          int64
	BlockNumber      int64
	BlockHash        Hash
	BlockTime        pgtype.Timestamptz
	TransactionIndex int32
	TxHash           Hash
	LogIndex         int32
	TokenAddress     Address
	Trader           Address
	IsBuy            bool
	EthGross         Uint256
	EthRefund        Uint256
	TokenAmount      Uint256
	ProtocolFee      Uint256
	CreatorFee       Uint256
	NewEthReserve    Uint256
	NewTokenReserve  Uint256
}

type LaunchPauseEvent struct {
	ChainID          int64
	BlockNumber      int64
	BlockHash        Hash
	BlockTime        pgtype.Timestamptz
	TransactionIndex int32
	TxHash           Hash
	LogIndex         int32
	Paused           bool
}

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
