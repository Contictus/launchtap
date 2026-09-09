package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/Contictus/launchtap/backend/deployments"
	"github.com/Contictus/launchtap/backend/internal/apiserver"
	"github.com/Contictus/launchtap/backend/internal/config"
	storepostgres "github.com/Contictus/launchtap/backend/internal/store/postgres"
)

func main() {
	if err := run(); err != nil {
		slog.Error("api stopped", "error", err)
		os.Exit(1)
	}
}

func run() error {
	c, err := config.Load(os.Getenv)
	if err != nil {
		return err
	}
	registry, err := deployments.LoadEmbedded()
	if err != nil {
		return err
	}
	if _, err := registry.Resolve(c.ChainID, c.DeploymentID, c.IndexerConfirmations); err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	pool, err := storepostgres.OpenPool(ctx, c.DatabaseURL, storepostgres.PoolOptions{})
	if err != nil {
		return err
	}
	defer pool.Close()
	ready := apiserver.ReadyFunc(func(ctx context.Context) error { return pool.Ping(ctx) })
	server := apiserver.New(apiserver.DefaultConfig(), ready, slog.Default())
	server.RegisterTokenRoutes(apiserver.TokenRoutes{Reader: storepostgres.TokenReader{Pool: pool, DeploymentID: c.DeploymentID}, ChainID: int64(c.ChainID)})
	server.RegisterCandleRoutes(apiserver.CandleRoutes{Reader: storepostgres.CandleReader{Pool: pool, DeploymentID: c.DeploymentID}, ChainID: int64(c.ChainID)})
	errCh := make(chan error, 1)
	go func() { errCh <- http.ListenAndServe(c.APIAddr, server.Handler) }()
	select {
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), apiserver.DefaultConfig().ShutdownTimeout)
		defer cancel()
		return server.Shutdown(shutdownCtx)
	case err := <-errCh:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	}
}
