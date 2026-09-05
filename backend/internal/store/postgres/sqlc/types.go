package sqlc

import (
	"fmt"
	"math/big"

	"github.com/jackc/pgx/v5/pgtype"
)

const (
	addressLength = 20
	hashLength    = 32
)

// Address is an exact EVM address stored as PostgreSQL bytea.
type Address [addressLength]byte

// ScanBytes implements pgtype.BytesScanner.
func (address *Address) ScanBytes(value []byte) error {
	if len(value) != addressLength {
		return fmt.Errorf("scan address: got %d bytes, want %d", len(value), addressLength)
	}
	copy(address[:], value)
	return nil
}

// BytesValue implements pgtype.BytesValuer.
func (address Address) BytesValue() ([]byte, error) {
	return address[:], nil
}

// Hash is an exact EVM hash stored as PostgreSQL bytea.
type Hash [hashLength]byte

// ScanBytes implements pgtype.BytesScanner.
func (hash *Hash) ScanBytes(value []byte) error {
	if len(value) != hashLength {
		return fmt.Errorf("scan hash: got %d bytes, want %d", len(value), hashLength)
	}
	copy(hash[:], value)
	return nil
}

// BytesValue implements pgtype.BytesValuer.
func (hash Hash) BytesValue() ([]byte, error) {
	return hash[:], nil
}

// Uint256 is an unsigned 256-bit integer stored as PostgreSQL numeric(78,0).
type Uint256 [hashLength]byte

// NewUint256 validates and copies value into its fixed-width representation.
func NewUint256(value *big.Int) (Uint256, error) {
	var result Uint256
	if value == nil {
		return result, fmt.Errorf("uint256 value is nil")
	}
	if value.Sign() < 0 {
		return result, fmt.Errorf("uint256 value is negative")
	}
	if value.BitLen() > 256 {
		return result, fmt.Errorf("uint256 value exceeds 256 bits")
	}
	value.FillBytes(result[:])
	return result, nil
}

// BigInt returns a copy of value as a big integer.
func (value Uint256) BigInt() *big.Int {
	return new(big.Int).SetBytes(value[:])
}

// ScanNumeric implements pgtype.NumericScanner.
func (value *Uint256) ScanNumeric(numeric pgtype.Numeric) error {
	if !numeric.Valid {
		return fmt.Errorf("scan uint256: value is NULL")
	}
	if numeric.NaN || numeric.InfinityModifier != pgtype.Finite {
		return fmt.Errorf("scan uint256: value is not finite")
	}
	integer, err := numericInteger(numeric)
	if err != nil {
		return fmt.Errorf("scan uint256: %w", err)
	}
	validated, err := NewUint256(integer)
	if err != nil {
		return fmt.Errorf("scan uint256: %w", err)
	}
	*value = validated
	return nil
}

// NumericValue implements pgtype.NumericValuer.
func (value Uint256) NumericValue() (pgtype.Numeric, error) {
	return pgtype.Numeric{Int: value.BigInt(), Valid: true}, nil
}

func numericInteger(numeric pgtype.Numeric) (*big.Int, error) {
	if numeric.Int == nil {
		return nil, fmt.Errorf("numeric coefficient is nil")
	}
	integer := new(big.Int).Set(numeric.Int)
	if integer.Sign() == 0 {
		return integer, nil
	}
	if numeric.Exp > 77 {
		return nil, fmt.Errorf("numeric value exceeds 256 bits")
	}
	if numeric.Exp < -78 {
		return nil, fmt.Errorf("numeric value is fractional")
	}
	if numeric.Exp == 0 {
		return integer, nil
	}
	exponent := int64(numeric.Exp)
	if exponent < 0 {
		exponent = -exponent
	}
	power := new(big.Int).Exp(big.NewInt(10), big.NewInt(exponent), nil)
	if numeric.Exp > 0 {
		return integer.Mul(integer, power), nil
	}
	quotient, remainder := new(big.Int), new(big.Int)
	quotient.QuoRem(integer, power, remainder)
	if remainder.Sign() != 0 {
		return nil, fmt.Errorf("numeric value is fractional")
	}
	return quotient, nil
}

var (
	_ pgtype.BytesScanner   = (*Address)(nil)
	_ pgtype.BytesValuer    = Address{}
	_ pgtype.BytesScanner   = (*Hash)(nil)
	_ pgtype.BytesValuer    = Hash{}
	_ pgtype.NumericScanner = (*Uint256)(nil)
	_ pgtype.NumericValuer  = Uint256{}
)
