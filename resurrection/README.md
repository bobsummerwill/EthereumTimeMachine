# Ethereum Resurrection

GPU mining to extend historical chains beyond their original blocks, reducing difficulty to CPU-mineable levels.

## Revival Options

|  | Homestead | Frontier |
|--|-----------|----------|
| Geth | v1.3.6 | v1.0.2 |
| Block | 1,919,999+ | 1,149,999+ |
| Start difficulty | ~62 TH | ~20.5 TH |
| Target difficulty | ~10 MH | ~50 MH |
| Reduction/block | ~4.83% | ~0.049% |
| Blocks needed | ~320 | ~26,500 |
| GPUs | 8x RTX 3090 | 8x RTX 3090 |
| Time | ~8 days | **~19 months** |
| Cost | ~$180 | **~$14,000** |

**Recommendation**: Start with Homestead. Frontier requires ~80x more blocks due to its simpler difficulty algorithm that only reduces by 1/2048 per block regardless of timestamp gap.

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

## Directory Structure

```
resurrection/
├── mining-script.sh   # GPU mining script (--era homestead|frontier)
├── deploy-vast.sh     # Vast.ai deployment CLI (search, create, deploy, ssh, logs)
└── generated-files/
    ├── miner-address.txt
    ├── miner-private-key.hex
    ├── miner-password.txt
    └── data/          # Nodekeys for P2P identity
```

## Deployment

### Using deploy-vast.sh (Recommended)

```bash
# Prerequisites
pip install vastai
vastai set api-key YOUR_API_KEY

# 1. Search for instances
./deploy-vast.sh search

# 2. Create instance
./deploy-vast.sh create OFFER_ID

# 3. Deploy mining (default: homestead)
./deploy-vast.sh deploy INSTANCE_ID homestead
# Or for Frontier:
./deploy-vast.sh deploy INSTANCE_ID frontier

# 4. Monitor
./deploy-vast.sh logs INSTANCE_ID
./deploy-vast.sh status INSTANCE_ID
./deploy-vast.sh ssh INSTANCE_ID

# 5. Cleanup
./deploy-vast.sh destroy INSTANCE_ID
```

### Manual Deployment

```bash
# Upload script
rsync -avzP mining-script.sh root@sshX.vast.ai:/root/ -e "ssh -p PORT"

# Run
ssh -p PORT root@sshX.vast.ai "nohup /root/mining-script.sh --era homestead > mining-output.log 2>&1 &"

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

## Frontier Difficulty Progression

With 8x RTX 3090 @ 845 MH/s (actual starting difficulty: 20.5 TH):

| Block | Difficulty | Block Time | Cumulative |
|-------|------------|------------|------------|
| 1 | 20.5 TH | 6.7 hours | 0.3 days |
| 100 | 19.5 TH | 6.4 hours | 27 days |
| 500 | 16.1 TH | 5.3 hours | 124 days |
| 1,000 | 12.6 TH | 4.1 hours | 223 days |
| 2,000 | 7.7 TH | 2.5 hours | 358 days |
| 5,000 | 1.8 TH | 36 min | 525 days |
| 10,000 | 158 GH | 3.1 min | 570 days |
| 20,000 | 1.2 GH | 1.4 sec | 575 days |
| ~26,500 | 50 MH | instant | ~575 days |

Total: ~575 days (~19 months) at $1/hr = ~$14,000.

**Why so slow?** Frontier's difficulty only drops by 1/2048 (~0.049%) per block, regardless of timestamp gap. The first 5,000 blocks consume 91% of total mining time.

## Troubleshooting

### P2P Sync: "No peers connected"

The mining script syncs chaindata from a chain-of-geths node before mining. If it reports no peers:

1. **Check the source node is running**:
   ```bash
   # On your chain-of-geths host (e.g., AWS EC2)
   docker ps | grep geth
   ```

2. **Check network connectivity from Vast.ai**:
   ```bash
   # Test TCP connection to the P2P port
   nc -zv 52.0.234.84 30311  # Homestead
   nc -zv 52.0.234.84 30312  # Frontier
   ```

3. **Check firewall/security groups**:
   - **AWS**: The Security Group must allow inbound TCP on port 30311 (Homestead) or 30312 (Frontier)
   - Common mistake: Port is only open for internal traffic, not external
   - Go to EC2 → Security Groups → Edit inbound rules → Add TCP port 30311/30312 from 0.0.0.0/0

### Frontier: "geth v1.0.2 binary not found"

Geth v1.0.2 has no official prebuilt Linux binary. The deploy script automatically builds it locally using Docker and uploads it to Vast.ai.

If this fails, ensure:
1. Docker is installed and running on your local machine
2. The `ethereumtimemachine/geth:v1.0.2` image exists (built by `chain-of-geths/build-images.sh`)

**Manual fix** (if automatic build fails):
```bash
# Build the image first (if needed)
cd chain-of-geths && ONLY_VERSION=v1.0.2 ./build-images.sh

# Extract the binary
docker run --rm --entrypoint /bin/sh -v /tmp:/out \
  ethereumtimemachine/geth:v1.0.2 \
  -c 'cp /usr/local/bin/geth /out/geth-v1.0.2'

# Upload to Vast.ai instance
scp -P PORT /tmp/geth-v1.0.2 root@sshX.vast.ai:/root/geth
```

### Mining stalled / ethminer died

The script auto-restarts ethminer if it crashes. Check logs:
```bash
tail -100 /root/ethminer.log
tail -100 /root/geth.log
```

Common issues:
- **GPU memory errors**: Reduce DAG load mode or check GPU health with `nvidia-smi`
- **OpenCL not found**: Ensure `/etc/OpenCL/vendors/nvidia.icd` exists
