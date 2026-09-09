package apiserver

import (
	"context"
	"math/big"
	"net/http"
	"strings"

	"github.com/Contictus/launchtap/backend/internal/curve"
	"github.com/danielgtaylor/huma/v2"
	"github.com/ethereum/go-ethereum/common"
)

type QuoteProvider interface {
	Quote(context.Context, common.Address, bool, *big.Int) (QuoteResult, error)
}
type QuoteResult struct {
	Input, Output, ProtocolFee, CreatorFee, Refund *big.Int
	Graduates                                      bool
	NextVirtualETH, NextVirtualToken               *big.Int
	Phase                                          string
	AsOfBlock                                      int64
	Finality                                       string
	ReserveSourceBlock                             int64
	ReserveSourceHash                              common.Hash
}
type QuoteRoutes struct{ Provider QuoteProvider }
type quoteInput struct {
	Token  string `path:"token"`
	Side   string `query:"side"`
	Amount string `query:"amount"`
}
type quoteOutput struct{ Body quoteBody }
type quoteBody struct {
	Input            string `json:"input"`
	Output           string `json:"output"`
	ProtocolFee      string `json:"protocol_fee"`
	CreatorFee       string `json:"creator_fee"`
	Refund           string `json:"refund"`
	Graduates        bool   `json:"graduates"`
	NextVirtualETH   string `json:"next_virtual_eth"`
	NextVirtualToken string `json:"next_virtual_token"`
	AsOfBlock        int64  `json:"as_of_block"`
	Finality         string `json:"finality"`
	Informational    bool   `json:"informational"`
}

func (r QuoteRoutes) Register(api huma.API) {
	huma.Register(api, huma.Operation{OperationID: "quoteCurve", Method: http.MethodGet, Path: "/tokens/{token}/quote", Tags: []string{"quotes"}}, r.handle)
}
func (r QuoteRoutes) handle(ctx context.Context, in *quoteInput) (*quoteOutput, error) {
	if r.Provider == nil {
		return nil, huma.Error503ServiceUnavailable("quote provider unavailable")
	}
	if !common.IsHexAddress(in.Token) {
		return nil, huma.Error400BadRequest("invalid token address")
	}
	amount, err := parseCanonicalUint256(in.Amount)
	if err != nil {
		return nil, huma.Error400BadRequest("amount must be a canonical uint256")
	}
	side := strings.ToLower(in.Side)
	if side != "buy" && side != "sell" {
		return nil, huma.Error400BadRequest("side must be buy or sell")
	}
	q, err := r.Provider.Quote(ctx, common.HexToAddress(in.Token), side == "buy", amount)
	if err != nil {
		return nil, huma.Error400BadRequest(err.Error())
	}
	return &quoteOutput{Body: quoteBody{Input: decimal(q.Input), Output: decimal(q.Output), ProtocolFee: decimal(q.ProtocolFee), CreatorFee: decimal(q.CreatorFee), Refund: decimal(q.Refund), Graduates: q.Graduates, NextVirtualETH: decimal(q.NextVirtualETH), NextVirtualToken: decimal(q.NextVirtualToken), AsOfBlock: q.AsOfBlock, Finality: q.Finality, Informational: true}}, nil
}
func parseCanonicalUint256(s string) (*big.Int, error) {
	if s == "" || (len(s) > 1 && s[0] == '0') || s[0] == '-' || strings.ContainsAny(s, ".+eE") {
		return nil, curve.ErrInvalidAmount{Field: "amount"}
	}
	n, ok := new(big.Int).SetString(s, 10)
	if !ok || n.Sign() < 0 || n.BitLen() > 256 {
		return nil, curve.ErrInvalidAmount{Field: "amount"}
	}
	return n, nil
}
