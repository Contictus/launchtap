package curve

import (
	"errors"
	"math/big"
	"math/rand"
	"testing"
)

func TestBuyProperties(t *testing.T) {
	parameters := vectorParameters(t)
	random := rand.New(rand.NewSource(11))
	for iteration := 0; iteration < 1_000; iteration++ {
		state := initialState(t, parameters)
		gross := new(big.Int).SetUint64(uint64(random.Int63n(1_000_000_000_000_000_000) + 1))
		beforePrice := mustSpotPrice(t, state)
		quote, err := Buy(state, parameters, gross)
		if err != nil {
			t.Fatalf("iteration %d: Buy() error = %v", iteration, err)
		}
		nextState := quote.NextState()
		afterPrice := mustSpotPrice(t, nextState)
		if afterPrice.Cmp(beforePrice) < 0 {
			t.Fatalf("iteration %d: spot price decreased", iteration)
		}
		assertProductAtLeastInvariant(t, parameters, nextState)
		sold := mustTokensSold(t, parameters, nextState)
		if sold.Sign() < 0 || sold.Cmp(parameters.CurveTokens()) > 0 {
			t.Fatalf("iteration %d: sold inventory %s is out of bounds", iteration, sold)
		}
		netIncrease := new(big.Int).Sub(nextState.VirtualETH(), state.VirtualETH())
		accounted := new(big.Int).Add(netIncrease, quote.ProtocolFee())
		accounted.Add(accounted, quote.CreatorFee())
		if accounted.Cmp(quote.ETHGrossUsed()) != 0 {
			t.Fatalf("iteration %d: buy fee conservation failed", iteration)
		}
	}
}

func TestSellAndRoundTripProperties(t *testing.T) {
	parameters := vectorParameters(t)
	random := rand.New(rand.NewSource(12))
	for iteration := 0; iteration < 1_000; iteration++ {
		initial := initialState(t, parameters)
		gross := new(big.Int).SetUint64(uint64(random.Int63n(500_000_000_000_000_000) + 1_000_000))
		buyQuote, err := Buy(initial, parameters, gross)
		if err != nil {
			t.Fatalf("iteration %d: Buy() error = %v", iteration, err)
		}
		if buyQuote.Graduates() {
			t.Fatalf("iteration %d: bounded property buy unexpectedly graduated", iteration)
		}
		boughtState := buyQuote.NextState()
		sellQuote, err := Sell(boughtState, parameters, buyQuote.TokensOut())
		if err != nil {
			t.Fatalf("iteration %d: Sell() error = %v", iteration, err)
		}
		if sellQuote.ETHOut().Cmp(buyQuote.ETHGrossUsed()) > 0 {
			t.Fatalf("iteration %d: round trip returned more ETH than buy used", iteration)
		}
		nextState := sellQuote.NextState()
		if nextState.VirtualETH().Cmp(initial.VirtualETH()) != 0 ||
			nextState.VirtualToken().Cmp(initial.VirtualToken()) != 0 {
			t.Fatalf("iteration %d: full round trip did not restore virtual reserves", iteration)
		}
		accounted := new(big.Int).Add(sellQuote.ETHOut(), sellQuote.ProtocolFee())
		accounted.Add(accounted, sellQuote.CreatorFee())
		if accounted.Cmp(sellQuote.ETHGross()) != 0 {
			t.Fatalf("iteration %d: sell fee conservation failed", iteration)
		}
		assertProductAtLeastInvariant(t, parameters, nextState)
	}
}

func TestGraduationOccursAtMostOnce(t *testing.T) {
	artifact, err := LoadEmbeddedVectors()
	if err != nil {
		t.Fatalf("LoadEmbeddedVectors() error = %v", err)
	}
	parameters := parametersFromVector(t, artifact.Parameters)
	finalVector := vectorCaseByID(t, artifact, "buy_final_refund_and_graduation")
	quote, err := Buy(
		stateFromVector(t, finalVector.InitialState),
		parameters,
		decimal(t, finalVector.Input.ETHGross),
	)
	if err != nil {
		t.Fatalf("Buy() error = %v", err)
	}
	if !quote.Graduates() || quote.NextState().Phase() != PhaseGraduated {
		t.Fatal("final buy did not graduate")
	}
	_, err = Buy(quote.NextState(), parameters, big.NewInt(1))
	var wrongPhase ErrWrongPhase
	if !errors.As(err, &wrongPhase) {
		t.Fatalf("second Buy() error = %v, want ErrWrongPhase", err)
	}
}

func initialState(t *testing.T, parameters Parameters) State {
	t.Helper()
	state, err := NewState(
		PhaseCurve,
		parameters.InitialVirtualETH(),
		parameters.InitialVirtualToken(),
		new(big.Int),
		new(big.Int),
	)
	if err != nil {
		t.Fatalf("NewState() error = %v", err)
	}
	return state
}

func mustSpotPrice(t *testing.T, state State) *big.Int {
	t.Helper()
	price, err := SpotPriceWad(state)
	if err != nil {
		t.Fatalf("SpotPriceWad() error = %v", err)
	}
	return price
}

func mustTokensSold(t *testing.T, parameters Parameters, state State) *big.Int {
	t.Helper()
	sold, err := TokensSold(parameters, state)
	if err != nil {
		t.Fatalf("TokensSold() error = %v", err)
	}
	return sold
}

func assertProductAtLeastInvariant(t *testing.T, parameters Parameters, state State) {
	t.Helper()
	product := new(big.Int).Mul(state.VirtualETH(), state.VirtualToken())
	if product.Cmp(parameters.Invariant()) < 0 {
		t.Fatalf("virtual reserve product %s is below invariant %s", product, parameters.Invariant())
	}
}
