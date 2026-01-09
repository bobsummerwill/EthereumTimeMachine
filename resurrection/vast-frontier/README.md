# Vast.ai Frontier Chain Extender (from block 1,149,999)

This folder provides scripts for crashing Frontier-era difficulty on **Vast.ai** GPU instances using **geth v1.0.2** (original Frontier release).

**WARNING**: Frontier is **99x slower** than Homestead due to its simpler difficulty algorithm!

## Goal

Reduce difficulty from **~17.5 TH** to **~50 MH** (CPU-mineable) by mining ~25,600 blocks with manipulated timestamps (20-minute gaps).

The script auto-stops at 50 MH and keeps geth running for P2P sync, enabling CPU mining handoff to other machines.

## Time & Cost Estimates

| GPU Config | Hashrate | Blocks | Time | Cost |
|------------|----------|--------|------|------|
| 1x RTX 3090 | 105 MH/s | ~25,600 | ~2 years | ~$17,520 |
| 4x RTX 3090 | 420 MH/s | ~25,600 | ~8 months | ~$5,760 |
| **8x RTX 3090** | **846 MH/s** | **~25,600** | **~4-6 months** | **~$3,000-4,000** |

**Recommendation**: Start with Homestead revival first. Frontier is a much larger undertaking.

## Why Frontier is 99x Harder

### Frontier Difficulty Algorithm (Pre-Homestead)

```
if timestamp_delta >= 13:
    new_difficulty = parent_difficulty - (parent_difficulty // 2048)
else:
    new_difficulty = parent_difficulty + (parent_difficulty // 2048)
```

With any timestamp gap > 13 seconds:
- Each block reduces difficulty by exactly `1/2048` (~0.049%)
- **No multiplier** like Homestead's `-99`
- ~25,600 blocks to crash from 17.5 TH to 50 MH

### Comparison with Homestead

| Factor | Homestead | Frontier |
|--------|-----------|----------|
| Algorithm | EIP-2 with -99 multiplier | Binary +/-1 only |
| Reduction/block | ~4.83% | ~0.049% |
| Blocks needed | ~320 | ~25,600 |
| Time (8x GPU) | ~8 days | ~4-6 months |
| Cost | ~$180 | ~$3,000-4,000 |

### Mathematical Explanation

**Homestead (EIP-2)**:
```
adjustment = max(1 - (timestamp_delta // 10), -99)
```
With 1200s gap: adjustment = -99, reducing difficulty by 99/2048 per block.

**Frontier**:
```
adjustment = -1 (if delta >= 13), +1 (if delta < 13)
```
With any gap >= 13s: adjustment = -1, reducing difficulty by only 1/2048 per block.

The ratio: 99/1 = **99x slower**.

## Prerequisites

1. **Chain-of-geths running** with geth v1.0.2 node accessible on port 30312
2. **Vast.ai account** with GPU credit
3. **Patience** - this is a multi-month project

## Vast.ai Deployment

The script has the chain-of-geths v1.0.2 enode pre-configured. If you're using a different deployment, override `P2P_ENODE` in the script.

### Quick Start

```bash
# 1. Search for 8x RTX 3090 instances
vastai search offers 'num_gpus=8 gpu_name=RTX_3090 inet_down>100' -o 'dph'

# 2. Create instance
vastai create instance OFFER_ID --image nvidia/cuda:11.8.0-devel-ubuntu22.04

# 3. Get SSH details
vastai show instance INSTANCE_ID

# 4. Upload this folder
rsync -avzP resurrection/vast-frontier/ root@sshX.vast.ai:/root/vast-frontier/ -e "ssh -p PORT"

# 5. Start mining
ssh -p PORT root@sshX.vast.ai "cd /root/vast-frontier && chmod +x vast-mining.sh && nohup ./vast-mining.sh > mining-output.log 2>&1 &"
```

### Monitoring

```bash
# Watch mining progress
ssh -p PORT root@sshX.vast.ai "tail -f /root/mining.log"

# Check current block number
ssh -p PORT root@sshX.vast.ai 'curl -s -X POST -H "Content-Type: application/json" \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}" \
  http://localhost:8545'

# Check difficulty
ssh -p PORT root@sshX.vast.ai 'curl -s -X POST -H "Content-Type: application/json" \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"latest\",false],\"id\":1}" \
  http://localhost:8545 | jq .result.difficulty'
```

### Long-Running Considerations

Since Frontier takes 4-6 months:

1. **Instance interruption**: Vast.ai instances can be preempted. Use `--resume` flag to continue after restart.

2. **Cost management**: Consider running only during off-peak hours or pausing periodically.

3. **Progress checkpoints**: The script logs every block mined. Save chaindata periodically:
   ```bash
   ssh -p PORT root@sshX.vast.ai "tar czf chaindata-backup-$(date +%Y%m%d).tar.gz /root/geth-data"
   ```

4. **Alternative strategy**: Consider accepting a higher target difficulty (e.g., 1 GH instead of 50 MH) to reduce mining time significantly.

## vast-mining.sh Features

The standalone `vast-mining.sh` script provides:
- **8 GPU mining** throughout (no tapering for fastest completion)
- **Auto-stop at 50 MH** difficulty threshold
- **P2P handoff mode**: When stopped, restarts geth with peers enabled for chaindata sync
- **Automatic restart** of geth/ethminer if they crash
- **Progress estimation**: Shows estimated blocks remaining based on Frontier algorithm

### CPU Mining After Handoff

Once GPU mining auto-stops at 50 MH:
1. Geth keeps running with P2P enabled
2. Connect other nodes to sync the extended chaindata
3. Start CPU mining on those nodes (~500 KH/s)
4. First CPU block takes ~100 seconds at 50 MH, then accelerates
5. Continue reducing difficulty to even lower levels if desired

## Key Files

| File | Purpose |
|------|---------|
| `vast-mining.sh` | Single-host Vast GPU script (8 GPUs, auto-stop at 50 MH) |
| `README.md` | This documentation |

## Difficulty Crash Projection

Starting from ~17.5 TH at block 1,149,999:

| Blocks Mined | Difficulty | Cumulative Time (8x GPU) |
|--------------|------------|--------------------------|
| 0 | 17.5 TH | 0 |
| 5,000 | ~14.0 TH | ~2 weeks |
| 10,000 | ~11.2 TH | ~1 month |
| 15,000 | ~9.0 TH | ~6 weeks |
| 20,000 | ~7.2 TH | ~2 months |
| 25,000 | ~5.8 TH | ~3 months |
| ~25,600 | 50 MH | ~4-6 months |

Note: Times are approximate. Actual mining time depends on difficulty and hashrate at each block.

## Why Geth v1.0.2?

Geth v1.0.2 is the last Frontier-era release before the Homestead fork. Using this version ensures:
- Original Frontier difficulty algorithm (no EIP-2)
- Authentic protocol behavior from August 2015
- Compatibility with chain-of-geths Frontier node (eth/60-61)

## Recommendation

**Start with Homestead first.** The Homestead revival takes ~8 days and costs ~$180. Once that's running, you can decide whether to invest 4-6 months and ~$3,000+ into Frontier revival.

Consider alternatives:
- Personal GPU hardware running continuously (lower $/hash over time)
- Higher target difficulty (e.g., 1 GH = ~15,000 blocks, ~2-3 months)
- Community mining pool (distribute the work)
