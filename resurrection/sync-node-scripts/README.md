# Sync Node Scripts

Scripts for managing the Vast.ai sync node that serves chaindata to external miners.

## Modes

The sync node operates in two modes:

| Mode | Mining | Work-refresher | How to enable |
|------|--------|----------------|---------------|
| **SYNC_MODE** (default) | OFF | not running | `rm /root/MINE_MODE` |
| MINE_MODE | ON | running | `touch /root/MINE_MODE` |

## Scripts

### onstart.sh
Runs on container startup. Checks for `MINE_MODE` file and conditionally starts mining.

### start-sync-node.sh
Starts geth WITHOUT the `--mine` flag. Used for sync-only mode.

### work-refresher.sh
Cycles `miner_stop`/`miner_start` every 60 seconds to prevent work expiration.
Only runs when `MINE_MODE` is enabled.

## Usage

```bash
# Enable mining on sync node:
touch /root/MINE_MODE && /root/onstart.sh

# Disable mining (sync-only):
rm /root/MINE_MODE && pkill -f work-refresher
curl -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"miner_stop","params":[],"id":1}' \
    http://127.0.0.1:8545
```

## Deployment

Copy scripts to sync node:
```bash
scp -P 20870 *.sh root@ssh6.vast.ai:/root/
```
