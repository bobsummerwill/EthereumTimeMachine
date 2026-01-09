# Vast.ai Homestead Mining

Crash Homestead difficulty from ~62 TH to ~10 MH in ~8 days (~$180).

See [../README.md](../README.md) for technical details.

## Quick Start

```bash
# 1. Find 8x RTX 3090 instance
vastai search offers 'num_gpus=8 gpu_name=RTX_3090 inet_down>100' -o 'dph'

# 2. Create and get SSH details
vastai create instance OFFER_ID --image nvidia/cuda:11.8.0-devel-ubuntu22.04
vastai show instance INSTANCE_ID

# 3. Upload and run
rsync -avzP . root@sshX.vast.ai:/root/vast-homestead/ -e "ssh -p PORT"
ssh -p PORT root@sshX.vast.ai "cd /root/vast-homestead && chmod +x vast-mining.sh && nohup ./vast-mining.sh > mining-output.log 2>&1 &"
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
| `vast-mining.sh` | Main script (8 GPUs, auto-stop at 10 MH) |
| `docker-compose.yml` | Alternative Docker-based setup |

## Resume After Interruption

```bash
./vast-mining.sh --resume
```
