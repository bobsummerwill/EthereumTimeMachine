# Ethereum Resurrection - Phase 2: Mining and Chain Extension

## Project Overview

Phase 2 of the Ethereum Time Machine project focuses on extending historical Ethereum chains beyond their original termination points. After establishing the chain-of-Geths infrastructure with synced Geth v1.0.3 and v1.3.6 nodes, this phase uses GPU mining with manipulated timestamps to rapidly crash chain difficulty to CPU-mineable levels.

The goal is to create functional, CPU-mineable historical chains that serve as educational testnets, allowing users to experience authentic Ethereum mining dynamics from different eras.

## Prerequisites

- Completed chain-of-Geths setup with synced Geth v1.0.3 (Frontier) and Geth v1.3.6 (Homestead) nodes
- GPU mining infrastructure (cloud GPU rental recommended - Vast.ai)
- Chaindata tarball exported from chain-of-Geths bridge nodes

## Core Objectives

1. Extend historical chains beyond their original blocks
2. Reduce mining difficulty to CPU-viable levels (~50 million, down from ~18 trillion)
3. Maintain era-specific protocol compatibility
4. Enable sustainable CPU mining for long-term operation
5. Provide educational access to historical Ethereum mining

## Available Revival Options

This phase offers two independent revival projects:

### Option 1: Homestead Era Revival (Recommended - Faster)
- **Target Era**: Pre-DAO Homestead (block 1,919,999, July 2016)
- **Starting Point**: Geth v1.3.6 synced to block 1,919,999
- **Initial Difficulty**: ~18 trillion
- **Target Difficulty**: ~50 million (CPU-mineable)
- **Blocks Required**: ~259 blocks
- **Timeline**: ~4.5 days with 8x RTX 3090 (~960 MH/s)
- **Cost**: ~$130 on Vast.ai ($1.12/hr)

### Option 2: Frontier Era Revival (Much Slower - Advanced)
- **Target Era**: Original Frontier release (blocks 0-1,149,999)
- **Starting Point**: Geth v1.0.3 synced to block 1,149,999
- **Initial Difficulty**: ~17.5 trillion
- **Target Difficulty**: ~50 million (CPU-mineable)
- **Blocks Required**: ~25,600 blocks (99x more than Homestead!)
- **Timeline**: **~4-6 months** with 8x RTX 3090
- **Cost**: ~$3,000-4,000 on Vast.ai
- **Note**: Frontier's binary difficulty algorithm lacks the -99 multiplier

## Technical Foundation

### Ethereum Difficulty Adjustment Algorithms

Both revival options rely on Ethereum's Proof-of-Work difficulty adjustment mechanisms. The key insight is that with manipulated timestamps (20-minute gaps), we can trigger maximum difficulty reduction per block.

#### Homestead Era Algorithm (EIP-2)
```
adjustment = max(1 - (timestamp_delta // 10), -99)
new_difficulty = parent_difficulty + (parent_difficulty // 2048) * adjustment + bomb
```

With a 20-minute (1200 second) timestamp gap:
- `adjustment = max(1 - (1200 // 10), -99) = max(1 - 120, -99) = -99`
- Each block reduces difficulty by: `(difficulty // 2048) * 99 ≈ 4.83%`
- **~259 blocks** to crash from 18T to 50M

#### Frontier Era Algorithm (Pre-Homestead)
```
if timestamp_delta < 13:
    new_difficulty = parent_difficulty + (parent_difficulty // 2048)
else:
    new_difficulty = parent_difficulty - (parent_difficulty // 2048)
```

With manipulated timestamps (> 13 seconds):
- Each block reduces difficulty by: `difficulty // 2048 ≈ 0.049%`
- Much slower than Homestead, but still achievable

#### Key Technical Insights

1. **Timestamp Manipulation via libfaketime**: Geth uses the system clock to propose block timestamps. By using `libfaketime`, we can lie about the current time, making geth propose blocks with 20-minute gaps without actually waiting.

2. **Consensus Compatibility**: Ethereum only requires:
   - `block.timestamp > parent.timestamp` (always satisfied)
   - `block.timestamp <= now + 15 seconds` (checked against node's clock, not parent)
   - Since we're lying about "now", our blocks pass validation

3. **Difficulty Bomb**: Based on block number only, not timestamps. A 10-year timestamp gap doesn't accelerate the bomb - we only add ~259 blocks, so bomb impact is negligible.

4. **Mining Requirements**: At 18T difficulty with 960 MH/s (8x RTX 3090), expected block time is ~5.2 hours. Total mining time is dominated by the first few blocks.

## Option 1: Homestead Era Revival (Recommended)

### Overview
Extend the pre-DAO Homestead chain (block 1,919,999) using Geth v1.3.6 with its improved difficulty adjustment algorithm (EIP-2) for faster difficulty reduction.

### Technical Specifications
- **Starting Block**: 1,919,999 (pre-DAO, from chain-of-geths bridge)
- **Initial Difficulty**: ~18 trillion
- **Target Difficulty**: ~50 million (CPU-mineable)
- **Blocks Required**: ~259 blocks
- **Gas Limit**: Dynamic (3M-4.7M range)
- **Block Reward**: 5 ETH

### Difficulty Progression (8x RTX 3090, 960 MH/s)

| Block | Difficulty | Block Time | Cumulative Time |
|-------|------------|------------|-----------------|
| 1 | 18.0T | 5.2 hours | 5.2 hours |
| 50 | 1.6T | 28 minutes | 27.4 hours |
| 100 | 144B | 2.5 minutes | 37.0 hours |
| 150 | 13B | 13.5 seconds | 40.6 hours |
| 200 | 1.1B | 1.2 seconds | 41.2 hours |
| 259 | 50M | instant | ~107 hours |

### Mining Architecture

```
[Vast.ai GPU Instance]
     |
     +-- docker-compose.yml
           |
           +-- geth (v1.3.6)
           |     - Runs with libfaketime
           |     - geth_time_stepper.py advances fake time after each block
           |     - Proposes blocks with 20-minute timestamp gaps
           |
           +-- ethminer (Genoil)
                 - Uses getwork RPC API
                 - Mines against geth's eth_getWork endpoint
```

### Cost Breakdown (Vast.ai)

| GPU Config | Hashrate | Time | Cost |
|------------|----------|------|------|
| 1x RTX 3090 | 120 MH/s | ~36 days | ~$140 |
| 4x RTX 3090 | 480 MH/s | ~9 days | ~$130 |
| 8x RTX 3090 | 960 MH/s | ~4.5 days | ~$130 |

Recommendation: **8x RTX 3090** for fastest completion at similar cost.

### Success Criteria
- Difficulty reduced to < 100 million
- Chain extended 259+ blocks beyond 1,919,999
- CPU can mine blocks in < 1 minute

## Option 2: Frontier Era Revival

### Overview
Extend the original Frontier chain using Geth v1.0.3 for the purest historical experience. **This is significantly harder than Homestead** due to the simpler difficulty algorithm.

### Technical Specifications
- **Starting Block**: ~1,149,999 (from chain-of-geths Frontier node)
- **Initial Difficulty**: ~17.5 trillion
- **Target Difficulty**: ~50 million (CPU-mineable)
- **Blocks Required**: ~25,600 blocks
- **Gas Limit**: Dynamic
- **Block Reward**: 5 ETH

### Why Frontier is 99x Harder

The Frontier difficulty algorithm only reduces by a fixed `1/2048` (~0.049%) per block when timestamp delta > 13 seconds:

```
if timestamp_delta >= 13:
    new_difficulty = parent_difficulty - (parent_difficulty // 2048)
```

There is **no multiplier** like Homestead's `-99`. Each block only removes `difficulty // 2048`, regardless of how large the timestamp gap is.

| Era | Reduction per block | Blocks to crash 17T→50M |
|-----|---------------------|-------------------------|
| Homestead | ~4.83% (with -99 multiplier) | ~259 |
| Frontier | ~0.049% (fixed 1/2048) | ~25,600 |

### Cost Estimate (Vast.ai)

| GPU Config | Time | Cost |
|------------|------|------|
| 8x RTX 3090 | ~4-6 months | ~$3,000-4,000 |

### Recommendation

**Start with Homestead.** Frontier revival is a much larger undertaking and may not be cost-effective with GPU rental. Consider:
- Personal GPU hardware running continuously
- Accepting a higher target difficulty (e.g., 1 billion instead of 50 million)
- Lower priority after Homestead is complete

## Implementation: Vast.ai Deployment

The [resurrection/vast-homestead/](resurrection/vast-homestead/) folder contains everything needed to deploy on Vast.ai:

### Quick Start

```bash
# 1. Generate deterministic identity
cd resurrection/vast-homestead
./generate-identity.sh

# 2. Search for 8x RTX 3090 instances
~/.local/vastai-venv/bin/vastai search offers 'num_gpus=8 gpu_name=RTX_3090 inet_down>100' -o 'dph'

# 3. Create instance (replace INSTANCE_ID)
~/.local/vastai-venv/bin/vastai create instance INSTANCE_ID --image nvidia/cuda:11.8.0-devel-ubuntu22.04

# 4. Upload chaindata (~27GB, ~6-7 hours over SSH)
rsync -avzP --progress chaindata.tar.gz root@sshX.vast.ai:/root/ -e "ssh -p PORT"

# 5. Upload code and start mining
rsync -avzP resurrection/vast-homestead/ root@sshX.vast.ai:/root/vast-homestead/ -e "ssh -p PORT"
ssh -p PORT root@sshX.vast.ai "cd /root/vast-homestead && docker compose up --build -d"
```

### Monitoring

```bash
# Watch mining progress
ssh -p PORT root@sshX.vast.ai "docker logs -f vast-homestead-geth"

# Check current block/difficulty
ssh -p PORT root@sshX.vast.ai 'curl -s -X POST -H "Content-Type: application/json" \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}" \
  http://localhost:8545'
```

### Automation Script

The [overnight-mining-automation.sh](resurrection/vast-homestead/overnight-mining-automation.sh) script handles:
- Uploading chaindata
- Starting docker-compose
- Periodic status checks
- Automatic logging

## Conclusion

Phase 2 uses GPU cloud computing (Vast.ai) to rapidly crash historical chain difficulty. With 8x RTX 3090 GPUs (~$1.12/hr), the difficulty can be reduced from 18 trillion to CPU-mineable levels (~50 million) in approximately 4.5 days at a total cost of ~$130.

**Current Status**: Homestead chain extension in progress on Vast.ai instance 29620927 (8x RTX 3090, Croatia).
