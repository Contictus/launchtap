//go:build integration

package postgres

import (
	"net"
	"net/url"
	"os"
	"testing"
	"time"
)

func TestPostgresIsReachable(t *testing.T) {
	t.Parallel()

	databaseURL := os.Getenv("DATABASE_URL")
	required := os.Getenv("INTEGRATION_REQUIRED") == "true"
	if databaseURL == "" {
		if required {
			t.Fatal("DATABASE_URL is required when INTEGRATION_REQUIRED=true")
		}
		t.Skip("DATABASE_URL is not set")
	}

	parsed, err := url.Parse(databaseURL)
	if err != nil {
		t.Fatalf("parse DATABASE_URL: %v", err)
	}
	host := parsed.Host
	if _, _, err := net.SplitHostPort(host); err != nil {
		host = net.JoinHostPort(parsed.Hostname(), "5432")
	}

	connection, err := net.DialTimeout("tcp", host, 5*time.Second)
	if err != nil {
		if required {
			t.Fatalf("connect to required PostgreSQL service: %v", err)
		}
		t.Skipf("PostgreSQL is unavailable: %v", err)
	}
	if err := connection.Close(); err != nil {
		t.Fatalf("close PostgreSQL reachability connection: %v", err)
	}
}
