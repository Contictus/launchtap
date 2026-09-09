package postgres

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ListenAPIRefresh owns one pool connection until ctx is cancelled. Callers
// restart it after connection failures; notifications are hints and may be lost.
func ListenAPIRefresh(ctx context.Context, pool *pgxpool.Pool, receive func([]byte)) error {
	return ListenAPIRefreshReady(ctx, pool, nil, receive)
}

// ListenAPIRefreshReady is the testable form that signals after LISTEN is
// active. Production callers normally use ListenAPIRefresh.
func ListenAPIRefreshReady(ctx context.Context, pool *pgxpool.Pool, ready chan<- struct{}, receive func([]byte)) error {
	if pool == nil || receive == nil {
		return fmt.Errorf("API refresh listener requires pool and receiver")
	}
	conn, err := pool.Acquire(ctx)
	if err != nil {
		return err
	}
	defer conn.Release()
	if _, err := conn.Exec(ctx, `LISTEN api_refresh`); err != nil {
		return err
	}
	if ready != nil {
		close(ready)
	}
	for {
		notification, err := conn.Conn().WaitForNotification(ctx)
		if err != nil {
			return err
		}
		if notification != nil {
			receive([]byte(notification.Payload))
		}
	}
}
