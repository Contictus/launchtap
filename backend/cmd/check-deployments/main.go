// Command check-deployments verifies deployment copies without a platform shell.
package main

import (
	"bytes"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
)

func main() {
	if err := compare("../contracts/deployments", "deployments/testdata"); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func compare(source, target string) error {
	for _, roots := range [][2]string{{source, target}, {target, source}} {
		if err := filepath.WalkDir(roots[0], func(path string, entry fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if entry.IsDir() {
				if entry.Name() == ".generated" {
					return fs.SkipDir
				}
				return nil
			}
			rel, err := filepath.Rel(roots[0], path)
			if err != nil {
				return err
			}
			a, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			b, err := os.ReadFile(filepath.Join(roots[1], rel))
			if err != nil {
				return err
			}
			if !bytes.Equal(a, b) {
				return fmt.Errorf("deployment drift: %s", rel)
			}
			return nil
		}); err != nil {
			return err
		}
	}
	return nil
}
