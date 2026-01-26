# Resurrection Mining Status

Check and manage the Homestead resurrection GPU mining operation.

## Environment

- **Vastai CLI:** `resurrection/.venv/bin/vastai`
- **Status file:** `resurrection/STATUS.md`
- **Deploy script:** `resurrection/deploy-vast.sh`

## Instructions

1. First, read `resurrection/STATUS.md` to understand current state and available commands
2. Use the vastai CLI to list instances:
   ```bash
   resurrection/.venv/bin/vastai show instances
   ```
3. SSH to instances to get live block numbers:
   ```bash
   ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p PORT root@HOST \
     "curl -s -X POST -H 'Content-Type: application/json' \
      --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' \
      http://127.0.0.1:8545" | python3 -c 'import sys,json; print(int(json.load(sys.stdin)["result"], 16))'
   ```
4. Report status in markdown table format with columns: Block, Status, Date/Time, Difficulty, Est. Time, Actual Time
5. If updating STATUS.md, fetch actual difficulty values from the chain - don't rely on formula estimates

## Key Metrics

- Target: Block 1920316 (~10 MH = CPU-mineable)
- Hashrate: ~1692 MH/s (2x 8x RTX 3090)
- Difficulty reduction: ~4.83% per block (Homestead EIP-2)
