package postgres

import (
	"math/big"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"
)

func TestProfileNumericPreservesPostgresNumericExponent(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name    string
		numeric pgtype.Numeric
		want    string
		wantErr bool
	}{
		{name: "positive exponent", numeric: pgtype.Numeric{Int: big.NewInt(12), Exp: 3, Valid: true}, want: "12000"},
		{name: "exact negative exponent", numeric: pgtype.Numeric{Int: big.NewInt(100), Exp: -2, Valid: true}, want: "1"},
		{name: "fractional negative exponent", numeric: pgtype.Numeric{Int: big.NewInt(1), Exp: -1, Valid: true}, wantErr: true},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			got, err := profileNumeric(test.numeric)
			if test.wantErr {
				if err == nil {
					t.Fatal("profileNumeric unexpectedly succeeded")
				}
				return
			}
			if err != nil {
				t.Fatalf("profileNumeric failed: %v", err)
			}
			if got.String() != test.want {
				t.Fatalf("profileNumeric = %s, want %s", got, test.want)
			}
		})
	}
}
