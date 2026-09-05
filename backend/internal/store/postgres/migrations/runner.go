// Package migrations owns the embedded PostgreSQL migrations and their explicit runner.
package migrations

import (
	"context"
	"database/sql"
	"embed"
	"errors"
	"fmt"
	"io/fs"
	"path/filepath"
	"time"

	"github.com/pressly/goose/v3"
	"github.com/pressly/goose/v3/lock"
)

//go:embed *.sql
var files embed.FS

// Command is an explicitly requested migration operation.
type Command string

const (
	CommandUp     Command = "up"
	CommandDown   Command = "down"
	CommandStatus Command = "status"
)

var ErrInvalidCommand = errors.New("migration command must be one of: up, down, status")

// Result is a stable representation of a goose migration result or status row.
type Result struct {
	Version   int64
	Source    string
	Direction string
	State     string
	AppliedAt time.Time
}

// ParseCommand rejects missing and implicit migration commands.
func ParseCommand(value string) (Command, error) {
	command := Command(value)
	switch command {
	case CommandUp, CommandDown, CommandStatus:
		return command, nil
	default:
		return "", fmt.Errorf("%w: %q", ErrInvalidCommand, value)
	}
}

// Run executes one explicit command against the embedded migration source.
func Run(ctx context.Context, db *sql.DB, command Command) ([]Result, error) {
	if db == nil {
		return nil, errors.New("database handle is required")
	}

	provider, err := newProvider(db)
	if err != nil {
		return nil, fmt.Errorf("create migration provider: %w", err)
	}

	switch command {
	case CommandUp:
		results, runErr := provider.Up(ctx)
		return appliedResults(results), wrapRunError(command, runErr)
	case CommandDown:
		result, runErr := provider.Down(ctx)
		if runErr != nil {
			return nil, wrapRunError(command, runErr)
		}
		return appliedResults([]*goose.MigrationResult{result}), nil
	case CommandStatus:
		statuses, runErr := provider.Status(ctx)
		if runErr != nil {
			return nil, wrapRunError(command, runErr)
		}
		return statusResults(statuses), nil
	default:
		return nil, fmt.Errorf("%w: %q", ErrInvalidCommand, command)
	}
}

func newProvider(db *sql.DB) (*goose.Provider, error) {
	migrationFS, err := fs.Sub(files, ".")
	if err != nil {
		return nil, fmt.Errorf("open embedded migrations: %w", err)
	}
	locker, err := lock.NewPostgresSessionLocker(
		lock.WithLockTimeout(1, 30),
		lock.WithUnlockTimeout(1, 10),
	)
	if err != nil {
		return nil, fmt.Errorf("create migration session lock: %w", err)
	}

	return goose.NewProvider(
		goose.DialectPostgres,
		db,
		migrationFS,
		goose.WithDisableGlobalRegistry(true),
		goose.WithLogger(goose.NopLogger()),
		goose.WithSessionLocker(locker),
	)
}

func appliedResults(results []*goose.MigrationResult) []Result {
	converted := make([]Result, 0, len(results))
	for _, result := range results {
		if result == nil || result.Source == nil {
			continue
		}
		converted = append(converted, Result{
			Version:   result.Source.Version,
			Source:    filepath.Base(result.Source.Path),
			Direction: result.Direction,
			State:     "complete",
		})
	}
	return converted
}

func statusResults(statuses []*goose.MigrationStatus) []Result {
	converted := make([]Result, 0, len(statuses))
	for _, status := range statuses {
		if status == nil || status.Source == nil {
			continue
		}
		converted = append(converted, Result{
			Version:   status.Source.Version,
			Source:    filepath.Base(status.Source.Path),
			State:     string(status.State),
			AppliedAt: status.AppliedAt,
		})
	}
	return converted
}

func wrapRunError(command Command, err error) error {
	if err == nil {
		return nil
	}
	return fmt.Errorf("run migration command %q: %w", command, err)
}
