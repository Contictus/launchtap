package pagination

import (
	"encoding/base64"
	"errors"
	"testing"
)

func TestCursorRoundTripAndStrictValidation(t *testing.T) {
	c := Cursor{Version: CurrentVersion, Snapshot: Snapshot{ChainID: 46630, BlockNumber: 7}, Endpoint: "tokens", Sort: "newest", Filters: "curve", Direction: "next", Key: []string{"7", "0x01"}}
	encoded, err := Encode(c)
	if err != nil {
		t.Fatal(err)
	}
	got, err := Decode(encoded)
	if err != nil {
		t.Fatal(err)
	}
	if got.Endpoint != c.Endpoint || got.Snapshot.ChainID != c.Snapshot.ChainID {
		t.Fatalf("round trip mismatch: %#v", got)
	}
	if _, err := Decode(encoded + "!"); !errors.Is(err, ErrInvalidCursor) {
		t.Fatalf("want invalid cursor, got %v", err)
	}
	unknown := base64.RawURLEncoding.EncodeToString([]byte(`{"version":1,"snapshot":{"chainId":1,"blockNumber":1,"blockHash":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]},"endpoint":"tokens","sort":"newest","filters":"","direction":"next","key":["1"],"extra":true}`))
	if _, err := Decode(unknown); !errors.Is(err, ErrInvalidCursor) {
		t.Fatalf("unknown cursor field accepted: %v", err)
	}
}

func TestCursorRequestAndReorgInvalidation(t *testing.T) {
	c := Cursor{Version: CurrentVersion, Snapshot: Snapshot{ChainID: 1, BlockNumber: 2}, Endpoint: "tokens", Sort: "newest", Direction: "next", Key: []string{"2"}}
	if err := c.ValidateRequest("tokens", "newest", "", "next", c.Snapshot); err != nil {
		t.Fatal(err)
	}
	changed := c.Snapshot
	changed.BlockHash[0] = 1
	if !errors.Is(c.ValidateRequest("tokens", "newest", "", "next", changed), ErrCursorInvalidated) {
		t.Fatal("reorg identity was not rejected")
	}
	if !errors.Is(c.ValidateRequest("tokens", "oldest", "", "next", c.Snapshot), ErrInvalidCursor) {
		t.Fatal("changed sort was not rejected")
	}
}
