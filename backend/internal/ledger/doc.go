// Package ledger contains persistence-neutral canonical chain-event inputs.
//
// Each event type mirrors its payload columns in 00003_event_ledger.sql and
// its decoded payload counterpart in internal/chain/types.go. Coordinates are
// represented once by EventCoordinates. The only deliberate differences are
// ChainID and block timestamp, which come from the indexer rather than an ABI
// event, and Pool* Pair, which is the emitting address rather than an ABI
// payload field. PostgreSQL codecs and chain decoder types do not cross this
// boundary.
package ledger
