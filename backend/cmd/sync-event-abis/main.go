package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
)

const (
	defaultSource      = "../contracts/abi/v1"
	defaultDestination = "internal/chain/abi/v1"
	fixtureSource      = "../contracts/fixtures/v1"
	fixtureDestination = "internal/chain/testdata"
)

func main() {
	check := flag.Bool("check", false, "fail unless the destination is byte-identical to the source")
	flag.Parse()

	var err error
	if *check {
		err = syncPaths(true)
	} else {
		err = syncPaths(false)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func syncPaths(check bool) error {
	for _, pair := range [][2]string{{defaultSource, defaultDestination}, {fixtureSource, fixtureDestination}} {
		if !check {
			if err := copyDirectory(pair[0], pair[1]); err != nil {
				return err
			}
		}
		if err := compareDirectories(pair[0], pair[1]); err != nil {
			return err
		}
	}
	return nil
}

func copyDirectory(source, destination string) error {
	return filepath.WalkDir(source, func(sourcePath string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		relative, err := filepath.Rel(source, sourcePath)
		if err != nil {
			return err
		}
		destinationPath := filepath.Join(destination, relative)
		if entry.IsDir() {
			return os.MkdirAll(destinationPath, 0o755)
		}
		body, err := os.ReadFile(sourcePath)
		if err != nil {
			return err
		}
		return os.WriteFile(destinationPath, body, 0o644)
	})
}

func compareDirectories(source, destination string) error {
	sourceFiles, err := readDirectory(source)
	if err != nil {
		return fmt.Errorf("read source event ABIs: %w", err)
	}
	destinationFiles, err := readDirectory(destination)
	if err != nil {
		return fmt.Errorf("read backend event ABI copy: %w", err)
	}
	sourceNames := sortedNames(sourceFiles)
	destinationNames := sortedNames(destinationFiles)
	if !slices.Equal(sourceNames, destinationNames) {
		return fmt.Errorf("event-ABI file set differs: source %v, destination %v", sourceNames, destinationNames)
	}
	for _, name := range sourceNames {
		if !bytes.Equal(sourceFiles[name], destinationFiles[name]) {
			return fmt.Errorf("event-ABI file differs: %s", name)
		}
	}
	return nil
}

func readDirectory(root string) (map[string][]byte, error) {
	files := make(map[string][]byte)
	err := filepath.WalkDir(root, func(filePath string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() {
			return nil
		}
		relative, err := filepath.Rel(root, filePath)
		if err != nil {
			return err
		}
		body, err := os.ReadFile(filePath)
		if err != nil {
			return err
		}
		files[filepath.ToSlash(relative)] = body
		return nil
	})
	if errors.Is(err, fs.ErrNotExist) {
		return nil, fmt.Errorf("directory %q does not exist", root)
	}
	return files, err
}

func sortedNames(files map[string][]byte) []string {
	names := make([]string, 0, len(files))
	for name := range files {
		names = append(names, name)
	}
	slices.Sort(names)
	return names
}
