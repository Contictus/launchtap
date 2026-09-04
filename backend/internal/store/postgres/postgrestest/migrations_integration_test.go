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
	assertMigrationResults(t, firstUp, []migrationResultWant{{version: 1, direction: "up"}, {version: 2, direction: "up"}, {version: 3, direction: "up"}, {version: 4, direction: "up"}})
	assertMigrationStates(t, ctx, database.DB, map[int64]string{1: "applied", 2: "applied", 3: "applied", 4: "applied"})
	assertTableExists(t, ctx, database.DB, "sync_state", true)
	assertTableExists(t, ctx, database.DB, "indexed_blocks", true)
	assertTableExists(t, ctx, database.DB, "token_launches", true)
	assertTableExists(t, ctx, database.DB, "tokens", true)

	down, err := migrations.Run(ctx, database.DB, migrations.CommandDown)
	if err != nil {
		t.Fatalf("migration down: %v", err)
	}
	assertMigrationResults(t, down, []migrationResultWant{{version: 4, direction: "down"}})
	assertMigrationStates(t, ctx, database.DB, map[int64]string{1: "applied", 2: "applied", 3: "applied", 4: "pending"})
	assertTableExists(t, ctx, database.DB, "sync_state", true)
	assertTableExists(t, ctx, database.DB, "indexed_blocks", true)
	assertTableExists(t, ctx, database.DB, "token_launches", true)
	assertTableExists(t, ctx, database.DB, "tokens", false)

	secondUp, err := migrations.Run(ctx, database.DB, migrations.CommandUp)
	if err != nil {
		t.Fatalf("second migration up: %v", err)
	}
	assertMigrationResults(t, secondUp, []migrationResultWant{{version: 4, direction: "up"}})
	assertMigrationStates(t, ctx, database.DB, map[int64]string{1: "applied", 2: "applied", 3: "applied", 4: "applied"})
	assertTableExists(t, ctx, database.DB, "sync_state", true)
	assertTableExists(t, ctx, database.DB, "indexed_blocks", true)
	assertTableExists(t, ctx, database.DB, "token_launches", true)
	assertTableExists(t, ctx, database.DB, "tokens", true)
}

type migrationResultWant struct {
	version   int64
	direction string
}

func assertMigrationResults(t testing.TB, results []migrations.Result, want []migrationResultWant) {
	t.Helper()
	if len(results) != len(want) {
		t.Fatalf("migration result count = %d, want %d: %+v", len(results), len(want), results)
	}
	for index := range want {
		if results[index].Version != want[index].version ||
			results[index].Direction != want[index].direction ||
			results[index].State != "complete" {
			t.Fatalf("migration result %d = %+v, want version=%d direction=%s state=complete", index, results[index], want[index].version, want[index].direction)
		}
	}
}

func assertMigrationStates(t testing.TB, ctx context.Context, database *sql.DB, want map[int64]string) {
	t.Helper()
	statuses, err := migrations.Run(ctx, database, migrations.CommandStatus)
	if err != nil {
		t.Fatalf("migration status: %v", err)
	}
	if len(statuses) != len(want) {
		t.Fatalf("migration status count = %d, want %d: %+v", len(statuses), len(want), statuses)
	}
	for _, status := range statuses {
		if wantState, ok := want[status.Version]; !ok || status.State != wantState {
			t.Fatalf("unexpected migration status: %+v; want %+v", status, want)
		}
	}
}

func assertTableExists(t testing.TB, ctx context.Context, database *sql.DB, table string, want bool) {
	t.Helper()
	var exists bool
	if err := database.QueryRowContext(ctx, `
		SELECT EXISTS (
			SELECT 1
			FROM pg_catalog.pg_class AS relation
			JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = relation.relnamespace
			WHERE namespace.nspname = 'public'
			  AND relation.relname = $1
			  AND relation.relkind = 'r'
		)
	`, table).Scan(&exists); err != nil {
		t.Fatalf("check table %q existence: %v", table, err)
	}
	if exists != want {
		t.Fatalf("table %q exists = %t, want %t", table, exists, want)
	}
}
