// Package postgrestest provisions isolated PostgreSQL databases for integration tests.
package postgrestest

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/url"
	"strings"
)

const databaseNamePrefix = "launchpad_test_"

func databaseURL(serverURL, databaseName string) (string, error) {
	parsed, err := url.Parse(serverURL)
	if err != nil {
		return "", fmt.Errorf("parse PostgreSQL URL: %w", err)
	}
	if parsed.Scheme != "postgres" && parsed.Scheme != "postgresql" {
		return "", fmt.Errorf("PostgreSQL URL has unsupported scheme %q", parsed.Scheme)
	}
	if parsed.Host == "" {
		return "", errorsForEmptyHost()
	}
	if databaseName == "" || strings.ContainsAny(databaseName, "/\\") {
		return "", fmt.Errorf("invalid database name %q", databaseName)
	}

	parsed.Path = "/" + databaseName
	parsed.RawPath = ""
	return parsed.String(), nil
}

func errorsForEmptyHost() error {
	return fmt.Errorf("PostgreSQL URL host is required")
}

func randomDatabaseName() (string, error) {
	var suffix [12]byte
	if _, err := rand.Read(suffix[:]); err != nil {
		return "", fmt.Errorf("generate database name: %w", err)
	}
	return databaseNamePrefix + hex.EncodeToString(suffix[:]), nil
}
