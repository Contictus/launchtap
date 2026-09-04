package config

import (
	"errors"
	"fmt"
	"net"
	"net/url"
	"regexp"
	"strconv"
	"strings"
)

const (
	defaultLogLevel         = "info"
	defaultAPIAddr          = ":8080"
	defaultIndexerChunkSize = uint64(1000)
	maxIndexerChunkSize     = uint64(10000)
)

var (
	ErrInvalid = errors.New("invalid configuration value")
	ErrMissing = errors.New("missing configuration value")

	deploymentIDPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9._-]{2,63}$`)
)

// FieldError identifies a configuration field that failed validation.
type FieldError struct {
	Field string
	Err   error
}

func (e *FieldError) Error() string {
	return fmt.Sprintf("%s: %v", e.Field, e.Err)
}

func (e *FieldError) Unwrap() error {
	return e.Err
}

// Config contains the shared backend process configuration. Environment values
// are trimmed before validation. IndexerConfirmations is nil when the local-only
// override is absent; deployment validation decides whether it is permitted.
type Config struct {
	ChainID              uint64  `env:"CHAIN_ID"`
	DeploymentID         string  `env:"DEPLOYMENT_ID"`
	RPCURL               string  `env:"RPC_URL"`
	DatabaseURL          string  `env:"DATABASE_URL"`
	PrivyAppID           string  `env:"PRIVY_APP_ID"`
	PrivyVerificationKey string  `env:"PRIVY_VERIFICATION_KEY"`
	LogLevel             string  `env:"LOG_LEVEL"`
	APIAddr              string  `env:"API_ADDR"`
	IndexerChunkSize     uint64  `env:"INDEXER_CHUNK_SIZE"`
	IndexerConfirmations *uint64 `env:"INDEXER_CONFIRMATIONS"`
	ETHUSDSource         string  `env:"ETH_USD_SOURCE"`
}

// DatabaseConfig is the reduced configuration surface used by migration-only
// commands, which do not require chain or API settings.
type DatabaseConfig struct {
	DatabaseURL string
}

// Load parses shared API and indexer configuration using only the supplied
// environment lookup function. It performs syntactic validation and no I/O.
func Load(getenv func(string) string) (Config, error) {
	if getenv == nil {
		return Config{}, &FieldError{Field: "getenv", Err: ErrMissing}
	}

	values := readEnvironment(getenv)

	chainID, err := requiredPositiveUint64("CHAIN_ID", values.chainID)
	if err != nil {
		return Config{}, err
	}
	if !deploymentIDPattern.MatchString(values.deploymentID) {
		return Config{}, invalidOrMissing("DEPLOYMENT_ID", values.deploymentID)
	}
	if err := validateURL("RPC_URL", values.rpcURL, "http", "https"); err != nil {
		return Config{}, err
	}
	if err := validateURL("DATABASE_URL", values.databaseURL, "postgres", "postgresql"); err != nil {
		return Config{}, err
	}

	logLevel, err := parseLogLevel(values.logLevel)
	if err != nil {
		return Config{}, err
	}
	apiAddr, err := parseAPIAddr(values.apiAddr)
	if err != nil {
		return Config{}, err
	}
	chunkSize, err := optionalBoundedUint64(
		"INDEXER_CHUNK_SIZE",
		values.indexerChunkSize,
		defaultIndexerChunkSize,
		1,
		maxIndexerChunkSize,
	)
	if err != nil {
		return Config{}, err
	}
	confirmations, err := optionalUint64("INDEXER_CONFIRMATIONS", values.indexerConfirmations)
	if err != nil {
		return Config{}, err
	}

	return Config{
		ChainID:              chainID,
		DeploymentID:         values.deploymentID,
		RPCURL:               values.rpcURL,
		DatabaseURL:          values.databaseURL,
		PrivyAppID:           values.privyAppID,
		PrivyVerificationKey: values.privyVerificationKey,
		LogLevel:             logLevel,
		APIAddr:              apiAddr,
		IndexerChunkSize:     chunkSize,
		IndexerConfirmations: confirmations,
		ETHUSDSource:         values.ethUSDSource,
	}, nil
}

// LoadDatabase parses only the configuration required by migration commands.
func LoadDatabase(getenv func(string) string) (DatabaseConfig, error) {
	if getenv == nil {
		return DatabaseConfig{}, &FieldError{Field: "getenv", Err: ErrMissing}
	}

	databaseURL := strings.TrimSpace(getenv("DATABASE_URL"))
	if err := validateURL("DATABASE_URL", databaseURL, "postgres", "postgresql"); err != nil {
		return DatabaseConfig{}, err
	}

	return DatabaseConfig{DatabaseURL: databaseURL}, nil
}

// RequireAPI validates settings required only by the API process.
func (c Config) RequireAPI() error {
	if strings.TrimSpace(c.PrivyAppID) == "" {
		return &FieldError{Field: "PRIVY_APP_ID", Err: ErrMissing}
	}
	if strings.TrimSpace(c.PrivyVerificationKey) == "" {
		return &FieldError{Field: "PRIVY_VERIFICATION_KEY", Err: ErrMissing}
	}

	return nil
}

type environmentValues struct {
	chainID              string
	deploymentID         string
	rpcURL               string
	databaseURL          string
	privyAppID           string
	privyVerificationKey string
	logLevel             string
	apiAddr              string
	indexerChunkSize     string
	indexerConfirmations string
	ethUSDSource         string
}

func readEnvironment(getenv func(string) string) environmentValues {
	return environmentValues{
		chainID:              strings.TrimSpace(getenv("CHAIN_ID")),
		deploymentID:         strings.TrimSpace(getenv("DEPLOYMENT_ID")),
		rpcURL:               strings.TrimSpace(getenv("RPC_URL")),
		databaseURL:          strings.TrimSpace(getenv("DATABASE_URL")),
		privyAppID:           strings.TrimSpace(getenv("PRIVY_APP_ID")),
		privyVerificationKey: strings.TrimSpace(getenv("PRIVY_VERIFICATION_KEY")),
		logLevel:             strings.TrimSpace(getenv("LOG_LEVEL")),
		apiAddr:              strings.TrimSpace(getenv("API_ADDR")),
		indexerChunkSize:     strings.TrimSpace(getenv("INDEXER_CHUNK_SIZE")),
		indexerConfirmations: strings.TrimSpace(getenv("INDEXER_CONFIRMATIONS")),
		ethUSDSource:         strings.TrimSpace(getenv("ETH_USD_SOURCE")),
	}
}

func requiredPositiveUint64(field, value string) (uint64, error) {
	if value == "" {
		return 0, &FieldError{Field: field, Err: ErrMissing}
	}

	parsed, err := strconv.ParseUint(value, 10, 64)
	if err != nil || parsed == 0 {
		return 0, &FieldError{Field: field, Err: ErrInvalid}
	}

	return parsed, nil
}

func optionalUint64(field, value string) (*uint64, error) {
	if value == "" {
		return nil, nil
	}

	parsed, err := strconv.ParseUint(value, 10, 64)
	if err != nil {
		return nil, &FieldError{Field: field, Err: ErrInvalid}
	}

	return &parsed, nil
}

func optionalBoundedUint64(field, value string, defaultValue, minValue, maxValue uint64) (uint64, error) {
	if value == "" {
		return defaultValue, nil
	}

	parsed, err := strconv.ParseUint(value, 10, 64)
	if err != nil || parsed < minValue || parsed > maxValue {
		return 0, &FieldError{Field: field, Err: ErrInvalid}
	}

	return parsed, nil
}

func validateURL(field, value string, allowedSchemes ...string) error {
	if value == "" {
		return &FieldError{Field: field, Err: ErrMissing}
	}

	parsed, err := url.Parse(value)
	if err != nil || parsed.Host == "" {
		return &FieldError{Field: field, Err: ErrInvalid}
	}

	for _, scheme := range allowedSchemes {
		if parsed.Scheme == scheme {
			return nil
		}
	}

	return &FieldError{Field: field, Err: ErrInvalid}
}

func parseLogLevel(value string) (string, error) {
	if value == "" {
		return defaultLogLevel, nil
	}

	switch value {
	case "debug", "info", "warn", "error":
		return value, nil
	default:
		return "", &FieldError{Field: "LOG_LEVEL", Err: ErrInvalid}
	}
}

func parseAPIAddr(value string) (string, error) {
	if value == "" {
		value = defaultAPIAddr
	}

	// API processes need a stable numeric listener. Ephemeral port zero and
	// service names such as "http" are intentionally rejected.
	_, port, err := net.SplitHostPort(value)
	if err != nil {
		return "", &FieldError{Field: "API_ADDR", Err: ErrInvalid}
	}
	parsedPort, err := strconv.ParseUint(port, 10, 16)
	if err != nil || parsedPort == 0 {
		return "", &FieldError{Field: "API_ADDR", Err: ErrInvalid}
	}

	return value, nil
}

func invalidOrMissing(field, value string) error {
	if value == "" {
		return &FieldError{Field: field, Err: ErrMissing}
	}

	return &FieldError{Field: field, Err: ErrInvalid}
}
