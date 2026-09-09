// Package apiserver owns the HTTP boundary. Huma and net/http types stop here.
package apiserver

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"github.com/danielgtaylor/huma/v2/adapters/humago"
)

type Config struct {
	AllowedOrigins                                                             []string
	ReadHeaderTimeout, ReadTimeout, WriteTimeout, IdleTimeout, ShutdownTimeout time.Duration
}

func DefaultConfig() Config {
	return Config{ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 15 * time.Second, IdleTimeout: 60 * time.Second, ShutdownTimeout: 5 * time.Second}
}

type Readiness interface{ Ready(context.Context) error }
type ReadyFunc func(context.Context) error

func (f ReadyFunc) Ready(ctx context.Context) error { return f(ctx) }

type Server struct {
	Handler http.Handler
	HTTP    *http.Server
	API     huma.API
}

type HealthResponse struct {
	Status string `json:"status"`
}
type humaHealthOutput struct {
	Status int `status:"200" json:"-"`
	Body   HealthResponse
}

func New(cfg Config, ready Readiness, logger *slog.Logger) *Server {
	if logger == nil {
		logger = slog.Default()
	}
	mux := http.NewServeMux()
	api := humago.NewWithPrefix(mux, "/v1", huma.DefaultConfig("Launchpad API", "1.0.0"))
	huma.Register(api, huma.Operation{OperationID: "healthz", Method: http.MethodGet, Path: "/healthz", Tags: []string{"system"}}, func(context.Context, *struct{}) (*humaHealthOutput, error) {
		return &humaHealthOutput{Status: http.StatusOK, Body: HealthResponse{Status: "ok"}}, nil
	})
	huma.Register(api, huma.Operation{OperationID: "readyz", Method: http.MethodGet, Path: "/readyz", Tags: []string{"system"}}, func(ctx context.Context, _ *struct{}) (*humaHealthOutput, error) {
		if ready == nil {
			return nil, huma.Error503ServiceUnavailable("readiness unavailable")
		}
		if err := ready.Ready(ctx); err != nil {
			return nil, huma.Error503ServiceUnavailable("service not ready")
		}
		return &humaHealthOutput{Status: http.StatusOK, Body: HealthResponse{Status: "ready"}}, nil
	})
	// Keep orchestration endpoints available at their conventional root paths;
	// the versioned aliases are included in the generated contract.
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(HealthResponse{Status: "ok"})
	})
	mux.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
		if ready == nil || ready.Ready(r.Context()) != nil {
			problem(w, http.StatusServiceUnavailable, "service not ready", RequestID(r.Context()))
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(HealthResponse{Status: "ready"})
	})
	h := middleware(mux, cfg, logger)
	serverCfg := cfg
	if serverCfg.ReadHeaderTimeout <= 0 {
		serverCfg = DefaultConfig()
	}
	return &Server{Handler: h, API: api, HTTP: &http.Server{Handler: h, ReadHeaderTimeout: serverCfg.ReadHeaderTimeout, ReadTimeout: serverCfg.ReadTimeout, WriteTimeout: serverCfg.WriteTimeout, IdleTimeout: serverCfg.IdleTimeout}}
}

func (s *Server) RegisterTokenRoutes(r TokenRoutes)   { r.Register(s.API) }
func (s *Server) RegisterQuoteRoutes(r QuoteRoutes)   { r.Register(s.API) }
func (s *Server) RegisterCandleRoutes(r CandleRoutes) { r.Register(s.API) }

func (s *Server) Shutdown(ctx context.Context) error { return s.HTTP.Shutdown(ctx) }

type ctxKey string

const requestIDKey ctxKey = "request_id"

func RequestID(ctx context.Context) string { v, _ := ctx.Value(requestIDKey).(string); return v }

func middleware(next http.Handler, cfg Config, logger *slog.Logger) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := strings.TrimSpace(r.Header.Get("X-Request-ID"))
		if id == "" {
			id = fmt.Sprintf("%d", time.Now().UnixNano())
		}
		w.Header().Set("X-Request-ID", id)
		ctx, cancel := context.WithTimeout(context.WithValue(r.Context(), requestIDKey, id), cfg.ReadTimeout)
		defer cancel()
		r = r.WithContext(ctx)
		defer func() {
			if v := recover(); v != nil {
				problem(w, http.StatusInternalServerError, "internal server error", id)
				logger.Error("panic recovered", "request_id", id)
			}
		}()
		if r.Method == http.MethodOptions {
			cors(w, cfg.AllowedOrigins, r)
			w.WriteHeader(http.StatusNoContent)
			return
		}
		cors(w, cfg.AllowedOrigins, r)
		next.ServeHTTP(w, r)
	})
}
func cors(w http.ResponseWriter, origins []string, r *http.Request) {
	origin := r.Header.Get("Origin")
	for _, allowed := range origins {
		if allowed == origin && origin != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization,Content-Type,privy-id-token,If-Match")
			return
		}
	}
}
func problem(w http.ResponseWriter, status int, detail, requestID string) {
	w.Header().Set("Content-Type", "application/problem+json")
	w.Header().Set("X-Request-ID", requestID)
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"type": "about:blank", "title": http.StatusText(status), "status": status, "detail": detail, "request_id": requestID})
}
