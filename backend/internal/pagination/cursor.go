package pagination

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
)

const CurrentVersion = 1

var (
	ErrInvalidCursor     = errors.New("invalid cursor")
	ErrCursorInvalidated = errors.New("cursor snapshot is no longer canonical")
)

type Snapshot struct {
	ChainID     int64    `json:"chainId"`
	BlockNumber int64    `json:"blockNumber"`
	BlockHash   [32]byte `json:"blockHash"`
}

type Cursor struct {
	Version   int      `json:"version"`
	Snapshot  Snapshot `json:"snapshot"`
	Endpoint  string   `json:"endpoint"`
	Sort      string   `json:"sort"`
	Filters   string   `json:"filters"`
	Direction string   `json:"direction"`
	Key       []string `json:"key"`
}

func Encode(c Cursor) (string, error) {
	if err := c.ValidateShape(); err != nil {
		return "", err
	}
	b, err := json.Marshal(c)
	if err != nil {
		return "", fmt.Errorf("encode cursor: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

func Decode(encoded string) (Cursor, error) {
	if encoded == "" {
		return Cursor{}, fmt.Errorf("%w: empty", ErrInvalidCursor)
	}
	b, err := base64.RawURLEncoding.Strict().DecodeString(encoded)
	if err != nil {
		return Cursor{}, fmt.Errorf("%w: base64: %v", ErrInvalidCursor, err)
	}
	dec := json.NewDecoder(bytes.NewReader(b))
	dec.DisallowUnknownFields()
	var c Cursor
	if err := dec.Decode(&c); err != nil {
		return Cursor{}, fmt.Errorf("%w: json: %v", ErrInvalidCursor, err)
	}
	var extra any
	if err := dec.Decode(&extra); err != io.EOF {
		return Cursor{}, fmt.Errorf("%w: trailing data", ErrInvalidCursor)
	}
	if err := c.ValidateShape(); err != nil {
		return Cursor{}, err
	}
	return c, nil
}

func (c Cursor) ValidateShape() error {
	if c.Version != CurrentVersion || c.Snapshot.ChainID <= 0 || c.Snapshot.BlockNumber < 0 ||
		c.Endpoint == "" || c.Sort == "" || c.Direction == "" || len(c.Key) == 0 {
		return fmt.Errorf("%w: unsupported shape", ErrInvalidCursor)
	}
	return nil
}

func (c Cursor) ValidateRequest(endpoint, sort, filters, direction string, snapshot Snapshot) error {
	if err := c.ValidateShape(); err != nil {
		return err
	}
	if c.Endpoint != endpoint || c.Sort != sort || c.Filters != filters || c.Direction != direction {
		return fmt.Errorf("%w: request changed", ErrInvalidCursor)
	}
	if c.Snapshot.ChainID != snapshot.ChainID || c.Snapshot.BlockNumber != snapshot.BlockNumber ||
		c.Snapshot.BlockHash != snapshot.BlockHash {
		return ErrCursorInvalidated
	}
	return nil
}
