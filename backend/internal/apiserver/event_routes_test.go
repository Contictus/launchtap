package apiserver

import (
	"bufio"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/Contictus/launchtap/backend/internal/realtime"
)

func TestSSEInitialRetryEventHeartbeatAndCancellation(t *testing.T) {
	hub := realtime.NewHub(4, 2)
	server := New(DefaultConfig(), ReadyFunc(func(context.Context) error { return nil }), nil)
	server.RegisterEventRoutes(EventRoutes{Hub: hub, ChainID: 46630, DeploymentID: "testnet", Heartbeat: 20 * time.Millisecond})
	httpServer := httptest.NewServer(server.Handler)
	defer httpServer.Close()
	ctx, cancel := context.WithCancel(t.Context())
	request, _ := http.NewRequestWithContext(ctx, http.MethodGet, httpServer.URL+"/v1/events", nil)
	request.Header.Set("Last-Event-ID", "ignored")
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = response.Body.Close() })
	if response.StatusCode != http.StatusOK || !strings.HasPrefix(response.Header.Get("Content-Type"), "text/event-stream") {
		t.Fatalf("status=%d content-type=%q", response.StatusCode, response.Header.Get("Content-Type"))
	}
	reader := bufio.NewReader(response.Body)
	initial := readUntil(t, reader, "refresh-only", time.Second)
	if !strings.Contains(initial, "retry: 3000") {
		t.Fatalf("initial=%q", initial)
	}
	heartbeat := readUntil(t, reader, "heartbeat", time.Second)
	if !strings.Contains(heartbeat, ": heartbeat") {
		t.Fatalf("heartbeat=%q", heartbeat)
	}
	for deadline := time.Now().Add(time.Second); hub.Active() != 1 && time.Now().Before(deadline); {
		time.Sleep(time.Millisecond)
	}
	hub.Publish(realtime.Event{Type: "token", ChainID: 46630, DeploymentID: "testnet", Token: "0xabc", AsOfBlock: 10})
	event := readUntil(t, reader, `"as_of_block":10`, time.Second)
	if !strings.Contains(event, "event: token") {
		t.Fatalf("event stream=%q", event)
	}
	cancel()
	_, _ = io.Copy(io.Discard, response.Body)
	for deadline := time.Now().Add(time.Second); hub.Active() != 0 && time.Now().Before(deadline); {
		time.Sleep(time.Millisecond)
	}
	if hub.Active() != 0 {
		t.Fatalf("active=%d", hub.Active())
	}
}

func TestSSEOutlivesServerWriteTimeout(t *testing.T) {
	hub := realtime.NewHub(2, 2)
	server := New(DefaultConfig(), ReadyFunc(func(context.Context) error { return nil }), nil)
	server.RegisterEventRoutes(EventRoutes{Hub: hub, ChainID: 46630, DeploymentID: "testnet", Heartbeat: 10 * time.Millisecond})
	httpServer := httptest.NewUnstartedServer(server.Handler)
	httpServer.Config.WriteTimeout = 30 * time.Millisecond
	httpServer.Start()
	defer httpServer.Close()

	ctx, cancel := context.WithCancel(t.Context())
	defer cancel()
	request, _ := http.NewRequestWithContext(ctx, http.MethodGet, httpServer.URL+"/v1/events", nil)
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = response.Body.Close() })
	reader := bufio.NewReader(response.Body)
	readUntil(t, reader, "refresh-only", time.Second)
	time.Sleep(60 * time.Millisecond)
	hub.Publish(realtime.Event{Type: "token", ChainID: 46630, DeploymentID: "testnet", Token: "0xabc", AsOfBlock: 11})
	event := readUntil(t, reader, `"as_of_block":11`, time.Second)
	if !strings.Contains(event, "event: token") {
		t.Fatalf("event stream=%q", event)
	}
	cancel()
	_ = response.Body.Close()
}

func readUntil(t *testing.T, reader *bufio.Reader, wanted string, timeout time.Duration) string {
	t.Helper()
	result := make(chan string, 1)
	go func() {
		var value strings.Builder
		for {
			line, err := reader.ReadString('\n')
			value.WriteString(line)
			if strings.Contains(value.String(), wanted) || err != nil {
				result <- value.String()
				return
			}
		}
	}()
	select {
	case value := <-result:
		return value
	case <-time.After(timeout):
		t.Fatalf("timed out waiting for %q", wanted)
		return ""
	}
}
