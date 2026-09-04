package config

import (
	"errors"
	"reflect"
	"testing"
)

func TestLoadParsesCompleteConfiguration(t *testing.T) {
	t.Parallel()

	env := validEnvironment()
	env["PRIVY_APP_ID"] = " app-id "
	env["PRIVY_VERIFICATION_KEY"] = " verification-key "
	env["LOG_LEVEL"] = "debug"
	env["API_ADDR"] = "127.0.0.1:9090"
	env["INDEXER_CHUNK_SIZE"] = "2500"
	env["INDEXER_CONFIRMATIONS"] = "12"
	env["ETH_USD_SOURCE"] = " unconfigured-source "

	got, err := Load(mapGetenv(env))
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	wantConfirmations := uint64(12)
	want := Config{
		ChainID:              4663,
		DeploymentID:         "robinhood-mainnet-v1",
		RPCURL:               "https://rpc.example.test/v2/key",
		DatabaseURL:          "postgresql://user:pass@db.example.test:5432/launchpad",
		PrivyAppID:           "app-id",
		PrivyVerificationKey: "verification-key",
		LogLevel:             "debug",
		APIAddr:              "127.0.0.1:9090",
		IndexerChunkSize:     2500,
		IndexerConfirmations: &wantConfirmations,
		ETHUSDSource:         "unconfigured-source",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("Load() = %#v, want %#v", got, want)
	}
}

func TestLoadUsesBoundedDefaults(t *testing.T) {
	t.Parallel()

	got, err := Load(mapGetenv(validEnvironment()))
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	if got.LogLevel != "info" {
		t.Errorf("LogLevel = %q, want info", got.LogLevel)
	}
	if got.APIAddr != ":8080" {
		t.Errorf("APIAddr = %q, want :8080", got.APIAddr)
	}
	if got.IndexerChunkSize != 1000 {
		t.Errorf("IndexerChunkSize = %d, want 1000", got.IndexerChunkSize)
	}
	if got.IndexerConfirmations != nil {
		t.Errorf("IndexerConfirmations = %v, want nil", got.IndexerConfirmations)
	}
}

func TestLoadIsDeterministicAndReadsEachFieldOnce(t *testing.T) {
	t.Parallel()

	env := validEnvironment()
	counts := make(map[string]int)
	getenv := func(key string) string {
		counts[key]++
		return env[key]
	}

	first, err := Load(getenv)
	if err != nil {
		t.Fatalf("first Load() error = %v", err)
	}
	second, err := Load(mapGetenv(env))
	if err != nil {
		t.Fatalf("second Load() error = %v", err)
	}
	if !reflect.DeepEqual(first, second) {
		t.Fatalf("Load() results differ: %#v != %#v", first, second)
	}
	for key, count := range counts {
		if count != 1 {
			t.Errorf("getenv(%q) called %d times, want 1", key, count)
		}
	}
}

func TestLoadRejectsMissingRequiredFields(t *testing.T) {
	t.Parallel()

	for _, field := range []string{"CHAIN_ID", "DEPLOYMENT_ID", "RPC_URL", "DATABASE_URL"} {
		field := field
		t.Run(field, func(t *testing.T) {
			t.Parallel()
			env := validEnvironment()
			env[field] = " \t "

			assertFieldError(t, Load, env, field, ErrMissing)
		})
	}
}

func TestLoadRejectsInvalidUniversalFields(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name  string
		field string
		value string
	}{
		{name: "zero chain id", field: "CHAIN_ID", value: "0"},
		{name: "negative chain id", field: "CHAIN_ID", value: "-1"},
		{name: "overflowing chain id", field: "CHAIN_ID", value: "18446744073709551616"},
		{name: "non-decimal chain id", field: "CHAIN_ID", value: "0x1237"},
		{name: "uppercase deployment id", field: "DEPLOYMENT_ID", value: "Robinhood-mainnet"},
		{name: "leading deployment hyphen", field: "DEPLOYMENT_ID", value: "-mainnet"},
		{name: "rpc scheme", field: "RPC_URL", value: "ws://rpc.example.test"},
		{name: "rpc host", field: "RPC_URL", value: "https:///missing-host"},
		{name: "database scheme", field: "DATABASE_URL", value: "mysql://db.example.test/launchpad"},
		{name: "database host", field: "DATABASE_URL", value: "postgres:///launchpad"},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			env := validEnvironment()
			env[test.field] = test.value

			assertFieldError(t, Load, env, test.field, ErrInvalid)
		})
	}
}

func TestLoadRejectsInvalidBoundedSettings(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name  string
		field string
		value string
	}{
		{name: "unknown log level", field: "LOG_LEVEL", value: "trace"},
		{name: "uppercase log level", field: "LOG_LEVEL", value: "INFO"},
		{name: "address without port", field: "API_ADDR", value: "localhost"},
		{name: "zero port", field: "API_ADDR", value: ":0"},
		{name: "port overflow", field: "API_ADDR", value: ":65536"},
		{name: "zero chunk", field: "INDEXER_CHUNK_SIZE", value: "0"},
		{name: "chunk above provisional maximum", field: "INDEXER_CHUNK_SIZE", value: "10001"},
		{name: "negative confirmations", field: "INDEXER_CONFIRMATIONS", value: "-1"},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			env := validEnvironment()
			env[test.field] = test.value

			assertFieldError(t, Load, env, test.field, ErrInvalid)
		})
	}
}

func TestLoadAcceptsChunkAndConfirmationBoundaries(t *testing.T) {
	t.Parallel()

	for _, chunkSize := range []string{"1", "10000"} {
		chunkSize := chunkSize
		t.Run("chunk_"+chunkSize, func(t *testing.T) {
			t.Parallel()
			env := validEnvironment()
			env["INDEXER_CHUNK_SIZE"] = chunkSize
			env["INDEXER_CONFIRMATIONS"] = "0"

			got, err := Load(mapGetenv(env))
			if err != nil {
				t.Fatalf("Load() error = %v", err)
			}
			if got.IndexerConfirmations == nil || *got.IndexerConfirmations != 0 {
				t.Fatalf("IndexerConfirmations = %v, want pointer to zero", got.IndexerConfirmations)
			}
		})
	}
}

func TestLoadDoesNotRequireOptionalProcessSettings(t *testing.T) {
	t.Parallel()

	env := validEnvironment()
	env["ETH_USD_SOURCE"] = "future-adapter"

	got, err := Load(mapGetenv(env))
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if got.ETHUSDSource != "future-adapter" {
		t.Fatalf("ETHUSDSource = %q, want future-adapter", got.ETHUSDSource)
	}
}

func TestRequireAPI(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name      string
		configure func(*Config)
		wantField string
	}{
		{
			name: "complete",
			configure: func(config *Config) {
				config.PrivyAppID = "app-id"
				config.PrivyVerificationKey = "verification-key"
			},
		},
		{
			name: "missing app id",
			configure: func(config *Config) {
				config.PrivyVerificationKey = "verification-key"
			},
			wantField: "PRIVY_APP_ID",
		},
		{
			name: "missing verification key",
			configure: func(config *Config) {
				config.PrivyAppID = "app-id"
			},
			wantField: "PRIVY_VERIFICATION_KEY",
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			var config Config
			test.configure(&config)

			err := config.RequireAPI()
			if test.wantField == "" {
				if err != nil {
					t.Fatalf("RequireAPI() error = %v", err)
				}
				return
			}

			assertError(t, err, test.wantField, ErrMissing)
		})
	}
}

func TestLoadDatabaseUsesReducedSurface(t *testing.T) {
	t.Parallel()

	env := map[string]string{
		"DATABASE_URL": " postgres://user:pass@127.0.0.1:5432/launchpad ",
	}
	got, err := LoadDatabase(mapGetenv(env))
	if err != nil {
		t.Fatalf("LoadDatabase() error = %v", err)
	}
	if got.DatabaseURL != "postgres://user:pass@127.0.0.1:5432/launchpad" {
		t.Fatalf("DatabaseURL = %q", got.DatabaseURL)
	}
}

func TestNilGetenvFails(t *testing.T) {
	t.Parallel()

	_, err := Load(nil)
	assertError(t, err, "getenv", ErrMissing)

	_, err = LoadDatabase(nil)
	assertError(t, err, "getenv", ErrMissing)
}

func validEnvironment() map[string]string {
	return map[string]string{
		"CHAIN_ID":      "4663",
		"DEPLOYMENT_ID": "robinhood-mainnet-v1",
		"RPC_URL":       "https://rpc.example.test/v2/key",
		"DATABASE_URL":  "postgresql://user:pass@db.example.test:5432/launchpad",
	}
}

func mapGetenv(values map[string]string) func(string) string {
	return func(key string) string {
		return values[key]
	}
}

func assertFieldError(
	t *testing.T,
	load func(func(string) string) (Config, error),
	env map[string]string,
	wantField string,
	wantCause error,
) {
	t.Helper()

	_, err := load(mapGetenv(env))
	assertError(t, err, wantField, wantCause)
}

func assertError(t *testing.T, err error, wantField string, wantCause error) {
	t.Helper()

	if err == nil {
		t.Fatalf("error = nil, want %s", wantField)
	}
	var fieldError *FieldError
	if !errors.As(err, &fieldError) {
		t.Fatalf("error type = %T, want *FieldError", err)
	}
	if fieldError.Field != wantField {
		t.Errorf("Field = %q, want %q", fieldError.Field, wantField)
	}
	if !errors.Is(err, wantCause) {
		t.Errorf("error = %v, want cause %v", err, wantCause)
	}
}
