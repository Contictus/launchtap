// Package realtime distributes best-effort refresh hints to API clients.
package realtime

import (
	"encoding/json"
	"errors"
	"sync"
	"sync/atomic"
)

var ErrCapacity = errors.New("SSE subscriber capacity reached")

type Event struct {
	Type           string `json:"type"`
	ChainID        int64  `json:"chain_id"`
	DeploymentID   string `json:"deployment_id"`
	Token          string `json:"token,omitempty"`
	AsOfBlock      int64  `json:"as_of_block,omitempty"`
	AsOfBlockHash  string `json:"as_of_block_hash,omitempty"`
	CommonAncestor int64  `json:"common_ancestor,omitempty"`
}

func Decode(data []byte) (Event, error) {
	var event Event
	if err := json.Unmarshal(data, &event); err != nil {
		return Event{}, err
	}
	if event.Type != "launch" && event.Type != "token" && event.Type != "reorg" {
		return Event{}, errors.New("unknown refresh event type")
	}
	if event.ChainID <= 0 || event.DeploymentID == "" {
		return Event{}, errors.New("refresh event scope is invalid")
	}
	return event, nil
}

type Subscription struct {
	C      <-chan Event
	cancel func()
	once   sync.Once
}

func (s *Subscription) Close() { s.once.Do(s.cancel) }

type Hub struct {
	mu          sync.Mutex
	subscribers map[uint64]chan Event
	nextID      uint64
	maximum     int
	buffer      int
	evictions   atomic.Uint64
	active      atomic.Int64
}

func NewHub(maximum, buffer int) *Hub {
	if maximum <= 0 {
		maximum = 1000
	}
	if buffer <= 0 {
		buffer = 16
	}
	return &Hub{subscribers: make(map[uint64]chan Event), maximum: maximum, buffer: buffer}
}

func (h *Hub) Subscribe() (*Subscription, error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if len(h.subscribers) >= h.maximum {
		return nil, ErrCapacity
	}
	h.nextID++
	id := h.nextID
	channel := make(chan Event, h.buffer)
	h.subscribers[id] = channel
	h.active.Add(1)
	return &Subscription{C: channel, cancel: func() { h.remove(id) }}, nil
}

func (h *Hub) Publish(event Event) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for id, channel := range h.subscribers {
		select {
		case channel <- event:
		default:
			delete(h.subscribers, id)
			close(channel)
			h.active.Add(-1)
			h.evictions.Add(1)
		}
	}
}

func (h *Hub) remove(id uint64) {
	h.mu.Lock()
	defer h.mu.Unlock()
	channel, ok := h.subscribers[id]
	if !ok {
		return
	}
	delete(h.subscribers, id)
	close(channel)
	h.active.Add(-1)
}

func (h *Hub) Active() int64     { return h.active.Load() }
func (h *Hub) Evictions() uint64 { return h.evictions.Load() }
