package stats

import (
	"context"
	"time"
)

const DefaultDirtyPollInterval = 5 * time.Second
const DefaultClaimLease = 30 * time.Second

type Claim struct {
	ChainID    int64
	Token      [20]byte
	Generation int64
}
type DirtySource interface {
	Poll(context.Context) ([]Claim, error)
	Claim(context.Context, string, int32) ([]Claim, error)
	Compute(context.Context, Claim) error
	Complete(context.Context, Claim, string) (bool, error)
}

// Worker treats notifications as hints and polls the durable dirty table on a
// fixed interval. A lost NOTIFY therefore delays work only until the next poll.
type Worker struct {
	Source       DirtySource
	WorkerID     string
	PollInterval time.Duration
	BatchSize    int32
	Wake         <-chan struct{}
}

func (w Worker) Run(ctx context.Context) error {
	interval := w.PollInterval
	if interval <= 0 {
		interval = DefaultDirtyPollInterval
	}
	batch := w.BatchSize
	if batch <= 0 {
		batch = 32
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		if err := w.drain(ctx, batch); err != nil {
			return err
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		case <-w.Wake:
		}
	}
}
func (w Worker) drain(ctx context.Context, batch int32) error {
	claims, err := w.Source.Claim(ctx, w.WorkerID, batch)
	if err != nil {
		return err
	}
	for _, claim := range claims {
		if err := w.Source.Compute(ctx, claim); err != nil {
			return err
		}
		if _, err := w.Source.Complete(ctx, claim, w.WorkerID); err != nil {
			return err
		}
	}
	return nil
}
