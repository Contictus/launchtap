package apiserver

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/Contictus/launchtap/backend/internal/holder"
	"github.com/Contictus/launchtap/backend/internal/pagination"
	"github.com/Contictus/launchtap/backend/internal/stats"
	"github.com/Contictus/launchtap/backend/internal/token"
	"github.com/Contictus/launchtap/backend/internal/trading"
	"github.com/danielgtaylor/huma/v2"
	"github.com/ethereum/go-ethereum/common"
)

type PublicRoutes struct {
	Tokens interface {
		token.Reader
		token.QuoteReader
	}
	Market interface {
		trading.Reader
		holder.Reader
	}
	Protocol stats.Reader
	ChainID  int64
}
type addressInput struct {
	Token string `path:"token"`
}
type snapshotDTO struct {
	ChainID     int64  `json:"chain_id"`
	BlockNumber int64  `json:"as_of_block"`
	BlockHash   string `json:"as_of_block_hash"`
	Finality    string `json:"finality"`
}
type tokenDetailDTO struct {
	Snapshot              snapshotDTO `json:"snapshot"`
	Address               string      `json:"address"`
	Curve                 string      `json:"curve"`
	Pair                  string      `json:"pair"`
	WETH                  string      `json:"weth"`
	Creator               string      `json:"creator"`
	ProtocolTreasury      string      `json:"protocol_treasury"`
	Name                  string      `json:"name"`
	Symbol                string      `json:"symbol"`
	Phase                 string      `json:"phase"`
	EngineVersion         uint16      `json:"engine_version"`
	TotalSupply           string      `json:"total_supply"`
	InitialVirtualETH     string      `json:"initial_virtual_eth"`
	InitialVirtualToken   string      `json:"initial_virtual_token"`
	CurveTokens           string      `json:"curve_tokens"`
	LPTokens              string      `json:"lp_tokens"`
	GraduationETH         string      `json:"graduation_eth"`
	TradeFeeBPS           uint16      `json:"trade_fee_bps"`
	ProtocolShareBPS      uint16      `json:"protocol_share_bps"`
	ReserveSource         string      `json:"reserve_source"`
	ETHReserve            string      `json:"eth_reserve"`
	TokenReserve          string      `json:"token_reserve"`
	RealCurveETH          string      `json:"real_curve_eth"`
	GraduationProgressBPS int32       `json:"graduation_progress_bps"`
	ReserveBlock          int64       `json:"reserve_block"`
	ReserveHash           string      `json:"reserve_hash"`
	Description           string      `json:"description"`
	ImageURL              string      `json:"image_url"`
	XURL                  string      `json:"x_url"`
	TelegramURL           string      `json:"telegram_url"`
	SpotPriceETH          string      `json:"spot_price_eth"`
	MarketCapETH          string      `json:"market_cap_eth"`
	FDVETH                string      `json:"fdv_eth"`
	LiquidityETH          string      `json:"liquidity_eth"`
	ATHPriceETH           string      `json:"ath_price_eth"`
	Volume24hETH          string      `json:"volume_24h_eth"`
	ATHAt                 string      `json:"ath_at"`
	PriceChange24hBPS     int32       `json:"price_change_24h_bps"`
	HolderCount           int64       `json:"holder_count"`
}
type detailOutput struct{ Body tokenDetailDTO }
type pageInput struct {
	Token  string `path:"token"`
	Cursor string `query:"cursor"`
	Limit  int    `query:"limit" minimum:"1" maximum:"100"`
}
type tradeDTO struct {
	Source           string  `json:"source"`
	Trader           *string `json:"trader"`
	Side             string  `json:"side"`
	ExecutionPrice   string  `json:"execution_price"`
	SpotPrice        string  `json:"spot_price"`
	ETHVolume        string  `json:"eth_volume"`
	TokenVolume      string  `json:"token_volume"`
	BlockNumber      int64   `json:"block_number"`
	TransactionIndex int32   `json:"transaction_index"`
	TxHash           string  `json:"tx_hash"`
	LogIndex         int32   `json:"log_index"`
	Time             string  `json:"time"`
	Finality         string  `json:"finality"`
}
type tradesBody struct {
	Snapshot   snapshotDTO `json:"snapshot"`
	Items      []tradeDTO  `json:"items"`
	NextCursor string      `json:"next_cursor,omitempty"`
}
type tradesOutput struct{ Body tradesBody }
type holderDTO struct {
	Address            string `json:"address"`
	Balance            string `json:"balance"`
	FirstAcquiredBlock int64  `json:"first_acquired_block"`
}
type holdersBody struct {
	Snapshot   snapshotDTO `json:"snapshot"`
	Items      []holderDTO `json:"items"`
	NextCursor string      `json:"next_cursor,omitempty"`
}
type holdersOutput struct{ Body holdersBody }
type protocolDTO struct {
	Snapshot           snapshotDTO `json:"snapshot"`
	Volume24hETH       string      `json:"volume_24h_eth"`
	VolumeAllTimeETH   string      `json:"volume_all_time_eth"`
	Launches24h        int64       `json:"launches_24h"`
	LaunchesAllTime    int64       `json:"launches_all_time"`
	Trades24h          int64       `json:"trades_24h"`
	TradesAllTime      int64       `json:"trades_all_time"`
	Graduations24h     int64       `json:"graduations_24h"`
	GraduationsAllTime int64       `json:"graduations_all_time"`
	UpdatedAt          string      `json:"updated_at"`
}
type protocolOutput struct{ Body protocolDTO }

func (r PublicRoutes) Register(api huma.API) {
	huma.Register(api, huma.Operation{OperationID: "getToken", Method: http.MethodGet, Path: "/tokens/{token}", Tags: []string{"tokens"}}, r.detail)
	huma.Register(api, huma.Operation{OperationID: "listTrades", Method: http.MethodGet, Path: "/tokens/{token}/trades", Tags: []string{"market"}}, r.trades)
	huma.Register(api, huma.Operation{OperationID: "listHolders", Method: http.MethodGet, Path: "/tokens/{token}/holders", Tags: []string{"market"}}, r.holders)
	huma.Register(api, huma.Operation{OperationID: "getProtocolStats", Method: http.MethodGet, Path: "/stats/protocol", Tags: []string{"stats"}}, r.protocol)
}
func address(value string) (common.Address, error) {
	if !common.IsHexAddress(value) {
		return common.Address{}, huma.Error400BadRequest("invalid token address")
	}
	return common.HexToAddress(value), nil
}
func mapReadError(ctx context.Context, err error) error {
	if errors.Is(err, token.ErrNotFound) {
		return apiProblem(http.StatusNotFound, "token_not_found", "Token not found")
	}
	if errors.Is(err, pagination.ErrCursorInvalidated) {
		return apiProblem(http.StatusConflict, "cursor_invalidated", "Cursor snapshot is no longer canonical")
	}
	if errors.Is(err, pagination.ErrInvalidCursor) {
		return apiProblem(http.StatusBadRequest, "invalid_cursor", "Cursor is invalid")
	}
	if errors.Is(err, context.Canceled) {
		return err
	}
	return apiRequestProblem(ctx, http.StatusInternalServerError, "internal_error", "Request failed")
}
func apiProblem(status int, code, detail string) error {
	return &huma.ErrorModel{Type: "urn:launchpad:problem:" + code, Title: http.StatusText(status), Status: status, Detail: detail}
}
func apiRequestProblem(ctx context.Context, status int, code, detail string) error {
	err := &huma.ErrorModel{Type: "urn:launchpad:problem:" + code, Title: http.StatusText(status), Status: status, Detail: detail}
	if id := RequestID(ctx); id != "" {
		err.Instance = "urn:launchpad:request:" + id
	}
	return err
}
func snapDTO(s pagination.Snapshot, f string) snapshotDTO {
	return snapshotDTO{ChainID: s.ChainID, BlockNumber: s.BlockNumber, BlockHash: common.Hash(s.BlockHash).Hex(), Finality: f}
}
func (r PublicRoutes) detail(ctx context.Context, in *addressInput) (*detailOutput, error) {
	a, e := address(in.Token)
	if e != nil {
		return nil, e
	}
	v, e := r.Tokens.Get(ctx, r.ChainID, a)
	if e != nil {
		return nil, mapReadError(ctx, e)
	}
	d := tokenDetailDTO{Snapshot: snapDTO(v.Snapshot, v.Finality), Address: v.Address.Hex(), Curve: v.Curve.Hex(), Pair: v.Pair.Hex(), WETH: v.WETH.Hex(), Creator: v.Creator.Hex(), ProtocolTreasury: v.ProtocolTreasury.Hex(), Name: v.Name, Symbol: v.Symbol, Phase: v.Phase, EngineVersion: v.EngineVersion, TotalSupply: decimal(v.TotalSupply), InitialVirtualETH: decimal(v.InitialVirtualETH), InitialVirtualToken: decimal(v.InitialVirtualToken), CurveTokens: decimal(v.CurveTokens), LPTokens: decimal(v.LPTokens), GraduationETH: decimal(v.GraduationETH), TradeFeeBPS: v.TradeFeeBPS, ProtocolShareBPS: v.ProtocolShareBPS, ReserveSource: v.ReserveSource, ETHReserve: decimal(v.ETHReserve), TokenReserve: decimal(v.TokenReserve), RealCurveETH: decimal(v.RealCurveETH), GraduationProgressBPS: v.GraduationProgressBPS, ReserveBlock: v.ReserveBlock, ReserveHash: v.ReserveHash.Hex(), Description: v.Description, ImageURL: v.ImageURL, XURL: v.XURL, TelegramURL: v.TelegramURL, SpotPriceETH: decimal(v.SpotPriceETH), MarketCapETH: decimal(v.MarketCapETH), FDVETH: decimal(v.FDVETH), LiquidityETH: decimal(v.LiquidityETH), ATHPriceETH: decimal(v.ATHPriceETH), Volume24hETH: decimal(v.Volume24hETH), ATHAt: v.ATHAt.UTC().Format(time.RFC3339Nano), PriceChange24hBPS: v.PriceChange24hBPS, HolderCount: v.HolderCount}
	return &detailOutput{Body: d}, nil
}
func cursor(value string) (*pagination.Cursor, error) {
	if value == "" {
		return nil, nil
	}
	c, e := pagination.Decode(value)
	if e != nil {
		return nil, apiProblem(http.StatusBadRequest, "invalid_cursor", "Cursor is invalid")
	}
	return &c, nil
}
func (r PublicRoutes) trades(ctx context.Context, in *pageInput) (*tradesOutput, error) {
	a, e := address(in.Token)
	if e != nil {
		return nil, e
	}
	cur, e := cursor(in.Cursor)
	if e != nil {
		return nil, e
	}
	limit := in.Limit
	if limit == 0 {
		limit = 20
	}
	p, e := r.Market.ListTrades(ctx, trading.Query{ChainID: r.ChainID, Token: a, Limit: limit, Cursor: cur})
	if e != nil {
		return nil, mapReadError(ctx, e)
	}
	body := tradesBody{Snapshot: snapDTO(p.Snapshot, p.Finality), Items: make([]tradeDTO, 0, len(p.Items)), NextCursor: p.NextCursor}
	for _, v := range p.Items {
		var trader *string
		if v.Trader != nil {
			x := v.Trader.Hex()
			trader = &x
		}
		side := "sell"
		if v.Buy {
			side = "buy"
		}
		body.Items = append(body.Items, tradeDTO{Source: v.Source, Trader: trader, Side: side, ExecutionPrice: decimal(v.ExecutionPrice), SpotPrice: decimal(v.SpotPrice), ETHVolume: decimal(v.ETHVolume), TokenVolume: decimal(v.TokenVolume), BlockNumber: v.BlockNumber, TransactionIndex: v.TransactionIndex, TxHash: v.TxHash.Hex(), LogIndex: v.LogIndex, Time: v.Time.UTC().Format(time.RFC3339Nano), Finality: v.Finality})
	}
	return &tradesOutput{Body: body}, nil
}
func (r PublicRoutes) holders(ctx context.Context, in *pageInput) (*holdersOutput, error) {
	a, e := address(in.Token)
	if e != nil {
		return nil, e
	}
	cur, e := cursor(in.Cursor)
	if e != nil {
		return nil, e
	}
	limit := in.Limit
	if limit == 0 {
		limit = 20
	}
	p, e := r.Market.ListHolders(ctx, holder.Query{ChainID: r.ChainID, Token: a, Limit: limit, Cursor: cur})
	if e != nil {
		return nil, mapReadError(ctx, e)
	}
	body := holdersBody{Snapshot: snapDTO(p.Snapshot, p.Finality), Items: make([]holderDTO, 0, len(p.Items)), NextCursor: p.NextCursor}
	for _, v := range p.Items {
		body.Items = append(body.Items, holderDTO{Address: v.Address.Hex(), Balance: decimal(v.Balance), FirstAcquiredBlock: v.FirstAcquiredBlock})
	}
	return &holdersOutput{Body: body}, nil
}
func (r PublicRoutes) protocol(ctx context.Context, _ *struct{}) (*protocolOutput, error) {
	v, e := r.Protocol.ReadProtocol(ctx, r.ChainID)
	if e != nil {
		return nil, mapReadError(ctx, e)
	}
	return &protocolOutput{Body: protocolDTO{Snapshot: snapDTO(v.Snapshot, v.Finality), Volume24hETH: decimal(v.Volume24hETH), VolumeAllTimeETH: decimal(v.VolumeAllTimeETH), Launches24h: v.Launches24h, LaunchesAllTime: v.LaunchesAllTime, Trades24h: v.Trades24h, TradesAllTime: v.TradesAllTime, Graduations24h: v.Graduations24h, GraduationsAllTime: v.GraduationsAllTime, UpdatedAt: v.UpdatedAt.UTC().Format(time.RFC3339Nano)}}, nil
}
