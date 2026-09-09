package stats

import (
	"context"
	"math/big"
	"time"

	"github.com/Contictus/launchtap/backend/internal/pagination"
)

type Protocol struct {
	Volume24hETH, VolumeAllTimeETH                                                             *big.Int
	Launches24h, LaunchesAllTime, Trades24h, TradesAllTime, Graduations24h, GraduationsAllTime int64
	UpdatedAt                                                                                  time.Time
	Snapshot                                                                                   pagination.Snapshot
	Finality                                                                                   string
}
type Reader interface {
	ReadProtocol(context.Context, int64) (Protocol, error)
}
