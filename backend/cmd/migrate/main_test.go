package main

import (
	"bytes"
	"context"
	"strings"
	"testing"

	"github.com/Contictus/launchtap/backend/internal/store/postgres/migrations"
)

func TestRunRequiresExplicitCommand(t *testing.T) {
	t.Parallel()

	for _, args := range [][]string{nil, {}, {"up", "extra"}, {"redo"}} {
		var stderr bytes.Buffer
		getenvCalled := false
		exitCode := run(t.Context(), args, func(string) string {
			getenvCalled = true
			return ""
		}, &bytes.Buffer{}, &stderr, nil)
		if exitCode != 2 {
			t.Fatalf("run(%v) exit code = %d, want 2", args, exitCode)
		}
		if getenvCalled {
			t.Fatalf("run(%v) loaded configuration before validating command", args)
		}
	}
}

func TestRunUsesDatabaseOnlyConfiguration(t *testing.T) {
	t.Parallel()

	const databaseURL = "postgres://user:pass@localhost:5432/launchpad?sslmode=disable"
	var stdout, stderr bytes.Buffer
	exitCode := run(t.Context(), []string{"status"}, func(key string) string {
		if key == "DATABASE_URL" {
			return databaseURL
		}
		return ""
	}, &stdout, &stderr, func(_ context.Context, gotURL string, command migrations.Command) ([]migrations.Result, error) {
		if gotURL != databaseURL {
			t.Fatalf("database URL = %q, want %q", gotURL, databaseURL)
		}
		if command != migrations.CommandStatus {
			t.Fatalf("command = %q, want status", command)
		}
		return []migrations.Result{{Version: 1, Source: "00001_initialize.sql", State: "applied"}}, nil
	})
	if exitCode != 0 {
		t.Fatalf("run exit code = %d, stderr = %q", exitCode, stderr.String())
	}
	if !strings.Contains(stdout.String(), "00001 applied 00001_initialize.sql") {
		t.Fatalf("unexpected stdout: %q", stdout.String())
	}
}

func TestRunRejectsMissingDatabaseURL(t *testing.T) {
	t.Parallel()

	var stderr bytes.Buffer
	exitCode := run(t.Context(), []string{"up"}, func(string) string { return "" }, &bytes.Buffer{}, &stderr, nil)
	if exitCode != 1 {
		t.Fatalf("exit code = %d, want 1", exitCode)
	}
	if !strings.Contains(stderr.String(), "DATABASE_URL") {
		t.Fatalf("stderr = %q, want DATABASE_URL error", stderr.String())
	}
}
