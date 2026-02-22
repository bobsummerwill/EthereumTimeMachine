# Ethereum Time Machine

Running authentic historical Ethereum software on contemporary hardware.

## Overview

The Ethereum Time Machine enables anyone to experience Ethereum as it was in 2015-2016 — the original Mist wallet, Frontier and Homestead geth, the whole stack. It consists of three components:

1. **Chain of Geths** — A protocol bridge chain that syncs modern mainnet chaindata down to ancient geth versions
2. **Resurrection** — GPU mining to crash historical chain difficulty from ~62 TH to CPU-mineable levels
3. **Running Mist** — The original Mist wallet running against historical geth via IPC

## Chain of Geths

A Docker Compose stack of 6 geth versions (v1.0.2 through v1.16.7) plus Lighthouse, wired together so adjacent nodes share overlapping `eth/*` subprotocols. This creates a protocol bridge from modern post-Merge Ethereum all the way down to Frontier-era geth.

```
lighthouse v8.0.1 + geth v1.16.7 (eth/68-69)  ← syncs mainnet
        ↓ offline RLP export/import
    geth v1.11.6 (eth/66-68)
        ↓ P2P eth/66
    geth v1.10.8 (eth/65-66)
        ↓ P2P eth/65
    geth v1.9.25 (eth/63-65)
        ↓ P2P eth/63
    geth v1.3.6 (eth/61-63)   ← Homestead
        ↓ P2P eth/61
    geth v1.0.2 (eth/60-61)   ← Frontier
```

The modern EL+CL pair syncs mainnet normally, then historical blocks are exported via RLP and imported into legacy nodes — bypassing the post-Merge consensus client requirement that makes it impossible to sync old geth versions directly.

Includes Prometheus + Grafana monitoring, deterministic key generation for static peering, and automated AWS EC2 deployment.

See [`chain-of-geths/README.md`](chain-of-geths/README.md) for full architecture, deployment guide, and workarounds.

## Resurrection

GPU mining to extend Homestead beyond block 1,920,000 (the DAO fork block), crashing difficulty so anyone can CPU-mine new blocks.

### Status: Mining Complete ✅

Difficulty reduced from **62.38 TH → 1.26 GH** (99.998% reduction) in 14 days.

| Date | Block | Difficulty | Reduction |
|------|-------|------------|-----------|
| Jan 15 | 1,920,000 | 59.4 TH | 0% |
| Jan 22 | 1,920,022 | 20.8 TH | 65% |
| Jan 26 | 1,920,074 | 2.0 TH | 96.6% |
| **Jan 29** | **1,920,944** | **1.26 GH** | **99.998%** |

Mining used 8x RTX 3090 GPUs (~846 MH/s) on Vast.ai. Homestead's difficulty algorithm (`max(1 - timestamp_delta/10, -99)`) allows ~4.83% reduction per block with large timestamp gaps — the natural 20-hour block time at high difficulty maxes this out automatically.

### Revival Options

|  | Homestead | Frontier |
|--|-----------|----------|
| Start difficulty | 62.38 TH | ~20.5 TH |
| Blocks needed | ~316 | ~26,500 |
| Time (8x RTX 3090) | ~18 days | ~19 months |
| Cost | ~$525 | ~$17,000 |

Frontier is dramatically slower because its difficulty algorithm only reduces by 1/2048 (~0.049%) per block regardless of timestamp gap.

See [`resurrection/README.md`](resurrection/README.md) for deployment scripts, difficulty math, troubleshooting, and the work expiration bug fix.

## Running Mist

The original Mist wallet and Ethereum Wallet running against historical geth versions via IPC. Version matching is critical — the IPC protocol evolved between releases.

### Confirmed Working Combinations

| Geth | Mist/Wallet | Era |
|------|-------------|-----|
| v1.1.0 (Aug 2015) | 0.2.6 (Sep 2015) | Frontier |
| v1.3.6 (Apr 2016) | 0.7.4 (May 2016) | Homestead |

Includes a complete Mist release table (0.2.6 through 0.11.1), Ethereum hard fork compatibility matrix, macOS version recommendations (10.12 Sierra is the sweet spot for old geth), Win64 and macOS binary download links, and troubleshooting for IPC mismatches and Go runtime issues on modern macOS.

Tested on 2010 ThinkPads with 4GB RAM.

See [`running-mist/README.md`](running-mist/README.md) for the full compatibility guide.

## Infographic

Open [`infographic.html`](infographic.html) in a browser for a visual overview.

## License

See [LICENSE](LICENSE).
