package curve

import (
	"errors"
	"math/big"
	"testing"
)

func TestNewParametersValidatesInSolidityOrder(t *testing.T) {
	valid := vectorParameters(t)
	one := big.NewInt(1)
	zero := new(big.Int)

	tests := []struct {
		name   string
		mutate func(*parameterInputs)
		assert func(error) bool
	}{
		{
			name: "supply allocation",
			mutate: func(input *parameterInputs) {
				input.totalSupply.Add(input.totalSupply, one)
			},
			assert: func(err error) bool {
				var target ErrInvalidSupplyAllocation
				return errors.As(err, &target)
			},
		},
		{
			name: "curve allocation",
			mutate: func(input *parameterInputs) {
				input.lpTokens.Set(input.curveTokens)
				input.totalSupply.Add(input.curveTokens, input.lpTokens)
			},
			assert: func(err error) bool {
				var target ErrInvalidCurveAllocation
				return errors.As(err, &target)
			},
		},
		{
			name: "graduation ETH",
			mutate: func(input *parameterInputs) {
				input.graduationETH.Set(zero)
			},
			assert: func(err error) bool { return errors.Is(err, ErrInvalidGraduationETH) },
		},
		{
			name: "virtual reserves",
			mutate: func(input *parameterInputs) {
				input.initialVirtualETH.Set(zero)
			},
			assert: func(err error) bool {
				var target ErrInvalidVirtualReserves
				return errors.As(err, &target)
			},
		},
		{
			name: "trade fee",
			mutate: func(input *parameterInputs) {
				input.tradeFeeBPS = 10_000
			},
			assert: func(err error) bool {
				var target ErrInvalidTradeFeeBPS
				return errors.As(err, &target)
			},
		},
		{
			name: "protocol share",
			mutate: func(input *parameterInputs) {
				input.protocolShareBPS = 10_001
			},
			assert: func(err error) bool {
				var target ErrInvalidProtocolShareBPS
				return errors.As(err, &target)
			},
		},
		{
			name: "curve boundary",
			mutate: func(input *parameterInputs) {
				input.graduationETH.Add(input.graduationETH, one)
			},
			assert: func(err error) bool {
				var target ErrInvalidCurveBoundary
				return errors.As(err, &target)
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			input := inputsFromParameters(valid)
			test.mutate(&input)
			_, err := input.build()
			if !test.assert(err) {
				t.Fatalf("NewParameters() error = %v", err)
			}
		})
	}
}

func TestConstructorsRejectInvalidUint256AndArithmeticOverflow(t *testing.T) {
	valid := inputsFromParameters(vectorParameters(t))
	tooLarge := new(big.Int).Add(maxUint256, big.NewInt(1))

	for name, value := range map[string]*big.Int{
		"nil":       nil,
		"negative":  big.NewInt(-1),
		"too large": tooLarge,
	} {
		t.Run(name, func(t *testing.T) {
			input := valid
			input.totalSupply = value
			_, err := input.build()
			var invalid ErrInvalidAmount
			if !errors.As(err, &invalid) {
				t.Fatalf("NewParameters() error = %v, want ErrInvalidAmount", err)
			}
		})
	}

	overflow := valid
	overflow.curveTokens = copyBig(maxUint256)
	overflow.lpTokens = big.NewInt(1)
	overflow.totalSupply = copyBig(maxUint256)
	if _, err := overflow.build(); !errors.Is(err, ErrArithmeticOverflow) {
		t.Fatalf("NewParameters() overflow error = %v", err)
	}

	if _, err := NewState(PhaseCurve, nil, big.NewInt(1), new(big.Int), new(big.Int)); err == nil {
		t.Fatal("NewState() accepted nil virtual ETH")
	}
}

func TestConstructorsAndAccessorsCopyBigInts(t *testing.T) {
	input := inputsFromParameters(vectorParameters(t))
	originalTotalSupply := copyBig(input.totalSupply)
	parameters, err := input.build()
	if err != nil {
		t.Fatalf("NewParameters() error = %v", err)
	}
	input.totalSupply.SetInt64(0)
	if parameters.TotalSupply().Cmp(originalTotalSupply) != 0 {
		t.Fatal("NewParameters() retained caller pointer")
	}
	returnedTotalSupply := parameters.TotalSupply()
	returnedTotalSupply.SetInt64(0)
	if parameters.TotalSupply().Cmp(originalTotalSupply) != 0 {
		t.Fatal("TotalSupply() exposed internal pointer")
	}

	virtualETH := parameters.InitialVirtualETH()
	virtualToken := parameters.InitialVirtualToken()
	state, err := NewState(PhaseCurve, virtualETH, virtualToken, new(big.Int), new(big.Int))
	if err != nil {
		t.Fatalf("NewState() error = %v", err)
	}
	virtualETH.SetInt64(0)
	if state.VirtualETH().Cmp(parameters.InitialVirtualETH()) != 0 {
		t.Fatal("NewState() retained caller pointer")
	}
	returnedVirtualToken := state.VirtualToken()
	returnedVirtualToken.SetInt64(0)
	if state.VirtualToken().Cmp(parameters.InitialVirtualToken()) != 0 {
		t.Fatal("VirtualToken() exposed internal pointer")
	}

	quote, err := Buy(state, parameters, big.NewInt(1_000_000))
	if err != nil {
		t.Fatalf("Buy() error = %v", err)
	}
	quote.TokensOut().SetInt64(0)
	nextState := quote.NextState()
	nextState.virtualETH.SetInt64(0)
	if quote.NextState().VirtualETH().Sign() == 0 || quote.TokensOut().Sign() == 0 {
		t.Fatal("BuyQuote exposed an internal pointer")
	}
}

func TestPhaseGatePrecedesInputValidation(t *testing.T) {
	parameters := vectorParameters(t)
	state, err := NewState(
		PhaseGraduated,
		parameters.FinalVirtualETH(),
		parameters.FinalVirtualToken(),
		new(big.Int),
		new(big.Int),
	)
	if err != nil {
		t.Fatalf("NewState() error = %v", err)
	}
	for name, quote := range map[string]func() error{
		"buy": func() error {
			_, quoteErr := Buy(state, parameters, nil)
			return quoteErr
		},
		"sell": func() error {
			_, quoteErr := Sell(state, parameters, nil)
			return quoteErr
		},
	} {
		t.Run(name, func(t *testing.T) {
			var wrongPhase ErrWrongPhase
			if err := quote(); !errors.As(err, &wrongPhase) {
				t.Fatalf("quote error = %v, want ErrWrongPhase", err)
			}
			if wrongPhase.Expected != PhaseCurve || wrongPhase.Actual != PhaseGraduated {
				t.Fatalf("wrong phase = %+v", wrongPhase)
			}
		})
	}
}

func TestClosedFormRejectsNonpositiveNetNeeded(t *testing.T) {
	parameters := vectorParameters(t)
	state, err := NewState(
		PhaseCurve,
		parameters.FinalVirtualETH(),
		new(big.Int).Add(parameters.FinalVirtualToken(), big.NewInt(1)),
		new(big.Int),
		new(big.Int),
	)
	if err != nil {
		t.Fatalf("NewState() error = %v", err)
	}
	_, err = Buy(state, parameters, big.NewInt(1_000_000_000_000_000_000))
	if !errors.Is(err, ErrInternalInvariant) {
		t.Fatalf("Buy() error = %v, want ErrInternalInvariant", err)
	}
}

func TestExactGrossForNetAcrossSupportedFeeRange(t *testing.T) {
	nets := []*big.Int{
		big.NewInt(1),
		big.NewInt(2),
		big.NewInt(9_999),
		big.NewInt(1_000_000_000),
		big.NewInt(1_000_000_000_000_000_000),
	}
	denominator := new(big.Int).SetUint64(uint64(bpsDenominator))
	for fee := uint16(0); fee < bpsDenominator; fee++ {
		feeBig := new(big.Int).SetUint64(uint64(fee))
		for _, net := range nets {
			gross, err := exactGrossForNet(net, fee)
			if err != nil {
				t.Fatalf("exactGrossForNet(%s, %d) error = %v", net, fee, err)
			}
			feeAmount := new(big.Int).Quo(new(big.Int).Mul(gross, feeBig), denominator)
			actualNet := new(big.Int).Sub(gross, feeAmount)
			if actualNet.Cmp(net) != 0 {
				t.Fatalf("fee %d: gross %s produces net %s, want %s", fee, gross, actualNet, net)
			}
		}
	}
}

func TestFullPrecisionPriceAndCheckedArithmetic(t *testing.T) {
	state, err := NewState(
		PhaseCurve,
		maxUint256,
		maxUint256,
		new(big.Int),
		new(big.Int),
	)
	if err != nil {
		t.Fatalf("NewState() error = %v", err)
	}
	price, err := SpotPriceWad(state)
	if err != nil {
		t.Fatalf("SpotPriceWad() error = %v", err)
	}
	if price.Cmp(wad) != 0 {
		t.Fatalf("SpotPriceWad() = %s, want %s", price, wad)
	}

	overflowCases := map[string]func() error{
		"add": func() error {
			_, operationErr := checkedAdd(maxUint256, big.NewInt(1))
			return operationErr
		},
		"subtract": func() error {
			_, operationErr := checkedSub(new(big.Int), big.NewInt(1))
			return operationErr
		},
		"multiply": func() error {
			_, operationErr := checkedMul(maxUint256, big.NewInt(2))
			return operationErr
		},
		"mulDiv quotient": func() error {
			_, operationErr := mulDiv(maxUint256, maxUint256, big.NewInt(1))
			return operationErr
		},
	}
	for name, operation := range overflowCases {
		t.Run(name, func(t *testing.T) {
			if err := operation(); !errors.Is(err, ErrArithmeticOverflow) {
				t.Fatalf("operation error = %v, want ErrArithmeticOverflow", err)
			}
		})
	}
	if _, err := ceilDiv(big.NewInt(1), new(big.Int)); !errors.Is(err, ErrDivisionByZero) {
		t.Fatalf("ceilDiv() error = %v, want ErrDivisionByZero", err)
	}
}

type parameterInputs struct {
	totalSupply         *big.Int
	curveTokens         *big.Int
	lpTokens            *big.Int
	graduationETH       *big.Int
	initialVirtualETH   *big.Int
	initialVirtualToken *big.Int
	tradeFeeBPS         uint16
	protocolShareBPS    uint16
}

func inputsFromParameters(parameters Parameters) parameterInputs {
	return parameterInputs{
		totalSupply:         parameters.TotalSupply(),
		curveTokens:         parameters.CurveTokens(),
		lpTokens:            parameters.LPTokens(),
		graduationETH:       parameters.GraduationETH(),
		initialVirtualETH:   parameters.InitialVirtualETH(),
		initialVirtualToken: parameters.InitialVirtualToken(),
		tradeFeeBPS:         parameters.TradeFeeBPS(),
		protocolShareBPS:    parameters.ProtocolShareBPS(),
	}
}

func (input parameterInputs) build() (Parameters, error) {
	return NewParameters(
		input.totalSupply,
		input.curveTokens,
		input.lpTokens,
		input.graduationETH,
		input.initialVirtualETH,
		input.initialVirtualToken,
		input.tradeFeeBPS,
		input.protocolShareBPS,
	)
}

func vectorParameters(t *testing.T) Parameters {
	t.Helper()
	artifact, err := LoadEmbeddedVectors()
	if err != nil {
		t.Fatalf("LoadEmbeddedVectors() error = %v", err)
	}
	return parametersFromVector(t, artifact.Parameters)
}
