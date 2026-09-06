package main

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/Contictus/launchtap/backend/deployments"
	"github.com/Contictus/launchtap/backend/internal/chain"
	"github.com/Contictus/launchtap/backend/internal/config"
	"github.com/Contictus/launchtap/backend/internal/indexer"
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
	defer owner.Close()
	decoder, err := chain.NewDecoder(deployment.EngineVersion)
	if err != nil {
		return err
	}
	discovery, err := chain.NewDiscoverer(source, decoder, deployment.Factory, c.IndexerLogAddressBatchSize)
	if err != nil {
		return err
	}
	store := storepostgres.IndexerStore{Pool: pool, Beginner: owner.Beginner()}
	router := indexer.LedgerRouter{Sink: storepostgres.NewAdapter(owner.DBTX()), ChainID: int64(c.ChainID)}
	engine, err := indexer.New(indexer.Settings{ChainID: int64(c.ChainID), DeploymentID: c.DeploymentID, Factory: deployment.Factory, StartBlock: int64(deployment.StartBlock), ChunkSize: int64(c.IndexerChunkSize), PollInterval: c.IndexerPollInterval}, store, source, discovery, decoder, router)
	if err != nil {
		return err
	}
	go func() {
		if err := owner.Watch(ctx); err != nil && !errors.Is(err, context.Canceled) {
			stop()
		}
	}()
	slog.Info("indexer started", "chain_id", c.ChainID, "deployment_id", c.DeploymentID, "start_block", deployment.StartBlock, "started_at", time.Now().UTC())
	return engine.Run(ctx)
}
