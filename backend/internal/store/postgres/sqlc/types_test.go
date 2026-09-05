package sqlc

import (
	"math/big"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"
)

func TestAddressAndHashRejectWrongLengths(t *testing.T) {
	t.Parallel()

	var address Address
	if err := address.ScanBytes(make([]byte, 19)); err == nil {
		t.Fatal("Address.ScanBytes accepted 19 bytes")
	}
	if err := address.ScanBytes(make([]byte, 20)); err != nil {
		t.Fatalf("Address.ScanBytes rejected 20 bytes: %v", err)
	}

	var hash Hash
	if err := hash.ScanBytes(make([]byte, 31)); err == nil {
		t.Fatal("Hash.ScanBytes accepted 31 bytes")
	}
	if err := hash.ScanBytes(make([]byte, 32)); err != nil {
		t.Fatalf("Hash.ScanBytes rejected 32 bytes: %v", err)
	}
}

func TestUint256Boundaries(t *testing.T) {
	t.Parallel()

	maximum := new(big.Int).Sub(new(big.Int).Lsh(big.NewInt(1), 256), big.NewInt(1))
	tests := []struct {
		name    string
		numeric pgtype.Numeric
		wantErr bool
	}{
		{name: "zero", numeric: pgtype.Numeric{Int: big.NewInt(0), Valid: true}},
		{name: "maximum", numeric: pgtype.Numeric{Int: maximum, Valid: true}},
		{name: "integral negative exponent", numeric: pgtype.Numeric{Int: big.NewInt(100), Exp: -2, Valid: true}},
		{name: "negative", numeric: pgtype.Numeric{Int: big.NewInt(-1), Valid: true}, wantErr: true},
		{name: "fractional", numeric: pgtype.Numeric{Int: big.NewInt(1), Exp: -1, Valid: true}, wantErr: true},
		{name: "above 256 bits", numeric: pgtype.Numeric{Int: new(big.Int).Lsh(big.NewInt(1), 256), Valid: true}, wantErr: true},
		{name: "oversized exponent", numeric: pgtype.Numeric{Int: big.NewInt(1), Exp: 1_000_000, Valid: true}, wantErr: true},
		{name: "null", numeric: pgtype.Numeric{}, wantErr: true},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			var value Uint256
			err := value.ScanNumeric(test.numeric)
			if test.wantErr && err == nil {
				t.Fatal("ScanNumeric unexpectedly succeeded")
			}
			if !test.wantErr && err != nil {
				t.Fatalf("ScanNumeric failed: %v", err)
			}
		})
	}
}

func TestUint256NumericRoundTrip(t *testing.T) {
	t.Parallel()

	want := new(big.Int).Lsh(big.NewInt(1), 200)
	value, err := NewUint256(want)
	if err != nil {
		t.Fatalf("NewUint256: %v", err)
	}
	numeric, err := value.NumericValue()
	if err != nil {
		t.Fatalf("NumericValue: %v", err)
	}
	if numeric.Int.Cmp(want) != 0 || numeric.Exp != 0 || !numeric.Valid {
		t.Fatalf("NumericValue = %+v, want %s", numeric, want)
	}
}
