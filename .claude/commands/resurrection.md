# Resurrection Mining Status

Check and manage the Homestead resurrection mining operation.

## Environment

- **Vastai CLI:** `resurrection/.venv/bin/vastai`
- **Status file:** `resurrection/STATUS.md`
- **Deploy script:** `resurrection/deploy-vast.sh`
- **Mining script:** `resurrection/mining-script.sh`

## Check Current Status

1. List running instances:
   ```bash
   resurrection/.venv/bin/vastai show instances
   ```

2. Get block and difficulty from sync node:
   ```bash
   ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p PORT root@HOST \
     "curl -s -X POST -H 'Content-Type: application/json' \
      --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"latest\", false],\"id\":1}' \
      http://127.0.0.1:8545"
   ```
   Parse with Python: `int(result["number"], 16)` for block, `int(result["difficulty"], 16)` for difficulty.

## Mining Controls

- **Start mining:** `curl -X POST -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","method":"miner_start","params":[],"id":1}' http://127.0.0.1:8545`
- **Stop mining:** `curl -X POST -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","method":"miner_stop","params":[],"id":1}' http://127.0.0.1:8545`
- **Check hashrate:** `eth_hashrate` RPC method

## Generate Geth Bundles

For desktop miners to join the resurrection chain:

```bash
cd resurrection

# Generate Windows bundle with mining support
./generate-geth-1.3.6-windows.sh

# Generate macOS bundles with mining support
./generate-geth-1.4.0-macos.sh    # First macOS version
./generate-geth-1.4.18-macos.sh   # Better macOS compatibility

# Generate node keys first if needed
./generate-keys.sh
```

Output bundles include:
- `run.bat`/`run.sh` - Sync only
- `run-mine.bat`/`run-mine.sh` - Sync AND mine to resurrection address

Mining address: `0x3ca943ef871bea7d0dfa34bff047b0e82be441ef`

## Difficulty Charts

Charts are in `resurrection/generated-files/`:
- `resurrection_chart.png` - Difficulty vs Block Number (log scale Y-axis)
- `resurrection_chart_timeline.png` - Difficulty vs Time (log scale Y-axis)
- `sync_mining_status.png` - Last 20 + Next 20 blocks matrix

### Chart Style (ALWAYS follow this)

1. **Fetch ALL blocks from chain** - use JSON-RPC batching (100 blocks per request)
2. **Two separate chart files** - one by block number, one by time
3. **Visual style:**
   - Cyan (`#00F0FF`) line connecting data points
   - Magenta (`#FF55CC`) circle at EVERY block
   - Yellow (`#FFE739`) star at current block
   - Log scale Y-axis with major gridlines only (10 MH, 100 MH, 1 GH, etc.)
   - Dark background (`#1a1a2e`)
   - Timeline chart: vertical day labels

### Generate Charts Workflow

See `resurrection/STATUS.md` "Chart Generation" section for full code.

Quick steps:
1. Get current block number
2. Batch fetch ALL blocks using JSON-RPC batching (100/request)
3. Generate charts with matplotlib - circle for every block

## Key Metrics

- **Current phase:** ThinkPads-only mining (~60 KH/s)
- **Target equilibrium:** ~0.9 MH for 15-second blocks @ 60 KH/s
- **Difficulty reduction:** ~4.83% per block (Homestead EIP-2) when block times > 1000s
- **Plateau phase:** Slower reduction when block times < 1000s

## Homestead EIP-2 Difficulty Formula

```python
diff_adj = max(1 - (block_time // 10), -99)
new_diff = parent_diff + (parent_diff // 2048) * diff_adj
```
