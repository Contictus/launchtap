package indexer

import (
	"context"
	"errors"
)

var ErrUnknownTransactionOutcome = errors.New("transaction outcome is unknown")
var ErrOwnershipLost = errors.New("indexer ownership lost")

// ExitCode maps process errors to an orchestrator-visible result. An unknown
// commit outcome is always non-zero so the process is restarted and replayed.
func ExitCode(err error) int {
	if err == nil {
		return 0
	}
	if errors.Is(err, context.Canceled) {
		return 0
	}
	return 1
}
