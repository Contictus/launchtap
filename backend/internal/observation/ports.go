package observation

import (
	"context"
	"errors"

	"github.com/Contictus/launchtap/backend/internal/pagination"
	"github.com/ethereum/go-ethereum/common"
)

var ErrNotFound = errors.New("canonical transaction observation not found")

type Event struct {
	Kind             string
	TxHash           common.Hash
	Token            *common.Address
	Pair             *common.Address
	BlockNumber      int64
	BlockHash        common.Hash
	BlockTime        string
	TransactionIndex int32
	LogIndex         int32
	Finality         string
}

type Observation struct {
	ChainID      int64
	DeploymentID string
	Snapshot     pagination.Snapshot
	Finality     string
	Events       []Event
}

type Reader interface {
	Get(context.Context, int64, string, common.Hash) (Observation, error)
}
