package apiserver

import (
	"context"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/Contictus/launchtap/backend/internal/pagination"
	"github.com/Contictus/launchtap/backend/internal/token"
	"github.com/ethereum/go-ethereum/common"
)

type tokenReaderStub struct{ page token.Page }

func (s tokenReaderStub) List(context.Context, token.ListQuery) (token.Page, error) {
	return s.page, nil
}
func (s tokenReaderStub) Get(context.Context, int64, common.Address) (token.Detail, error) {
	return token.Detail{}, nil
}

func TestTokenListWireContract(t *testing.T) {
	snapshot := pagination.Snapshot{ChainID: 46630, BlockNumber: 42, BlockHash: [32]byte{31: 1}}
	reader := tokenReaderStub{page: token.Page{Items: []token.Summary{{Address: common.HexToAddress("0x0000000000000000000000000000000000000001"), Name: "Alpha", Symbol: "ALP", Phase: "curve", TotalSupply: big.NewInt(123), MarketCapETH: big.NewInt(456), Volume24hETH: big.NewInt(7)}}, Snapshot: snapshot, Finality: "safe"}}
	s := New(DefaultConfig(), ReadyFunc(func(context.Context) error { return nil }), nil)
	s.RegisterTokenRoutes(TokenRoutes{Reader: reader, ChainID: 46630})
	w := httptest.NewRecorder()
	s.Handler.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/v1/tokens?phase=curve&sort=newest", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
	body := w.Body.String()
	for _, want := range []string{`"total_supply":"123"`, `"as_of_block_hash":"0x0000000000000000000000000000000000000000000000000000000000000001"`, `"finality":"safe"`} {
		if !strings.Contains(body, want) {
			t.Fatalf("body missing %s: %s", want, body)
		}
	}
}
