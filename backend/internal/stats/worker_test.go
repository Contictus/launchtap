package stats

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestWorkerRetriesFailedClaimAndHonorsCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	wake := make(chan struct{}, 1)
	claim := Claim{ChainID: 4663, Token: [20]byte{1}, Generation: 7}
	source := &workerTestSource{claim: claim, cancel: cancel}
	workerErrors := make(chan error, 1)
	worker := Worker{
		Source:    source,
		WorkerID:  "worker-test",
		BatchSize: 1,
		Wake:      wake,
		OnError:   func(got Claim, err error) { workerErrors <- err },
	}

	done := make(chan error, 1)
	go func() { done <- worker.Run(ctx) }()

	select {
	case err := <-workerErrors:
		if !errors.Is(err, errTestCompute) {
			t.Fatalf("OnError received %v, want %v", err, errTestCompute)
		}
	case <-time.After(time.Second):
		t.Fatal("worker did not report the compute error")
	}
	wake <- struct{}{}

	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("Run returned %v, want context cancellation", err)
		}
	case <-time.After(time.Second):
		t.Fatal("worker did not stop after cancellation")
	}
	if source.claimCalls != 2 || source.computeCalls != 2 || source.completeCalls != 1 {
		t.Fatalf("calls: claim=%d compute=%d complete=%d; want 2, 2, 1",
			source.claimCalls, source.computeCalls, source.completeCalls)
	}
}

var errTestCompute = errors.New("test compute failure")

type workerTestSource struct {
	claim         Claim
	cancel        context.CancelFunc
	claimCalls    int
	computeCalls  int
	completeCalls int
}

func (source *workerTestSource) Claim(context.Context, string, int32) ([]Claim, error) {
	source.claimCalls++
	return []Claim{source.claim}, nil
}

func (source *workerTestSource) Compute(context.Context, Claim) error {
	source.computeCalls++
	if source.computeCalls == 1 {
		return errTestCompute
	}
	return nil
}

func (source *workerTestSource) Complete(context.Context, Claim, string) (bool, error) {
	source.completeCalls++
	source.cancel()
	return true, nil
}
