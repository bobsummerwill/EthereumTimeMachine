# Vast.ai Frontier Mining

Crash Frontier difficulty from ~17.5 TH to ~50 MH in ~4-6 months (~$3,000-4,000).

**WARNING**: Frontier is 99x slower than Homestead. Start with Homestead first.

See [../README.md](../README.md) for technical details.

## Quick Start

```bash
# 1. Find 8x RTX 3090 instance
vastai search offers 'num_gpus=8 gpu_name=RTX_3090 inet_down>100' -o 'dph'

# 2. Create and get SSH details
vastai create instance OFFER_ID --image nvidia/cuda:11.8.0-devel-ubuntu22.04
vastai show instance INSTANCE_ID

# 3. Upload and run
rsync -avzP . root@sshX.vast.ai:/root/vast-frontier/ -e "ssh -p PORT"
ssh -p PORT root@sshX.vast.ai "cd /root/vast-frontier && chmod +x vast-mining.sh && nohup ./vast-mining.sh > mining-output.log 2>&1 &"
```

## Monitoring

```bash
tail -f /root/mining.log           # Script progress
tail -f /root/geth.log             # Geth output
tail -f /root/ethminer.log         # Miner output
```

## Key Files

| File | Purpose |
|------|---------|
| `vast-mining.sh` | Main script (8 GPUs, auto-stop at 50 MH) |

## Long-Running Tips

Since this takes 4-6 months:

1. **Backup periodically**: `tar czf chaindata-backup.tar.gz /root/geth-data`
2. **Resume after interruption**: `./vast-mining.sh --resume`
3. **Consider higher target**: 1 GH instead of 50 MH = ~2-3 months
