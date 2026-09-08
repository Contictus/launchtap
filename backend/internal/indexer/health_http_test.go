package indexer

import (
	"net/http/httptest"
	"testing"
	"time"

	"github.com/Contictus/launchtap/backend/internal/ledger"
)

func TestHealthHandlerReturnsSnapshot(t *testing.T) {
	tracker := new(HealthTracker)
	tracker.Set(Health{ChainID: 46630, OwnershipHeld: true, RPCHealthy: true})
	tracker.Committed(State{ChainID: 46630, Observed: &ledger.IndexedBlock{BlockNumber: 12, BlockTime: time.Now().UTC()}})
	recorder := httptest.NewRecorder()
	HealthHandler(tracker).ServeHTTP(recorder, httptest.NewRequest("GET", "/healthz", nil))
	if recorder.Code != 200 || !contains(recorder.Body.String(), "46630") {
		t.Fatalf("unexpected health response: %s", recorder.Body.String())
	}
}

func TestHealthHandlerBecomesNotReadyAfterOwnershipLoss(t *testing.T) {
	tracker := new(HealthTracker)
	tracker.Set(Health{ChainID: 46630, OwnershipHeld: true, RPCHealthy: true})
	tracker.Committed(State{ChainID: 46630, Observed: &ledger.IndexedBlock{BlockNumber: 12, BlockTime: time.Now().UTC()}})
	tracker.OwnershipLost(assertionError("connection closed"))
	recorder := httptest.NewRecorder()
	HealthHandler(tracker).ServeHTTP(recorder, httptest.NewRequest("GET", "/healthz", nil))
	if recorder.Code != 503 || tracker.Snapshot().OwnershipHeld {
		t.Fatalf("ownership loss response = %d snapshot=%+v", recorder.Code, tracker.Snapshot())
	}
}

type assertionError string

func (e assertionError) Error() string { return string(e) }

func contains(s, part string) bool {
	for i := 0; i+len(part) <= len(s); i++ {
		if s[i:i+len(part)] == part {
			return true
		}
	}
	return false
}
