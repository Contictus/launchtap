package apiserver

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/Contictus/launchtap/backend/internal/observation"
	"github.com/Contictus/launchtap/backend/internal/pagination"
	"github.com/ethereum/go-ethereum/common"
)

type observationReaderStub struct {
	value observation.Observation
	err   error
}

func (s observationReaderStub) Get(context.Context, int64, string, common.Hash) (observation.Observation, error) {
	return s.value, s.err
}

func TestCanonicalObservationRequiresExactHash(t *testing.T) {
	hash := common.HexToHash("0x" + "11" + strings.Repeat("00", 31))
	block := common.HexToHash("0x" + "22" + strings.Repeat("00", 31))
	token := common.HexToAddress("0x" + "33" + strings.Repeat("00", 19))
	server := New(DefaultConfig(), ReadyFunc(func(context.Context) error { return nil }), nil)
	server.RegisterObservationRoutes(ObservationRoutes{
		Reader: observationReaderStub{value: observation.Observation{
			ChainID: 46630, DeploymentID: "testnet", Snapshot: pagination.Snapshot{ChainID: 46630, BlockNumber: 7, BlockHash: [32]byte(block)}, Finality: "safe",
			Events: []observation.Event{{Kind: "trade", TxHash: hash, Token: &token, BlockNumber: 7, BlockHash: block, Finality: "safe"}},
		}}, ChainID: 46630, DeploymentID: "testnet",
	})
	request := httptest.NewRequest(http.MethodGet, "/v1/transactions/0x"+hash.Hex()[2:], nil)
	response := httptest.NewRecorder()
	server.Handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
	var body struct {
		Events []struct {
			Kind     string  `json:"kind"`
			Token    *string `json:"token"`
			Finality string  `json:"finality"`
		} `json:"events"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if len(body.Events) != 1 || body.Events[0].Kind != "trade" || body.Events[0].Token == nil || body.Events[0].Finality != "safe" {
		t.Fatalf("body=%s", response.Body.String())
	}
}

func TestCanonicalObservationRejectsMalformedAndNotIndexed(t *testing.T) {
	server := New(DefaultConfig(), ReadyFunc(func(context.Context) error { return nil }), nil)
	server.RegisterObservationRoutes(ObservationRoutes{Reader: observationReaderStub{err: observation.ErrNotFound}, ChainID: 46630, DeploymentID: "testnet"})
	for path, status := range map[string]int{"/v1/transactions/0x1234": http.StatusBadRequest, "/v1/transactions/0x" + "44" + strings.Repeat("00", 31): http.StatusNotFound} {
		response := httptest.NewRecorder()
		server.Handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, path, nil))
		if response.Code != status {
			t.Fatalf("path=%s status=%d body=%s", path, response.Code, response.Body.String())
		}
	}
}
