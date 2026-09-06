package indexer

import "time"

// Health is the read-only operational snapshot exposed by the runtime. Writers
// update it only after a transaction outcome is known.
type Health struct {
	ChainID, Observed, Safe, Finalized int64
	ObservedAt, SafeAt, FinalizedAt    time.Time
	ObservedLag, SafeLag, FinalizedLag time.Duration
	OwnershipHeld, RPCHealthy          bool
	DirtyWork                          int64
	LastReorgID                        int64
	LastReorgDepth                     int64
	LastReorgAt                        time.Time
	PhaseCounts                        map[string]int64
	LastError                          string
}

type HealthTracker struct{ snapshot Health }

func (h *HealthTracker) Set(snapshot Health) {
	snapshot.PhaseCounts = cloneCounts(snapshot.PhaseCounts)
	h.snapshot = snapshot
}
func (h *HealthTracker) Snapshot() Health {
	snapshot := h.snapshot
	snapshot.PhaseCounts = cloneCounts(snapshot.PhaseCounts)
	return snapshot
}
func cloneCounts(source map[string]int64) map[string]int64 {
	if source == nil {
		return nil
	}
	result := make(map[string]int64, len(source))
	for key, value := range source {
		result[key] = value
	}
	return result
}
