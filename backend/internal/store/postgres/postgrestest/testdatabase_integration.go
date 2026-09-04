//go:build integration

package postgrestest

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/Contictus/launchtap/backend/internal/store/postgres"
	"github.com/Contictus/launchtap/backend/internal/store/postgres/migrations"
	"github.com/jackc/pgx/v5"
	"github.com/testcontainers/testcontainers-go"
	tcpostgres "github.com/testcontainers/testcontainers-go/modules/postgres"
)

const (
	postgresImage            = "postgres:18.6-alpine"
	dockerStartupTimeout     = 45 * time.Second
	databaseOperationTimeout = 15 * time.Second
	containerCleanupTimeout  = 30 * time.Second
)

// Database is an isolated PostgreSQL database owned by one test.
type Database struct {
	Name string
	URL  string
	DB   *sql.DB
}

// New creates an unmigrated database and registers all cleanup with the test.
func New(t testing.TB) *Database {
	t.Helper()

	serverURL := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if serverURL == "" {
		serverURL = startContainer(t)
	}

	databaseName, err := randomDatabaseName()
	if err != nil {
		t.Fatalf("create isolated database name: %v", err)
	}
	adminURL, err := databaseURL(serverURL, "postgres")
	if err != nil {
		t.Fatalf("create PostgreSQL maintenance URL: %v", err)
	}
	targetURL, err := databaseURL(serverURL, databaseName)
	if err != nil {
		t.Fatalf("create isolated database URL: %v", err)
	}

	createDatabase(t, adminURL, databaseName)

	database := &Database{Name: databaseName, URL: targetURL}
	t.Cleanup(func() {
		cleanupDatabase(t, database, adminURL)
	})

	database.DB, err = postgres.Open(targetURL)
	if err != nil {
		t.Fatalf("open isolated database %q: %v", databaseName, err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), databaseOperationTimeout)
	defer cancel()
	if err := database.DB.PingContext(ctx); err != nil {
		t.Fatalf("connect to isolated database %q: %v", databaseName, err)
	}

	return database
}

// NewMigrated creates an isolated database and applies all embedded migrations.
func NewMigrated(t testing.TB) *Database {
	t.Helper()

	database := New(t)
	ctx, cancel := context.WithTimeout(context.Background(), databaseOperationTimeout)
	defer cancel()
	if _, err := migrations.Run(ctx, database.DB, migrations.CommandUp); err != nil {
		t.Fatalf("migrate isolated database %q: %v", database.Name, err)
	}
	return database
}

func startContainer(t testing.TB) string {
	t.Helper()

	required := strings.EqualFold(strings.TrimSpace(os.Getenv("INTEGRATION_REQUIRED")), "true")
	healthCtx, healthCancel := context.WithTimeout(context.Background(), databaseOperationTimeout)
	healthErr := dockerHealth(healthCtx)
	healthCancel()
	if healthErr != nil {
		message := fmt.Sprintf("Docker is unavailable for PostgreSQL integration tests: %v", healthErr)
		if required {
			t.Fatal(message)
		}
		t.Skip(message)
	}

	ctx, cancel := context.WithTimeout(context.Background(), dockerStartupTimeout)
	defer cancel()
	container, err := tcpostgres.Run(
		ctx,
		postgresImage,
		tcpostgres.WithDatabase("postgres"),
		tcpostgres.WithUsername("postgres"),
		tcpostgres.WithPassword("postgres"),
		tcpostgres.BasicWaitStrategies(),
	)
	if err != nil {
		t.Fatalf("start %s test container: %v", postgresImage, err)
	}
	t.Cleanup(func() {
		cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), containerCleanupTimeout)
		defer cleanupCancel()
		if err := testcontainers.TerminateContainer(container, testcontainers.StopContext(cleanupCtx)); err != nil {
			t.Errorf("terminate PostgreSQL test container: %v", err)
		}
	})

	connectionString, err := container.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatalf("get PostgreSQL test-container URL: %v", err)
	}
	return connectionString
}

func dockerHealth(ctx context.Context) (err error) {
	defer func() {
		if recovered := recover(); recovered != nil {
			err = fmt.Errorf("docker provider panicked: %v", recovered)
		}
	}()

	provider, err := testcontainers.ProviderDocker.GetProvider()
	if err != nil {
		return err
	}
	defer func() {
		if closeErr := provider.Close(); err == nil && closeErr != nil {
			err = closeErr
		}
	}()
	return provider.Health(ctx)
}

func createDatabase(t testing.TB, adminURL, databaseName string) {
	t.Helper()

	adminDB, err := postgres.Open(adminURL)
	if err != nil {
		t.Fatalf("open PostgreSQL maintenance database: %v", err)
	}
	defer func() {
		if err := adminDB.Close(); err != nil {
			t.Errorf("close PostgreSQL maintenance database: %v", err)
		}
	}()

	ctx, cancel := context.WithTimeout(context.Background(), databaseOperationTimeout)
	defer cancel()
	if err := adminDB.PingContext(ctx); err != nil {
		t.Fatalf("connect to supplied PostgreSQL server: %v", err)
	}
	if _, err := adminDB.ExecContext(ctx, "CREATE DATABASE "+pgx.Identifier{databaseName}.Sanitize()); err != nil {
		t.Fatalf("create isolated database %q: %v", databaseName, err)
	}
}

func cleanupDatabase(t testing.TB, database *Database, adminURL string) {
	t.Helper()

	if database.DB != nil {
		if err := database.DB.Close(); err != nil {
			t.Errorf("close isolated database %q: %v", database.Name, err)
		}
	}

	adminDB, err := postgres.Open(adminURL)
	if err != nil {
		t.Errorf("open PostgreSQL maintenance database for cleanup: %v", err)
		return
	}
	defer func() {
		if err := adminDB.Close(); err != nil {
			t.Errorf("close PostgreSQL cleanup connection: %v", err)
		}
	}()

	ctx, cancel := context.WithTimeout(context.Background(), databaseOperationTimeout)
	defer cancel()
	statement := "DROP DATABASE IF EXISTS " + pgx.Identifier{database.Name}.Sanitize() + " WITH (FORCE)"
	if _, err := adminDB.ExecContext(ctx, statement); err != nil {
		t.Errorf("drop isolated database %q: %v", database.Name, err)
	}
}
