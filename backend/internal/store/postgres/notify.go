package postgres

import (
	"context"
	"log/slog"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ListenMarketDirty keeps a pool connection subscribed to the durable dirty hint.
// Notification loss is harmless because the worker polls aggregation_dirty.
func ListenMarketDirty(ctx context.Context, pool *pgxpool.Pool, wake chan<- struct{}) error {
	conn, err := pool.Acquire(ctx)
	if err != nil {
		return err
	}
	defer conn.Release()
	if _, err := conn.Exec(ctx, `LISTEN market_dirty`); err != nil {
		return err
	}
	for {
		n, err := conn.Conn().WaitForNotification(ctx)
		if err != nil {
			return err
		}
		if n != nil {
			select {
			case wake <- struct{}{}:
			default:
			}
			slog.Debug("market dirty notification received")
		}
	}
}
