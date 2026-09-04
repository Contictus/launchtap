package postgres

import (
	"database/sql"

	_ "github.com/jackc/pgx/v5/stdlib"
)

// Open creates a database handle backed by pgx's database/sql adapter.
// Callers must close the returned handle.
func Open(databaseURL string) (*sql.DB, error) {
	return sql.Open("pgx", databaseURL)
}
