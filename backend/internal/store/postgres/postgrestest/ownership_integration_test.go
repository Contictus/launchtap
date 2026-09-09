//go:build integration

package postgrestest

import (
	"context"
	"errors"
	"testing"

	storepostgres "github.com/Contictus/launchtap/backend/internal/store/postgres"
)

func TestOwnershipFencesTerminatedSession(t *testing.T) {
	database := NewMigrated(t)
	ctx := t.Context()
	first, err := storepostgres.AcquireOwnership(ctx, database.URL, 49020, "test-owner")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = first.Close() })
	if second, err := storepostgres.AcquireOwnership(ctx, database.URL, 49020, "test-owner"); !errors.Is(err, storepostgres.ErrOwnershipBusy) {
		if second != nil {
			_ = second.Close()
		}
		t.Fatalf("second owner: %v", err)
	}
	var terminated bool
	if err := database.DB.QueryRowContext(ctx, `SELECT pg_terminate_backend($1)`, first.BackendPID()).Scan(&terminated); err != nil || !terminated {
		t.Fatalf("terminate owner: %v", err)
	}
	second, err := storepostgres.AcquireOwnership(ctx, database.URL, 49020, "test-owner")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = second.Close() }()
	called := false
	if err := first.WithinTx(ctx, func(context.Context, *storepostgres.Adapter) error { called = true; return nil }); err == nil || called {
		t.Fatalf("dead owner wrote before probe: called=%t err=%v", called, err)
	}
	if err := first.Probe(ctx); !errors.Is(err, storepostgres.ErrOwnershipLost) {
		t.Fatalf("probe error: %v", err)
	}
	if err := second.WithinTx(ctx, func(context.Context, *storepostgres.Adapter) error { return nil }); err != nil {
		t.Fatal(err)
	}
}
