package sqlc

import (
	"os"
	"path"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"testing"
)

var (
	createTablePattern = regexp.MustCompile(`(?ms)^CREATE TABLE\s+([a-z_][a-z0-9_]*)\s*\((.*?)^\);`)
	columnPattern      = regexp.MustCompile(`(?m)^\s+([a-z_][a-z0-9_]*)\s+(BYTEA|NUMERIC\(78,0\)|NUMERIC\(38,18\))([^,]*),`)
	overridePattern    = regexp.MustCompile(`(?m)^\s+- column: "([^"]+)"\r?\n\s+go_type: \{type: "(Address|Hash|Uint256)"(, pointer: true)?\}`)
)

type configuredOverride struct {
	pattern  string
	typeName string
	pointer  bool
}

func TestColumnOverridesCoverFixedWidthSchema(t *testing.T) {
	t.Parallel()

	packageDir := currentPackageDir(t)
	configBytes, err := os.ReadFile(filepath.Join(packageDir, "../../../../sqlc.yaml"))
	if err != nil {
		t.Fatalf("read sqlc config: %v", err)
	}
	overrides := parseOverrides(string(configBytes))

	migrationPaths, err := filepath.Glob(filepath.Join(packageDir, "../migrations/*.sql"))
	if err != nil {
		t.Fatalf("glob migrations: %v", err)
	}
	sort.Strings(migrationPaths)
	for _, migrationPath := range migrationPaths {
		migrationBytes, readErr := os.ReadFile(migrationPath)
		if readErr != nil {
			t.Fatalf("read migration %s: %v", migrationPath, readErr)
		}
		assertMigrationOverrides(t, string(migrationBytes), overrides)
	}
}

func parseOverrides(config string) []configuredOverride {
	matches := overridePattern.FindAllStringSubmatch(config, -1)
	overrides := make([]configuredOverride, 0, len(matches))
	for _, match := range matches {
		overrides = append(overrides, configuredOverride{
			pattern:  match[1],
			typeName: match[2],
			pointer:  match[3] != "",
		})
	}
	return overrides
}

func assertMigrationOverrides(t *testing.T, migration string, overrides []configuredOverride) {
	t.Helper()
	for _, tableMatch := range createTablePattern.FindAllStringSubmatch(migration, -1) {
		table, body := tableMatch[1], tableMatch[2]
		for _, columnMatch := range columnPattern.FindAllStringSubmatch(body, -1) {
			column, sqlType, suffix := columnMatch[1], columnMatch[2], columnMatch[3]
			qualified := table + "." + column
			switch sqlType {
			case "NUMERIC(38,18)":
				if matched, ok := matchingOverride(qualified, overrides); ok && matched.typeName == "Uint256" {
					t.Errorf("USD column %s must not use Uint256", qualified)
				}
			case "NUMERIC(78,0)":
				assertOverride(t, qualified, "Uint256", false, overrides)
			case "BYTEA":
				lengthPattern := regexp.MustCompile(`octet_length\(` + regexp.QuoteMeta(column) + `\) = (20|32)`)
				lengthMatch := lengthPattern.FindStringSubmatch(body)
				if lengthMatch == nil {
					t.Errorf("BYTEA column %s has no fixed-length constraint", qualified)
					continue
				}
				expectedType := "Address"
				if lengthMatch[1] == "32" {
					expectedType = "Hash"
				}
				assertOverride(t, qualified, expectedType, !strings.Contains(suffix, "NOT NULL"), overrides)
			}
		}
	}
}

func assertOverride(
	t *testing.T,
	qualified string,
	expectedType string,
	expectedPointer bool,
	overrides []configuredOverride,
) {
	t.Helper()
	matched, ok := matchingOverride(qualified, overrides)
	if !ok {
		t.Errorf("column %s has no sqlc override", qualified)
		return
	}
	if matched.typeName != expectedType || matched.pointer != expectedPointer {
		t.Errorf(
			"column %s override = %s pointer=%t, want %s pointer=%t",
			qualified, matched.typeName, matched.pointer, expectedType, expectedPointer,
		)
	}
}

func matchingOverride(qualified string, overrides []configuredOverride) (configuredOverride, bool) {
	for _, override := range overrides {
		matched, err := path.Match(override.pattern, qualified)
		if err == nil && matched {
			return override, true
		}
	}
	return configuredOverride{}, false
}

func currentPackageDir(t testing.TB) string {
	t.Helper()
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("resolve current package path")
	}
	return filepath.Dir(filename)
}
