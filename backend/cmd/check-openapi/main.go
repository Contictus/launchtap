package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
)

func main() {
	b, err := os.ReadFile("openapi/v1.json")
	if err != nil {
		panic(err)
	}
	var doc struct {
		OpenAPI string                     `json:"openapi"`
		Paths   map[string]json.RawMessage `json:"paths"`
	}
	dec := json.NewDecoder(bytes.NewReader(b))
	if err := dec.Decode(&doc); err != nil {
		panic(err)
	}
	if doc.OpenAPI != "3.1.0" || len(doc.Paths) == 0 {
		panic("invalid OpenAPI contract")
	}
	for _, path := range []string{"/v1/healthz", "/v1/readyz", "/v1/tokens"} {
		if _, ok := doc.Paths[path]; !ok {
			panic(fmt.Sprintf("missing path %s", path))
		}
	}
}
