# Running Instances List

Quick check of all running Vast.ai instances for the resurrection project.

## Quick Status Check

1. List all instances:
   ```bash
   resurrection/.venv/bin/vastai show instances
   ```

2. Get block number from an instance:
   ```bash
   ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p PORT root@HOST \
     "curl -s -X POST -H 'Content-Type: application/json' \
      --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' \
      http://127.0.0.1:8545" | python3 -c 'import sys,json; print(int(json.load(sys.stdin)["result"], 16))'
   ```

3. Get full block details (number, difficulty, timestamp):
   ```bash
   ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p PORT root@HOST \
     "curl -s -X POST -H 'Content-Type: application/json' \
      --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"latest\", false],\"id\":1}' \
      http://127.0.0.1:8545"
   ```

4. Check GPU utilization:
   ```bash
   ssh -o ConnectTimeout=10 -p PORT root@HOST "nvidia-smi --query-gpu=name,utilization.gpu,temperature.gpu --format=csv"
   ```

## Current Sync Node

The sync node serves chaindata to all miners. Get current connection details:

```bash
resurrection/.venv/bin/vastai show instances
# Look for the running instance, note SSH host and port
```

## Output Format

Present results as a table:

| Instance ID | GPU | SSH Host | SSH Port | Block | Difficulty | Status |
|-------------|-----|----------|----------|-------|------------|--------|

## Mining Status Commands (via SSH to sync node)

- **Check mining:** `eth_mining` RPC method
- **Check hashrate:** `eth_hashrate` RPC method
- **Start mining:** `miner_start` RPC method
- **Stop mining:** `miner_stop` RPC method

## Notes

- Instance SSH details change when instances restart - always check `vastai show instances` first
- The sync node exposes P2P port for external miners (ThinkPads, MacBooks)
- Static nodes file points miners to the sync node's P2P port
