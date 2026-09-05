package curve

import (
	"encoding/json"
	"errors"
	"io/fs"
	"strings"
	"testing"
)

func TestLoadEmbeddedVectors(t *testing.T) {
	artifact, err := LoadEmbeddedVectors()
	if err != nil {
		t.Fatalf("LoadEmbeddedVectors() error = %v", err)
	}
	if artifact.SchemaVersion != 1 || artifact.EngineVersion != 1 {
		t.Fatalf("versions = schema %d, engine %d", artifact.SchemaVersion, artifact.EngineVersion)
	}
	if len(artifact.Cases) < 11 {
		t.Fatalf("len(Cases) = %d, want at least 11", len(artifact.Cases))
	}
	if artifact.Parameters.TotalSupply != "1000000000000000000000000000" {
		t.Fatalf("TotalSupply = %q", artifact.Parameters.TotalSupply)
	}
	if artifact.Cases[0].Input.TokensIn != "0" {
		t.Fatalf("first TokensIn = %q, want present zero amount", artifact.Cases[0].Input.TokensIn)
	}
	if artifact.Cases[0].Output == nil || artifact.Cases[0].ExpectedRevert != nil {
		t.Fatal("first case nullable fields were not preserved")
	}
	if artifact.Cases[7].Output != nil || artifact.Cases[7].ExpectedRevert == nil {
		t.Fatal("revert case nullable fields were not preserved")
	}

	requiredCases := map[string]bool{
		"buy_normal":                       false,
		"buy_one_wei":                      false,
		"buy_fee_split_dust":               false,
		"buy_final_exact":                  false,
		"buy_final_refund_and_graduation":  false,
		"sell_normal":                      false,
		"sell_full":                        false,
		"invalid_buy_zero_input":           false,
		"invalid_sell_zero_input":          false,
		"invalid_sell_oversell":            false,
		"invalid_sell_one_wei_zero_output": false,
	}
	for _, vectorCase := range artifact.Cases {
		if _, required := requiredCases[vectorCase.ID]; required {
			requiredCases[vectorCase.ID] = true
		}
	}
	for id, found := range requiredCases {
		if !found {
			t.Errorf("required vector case %q is missing", id)
		}
	}
}

func TestLoadVectorsRejectsInvalidArtifacts(t *testing.T) {
	tests := map[string]func(map[string]any){
		"unknown field": func(value map[string]any) {
			value["unexpected"] = true
		},
		"unknown nested output field": func(value map[string]any) {
			firstCase(value)["output"].(map[string]any)["unexpected"] = true
		},
		"missing required field": func(value map[string]any) {
			delete(value, "amountEncoding")
		},
		"missing nested required field": func(value map[string]any) {
			delete(firstCase(value)["input"].(map[string]any), "ethGross")
		},
		"malformed amount": func(value map[string]any) {
			value["parameters"].(map[string]any)["totalSupply"] = "01"
		},
		"malformed case id": func(value map[string]any) {
			firstCase(value)["id"] = "BUY-NORMAL"
		},
		"unknown operation": func(value map[string]any) {
			firstCase(value)["operation"] = "swap"
		},
		"unknown phase": func(value map[string]any) {
			firstCase(value)["initialState"].(map[string]any)["phase"] = "pending"
		},
		"malformed revert hex": func(value map[string]any) {
			cases := value["cases"].([]any)
			cases[7].(map[string]any)["expectedRevert"].(map[string]any)["data"] = "0xAB"
		},
		"trade fee out of range": func(value map[string]any) {
			value["parameters"].(map[string]any)["tradeFeeBps"] = float64(10000)
		},
		"protocol share out of range": func(value map[string]any) {
			value["parameters"].(map[string]any)["protocolShareBps"] = float64(10001)
		},
		"fewer than minimum cases": func(value map[string]any) {
			value["cases"] = value["cases"].([]any)[:10]
		},
		"invalid nullable output": func(value map[string]any) {
			firstCase(value)["output"] = "not-an-object"
		},
		"missing nullable field": func(value map[string]any) {
			delete(firstCase(value), "expectedRevert")
		},
		"wrong schema const": func(value map[string]any) {
			value["schemaVersion"] = float64(2)
		},
	}

	source := embeddedJSON(t)
	for name, mutate := range tests {
		t.Run(name, func(t *testing.T) {
			body := mutateJSON(t, source, mutate)
			if _, err := LoadVectors(strings.NewReader(body)); err == nil {
				t.Fatal("LoadVectors() error = nil")
			}
		})
	}
}

func TestLoadVectorsRejectsTrailingContent(t *testing.T) {
	if _, err := LoadVectors(strings.NewReader(embeddedJSON(t) + `{}`)); err == nil {
		t.Fatal("LoadVectors() error = nil for trailing JSON")
	}
}

func embeddedJSON(t *testing.T) string {
	t.Helper()
	body, err := fs.ReadFile(embeddedVectors, embeddedVectorPath)
	if err != nil {
		t.Fatalf("read embedded vectors: %v", err)
	}
	return string(body)
}

func mutateJSON(t *testing.T, source string, mutate func(map[string]any)) string {
	t.Helper()
	var value map[string]any
	if err := json.Unmarshal([]byte(source), &value); err != nil {
		t.Fatalf("decode fixture: %v", err)
	}
	mutate(value)
	body, err := json.Marshal(value)
	if err != nil {
		t.Fatalf("encode fixture: %v", err)
	}
	return string(body)
}

func firstCase(value map[string]any) map[string]any {
	return value["cases"].([]any)[0].(map[string]any)
}

func TestEmbeddedVectorFileExists(t *testing.T) {
	_, err := fs.Stat(embeddedVectors, embeddedVectorPath)
	if errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("embedded vector file is missing: %v", err)
	}
	if err != nil {
		t.Fatalf("stat embedded vector file: %v", err)
	}
}
