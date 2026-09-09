package main

import (
	"bytes"
	"flag"
	"os"

	"github.com/Contictus/launchtap/backend/internal/apiserver"
)

func main() {
	write := flag.Bool("write", false, "write the generated contract")
	flag.Parse()
	generated, err := apiserver.GenerateOpenAPI()
	if err != nil {
		panic(err)
	}
	if *write {
		if err := os.WriteFile("openapi/v1.json", generated, 0o644); err != nil {
			panic(err)
		}
		return
	}
	committed, err := os.ReadFile("openapi/v1.json")
	if err != nil {
		panic(err)
	}
	if !bytes.Equal(generated, committed) {
		panic("openapi/v1.json is stale; run check-openapi --write")
	}
}
