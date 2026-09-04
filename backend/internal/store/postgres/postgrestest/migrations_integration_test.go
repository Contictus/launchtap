//go:build integration

package postgrestest

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"github.com/Contictus/launchtap/backend/internal/store/postgres/migrations"
)

func TestMigrationsUpDownUp(t *testing.T) {
	t.Parallel()

	database := New(t)
	ctx, cancel := context.WithTimeout(t.Context(), 30*time.Second)
	defer cancel()

	firstUp, err := migrations.Run(ctx, database.DB, migrations.CommandUp)
	if err != nil {
		t.Fatalf("first migration up: %v", err)
	}
	assertSingleMigration(t, firstUp, "up")
	assertMigrationState(t, ctx, database.DB, "applied")

	down, err := migrations.Run(ctx, database.DB, migrations.CommandDown)
	if err != nil {
		t.Fatalf("migration down: %v", err)
	}
	assertSingleMigration(t, down, "down")
	assertMigrationState(t, ctx, database.DB, "pending")

	secondUp, err := migrations.Run(ctx, database.DB, migrations.CommandUp)
	if err != nil {
		t.Fatalf("second migration up: %v", err)
	}
	assertSingleMigration(t, secondUp, "up")
	assertMigrationState(t, ctx, database.DB, "applied")
}

func assertSingleMigration(t testing.TB, results []migrations.Result, direction string) {
	t.Helper()
	if len(results) != 1 {
		t.Fatalf("%s result count = %d, want 1", direction, len(results))
	}
	if results[0].Version != 1 || results[0].Direction != direction || results[0].State != "complete" {
		t.Fatalf("unexpected %s result: %+v", direction, results[0])
	}
}

func assertMigrationState(t testing.TB, ctx context.Context, database *sql.DB, want string) {
	t.Helper()
	statuses, err := migrations.Run(ctx, database, migrations.CommandStatus)
	if err != nil {
		t.Fatalf("migration status: %v", err)
	}
	if len(statuses) != 1 || statuses[0].Version != 1 || statuses[0].State != want {
		t.Fatalf("migration status = %+v, want version 1 %s", statuses, want)
	}
}
