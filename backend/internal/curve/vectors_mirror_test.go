package curve

import (
	"errors"
	"math/big"
	"testing"
)

func TestSolidityVectors(t *testing.T) {
	artifact, err := LoadEmbeddedVectors()
	if err != nil {
		t.Fatalf("LoadEmbeddedVectors() error = %v", err)
	}
	parameters := parametersFromVector(t, artifact.Parameters)

	for _, vectorCase := range artifact.Cases {
		vectorCase := vectorCase
		t.Run(vectorCase.ID, func(t *testing.T) {
			state := stateFromVector(t, vectorCase.InitialState)
			assertDerivedVectorState(t, parameters, state, vectorCase.InitialState)

			switch vectorCase.Operation {
			case "buy":
				quote, quoteErr := Buy(state, parameters, decimal(t, vectorCase.Input.ETHGross))
				if vectorCase.ExpectedRevert != nil {
					assertVectorError(t, quoteErr, vectorCase.ExpectedRevert.Name)
					return
				}
				if quoteErr != nil {
					t.Fatalf("Buy() error = %v", quoteErr)
				}
				assertBuyVectorOutput(t, quote, *vectorCase.Output)
				assertVectorState(t, parameters, quote.NextState(), vectorCase.NextState)
			case "sell":
				quote, quoteErr := Sell(state, parameters, decimal(t, vectorCase.Input.TokensIn))
				if vectorCase.ExpectedRevert != nil {
					assertVectorError(t, quoteErr, vectorCase.ExpectedRevert.Name)
					return
				}
				if quoteErr != nil {
					t.Fatalf("Sell() error = %v", quoteErr)
				}
				assertSellVectorOutput(t, quote, vectorCase.Input.TokensIn, *vectorCase.Output)
				assertVectorState(t, parameters, quote.NextState(), vectorCase.NextState)
			default:
				t.Fatalf("unsupported operation %q", vectorCase.Operation)
			}
		})
	}
}

func parametersFromVector(t *testing.T, vector VectorParameters) Parameters {
	t.Helper()
	parameters, err := NewParameters(
		decimal(t, vector.TotalSupply),
		decimal(t, vector.CurveTokens),
		decimal(t, vector.LPTokens),
		decimal(t, vector.GraduationETH),
		decimal(t, vector.InitialVirtualETH),
		decimal(t, vector.InitialVirtualToken),
		uint16(vector.TradeFeeBPS),
		uint16(vector.ProtocolShareBPS),
	)
	if err != nil {
		t.Fatalf("NewParameters() error = %v", err)
	}
	return parameters
}

func stateFromVector(t *testing.T, vector VectorState) State {
	t.Helper()
	var phase Phase
	switch vector.Phase {
	case "curve":
		phase = PhaseCurve
	case "graduated":
		phase = PhaseGraduated
	default:
		t.Fatalf("unsupported vector phase %q", vector.Phase)
	}
	state, err := NewState(
		phase,
		decimal(t, vector.VirtualETH),
		decimal(t, vector.VirtualToken),
		decimal(t, vector.ProtocolFees),
		decimal(t, vector.CreatorFees),
	)
	if err != nil {
		t.Fatalf("NewState() error = %v", err)
	}
	return state
}

func assertBuyVectorOutput(t *testing.T, quote BuyQuote, expected VectorOutput) {
	t.Helper()
	assertAmount(t, "ethGross", quote.ETHGrossUsed(), expected.ETHGross)
	assertAmount(t, "ethRefund", quote.Refund(), expected.ETHRefund)
	assertAmount(t, "ethOut", new(big.Int), expected.ETHOut)
	assertAmount(t, "tokenAmount", quote.TokensOut(), expected.TokenAmount)
	assertAmount(t, "protocolFee", quote.ProtocolFee(), expected.ProtocolFee)
	assertAmount(t, "creatorFee", quote.CreatorFee(), expected.CreatorFee)
	if quote.Graduates() != expected.Graduates {
		t.Fatalf("Graduates() = %t, want %t", quote.Graduates(), expected.Graduates)
	}
}

func assertSellVectorOutput(t *testing.T, quote SellQuote, tokensIn string, expected VectorOutput) {
	t.Helper()
	assertAmount(t, "ethGross", quote.ETHGross(), expected.ETHGross)
	assertAmount(t, "ethRefund", new(big.Int), expected.ETHRefund)
	assertAmount(t, "ethOut", quote.ETHOut(), expected.ETHOut)
	if expected.TokenAmount != tokensIn {
		t.Errorf("tokenAmount = %s, want input tokensIn %s", expected.TokenAmount, tokensIn)
	}
	assertAmount(t, "protocolFee", quote.ProtocolFee(), expected.ProtocolFee)
	assertAmount(t, "creatorFee", quote.CreatorFee(), expected.CreatorFee)
	if expected.Graduates {
		t.Fatal("sell vector unexpectedly graduates")
	}
}

func assertVectorState(t *testing.T, parameters Parameters, state State, expected VectorState) {
	t.Helper()
	expectedPhase := PhaseCurve
	if expected.Phase == "graduated" {
		expectedPhase = PhaseGraduated
	}
	if state.Phase() != expectedPhase {
		t.Errorf("Phase() = %d, want %d", state.Phase(), expectedPhase)
	}
	assertAmount(t, "virtualEth", state.VirtualETH(), expected.VirtualETH)
	assertAmount(t, "virtualToken", state.VirtualToken(), expected.VirtualToken)
	assertAmount(t, "protocolFees", state.ProtocolFees(), expected.ProtocolFees)
	assertAmount(t, "creatorFees", state.CreatorFees(), expected.CreatorFees)
	assertDerivedVectorState(t, parameters, state, expected)
}

func assertDerivedVectorState(t *testing.T, parameters Parameters, state State, expected VectorState) {
	t.Helper()
	tokensSold, err := TokensSold(parameters, state)
	if err != nil {
		t.Fatalf("TokensSold() error = %v", err)
	}
	realCurveETH, err := RealCurveETH(parameters, state)
	if err != nil {
		t.Fatalf("RealCurveETH() error = %v", err)
	}
	assertAmount(t, "tokensSold", tokensSold, expected.TokensSold)
	assertAmount(t, "realCurveEth", realCurveETH, expected.RealCurveETH)
}

func assertVectorError(t *testing.T, err error, name string) {
	t.Helper()
	if err == nil {
		t.Fatalf("quote error = nil, want %s", name)
	}
	switch name {
	case "ZeroInput":
		if !errors.Is(err, ErrZeroInput) {
			t.Fatalf("quote error = %v, want ErrZeroInput", err)
		}
	case "ZeroOutput":
		if !errors.Is(err, ErrZeroOutput) {
			t.Fatalf("quote error = %v, want ErrZeroOutput", err)
		}
	case "Oversell":
		var oversell ErrOversell
		if !errors.As(err, &oversell) {
			t.Fatalf("quote error = %v, want ErrOversell", err)
		}
	case "WrongPhase":
		var wrongPhase ErrWrongPhase
		if !errors.As(err, &wrongPhase) {
			t.Fatalf("quote error = %v, want ErrWrongPhase", err)
		}
	default:
		t.Fatalf("unsupported expected revert %q", name)
	}
}

func assertAmount(t *testing.T, name string, actual *big.Int, expected string) {
	t.Helper()
	if actual.String() != expected {
		t.Errorf("%s = %s, want %s", name, actual, expected)
	}
}

func decimal(t *testing.T, value string) *big.Int {
	t.Helper()
	parsed, ok := new(big.Int).SetString(value, 10)
	if !ok {
		t.Fatalf("invalid decimal %q", value)
	}
	return parsed
}
