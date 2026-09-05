package postgres

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const rollbackTimeout = 5 * time.Second

// WithinTx runs fn against an Adapter bound to one READ COMMITTED transaction.
// The callback must not retain the adapter after it returns.
func WithinTx(
	ctx context.Context,
	pool *pgxpool.Pool,
	fn func(context.Context, *Adapter) error,
) (err error) {
	tx, err := pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.ReadCommitted})
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}

	defer func() {
		if recovered := recover(); recovered != nil {
			if rollbackErr := rollbackTx(tx); rollbackErr != nil {
				slog.Error("rollback transaction while handling panic", "error", rollbackErr)
			}
			panic(recovered)
		}
	}()

	if callbackErr := fn(ctx, NewAdapter(tx)); callbackErr != nil {
		return rollbackWithCause(tx, fmt.Errorf("transaction callback: %w", callbackErr))
	}
	if contextErr := ctx.Err(); contextErr != nil {
		return rollbackWithCause(tx, fmt.Errorf("transaction context: %w", contextErr))
	}
	if commitErr := tx.Commit(ctx); commitErr != nil {
		return rollbackWithCause(tx, fmt.Errorf("commit transaction: %w", commitErr))
	}
	return nil
}

func rollbackWithCause(tx pgx.Tx, cause error) error {
	if rollbackErr := rollbackTx(tx); rollbackErr != nil {
		return errors.Join(cause, fmt.Errorf("rollback transaction: %w", rollbackErr))
	}
	return cause
}

func rollbackTx(tx pgx.Tx) error {
	ctx, cancel := context.WithTimeout(context.Background(), rollbackTimeout)
	defer cancel()

	err := tx.Rollback(ctx)
	if errors.Is(err, pgx.ErrTxClosed) {
		return nil
	}
	return err
}
