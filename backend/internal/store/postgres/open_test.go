package postgres

import (
	"context"
	"strings"
	"testing"
)

func TestOpenPoolRejectsTooFewConnections(t *testing.T) {
	_, err := OpenPool(t.Context(), "postgres://user:pass@127.0.0.1:5432/launchpad", PoolOptions{MaxConns: 3})
	if err == nil || !strings.Contains(err.Error(), "below minimum 4") {
		t.Fatalf("OpenPool error = %v, want minimum connection error", err)
	}
}

func TestOpenPoolUsesDefaultAndExplicitCapacity(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())
	defer cancel()
	for _, maxConns := range []int32{0, 4, 8} {
		pool, err := OpenPool(ctx, "postgres://user:pass@127.0.0.1:5432/launchpad", PoolOptions{MaxConns: maxConns})
		if err != nil {
			t.Fatalf("OpenPool(%d): %v", maxConns, err)
		}
		pool.Close()
	}
}
