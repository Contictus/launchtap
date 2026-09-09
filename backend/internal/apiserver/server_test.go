package apiserver

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthAndReadiness(t *testing.T) {
	s := New(DefaultConfig(), ReadyFunc(func(context.Context) error { return nil }), nil)
	for _, path := range []string{"/healthz", "/v1/healthz", "/readyz", "/v1/readyz"} {
		r := httptest.NewRequest(http.MethodGet, path, nil)
		w := httptest.NewRecorder()
		s.Handler.ServeHTTP(w, r)
		if w.Code != http.StatusOK {
			t.Fatalf("%s status=%d", path, w.Code)
		}
		if w.Header().Get("X-Request-ID") == "" {
			t.Fatalf("%s missing request id", path)
		}
	}
}

func TestReadinessFailureIsProblem(t *testing.T) {
	s := New(DefaultConfig(), ReadyFunc(func(context.Context) error { return context.Canceled }), nil)
	w := httptest.NewRecorder()
	s.Handler.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("status=%d", w.Code)
	}
	if got := w.Header().Get("Content-Type"); got != "application/problem+json" {
		t.Fatalf("content type=%q", got)
	}
}

func TestCanonicalUint256(t *testing.T) {
	for _, value := range []string{"", "01", "-1", "1.0", "1e3", "+1"} {
		if _, err := parseCanonicalUint256(value); err == nil {
			t.Fatalf("accepted %q", value)
		}
	}
	if n, err := parseCanonicalUint256("0"); err != nil || n.Sign() != 0 {
		t.Fatalf("zero: %v", err)
	}
}
