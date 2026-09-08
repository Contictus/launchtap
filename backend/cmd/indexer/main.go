package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/Contictus/launchtap/backend/deployments"
	"github.com/Contictus/launchtap/backend/internal/chain"
	"github.com/Contictus/launchtap/backend/internal/config"
	"github.com/Contictus/launchtap/backend/internal/indexer"
	"github.com/Contictus/launchtap/backend/internal/stats"
	storepostgres "github.com/Contictus/launchtap/backend/internal/store/postgres"
)

func main() {
	if err := run(); err != nil {
		slog.Error("indexer stopped", "error", err)
		os.Exit(indexer.ExitCode(err))
	}
}
func run() error {
	c, err := config.Load(os.Getenv)
	if err != nil {
		return err
	}
	if err := c.RequireIndexer(); err != nil {
		return err
	}
	registry, err := deployments.LoadEmbedded()
	if err != nil {
		return err
	}
	deployment, err := registry.Resolve(c.ChainID, c.DeploymentID, c.IndexerConfirmations)
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	source, err := chain.Dial(ctx, c.RPCURL, chain.RPCConfig{Timeout: c.RPCTimeout, MaxRetries: c.RPCMaxRetries, RetryBackoff: c.RPCRetryBackoff})
	if err != nil {
		return err
	}
	defer source.Close()
	pool, err := storepostgres.OpenPool(ctx, c.DatabaseURL, storepostgres.PoolOptions{})
	if err != nil {
		return err
	}
	defer pool.Close()
	owner, err := storepostgres.AcquireOwnership(ctx, c.DatabaseURL, int64(c.ChainID), c.DeploymentID)
	if err != nil {
		return err
	}
	defer func() { _ = owner.Close() }()
	decoder, err := chain.NewDecoder(deployment.EngineVersion)
	if err != nil {
		return err
	}
	discovery, err := chain.NewDiscoverer(source, decoder, deployment.Factory, c.IndexerLogAddressBatchSize)
	if err != nil {
		return err
	}
	store := storepostgres.IndexerStore{Pool: pool, Beginner: owner.Beginner(), ChainID: int64(c.ChainID), DeploymentID: c.DeploymentID}
	router := indexer.LedgerRouter{ChainID: int64(c.ChainID)}
	engine, err := indexer.New(indexer.Settings{ChainID: int64(c.ChainID), DeploymentID: c.DeploymentID, Factory: deployment.Factory, StartBlock: int64(deployment.StartBlock), ChunkSize: int64(c.IndexerChunkSize), PollInterval: c.IndexerPollInterval}, store, source, discovery, decoder, router)
	if err != nil {
		return err
	}
	watchErrors := make(chan error, 1)
	go func() {
		if err := owner.Watch(ctx); err != nil && !errors.Is(err, context.Canceled) {
			watchErrors <- err
			stop()
		}
	}()
	wake := make(chan struct{}, 1)
	health := new(indexer.HealthTracker)
	health.Set(indexer.Health{ChainID: int64(c.ChainID), OwnershipHeld: true, RPCHealthy: true})
	healthServer := &http.Server{Addr: c.APIAddr, Handler: indexer.HealthHandler(health)}
	go func() {
		if err := healthServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Warn("health server stopped", "error", err)
		}
	}()
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = healthServer.Shutdown(shutdownCtx)
	}()
	aggregation := stats.Worker{Source: storepostgres.AggregationSource{Adapter: storepostgres.NewAdapter(pool), ChainID: int64(c.ChainID)}, WorkerID: c.IndexerWorkerID, PollInterval: stats.DefaultDirtyPollInterval, BatchSize: 32, Wake: wake, OnError: func(claim stats.Claim, err error) {
		slog.Error("aggregation compute failed", "chain_id", claim.ChainID, "token", fmt.Sprintf("%x", claim.Token), "error", err)
	}}
	go func() {
		if err := storepostgres.ListenMarketDirty(ctx, pool, wake); err != nil && !errors.Is(err, context.Canceled) {
			slog.Warn("market dirty listener stopped", "error", err)
		}
	}()
	aggregationErrors := make(chan error, 1)
	go func() {
		if err := aggregation.Run(ctx); err != nil && !errors.Is(err, context.Canceled) {
			aggregationErrors <- err
			stop()
		}
	}()
	slog.Info("indexer started", "chain_id", c.ChainID, "deployment_id", c.DeploymentID, "start_block", deployment.StartBlock, "started_at", time.Now().UTC())
	runErr := engine.Run(ctx)
	select {
	case err := <-watchErrors:
		return fmt.Errorf("ownership watchdog: %w", err)
	case err := <-aggregationErrors:
		return fmt.Errorf("aggregation worker: %w", err)
	default:
	}
	return runErr
}
