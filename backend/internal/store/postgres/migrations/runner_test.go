package migrations

import (
	"errors"
	"testing"
)

func TestParseCommand(t *testing.T) {
	t.Parallel()

	for _, command := range []Command{CommandUp, CommandDown, CommandStatus} {
		command := command
		t.Run(string(command), func(t *testing.T) {
			t.Parallel()

			got, err := ParseCommand(string(command))
			if err != nil {
				t.Fatalf("ParseCommand(%q): %v", command, err)
			}
			if got != command {
				t.Fatalf("ParseCommand(%q) = %q, want %q", command, got, command)
			}
		})
	}
}

func TestParseCommandRejectsMissingAndUnknown(t *testing.T) {
	t.Parallel()

	for _, value := range []string{"", "UP", "redo", "up extra"} {
		_, err := ParseCommand(value)
		if !errors.Is(err, ErrInvalidCommand) {
			t.Fatalf("ParseCommand(%q) error = %v, want ErrInvalidCommand", value, err)
		}
	}
}

func TestRunRejectsNilDatabase(t *testing.T) {
	t.Parallel()

	if _, err := Run(t.Context(), nil, CommandUp); err == nil {
		t.Fatal("Run(nil database) succeeded")
	}
}
