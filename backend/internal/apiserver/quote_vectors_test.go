package apiserver_test

import (
	"bytes"
	"context"
	"encoding/json"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/Contictus/launchtap/backend/internal/apiserver"
	"github.com/Contictus/launchtap/backend/internal/curve"
	"github.com/Contictus/launchtap/backend/internal/pagination"
	"github.com/Contictus/launchtap/backend/internal/quote"
	"github.com/Contictus/launchtap/backend/internal/token"
	"github.com/ethereum/go-ethereum/common"
)

type vectorReader struct{ state token.QuoteState }

func (r vectorReader) ReadQuoteState(context.Context, int64, common.Address) (token.QuoteState, error) {
	return r.state, nil
}
func amount(s string) *big.Int { n, _ := new(big.Int).SetString(s, 10); return n }

func TestQuoteHTTPReplaysSolidityVectors(t *testing.T) {
	artifact, err := curve.LoadEmbeddedVectors()
	if err != nil {
		t.Fatal(err)
	}
	p := artifact.Parameters
	for _, tc := range artifact.Cases {
		tc := tc
		t.Run(tc.ID, func(t *testing.T) {
			phase := "curve"
			if tc.InitialState.Phase != "curve" {
				phase = "graduated"
			}
			state := token.QuoteState{Detail: token.Detail{Summary: token.Summary{TotalSupply: amount(p.TotalSupply), Phase: phase}, CurveTokens: amount(p.CurveTokens), LPTokens: amount(p.LPTokens), GraduationETH: amount(p.GraduationETH), InitialVirtualETH: amount(p.InitialVirtualETH), InitialVirtualToken: amount(p.InitialVirtualToken), TradeFeeBPS: uint16(p.TradeFeeBPS), ProtocolShareBPS: uint16(p.ProtocolShareBPS), ETHReserve: amount(tc.InitialState.VirtualETH), TokenReserve: amount(tc.InitialState.VirtualToken), ReserveHash: common.HexToHash("0x01"), ReserveBlock: 1, Snapshot: pagination.Snapshot{ChainID: 1, BlockNumber: 1, BlockHash: [32]byte{31: 1}}, Finality: "safe"}, ProtocolFees: amount(tc.InitialState.ProtocolFees), CreatorFees: amount(tc.InitialState.CreatorFees)}
			s := apiserver.New(apiserver.DefaultConfig(), apiserver.ReadyFunc(func(context.Context) error { return nil }), nil)
			s.RegisterQuoteRoutes(apiserver.QuoteRoutes{Provider: quote.Service{Reader: vectorReader{state: state}, ChainID: 1}})
			side := "buy"
			input := tc.Input.ETHGross
			if tc.Operation == "sell" {
				side = "sell"
				input = tc.Input.TokensIn
			}
			body, _ := json.Marshal(map[string]string{"side": side, "amount": input})
			req := httptest.NewRequest(http.MethodPost, "/v1/tokens/0x0000000000000000000000000000000000000001/quote", bytes.NewReader(body))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()
			s.Handler.ServeHTTP(w, req)
			if tc.ExpectedRevert != nil {
				wantStatus, wantType := http.StatusBadRequest, "zero_input"
				switch tc.ExpectedRevert.Name {
				case "Oversell":
					wantStatus, wantType = http.StatusUnprocessableEntity, "oversell"
				case "ZeroOutput":
					wantStatus, wantType = http.StatusUnprocessableEntity, "zero_output"
				}
				if w.Code != wantStatus || !strings.Contains(w.Body.String(), "urn:launchpad:problem:"+wantType) {
					t.Fatalf("status=%d want=%d body=%s", w.Code, wantStatus, w.Body.String())
				}
				return
			}
			if w.Code != http.StatusOK {
				t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
			}
			var got map[string]any
			if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
				t.Fatal(err)
			}
			wantOutput := tc.Output.TokenAmount
			if tc.Operation == "sell" {
				wantOutput = tc.Output.ETHOut
			}
			want := map[string]any{
				"input": input, "output": wantOutput, "protocol_fee": tc.Output.ProtocolFee,
				"creator_fee": tc.Output.CreatorFee, "refund": tc.Output.ETHRefund,
				"graduates": tc.Output.Graduates, "next_virtual_eth": tc.NextState.VirtualETH,
				"next_virtual_token": tc.NextState.VirtualToken, "finality": "safe",
				"reserve_source_hash": common.HexToHash("0x01").Hex(), "informational": true,
			}
			for field, expected := range want {
				if got[field] != expected {
					t.Fatalf("%s=%v want=%v body=%s", field, got[field], expected, w.Body.String())
				}
			}
			if got["as_of_block"] != float64(1) || got["reserve_source_block"] != float64(1) {
				t.Fatalf("snapshot metadata=%v", got)
			}
		})
	}
}

func TestQuoteHTTPMapsWrongPhase(t *testing.T) {
	artifact, err := curve.LoadEmbeddedVectors()
	if err != nil {
		t.Fatal(err)
	}
	p := artifact.Parameters
	state := token.QuoteState{Detail: token.Detail{Summary: token.Summary{TotalSupply: amount(p.TotalSupply), Phase: "graduated"}, CurveTokens: amount(p.CurveTokens), LPTokens: amount(p.LPTokens), GraduationETH: amount(p.GraduationETH), InitialVirtualETH: amount(p.InitialVirtualETH), InitialVirtualToken: amount(p.InitialVirtualToken), TradeFeeBPS: uint16(p.TradeFeeBPS), ProtocolShareBPS: uint16(p.ProtocolShareBPS), ETHReserve: amount(p.InitialVirtualETH), TokenReserve: amount(p.InitialVirtualToken)}, ProtocolFees: new(big.Int), CreatorFees: new(big.Int)}
	s := apiserver.New(apiserver.DefaultConfig(), apiserver.ReadyFunc(func(context.Context) error { return nil }), nil)
	s.RegisterQuoteRoutes(apiserver.QuoteRoutes{Provider: quote.Service{Reader: vectorReader{state: state}, ChainID: 1}})
	body := bytes.NewBufferString(`{"side":"buy","amount":"1"}`)
	req := httptest.NewRequest(http.MethodPost, "/v1/tokens/0x0000000000000000000000000000000000000001/quote", body)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	s.Handler.ServeHTTP(w, req)
	if w.Code != http.StatusConflict || !strings.Contains(w.Body.String(), "urn:launchpad:problem:wrong_phase") {
		t.Fatalf("status=%d body=%s", w.Code, w.Body.String())
	}
}
