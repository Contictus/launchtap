package postgrestest

import (
	"net/url"
	"strings"
	"testing"
)

func TestDatabaseURLReplacesOnlyDatabaseName(t *testing.T) {
	t.Parallel()

	raw := "postgres://user:secret@localhost:5432/configured_db?sslmode=disable&application_name=test"
	got, err := databaseURL(raw, "isolated_db")
	if err != nil {
		t.Fatalf("databaseURL: %v", err)
	}
	parsed, err := url.Parse(got)
	if err != nil {
		t.Fatalf("parse result: %v", err)
	}
	if parsed.Path != "/isolated_db" {
		t.Fatalf("database path = %q, want /isolated_db", parsed.Path)
	}
	if parsed.Host != "localhost:5432" || parsed.User.Username() != "user" {
		t.Fatalf("server coordinates changed: %q", got)
	}
	if parsed.Query().Get("sslmode") != "disable" || parsed.Query().Get("application_name") != "test" {
		t.Fatalf("connection options changed: %q", got)
	}
}

func TestDatabaseURLRejectsInvalidInput(t *testing.T) {
	t.Parallel()

	tests := []struct {
		serverURL string
		name      string
	}{
		{"http://localhost/db", "isolated"},
		{"postgres:///db", "isolated"},
		{"postgres://localhost/db", ""},
		{"postgres://localhost/db", "bad/name"},
	}
	for _, test := range tests {
		if _, err := databaseURL(test.serverURL, test.name); err == nil {
			t.Fatalf("databaseURL(%q, %q) succeeded", test.serverURL, test.name)
		}
	}
}

func TestRandomDatabaseNameIsUniqueAndSafe(t *testing.T) {
	t.Parallel()

	first, err := randomDatabaseName()
	if err != nil {
		t.Fatalf("randomDatabaseName: %v", err)
	}
	second, err := randomDatabaseName()
	if err != nil {
		t.Fatalf("randomDatabaseName: %v", err)
	}
	if first == second {
		t.Fatalf("generated duplicate database name %q", first)
	}
	for _, name := range []string{first, second} {
		if !strings.HasPrefix(name, databaseNamePrefix) || len(name) > 63 {
			t.Fatalf("unsafe database name %q", name)
		}
	}
}
