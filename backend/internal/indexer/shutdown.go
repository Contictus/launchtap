package indexer

import "errors"

var ErrUnknownTransactionOutcome = errors.New("transaction outcome is unknown")

// ExitCode maps process errors to an orchestrator-visible result. An unknown
// commit outcome is always non-zero so the process is restarted and replayed.
func ExitCode(err error) int {
	if err == nil {
		return 0
	}
	return 1
}
