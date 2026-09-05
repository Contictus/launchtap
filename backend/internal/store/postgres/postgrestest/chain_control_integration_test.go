//go:build integration

package postgrestest

import (
	"bytes"
	"context"
	"database/sql"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
)

const insertIndexedBlockSQL = `
	INSERT INTO indexed_blocks (
		chain_id,
		block_number,
		block_hash,
		parent_hash,
		block_time,
		finality_status
	) VALUES ($1, $2, $3, $4, $5, $6)
`

func TestChainControlSchema(t *testing.T) {
	database := NewMigrated(t)
	ctx, cancel := context.WithTimeout(t.Context(), 30*time.Second)
	defer cancel()

	t.Run("sync state constraints", func(t *testing.T) {
		testSyncStateConstraints(t, ctx, database.DB)
	})
	t.Run("indexed block constraints", func(t *testing.T) {
		testIndexedBlockConstraints(t, ctx, database.DB)
	})
	t.Run("immutable block identity", func(t *testing.T) {
		testImmutableBlockIdentity(t, ctx, database.DB)
	})
	t.Run("common ancestor query", func(t *testing.T) {
		testCommonAncestorQuery(t, ctx, database.DB)
	})
}

func testSyncStateConstraints(t *testing.T, ctx context.Context, database *sql.DB) {
	t.Helper()
	at := time.Date(2026, time.September, 4, 12, 0, 0, 0, time.UTC)
	observedHash := hashBytes(0x10)
	safeHash := hashBytes(0x11)
	finalizedHash := hashBytes(0x12)

	if _, err := database.ExecContext(ctx, `
		INSERT INTO sync_state (
			chain_id, deployment_id,
			observed_number, observed_hash, observed_at,
			safe_number, safe_hash, safe_at,
			finalized_number, finalized_hash, finalized_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
	`, 46630, "robinhood-mainnet-v1", 100, observedHash, at, 99, safeHash, at, 98, finalizedHash, at); err != nil {
		t.Fatalf("insert valid sync state: %v", err)
	}

	tests := []struct {
		name       string
		statement  string
		args       []any
		constraint string
	}{
		{
			name:       "positive chain id",
			statement:  `INSERT INTO sync_state (chain_id, deployment_id) VALUES ($1, $2)`,
			args:       []any{0, "chain-zero"},
			constraint: "sync_state_chain_id_positive",
		},
		{
			name:       "deployment id format",
			statement:  `INSERT INTO sync_state (chain_id, deployment_id) VALUES ($1, $2)`,
			args:       []any{46630, "Invalid ID"},
			constraint: "sync_state_deployment_id_format",
		},
		{
			name:       "nonnegative observed number",
			statement:  `INSERT INTO sync_state (chain_id, deployment_id, observed_number, observed_hash, observed_at) VALUES ($1, $2, $3, $4, $5)`,
			args:       []any{46630, "negative-observed", -1, observedHash, at},
			constraint: "sync_state_observed_number_nonnegative",
		},
		{
			name: "nonnegative safe number",
			statement: `
				INSERT INTO sync_state (
					chain_id, deployment_id,
					observed_number, observed_hash, observed_at,
					safe_number, safe_hash, safe_at
				) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
			`,
			args:       []any{46630, "negative-safe", 100, observedHash, at, -1, safeHash, at},
			constraint: "sync_state_safe_number_nonnegative",
		},
		{
			name: "nonnegative finalized number",
			statement: `
				INSERT INTO sync_state (
					chain_id, deployment_id,
					observed_number, observed_hash, observed_at,
					safe_number, safe_hash, safe_at,
					finalized_number, finalized_hash, finalized_at
				) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
			`,
			args:       []any{46630, "negative-finalized", 100, observedHash, at, 99, safeHash, at, -1, finalizedHash, at},
			constraint: "sync_state_finalized_number_nonnegative",
		},
		{
			name:       "observed triple is complete",
			statement:  `INSERT INTO sync_state (chain_id, deployment_id, observed_number) VALUES ($1, $2, $3)`,
			args:       []any{46630, "partial-observed", 100},
			constraint: "sync_state_observed_complete",
		},
		{
			name:       "safe triple is complete",
			statement:  `INSERT INTO sync_state (chain_id, deployment_id, observed_number, observed_hash, observed_at, safe_number) VALUES ($1, $2, $3, $4, $5, $6)`,
			args:       []any{46630, "partial-safe", 100, observedHash, at, 99},
			constraint: "sync_state_safe_complete",
		},
		{
			name: "finalized triple is complete",
			statement: `
				INSERT INTO sync_state (
					chain_id, deployment_id,
					observed_number, observed_hash, observed_at,
					safe_number, safe_hash, safe_at,
					finalized_number
				) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
			`,
			args:       []any{46630, "partial-finalized", 100, observedHash, at, 99, safeHash, at, 98},
			constraint: "sync_state_finalized_complete",
		},
		{
			name:       "observed hash length",
			statement:  `INSERT INTO sync_state (chain_id, deployment_id, observed_number, observed_hash, observed_at) VALUES ($1, $2, $3, $4, $5)`,
			args:       []any{46630, "short-observed-hash", 100, bytes.Repeat([]byte{0x01}, 31), at},
			constraint: "sync_state_observed_hash_length",
		},
		{
			name: "safe hash length",
			statement: `
				INSERT INTO sync_state (
					chain_id, deployment_id,
					observed_number, observed_hash, observed_at,
					safe_number, safe_hash, safe_at
				) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
			`,
			args:       []any{46630, "short-safe-hash", 100, observedHash, at, 99, bytes.Repeat([]byte{0x02}, 31), at},
			constraint: "sync_state_safe_hash_length",
		},
		{
			name: "finalized hash length",
			statement: `
				INSERT INTO sync_state (
					chain_id, deployment_id,
					observed_number, observed_hash, observed_at,
					safe_number, safe_hash, safe_at,
					finalized_number, finalized_hash, finalized_at
				) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
			`,
			args:       []any{46630, "short-finalized-hash", 100, observedHash, at, 99, safeHash, at, 98, bytes.Repeat([]byte{0x03}, 31), at},
			constraint: "sync_state_finalized_hash_length",
		},
		{
			name:       "safe requires observed",
			statement:  `INSERT INTO sync_state (chain_id, deployment_id, safe_number, safe_hash, safe_at) VALUES ($1, $2, $3, $4, $5)`,
			args:       []any{46630, "safe-without-observed", 99, safeHash, at},
			constraint: "sync_state_safe_not_ahead",
		},
		{
			name: "finalized requires safe",
			statement: `
				INSERT INTO sync_state (
					chain_id, deployment_id,
					observed_number, observed_hash, observed_at,
					finalized_number, finalized_hash, finalized_at
				) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
			`,
			args:       []any{46630, "finalized-without-safe", 100, observedHash, at, 98, finalizedHash, at},
			constraint: "sync_state_finalized_not_ahead",
		},
		{
			name: "safe is bounded by observed",
			statement: `
				INSERT INTO sync_state (
					chain_id, deployment_id,
					observed_number, observed_hash, observed_at,
					safe_number, safe_hash, safe_at
				) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
			`,
			args:       []any{46630, "safe-ahead", 100, observedHash, at, 101, safeHash, at},
			constraint: "sync_state_safe_not_ahead",
		},
		{
			name: "finalized is bounded by safe",
			statement: `
				INSERT INTO sync_state (
					chain_id, deployment_id,
					observed_number, observed_hash, observed_at,
					safe_number, safe_hash, safe_at,
					finalized_number, finalized_hash, finalized_at
				) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
			`,
			args:       []any{46630, "finalized-ahead", 100, observedHash, at, 99, safeHash, at, 100, finalizedHash, at},
			constraint: "sync_state_finalized_not_ahead",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, err := database.ExecContext(ctx, test.statement, test.args...)
			assertConstraintViolation(t, err, test.constraint)
		})
	}
}

func testIndexedBlockConstraints(t *testing.T, ctx context.Context, database *sql.DB) {
	t.Helper()
	blockTime := time.Date(2026, time.September, 4, 12, 0, 0, 0, time.UTC)
	tests := []struct {
		name       string
		chainID    int64
		number     int64
		hash       []byte
		parentHash []byte
		status     string
		constraint string
	}{
		{"positive chain id", 0, 1, hashBytes(0x20), hashBytes(0x19), "observed", "indexed_blocks_chain_id_positive"},
		{"nonnegative block number", 46630, -1, hashBytes(0x21), hashBytes(0x20), "observed", "indexed_blocks_block_number_nonnegative"},
		{"block hash length", 46630, 1, bytes.Repeat([]byte{0x22}, 31), hashBytes(0x21), "observed", "indexed_blocks_block_hash_length"},
		{"parent hash length", 46630, 2, hashBytes(0x23), bytes.Repeat([]byte{0x22}, 31), "observed", "indexed_blocks_parent_hash_length"},
		{"finality status", 46630, 3, hashBytes(0x24), hashBytes(0x23), "pending", "indexed_blocks_finality_status_valid"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, err := database.ExecContext(
				ctx,
				insertIndexedBlockSQL,
				test.chainID,
				test.number,
				test.hash,
				test.parentHash,
				blockTime,
				test.status,
			)
			assertConstraintViolation(t, err, test.constraint)
		})
	}
}

func testImmutableBlockIdentity(t *testing.T, ctx context.Context, database *sql.DB) {
	t.Helper()
	const chainID int64 = 46631
	blockTime := time.Date(2026, time.September, 4, 13, 0, 0, 0, time.UTC)
	originalHash := hashBytes(0x31)
	originalParent := hashBytes(0x30)
	mustInsertBlock(t, ctx, database, chainID, 1, originalHash, originalParent, blockTime, "observed")

	_, err := database.ExecContext(
		ctx,
		insertIndexedBlockSQL,
		chainID,
		1,
		hashBytes(0x32),
		originalParent,
		blockTime,
		"observed",
	)
	assertConstraintViolation(t, err, "indexed_blocks_pkey")

	_, err = database.ExecContext(
		ctx,
		insertIndexedBlockSQL,
		chainID,
		2,
		originalHash,
		originalParent,
		blockTime.Add(time.Second),
		"observed",
	)
	assertConstraintViolation(t, err, "indexed_blocks_block_hash_key")

	_, err = database.ExecContext(ctx, `
		INSERT INTO indexed_blocks (
			chain_id, block_number, block_hash, parent_hash, block_time, finality_status
		) VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (chain_id, block_number) DO UPDATE SET
			block_hash = EXCLUDED.block_hash,
			parent_hash = EXCLUDED.parent_hash,
			block_time = EXCLUDED.block_time
	`, chainID, 1, hashBytes(0x33), originalParent, blockTime.Add(time.Second), "observed")
	assertImmutableIdentityViolation(t, err)

	var storedHash []byte
	var storedTime time.Time
	if err := database.QueryRowContext(ctx, `
		SELECT block_hash, block_time
		FROM indexed_blocks
		WHERE chain_id = $1 AND block_number = $2
	`, chainID, 1).Scan(&storedHash, &storedTime); err != nil {
		t.Fatalf("read block after rejected upsert: %v", err)
	}
	if !bytes.Equal(storedHash, originalHash) || !storedTime.Equal(blockTime) {
		t.Fatalf("rejected upsert changed block identity: hash=%x time=%s", storedHash, storedTime)
	}

	if _, err := database.ExecContext(ctx, `
		UPDATE indexed_blocks
		SET finality_status = 'safe'
		WHERE chain_id = $1 AND block_number = $2
	`, chainID, 1); err != nil {
		t.Fatalf("update finality only: %v", err)
	}
	var status string
	if err := database.QueryRowContext(ctx, `
		SELECT finality_status
		FROM indexed_blocks
		WHERE chain_id = $1 AND block_number = $2
	`, chainID, 1).Scan(&status); err != nil {
		t.Fatalf("read updated finality: %v", err)
	}
	if status != "safe" {
		t.Fatalf("finality status = %q, want safe", status)
	}
}

func testCommonAncestorQuery(t *testing.T, ctx context.Context, database *sql.DB) {
	t.Helper()
	const chainID int64 = 46632
	blockTime := time.Date(2026, time.September, 4, 14, 0, 0, 0, time.UTC)
	preStart := hashBytes(0x40)
	block100 := hashBytes(0x41)
	block101 := hashBytes(0x42)
	block102Canonical := hashBytes(0x43)
	block103Canonical := hashBytes(0x44)

	mustInsertBlock(t, ctx, database, chainID, 100, block100, preStart, blockTime, "finalized")
	mustInsertBlock(t, ctx, database, chainID, 101, block101, block100, blockTime.Add(time.Second), "safe")
	mustInsertBlock(t, ctx, database, chainID, 102, block102Canonical, block101, blockTime.Add(2*time.Second), "observed")
	mustInsertBlock(t, ctx, database, chainID, 103, block103Canonical, block102Canonical, blockTime.Add(3*time.Second), "observed")

	block102Fork := hashBytes(0x45)
	block103Fork := hashBytes(0x46)
	var ancestorNumber int64
	var ancestorHash []byte
	if err := database.QueryRowContext(ctx, `
		WITH RECURSIVE candidate_chain (block_number, block_hash, parent_hash) AS (
			VALUES
				(103::BIGINT, $2::BYTEA, $3::BYTEA),
				(102::BIGINT, $3::BYTEA, $4::BYTEA),
				(101::BIGINT, $4::BYTEA, $5::BYTEA)
		),
		walk AS (
			SELECT block_number, block_hash, parent_hash
			FROM candidate_chain
			WHERE block_hash = $2
			UNION ALL
			SELECT candidate.block_number, candidate.block_hash, candidate.parent_hash
			FROM walk
			JOIN candidate_chain AS candidate ON candidate.block_hash = walk.parent_hash
		)
		SELECT stored.block_number, stored.block_hash
		FROM walk
		JOIN indexed_blocks AS stored
		  ON stored.chain_id = $1
		 AND stored.block_hash = walk.block_hash
		ORDER BY stored.block_number DESC
		LIMIT 1
	`, chainID, block103Fork, block102Fork, block101, block100).Scan(&ancestorNumber, &ancestorHash); err != nil {
		t.Fatalf("find common ancestor: %v", err)
	}
	if ancestorNumber != 101 || !bytes.Equal(ancestorHash, block101) {
		t.Fatalf("common ancestor = (%d, %x), want (101, %x)", ancestorNumber, ancestorHash, block101)
	}
}

func mustInsertBlock(
	t testing.TB,
	ctx context.Context,
	database *sql.DB,
	chainID int64,
	blockNumber int64,
	blockHash []byte,
	parentHash []byte,
	blockTime time.Time,
	status string,
) {
	t.Helper()
	if _, err := database.ExecContext(
		ctx,
		insertIndexedBlockSQL,
		chainID,
		blockNumber,
		blockHash,
		parentHash,
		blockTime,
		status,
	); err != nil {
		t.Fatalf("insert block %d: %v", blockNumber, err)
	}
}

func assertConstraintViolation(t testing.TB, err error, constraint string) {
	t.Helper()
	if err == nil {
		t.Fatalf("expected constraint %q to reject statement", constraint)
	}
	var postgresError *pgconn.PgError
	if !errors.As(err, &postgresError) {
		t.Fatalf("error type = %T, want *pgconn.PgError: %v", err, err)
	}
	if postgresError.Code != "23505" && postgresError.Code != "23514" {
		t.Fatalf("SQLSTATE = %s, want unique/check violation for constraint %q: %v", postgresError.Code, constraint, err)
	}
	if postgresError.ConstraintName != constraint {
		t.Fatalf("constraint = %q, want %q: %v", postgresError.ConstraintName, constraint, err)
	}
}

func assertImmutableIdentityViolation(t testing.TB, err error) {
	t.Helper()
	if err == nil {
		t.Fatal("expected immutable block identity trigger to reject update")
	}
	var postgresError *pgconn.PgError
	if !errors.As(err, &postgresError) {
		t.Fatalf("error type = %T, want *pgconn.PgError: %v", err, err)
	}
	if postgresError.Code != "P0001" || !strings.Contains(postgresError.Message, "block identity is immutable") {
		t.Fatalf("unexpected immutable identity error: code=%s message=%q", postgresError.Code, postgresError.Message)
	}
}

func hashBytes(value byte) []byte {
	return bytes.Repeat([]byte{value}, 32)
}
