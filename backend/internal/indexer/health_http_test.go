package indexer

import (
	"net/http/httptest"
	"testing"
)

func TestHealthHandlerReturnsSnapshot(t *testing.T) {
	tracker := new(HealthTracker)
	tracker.Set(Health{ChainID: 46630, OwnershipHeld: true, RPCHealthy: true})
	recorder := httptest.NewRecorder()
	HealthHandler(tracker).ServeHTTP(recorder, httptest.NewRequest("GET", "/healthz", nil))
	if recorder.Code != 200 || !contains(recorder.Body.String(), "46630") {
		t.Fatalf("unexpected health response: %s", recorder.Body.String())
	}
}

func contains(s, part string) bool {
	for i := 0; i+len(part) <= len(s); i++ {
		if s[i:i+len(part)] == part {
			return true
		}
	}
	return false
}
