// Package metadata owns creator-editable token metadata and image contracts.
package metadata

import (
	"context"
	"errors"
	"time"

	"github.com/ethereum/go-ethereum/common"
)

var (
	ErrNotFound         = errors.New("token or image not found")
	ErrUnauthorized     = errors.New("linked wallet is not the token creator")
	ErrRevisionConflict = errors.New("metadata or image revision conflict")
)

type Metadata struct {
	Description, ImageURL, XURL, TelegramURL string
	Revision                                 int64
	UpdatedAt                                time.Time
}

type Image struct {
	ContentType string
	Content     []byte
	SHA256      [32]byte
	Revision    int64
	UpdatedAt   time.Time
}

type Store interface {
	ReplaceMetadata(context.Context, int64, common.Address, []common.Address, Metadata) (int64, error)
	ReplaceImage(context.Context, int64, common.Address, []common.Address, Image) (int64, error)
	GetMetadata(context.Context, int64, common.Address) (Metadata, error)
	GetImage(context.Context, int64, common.Address) (Image, error)
}
