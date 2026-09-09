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
	"github.com/Contictus/launchtap/backend/internal/quote"
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
	readyStore := storepostgres.NewAdapter(pool)
	ready := apiserver.ReadyFunc(func(ctx context.Context) error {
		if err := pool.Ping(ctx); err != nil {
			return err
		}
		state, err := readyStore.GetSyncState(ctx, int64(c.ChainID), c.DeploymentID)
		if err != nil {
			return err
		}
		if !state.ObservedNumber.Valid || state.ObservedHash == nil || !state.ObservedAt.Valid {
			return errors.New("indexed watermark is incomplete")
		}
		return nil
	})
	apiConfig := apiserver.DefaultConfig()
	apiConfig.AllowedOrigins = c.APIAllowedOrigins
	server := apiserver.New(apiConfig, ready, slog.Default())
	server.RegisterTokenRoutes(apiserver.TokenRoutes{Reader: storepostgres.TokenReader{Pool: pool, DeploymentID: c.DeploymentID}, ChainID: int64(c.ChainID)})
	server.RegisterCandleRoutes(apiserver.CandleRoutes{Reader: storepostgres.CandleReader{Pool: pool, DeploymentID: c.DeploymentID}, ChainID: int64(c.ChainID)})
	tokens := storepostgres.TokenReader{Pool: pool, DeploymentID: c.DeploymentID}
	market := storepostgres.MarketReader{Pool: pool, DeploymentID: c.DeploymentID}
	protocol := storepostgres.ProtocolReader{Pool: pool, DeploymentID: c.DeploymentID}
	server.RegisterPublicRoutes(apiserver.PublicRoutes{Tokens: tokens, Market: market, Protocol: protocol, ChainID: int64(c.ChainID)})
	server.RegisterQuoteRoutes(apiserver.QuoteRoutes{Provider: quote.Service{Reader: tokens, ChainID: int64(c.ChainID)}})
	server.HTTP.Addr = c.APIAddr
	errCh := make(chan error, 1)
	go func() { errCh <- server.HTTP.ListenAndServe() }()
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
