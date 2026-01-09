# Ethereum Resurrection

GPU mining to extend historical chains beyond their original blocks, reducing difficulty to CPU-mineable levels.

## Revival Options

|  | Homestead | Frontier |
|--|-----------|----------|
| Geth | v1.3.6 | v1.0.2 |
| Block | 1,919,999+ | 1,149,999+ |
| Start difficulty | ~62 TH | ~17.5 TH |
| Target difficulty | ~10 MH | ~50 MH |
| Reduction/block | ~4.83% | ~0.049% |
| Blocks needed | ~320 | ~25,600 |
| GPUs | 8x RTX 3090 | 8x RTX 3090 |
| Time | ~8 days | ~4-6 months |
| Cost | ~$180 | ~$3,000-4,000 |

**Recommendation**: Start with Homestead. Frontier is 99x slower due to its simpler difficulty algorithm.

## How It Works

### Difficulty Algorithms

**Homestead (EIP-2)**:
```
adjustment = max(1 - (timestamp_delta // 10), -99)
new_difficulty = parent_difficulty + (parent_difficulty // 2048) * adjustment
```
With 20-minute gaps: adjustment = -99, reducing difficulty by ~4.83% per block.

**Frontier**:
```
if timestamp_delta >= 13:
    new_difficulty = parent_difficulty - (parent_difficulty // 2048)
```
Only reduces by 1/2048 (~0.049%) per block regardless of timestamp gap.

### Timestamp Manipulation

We use `libfaketime` to make geth think the system time is 20 minutes ahead. Geth proposes blocks with that timestamp, triggering maximum difficulty reduction without waiting.

### Auto-Stop & P2P Handoff

Scripts auto-stop when difficulty reaches target threshold, then restart geth with P2P enabled for chaindata sync to other machines for CPU mining.

## Deployment

- **[vast-homestead/](vast-homestead/)** - Homestead mining on Vast.ai
- **[vast-frontier/](vast-frontier/)** - Frontier mining on Vast.ai

### Quick Start (Homestead)

```bash
# Upload and run
rsync -avzP vast-homestead/ root@sshX.vast.ai:/root/vast-homestead/ -e "ssh -p PORT"
ssh -p PORT root@sshX.vast.ai "cd /root/vast-homestead && chmod +x vast-mining.sh && nohup ./vast-mining.sh > mining-output.log 2>&1 &"

# Monitor
ssh -p PORT root@sshX.vast.ai "tail -f /root/mining.log"
```

## Homestead Difficulty Progression

| Block | Difficulty | Block Time | Cumulative |
|-------|------------|------------|------------|
| 1 | 62.4 TH | 20.5 hours | 20.5 hours |
| 50 | 5.5 TH | 1.8 hours | 89 hours |
| 100 | 490 GH | 9.7 min | 155 hours |
| 150 | 43 GH | 51 sec | 171 hours |
| 200 | 3.8 GH | 4.5 sec | 175 hours |
| ~320 | 10 MH | instant | ~176 hours |

Total: ~180 hours (~7.5 days) including overhead.
