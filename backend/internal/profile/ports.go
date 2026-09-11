// Package profile owns the authenticated account action read contract.
package profile

import (
	"context"
	"math/big"

	"github.com/Contictus/launchtap/backend/internal/pagination"
	"github.com/ethereum/go-ethereum/common"
)

type Action struct {
	Token       common.Address
	Curve       common.Address
	Name        string
	Symbol      string
	Phase       string
	CreatorFees *big.Int
	Refund      *big.Int
}

type Page struct {
	Items    []Action
	Snapshot pagination.Snapshot
	Finality string
}

type Reader interface {
	List(ctx context.Context, chainID int64, wallets []common.Address) (Page, error)
}
