package indexer

import (
	"encoding/json"
	"net/http"
	"sync"
	"time"
)

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

type HealthTracker struct {
	mu       sync.RWMutex
	snapshot Health
}

func (h *HealthTracker) Set(snapshot Health) {
	h.mu.Lock()
	defer h.mu.Unlock()
	snapshot.PhaseCounts = cloneCounts(snapshot.PhaseCounts)
	h.snapshot = snapshot
}
func (h *HealthTracker) Snapshot() Health {
	h.mu.RLock()
	defer h.mu.RUnlock()
	snapshot := h.snapshot
	snapshot.PhaseCounts = cloneCounts(snapshot.PhaseCounts)
	return snapshot
}

// HealthHandler exposes the operational snapshot as JSON for orchestrators.
func HealthHandler(tracker *HealthTracker) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(tracker.Snapshot()); err != nil {
			return
		}
	})
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
