package quote

import (
	"context"
	"math/big"

	"github.com/Contictus/launchtap/backend/internal/curve"
	"github.com/Contictus/launchtap/backend/internal/token"
	"github.com/ethereum/go-ethereum/common"
)

type Service struct {
	Reader  token.QuoteReader
	ChainID int64
}

type Result struct {
	Input, Output, ProtocolFee, CreatorFee, Refund *big.Int
	Graduates                                      bool
	NextVirtualETH, NextVirtualToken               *big.Int
	AsOfBlock                                      int64
	Finality                                       string
	ReserveSourceBlock                             int64
	ReserveSourceHash                              common.Hash
}
type Provider interface {
	Quote(context.Context, common.Address, bool, *big.Int) (Result, error)
}

func (s Service) Quote(ctx context.Context, address common.Address, buy bool, amount *big.Int) (Result, error) {
	state, err := s.Reader.ReadQuoteState(ctx, s.ChainID, address)
	if err != nil {
		return Result{}, err
	}
	d := state.Detail
	p, err := curve.NewParameters(d.TotalSupply, d.CurveTokens, d.LPTokens, d.GraduationETH, d.InitialVirtualETH, d.InitialVirtualToken, d.TradeFeeBPS, d.ProtocolShareBPS)
	if err != nil {
		return Result{}, err
	}
	phase := curve.PhaseCurve
	if d.Phase == "graduated" {
		phase = curve.PhaseGraduated
	}
	cs, err := curve.NewState(phase, d.ETHReserve, d.TokenReserve, state.ProtocolFees, state.CreatorFees)
	if err != nil {
		return Result{}, err
	}
	result := Result{Input: new(big.Int).Set(amount), AsOfBlock: d.Snapshot.BlockNumber, Finality: d.Finality, ReserveSourceBlock: d.ReserveBlock, ReserveSourceHash: d.ReserveHash}
	if buy {
		q, e := curve.Buy(cs, p, amount)
		if e != nil {
			return result, e
		}
		n := q.NextState()
		result.Output = q.TokensOut()
		result.ProtocolFee = q.ProtocolFee()
		result.CreatorFee = q.CreatorFee()
		result.Refund = q.Refund()
		result.Graduates = q.Graduates()
		result.NextVirtualETH = n.VirtualETH()
		result.NextVirtualToken = n.VirtualToken()
		return result, nil
	}
	q, e := curve.Sell(cs, p, amount)
	if e != nil {
		return result, e
	}
	n := q.NextState()
	result.Output = q.ETHOut()
	result.ProtocolFee = q.ProtocolFee()
	result.CreatorFee = q.CreatorFee()
	result.Refund = new(big.Int)
	result.NextVirtualETH = n.VirtualETH()
	result.NextVirtualToken = n.VirtualToken()
	return result, nil
}
