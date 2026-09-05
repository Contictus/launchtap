package curve

import (
	"bytes"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"regexp"
	"strings"
)

const embeddedVectorPath = "testdata/curve-v1.json"

var (
	//go:embed testdata/curve-v1.json
	embeddedVectors embed.FS

	amountPattern = regexp.MustCompile(`^(0|[1-9][0-9]*)$`)
	caseIDPattern = regexp.MustCompile(`^[a-z0-9_]+$`)
	revertPattern = regexp.MustCompile(`^0x[0-9a-f]+$`)
)

// VectorArtifact is the validated, versioned Solidity curve-vector artifact.
// Amount fields intentionally remain decimal strings until the arithmetic
// mirror consumes them.
type VectorArtifact struct {
	Schema         string           `json:"$schema"`
	SchemaVersion  int              `json:"schemaVersion"`
	EngineVersion  int              `json:"engineVersion"`
	AmountEncoding string           `json:"amountEncoding"`
	Parameters     VectorParameters `json:"parameters"`
	Cases          []VectorCase     `json:"cases"`
}

type VectorParameters struct {
	TotalSupply         string `json:"totalSupply"`
	CurveTokens         string `json:"curveTokens"`
	LPTokens            string `json:"lpTokens"`
	GraduationETH       string `json:"graduationEth"`
	InitialVirtualETH   string `json:"initialVirtualEth"`
	InitialVirtualToken string `json:"initialVirtualToken"`
	TradeFeeBPS         int    `json:"tradeFeeBps"`
	ProtocolShareBPS    int    `json:"protocolShareBps"`
}

type VectorState struct {
	Phase        string `json:"phase"`
	VirtualETH   string `json:"virtualEth"`
	VirtualToken string `json:"virtualToken"`
	TokensSold   string `json:"tokensSold"`
	RealCurveETH string `json:"realCurveEth"`
	ProtocolFees string `json:"protocolFees"`
	CreatorFees  string `json:"creatorFees"`
}

type VectorInput struct {
	ETHGross string `json:"ethGross"`
	TokensIn string `json:"tokensIn"`
}

type VectorOutput struct {
	ETHGross    string `json:"ethGross"`
	ETHRefund   string `json:"ethRefund"`
	ETHOut      string `json:"ethOut"`
	TokenAmount string `json:"tokenAmount"`
	ProtocolFee string `json:"protocolFee"`
	CreatorFee  string `json:"creatorFee"`
	Graduates   bool   `json:"graduates"`
}

type VectorRevert struct {
	Name string `json:"name"`
	Data string `json:"data"`
}

type VectorCase struct {
	ID             string        `json:"id"`
	Operation      string        `json:"operation"`
	InitialState   VectorState   `json:"initialState"`
	Input          VectorInput   `json:"input"`
	Output         *VectorOutput `json:"output"`
	NextState      VectorState   `json:"nextState"`
	ExpectedRevert *VectorRevert `json:"expectedRevert"`
}

// LoadEmbeddedVectors loads the committed backend copy of the Solidity vectors.
func LoadEmbeddedVectors() (VectorArtifact, error) {
	body, err := embeddedVectors.ReadFile(embeddedVectorPath)
	if err != nil {
		return VectorArtifact{}, fmt.Errorf("read embedded curve vectors: %w", err)
	}

	artifact, err := LoadVectors(bytes.NewReader(body))
	if err != nil {
		return VectorArtifact{}, fmt.Errorf("load embedded curve vectors: %w", err)
	}
	return artifact, nil
}

// LoadVectors decodes and validates one curve-vector JSON document against the
// locked v1 schema using only the standard library.
func LoadVectors(reader io.Reader) (VectorArtifact, error) {
	decoder := json.NewDecoder(reader)
	decoder.DisallowUnknownFields()

	var raw rawArtifact
	if err := decoder.Decode(&raw); err != nil {
		return VectorArtifact{}, fmt.Errorf("decode curve vectors: %w", err)
	}
	var trailing json.RawMessage
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		if err == nil {
			return VectorArtifact{}, errors.New("decode curve vectors: trailing JSON value")
		}
		return VectorArtifact{}, fmt.Errorf("decode curve vectors trailing content: %w", err)
	}

	artifact, err := raw.validate()
	if err != nil {
		return VectorArtifact{}, fmt.Errorf("validate curve vectors: %w", err)
	}
	return artifact, nil
}

type rawArtifact struct {
	Schema         *string        `json:"$schema"`
	SchemaVersion  *int           `json:"schemaVersion"`
	EngineVersion  *int           `json:"engineVersion"`
	AmountEncoding *string        `json:"amountEncoding"`
	Parameters     *rawParameters `json:"parameters"`
	Cases          *[]rawCase     `json:"cases"`
}

type rawParameters struct {
	TotalSupply         *string `json:"totalSupply"`
	CurveTokens         *string `json:"curveTokens"`
	LPTokens            *string `json:"lpTokens"`
	GraduationETH       *string `json:"graduationEth"`
	InitialVirtualETH   *string `json:"initialVirtualEth"`
	InitialVirtualToken *string `json:"initialVirtualToken"`
	TradeFeeBPS         *int    `json:"tradeFeeBps"`
	ProtocolShareBPS    *int    `json:"protocolShareBps"`
}

type rawState struct {
	Phase        *string `json:"phase"`
	VirtualETH   *string `json:"virtualEth"`
	VirtualToken *string `json:"virtualToken"`
	TokensSold   *string `json:"tokensSold"`
	RealCurveETH *string `json:"realCurveEth"`
	ProtocolFees *string `json:"protocolFees"`
	CreatorFees  *string `json:"creatorFees"`
}

type rawInput struct {
	ETHGross *string `json:"ethGross"`
	TokensIn *string `json:"tokensIn"`
}

type rawOutput struct {
	ETHGross    *string `json:"ethGross"`
	ETHRefund   *string `json:"ethRefund"`
	ETHOut      *string `json:"ethOut"`
	TokenAmount *string `json:"tokenAmount"`
	ProtocolFee *string `json:"protocolFee"`
	CreatorFee  *string `json:"creatorFee"`
	Graduates   *bool   `json:"graduates"`
}

type rawRevert struct {
	Name *string `json:"name"`
	Data *string `json:"data"`
}

type rawCase struct {
	ID             *string         `json:"id"`
	Operation      *string         `json:"operation"`
	InitialState   *rawState       `json:"initialState"`
	Input          *rawInput       `json:"input"`
	Output         json.RawMessage `json:"output"`
	NextState      *rawState       `json:"nextState"`
	ExpectedRevert json.RawMessage `json:"expectedRevert"`
}

func (raw rawArtifact) validate() (VectorArtifact, error) {
	if err := requireConst("$schema", raw.Schema, "./curve.schema.json"); err != nil {
		return VectorArtifact{}, err
	}
	if err := requireIntConst("schemaVersion", raw.SchemaVersion, 1); err != nil {
		return VectorArtifact{}, err
	}
	if err := requireIntConst("engineVersion", raw.EngineVersion, 1); err != nil {
		return VectorArtifact{}, err
	}
	if err := requireConst("amountEncoding", raw.AmountEncoding, "uint256-decimal-string"); err != nil {
		return VectorArtifact{}, err
	}
	if raw.Parameters == nil {
		return VectorArtifact{}, errors.New("parameters is required and must be an object")
	}
	parameters, err := raw.Parameters.validate()
	if err != nil {
		return VectorArtifact{}, fmt.Errorf("parameters: %w", err)
	}
	if raw.Cases == nil {
		return VectorArtifact{}, errors.New("cases is required and must be an array")
	}
	if len(*raw.Cases) < 11 {
		return VectorArtifact{}, fmt.Errorf("cases must contain at least 11 entries, got %d", len(*raw.Cases))
	}
	cases := make([]VectorCase, len(*raw.Cases))
	for index, rawCase := range *raw.Cases {
		parsed, parseErr := rawCase.validate()
		if parseErr != nil {
			return VectorArtifact{}, fmt.Errorf("cases[%d]: %w", index, parseErr)
		}
		cases[index] = parsed
	}
	return VectorArtifact{
		Schema:         *raw.Schema,
		SchemaVersion:  *raw.SchemaVersion,
		EngineVersion:  *raw.EngineVersion,
		AmountEncoding: *raw.AmountEncoding,
		Parameters:     parameters,
		Cases:          cases,
	}, nil
}

func (raw rawParameters) validate() (VectorParameters, error) {
	amounts := []struct {
		name  string
		value *string
	}{
		{"totalSupply", raw.TotalSupply},
		{"curveTokens", raw.CurveTokens},
		{"lpTokens", raw.LPTokens},
		{"graduationEth", raw.GraduationETH},
		{"initialVirtualEth", raw.InitialVirtualETH},
		{"initialVirtualToken", raw.InitialVirtualToken},
	}
	for _, amount := range amounts {
		if err := requirePattern(amount.name, amount.value, amountPattern); err != nil {
			return VectorParameters{}, err
		}
	}
	if err := requireRange("tradeFeeBps", raw.TradeFeeBPS, 0, 9999); err != nil {
		return VectorParameters{}, err
	}
	if err := requireRange("protocolShareBps", raw.ProtocolShareBPS, 0, 10000); err != nil {
		return VectorParameters{}, err
	}
	return VectorParameters{
		TotalSupply:         *raw.TotalSupply,
		CurveTokens:         *raw.CurveTokens,
		LPTokens:            *raw.LPTokens,
		GraduationETH:       *raw.GraduationETH,
		InitialVirtualETH:   *raw.InitialVirtualETH,
		InitialVirtualToken: *raw.InitialVirtualToken,
		TradeFeeBPS:         *raw.TradeFeeBPS,
		ProtocolShareBPS:    *raw.ProtocolShareBPS,
	}, nil
}

func (raw rawCase) validate() (VectorCase, error) {
	if err := requirePattern("id", raw.ID, caseIDPattern); err != nil {
		return VectorCase{}, err
	}
	if err := requireEnum("operation", raw.Operation, "buy", "sell"); err != nil {
		return VectorCase{}, err
	}
	if raw.InitialState == nil {
		return VectorCase{}, errors.New("initialState is required and must be an object")
	}
	initialState, err := raw.InitialState.validate("initialState")
	if err != nil {
		return VectorCase{}, err
	}
	if raw.Input == nil {
		return VectorCase{}, errors.New("input is required and must be an object")
	}
	input, err := raw.Input.validate()
	if err != nil {
		return VectorCase{}, err
	}
	output, err := decodeNullable[rawOutput, VectorOutput]("output", raw.Output, func(value rawOutput) (VectorOutput, error) {
		return value.validate()
	})
	if err != nil {
		return VectorCase{}, err
	}
	if raw.NextState == nil {
		return VectorCase{}, errors.New("nextState is required and must be an object")
	}
	nextState, err := raw.NextState.validate("nextState")
	if err != nil {
		return VectorCase{}, err
	}
	expectedRevert, err := decodeNullable[rawRevert, VectorRevert]("expectedRevert", raw.ExpectedRevert, func(value rawRevert) (VectorRevert, error) {
		return value.validate()
	})
	if err != nil {
		return VectorCase{}, err
	}
	return VectorCase{
		ID:             *raw.ID,
		Operation:      *raw.Operation,
		InitialState:   initialState,
		Input:          input,
		Output:         output,
		NextState:      nextState,
		ExpectedRevert: expectedRevert,
	}, nil
}

func (raw rawState) validate(name string) (VectorState, error) {
	if err := requireEnum(name+".phase", raw.Phase, "curve", "graduated"); err != nil {
		return VectorState{}, err
	}
	amounts := []struct {
		name  string
		value *string
	}{
		{"virtualEth", raw.VirtualETH},
		{"virtualToken", raw.VirtualToken},
		{"tokensSold", raw.TokensSold},
		{"realCurveEth", raw.RealCurveETH},
		{"protocolFees", raw.ProtocolFees},
		{"creatorFees", raw.CreatorFees},
	}
	for _, amount := range amounts {
		if err := requirePattern(name+"."+amount.name, amount.value, amountPattern); err != nil {
			return VectorState{}, err
		}
	}
	return VectorState{
		Phase:        *raw.Phase,
		VirtualETH:   *raw.VirtualETH,
		VirtualToken: *raw.VirtualToken,
		TokensSold:   *raw.TokensSold,
		RealCurveETH: *raw.RealCurveETH,
		ProtocolFees: *raw.ProtocolFees,
		CreatorFees:  *raw.CreatorFees,
	}, nil
}

func (raw rawInput) validate() (VectorInput, error) {
	if err := requirePattern("input.ethGross", raw.ETHGross, amountPattern); err != nil {
		return VectorInput{}, err
	}
	if err := requirePattern("input.tokensIn", raw.TokensIn, amountPattern); err != nil {
		return VectorInput{}, err
	}
	return VectorInput{ETHGross: *raw.ETHGross, TokensIn: *raw.TokensIn}, nil
}

func (raw rawOutput) validate() (VectorOutput, error) {
	amounts := []struct {
		name  string
		value *string
	}{
		{"ethGross", raw.ETHGross},
		{"ethRefund", raw.ETHRefund},
		{"ethOut", raw.ETHOut},
		{"tokenAmount", raw.TokenAmount},
		{"protocolFee", raw.ProtocolFee},
		{"creatorFee", raw.CreatorFee},
	}
	for _, amount := range amounts {
		if err := requirePattern("output."+amount.name, amount.value, amountPattern); err != nil {
			return VectorOutput{}, err
		}
	}
	if raw.Graduates == nil {
		return VectorOutput{}, errors.New("output.graduates is required and must be a boolean")
	}
	return VectorOutput{
		ETHGross:    *raw.ETHGross,
		ETHRefund:   *raw.ETHRefund,
		ETHOut:      *raw.ETHOut,
		TokenAmount: *raw.TokenAmount,
		ProtocolFee: *raw.ProtocolFee,
		CreatorFee:  *raw.CreatorFee,
		Graduates:   *raw.Graduates,
	}, nil
}

func (raw rawRevert) validate() (VectorRevert, error) {
	if raw.Name == nil || *raw.Name == "" {
		return VectorRevert{}, errors.New("expectedRevert.name is required and must not be empty")
	}
	if err := requirePattern("expectedRevert.data", raw.Data, revertPattern); err != nil {
		return VectorRevert{}, err
	}
	return VectorRevert{Name: *raw.Name, Data: *raw.Data}, nil
}

func decodeNullable[Raw any, Value any](name string, body json.RawMessage, validate func(Raw) (Value, error)) (*Value, error) {
	if body == nil {
		return nil, fmt.Errorf("%s is required", name)
	}
	if bytes.Equal(bytes.TrimSpace(body), []byte("null")) {
		return nil, nil
	}
	decoder := json.NewDecoder(strings.NewReader(string(body)))
	decoder.DisallowUnknownFields()
	var raw Raw
	if err := decoder.Decode(&raw); err != nil {
		return nil, fmt.Errorf("%s must be an object or null: %w", name, err)
	}
	var trailing json.RawMessage
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		return nil, fmt.Errorf("%s contains trailing JSON", name)
	}
	value, err := validate(raw)
	if err != nil {
		return nil, err
	}
	return &value, nil
}

func requireConst(name string, value *string, expected string) error {
	if value == nil {
		return fmt.Errorf("%s is required", name)
	}
	if *value != expected {
		return fmt.Errorf("%s must be %q", name, expected)
	}
	return nil
}

func requireIntConst(name string, value *int, expected int) error {
	if value == nil {
		return fmt.Errorf("%s is required", name)
	}
	if *value != expected {
		return fmt.Errorf("%s must be %d", name, expected)
	}
	return nil
}

func requirePattern(name string, value *string, pattern *regexp.Regexp) error {
	if value == nil {
		return fmt.Errorf("%s is required", name)
	}
	if !pattern.MatchString(*value) {
		return fmt.Errorf("%s has invalid format", name)
	}
	return nil
}

func requireEnum(name string, value *string, allowed ...string) error {
	if value == nil {
		return fmt.Errorf("%s is required", name)
	}
	for _, candidate := range allowed {
		if *value == candidate {
			return nil
		}
	}
	return fmt.Errorf("%s has unsupported value %q", name, *value)
}

func requireRange(name string, value *int, minimum, maximum int) error {
	if value == nil {
		return fmt.Errorf("%s is required", name)
	}
	if *value < minimum || *value > maximum {
		return fmt.Errorf("%s must be between %d and %d", name, minimum, maximum)
	}
	return nil
}
