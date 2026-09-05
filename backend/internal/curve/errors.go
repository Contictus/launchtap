package curve

import (
	"errors"
	"fmt"
	"math/big"
)

var (
	ErrZeroInput            = errors.New("curve: zero input")
	ErrZeroOutput           = errors.New("curve: zero output")
	ErrArithmeticOverflow   = errors.New("curve: arithmetic overflow")
	ErrDivisionByZero       = errors.New("curve: division by zero")
	ErrInternalInvariant    = errors.New("curve: internal invariant violation")
	ErrInvalidGraduationETH = errors.New("curve: invalid graduation ETH")
)

// ErrInvalidAmount reports a nil, negative, or wider-than-uint256 amount.
type ErrInvalidAmount struct {
	Field string
}

func (err ErrInvalidAmount) Error() string {
	return fmt.Sprintf("curve: %s must be a uint256", err.Field)
}

// ErrInvalidSupplyAllocation mirrors InvalidSupplyAllocation.
type ErrInvalidSupplyAllocation struct {
	TotalSupply *big.Int
	CurveTokens *big.Int
	LPTokens    *big.Int
}

func (err ErrInvalidSupplyAllocation) Error() string {
	return "curve: total supply does not equal curve tokens plus LP tokens"
}

// ErrInvalidCurveAllocation mirrors InvalidCurveAllocation.
type ErrInvalidCurveAllocation struct {
	CurveTokens *big.Int
	LPTokens    *big.Int
}

func (err ErrInvalidCurveAllocation) Error() string {
	return "curve: curve token allocation must exceed a nonzero LP allocation"
}

// ErrInvalidVirtualReserves mirrors InvalidVirtualReserves.
type ErrInvalidVirtualReserves struct {
	InitialVirtualETH   *big.Int
	InitialVirtualToken *big.Int
	CurveTokens         *big.Int
}

func (err ErrInvalidVirtualReserves) Error() string {
	return "curve: invalid initial virtual reserves"
}

// ErrInvalidTradeFeeBPS mirrors InvalidTradeFeeBps.
type ErrInvalidTradeFeeBPS struct {
	TradeFeeBPS uint16
}

func (err ErrInvalidTradeFeeBPS) Error() string {
	return fmt.Sprintf("curve: trade fee BPS %d must be below 10000", err.TradeFeeBPS)
}

// ErrInvalidProtocolShareBPS mirrors InvalidProtocolShareBps.
type ErrInvalidProtocolShareBPS struct {
	ProtocolShareBPS uint16
}

func (err ErrInvalidProtocolShareBPS) Error() string {
	return fmt.Sprintf("curve: protocol share BPS %d must not exceed 10000", err.ProtocolShareBPS)
}

// ErrInvalidCurveBoundary mirrors InvalidCurveBoundary.
type ErrInvalidCurveBoundary struct {
	Invariant         *big.Int
	FinalVirtualToken *big.Int
	FinalVirtualETH   *big.Int
}

func (err ErrInvalidCurveBoundary) Error() string {
	return "curve: virtual reserves do not round-trip at the graduation boundary"
}

// ErrWrongPhase mirrors WrongPhase(expected, actual).
type ErrWrongPhase struct {
	Expected Phase
	Actual   Phase
}

func (err ErrWrongPhase) Error() string {
	return fmt.Sprintf("curve: wrong phase: expected %d, actual %d", err.Expected, err.Actual)
}

// ErrOversell mirrors Oversell(tokensIn, tokensSold).
type ErrOversell struct {
	Attempted *big.Int
	Sold      *big.Int
}

func (err ErrOversell) Error() string {
	return fmt.Sprintf("curve: attempted to sell %s tokens with %s sold", err.Attempted, err.Sold)
}
