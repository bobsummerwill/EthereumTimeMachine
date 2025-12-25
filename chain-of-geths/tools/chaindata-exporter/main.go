package main

import (
    "encoding/json"
    "fmt"
    "os"
    "path/filepath"
    "strconv"

    "github.com/ethereum/go-ethereum/common"
    "github.com/ethereum/go-ethereum/core/rawdb"
    "github.com/ethereum/go-ethereum/ethdb/leveldb"
    "github.com/ethereum/go-ethereum/rlp"
)

type progress struct {
    LastDone uint64 `json:"last_done"`
}

func envUint64(name string) (uint64, error) {
    v := os.Getenv(name)
    if v == "" {
        return 0, fmt.Errorf("missing env var: %s", name)
    }
    n, err := strconv.ParseUint(v, 10, 64)
    if err != nil {
        return 0, fmt.Errorf("invalid %s=%q: %w", name, v, err)
    }
    return n, nil
}

func writeProgress(path string, n uint64) error {
    b, err := json.Marshal(progress{LastDone: n})
    if err != nil {
        return err
    }
    b = append(b, '\n')
    return os.WriteFile(path, b, 0o644)
}

func main() {
    datadir := os.Getenv("DATADIR")
    if datadir == "" {
        fmt.Fprintln(os.Stderr, "missing env var: DATADIR")
        os.Exit(2)
    }
    outFile := os.Getenv("OUT_FILE")
    if outFile == "" {
        fmt.Fprintln(os.Stderr, "missing env var: OUT_FILE")
        os.Exit(2)
    }
    progressFile := os.Getenv("PROGRESS_FILE")
    if progressFile == "" {
        progressFile = outFile + ".progress"
    }
    start, err := envUint64("START_BLOCK")
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(2)
    }
    end, err := envUint64("END_BLOCK")
    if err != nil {
        fmt.Fprintln(os.Stderr, err)
        os.Exit(2)
    }
    if start > end {
        fmt.Fprintf(os.Stderr, "Nothing to do (start=%d > end=%d)\n", start, end)
        os.Exit(0)
    }

    // Geth instance dir layout: <datadir>/geth/chaindata (+ freezer under ancient)
    chaindata := filepath.Join(datadir, "geth", "chaindata")
    ancient := filepath.Join(chaindata, "ancient")

    // Open DB (must be exclusive; caller should stop geth-v1-9-25 first).
    kv, err := leveldb.New(chaindata, 128, 128, "")
    if err != nil {
        fmt.Fprintf(os.Stderr, "open leveldb failed: %v\n", err)
        os.Exit(1)
    }
    defer kv.Close()

    db, err := rawdb.NewDatabaseWithFreezer(kv, ancient, "")
    if err != nil {
        fmt.Fprintf(os.Stderr, "open freezer failed: %v\n", err)
        os.Exit(1)
    }
    defer db.Close()

    if err := os.MkdirAll(filepath.Dir(outFile), 0o755); err != nil {
        fmt.Fprintf(os.Stderr, "mkdir out dir failed: %v\n", err)
        os.Exit(1)
    }
    if err := os.MkdirAll(filepath.Dir(progressFile), 0o755); err != nil {
        fmt.Fprintf(os.Stderr, "mkdir progress dir failed: %v\n", err)
        os.Exit(1)
    }

    f, err := os.OpenFile(outFile, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o644)
    if err != nil {
        fmt.Fprintf(os.Stderr, "open out file failed: %v\n", err)
        os.Exit(1)
    }
    defer f.Close()

    fmt.Fprintf(os.Stderr, "Exporting blocks %d..%d from %s -> %s\n", start, end, chaindata, outFile)

    for n := start; n <= end; n++ {
        h := rawdb.ReadCanonicalHash(db, n)
        if h == (common.Hash{}) {
            fmt.Fprintf(os.Stderr, "missing canonical hash for block %d\n", n)
            os.Exit(1)
        }
        block := rawdb.ReadBlock(db, h, n)
        if block == nil {
            fmt.Fprintf(os.Stderr, "missing block for block %d hash=%s\n", n, h.Hex())
            os.Exit(1)
        }
        if err := rlp.Encode(f, block); err != nil {
            fmt.Fprintf(os.Stderr, "rlp encode failed at block %d: %v\n", n, err)
            os.Exit(1)
        }
        if err := writeProgress(progressFile, n); err != nil {
            fmt.Fprintf(os.Stderr, "progress write failed at block %d: %v\n", n, err)
            os.Exit(1)
        }
        if n%10000 == 0 {
            fmt.Fprintf(os.Stderr, "done %d\n", n)
        }
    }

    fmt.Fprintf(os.Stderr, "Completed %d..%d (progress=%s)\n", start, end, progressFile)
}
