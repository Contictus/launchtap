package apiserver

import (
	"bytes"
	"context"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
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

func TestServerBoundaries(t *testing.T) {
	cfg := DefaultConfig()
	cfg.AllowedOrigins = []string{"https://app.example"}
	var logs bytes.Buffer
	s := New(cfg, ReadyFunc(func(context.Context) error { return nil }), slog.New(slog.NewJSONHandler(&logs, nil)))
	if s.HTTP.ReadHeaderTimeout != 5*time.Second || s.HTTP.ReadTimeout != 15*time.Second || s.HTTP.WriteTimeout != 15*time.Second || s.HTTP.IdleTimeout != 60*time.Second || s.HTTP.MaxHeaderBytes != 32<<10 {
		t.Fatal("server timeout or header limits changed")
	}
	req := httptest.NewRequest(http.MethodOptions, "/v1/healthz", nil)
	req.Header.Set("Origin", "https://app.example")
	req.Header.Set("Authorization", "Bearer secret")
	w := httptest.NewRecorder()
	s.Handler.ServeHTTP(w, req)
	if w.Code != http.StatusNoContent || w.Header().Get("Access-Control-Allow-Origin") != "https://app.example" {
		t.Fatalf("preflight status=%d headers=%v", w.Code, w.Header())
	}
	if strings.Contains(logs.String(), "secret") {
		t.Fatal("access log leaked authorization")
	}
	bad := httptest.NewRequest(http.MethodOptions, "/v1/healthz", nil)
	bad.Header.Set("Origin", "https://evil.example")
	badW := httptest.NewRecorder()
	s.Handler.ServeHTTP(badW, bad)
	if badW.Code != http.StatusForbidden {
		t.Fatalf("disallowed origin status=%d", badW.Code)
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
