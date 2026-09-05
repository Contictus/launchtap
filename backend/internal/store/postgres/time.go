package postgres

import (
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

func equalTimestamptz(left, right pgtype.Timestamptz) bool {
	if left.Valid != right.Valid || left.InfinityModifier != right.InfinityModifier {
		return false
	}
	return !left.Valid || left.Time.Truncate(time.Microsecond).Equal(right.Time.Truncate(time.Microsecond))
}
