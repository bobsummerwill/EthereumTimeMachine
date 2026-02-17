# Homestead Resurrection Status

GPU mining operation to extend the historical Ethereum Homestead chain beyond block 1,919,999, reducing difficulty from 62.38 TH and achieving sustainable block times.

**For Claude:** When user asks about vast.ai instances, mining status, current block, difficulty, or resurrection progress, use this file as the reference. Run the status check commands below to get current data, then generate the table and/or chart as needed. **ALWAYS fetch actual block data from the chain** - don't rely on formula estimates which can drift from actual values.

---

## Current Status

**Last Updated:** 2026-02-16

**Mode:** Flat-out GPU mining on GTX 1080 sync node (instance 29980870). Difficulty climbing toward ~500 MH equilibrium with ~20s block times.

| Metric | Value |
|--------|-------|
| Mining Mode | Flat-out GPU (ethminer + OpenCL) |
| Mining Node | Instance 29980870, GTX 1080 |
| Expected Equilibrium | ~500 MH difficulty, ~20s blocks |
| Work Refresher | `work-refresher-nogap.sh` (84s expiry safety net) |

## Mining Instances (Vast.ai)

| ID | GPU | Status | Role | SSH |
|----|-----|--------|------|-----|
| 29980870 | 1x GTX 1080 | Running | GPU mining (ethminer) | `ssh -p 20870 root@ssh6.vast.ai` |
| 31512513 | 1x Quadro P4000 | Stopped | Idle (isolated, no peers) | `ssh -p 32512 root@ssh2.vast.ai` |

**Vastai CLI:** `resurrection/.venv/bin/vastai`

## Lessons Learned: The Wasted Two Weeks (Jan 30 - Feb 16)

### What happened

After the initial GPU mining phase (Jan 15-29) successfully reduced difficulty from 62.38 TH to ~1.26 GH using 16x RTX 3090s, the big GPU instances were shut down. The sync node (GTX 1080) continued mining using `work-refresher.sh` with a 1000s minimum gap between blocks, aiming to drive difficulty to CPU-mineable levels.

Difficulty dropped from 1.26 GH (Jan 29) through 29 MH (Feb 1) to ~2.9 MH (Feb 13), where it stalled and stopped dropping. **Two weeks were spent getting from 29 MH to 2.9 MH with no further progress possible.**

### Why it stalled: the difficulty bomb floor

The Homestead difficulty formula includes a "difficulty bomb":
```
bomb = 2^(floor(block_number / 100000) - 2)
```

At block ~1.92M: `bomb = 2^17 = 131,072` added to every block's difficulty.

The controlled mining with 1000s gaps achieves the maximum EIP-2 reduction of ~4.83% per block (`adjustment = parent_diff // 2048 * -99`). At the floor, this reduction exactly equals the bomb addition:
```
parent_diff // 2048 * 99 = 131,072  →  floor ≈ 2.71 MH
```

**No mining strategy can push difficulty below ~2.71 MH at these block numbers.** The bomb is an absolute floor. On mainnet this was invisible because the bomb (131K) was negligible against 62 TH of difficulty. But after grinding difficulty down by 23,000x, the bomb dominates.

### Why CPU mining doesn't work at the floor

At 2.71 MH with ~90 KH/s (4 laptops), blocks average ~30 seconds. But once natural mining starts, the bomb pushes difficulty up rapidly:

- At 15s block times: `adj_factor = 0`, bomb adds 131K/block unopposed
- Difficulty rockets from 2.7 MH to ~16-23 MH within hours
- Equilibrium for 90 KH/s: ~16 MH difficulty, ~3 minute blocks

The 2.71 MH floor **only holds with artificial 1000s gaps**. Natural mining at any hashrate finds a much higher equilibrium.

### The solution: keep a GPU mining

Even a single GPU (~25 MH/s) maintains ~20s blocks at equilibrium (~500 MH). The difficulty is higher but the GPU hashrate more than compensates. The bomb's 131K/block contribution is negligible at 500 MH.

| Setup | Equilibrium Difficulty | Block Time |
|-------|----------------------|------------|
| CPUs only (90 KH/s) | 16 MH | ~3 min |
| GTX 1080 (25 MH/s) | 500 MH | ~20s |
| Quadro P4000 (22 MH/s) | 440 MH | ~20s |
| 1x RTX 3090 (106 MH/s) | 2.1 GH | ~20s |
| 4x RTX 3090 (424 MH/s) | 6.7 GH | ~16s |

All GPU setups snap to the adj=-1 equilibrium band (~20s blocks). The difficulty scales linearly with hashrate, but block time stays constant. Even the cheapest single-GPU Vast.ai instance (~$0.05-0.10/hr) is sufficient.

## Block History (Mined)

| Block | Status | Date/Time (UTC) | Difficulty | Est. Time | Actual Time |
|-------|--------|-----------------|------------|-----------|-------------|
| 1919999 | SYNCED | 2016-07-20 13:20 | 62.38 TH | - | ~14s |
| 1920000 | MINED | 2026-01-15 07:38 | 59.36 TH | 9.7h | 9.5y |
| 1920001 | MINED | 2026-01-16 18:29 | 56.49 TH | 9.3h | 34.9h |
| 1920002 | MINED | 2026-01-17 08:22 | 53.76 TH | 8.8h | 13.9h |
| 1920003 | MINED | 2026-01-17 20:03 | 51.16 TH | 8.4h | 11.7h |
| 1920004 | MINED | 2026-01-18 05:17 | 48.69 TH | 8.0h | 9.2h |
| 1920005 | MINED | 2026-01-18 10:19 | 46.34 TH | 7.6h | 5.0h |
| 1920006 | MINED | 2026-01-18 15:32 | 44.10 TH | 7.2h | 5.2h |
| 1920007 | MINED | 2026-01-18 16:06 | 41.96 TH | 6.9h | 34m |
| 1920008 | MINED | 2026-01-19 06:57 | 39.93 TH | 6.6h | 14.9h |
| 1920009 | MINED | 2026-01-19 18:17 | 38.00 TH | 6.2h | 11.3h |
| 1920010 | MINED | 2026-01-19 22:57 | 36.17 TH | 5.9h | 4.7h |
| 1920011 | MINED | 2026-01-20 02:11 | 34.42 TH | 5.6h | 3.2h |
| 1920012 | MINED | 2026-01-20 05:44 | 32.75 TH | 5.4h | 3.5h |
| 1920013 | MINED | 2026-01-20 08:08 | 31.17 TH | 5.1h | 2.4h |
| 1920014 | MINED | 2026-01-20 08:11 | 30.88 TH | 5.1h | 3.4m |
| 1920015 | MINED | 2026-01-20 19:27 | 29.39 TH | 4.8h | 11.3h |
| 1920016 | MINED | 2026-01-21 01:30 | 27.97 TH | 4.6h | 6.0h |
| 1920017 | MINED | 2026-01-21 06:50 | 26.62 TH | 4.4h | 5.3h |
| 1920018 | MINED | 2026-01-21 11:16 | 25.33 TH | 4.2h | 4.4h |
| 1920019 | MINED | 2026-01-21 15:58 | 24.10 TH | 4.0h | 4.7h |
| 1920020 | MINED | 2026-01-22 00:52 | 22.94 TH | 3.8h | 8.9h |
| 1920021 | MINED | 2026-01-22 01:08 | 21.87 TH | 3.6h | 16m |
| 1920022 | MINED | 2026-01-22 20:21 | 20.81 TH | 3.4h | 19.2h |
| 1920023 | MINED | 2026-01-23 02:49 | 19.80 TH | 3.3h | 6.5h |
| 1920024 | MINED | 2026-01-23 14:03 | 18.85 TH | 3.1h | 11.2h |
| 1920025 | MINED | 2026-01-23 17:00 | 17.94 TH | 2.9h | 3.0h |
| 1920026 | MINED | 2026-01-23 17:20 | 17.07 TH | 2.8h | 20.3m |
| 1920027 | MINED | 2026-01-23 21:59 | 16.24 TH | 2.7h | 4.7h |
| 1920028 | MINED | 2026-01-24 00:10 | 15.46 TH | 2.5h | 2.2h |
| 1920029 | MINED | 2026-01-24 03:41 | 14.71 TH | 2.4h | 3.5h |
| 1920030 | MINED | 2026-01-24 12:23 | 14.00 TH | 2.3h | 8.7h |
| 1920031 | MINED | 2026-01-24 15:58 | 13.32 TH | 2.2h | 3.6h |
| ... | ... | ... | ... | ... | ... |
| 1920040 | MINED | 2026-01-25 08:00 | 8.53 TH | 1.4h | - |
| 1920050 | MINED | 2026-01-26 02:37 | 5.20 TH | 51m | - |
| 1920060 | MINED | 2026-01-26 11:02 | 3.34 TH | 33m | - |
| 1920070 | MINED | 2026-01-26 19:46 | 2.36 TH | 23m | - |
| 1920080 | MINED | 2026-01-27 01:29 | 1.61 TH | 16m | - |
| 1920090 | MINED | 2026-01-27 03:07 | 1.31 TH | 13m | - |
| 1920100 | MINED | 2026-01-27 04:20 | 799 GH | 8m | - |
| 1920150 | MINED | 2026-01-27 05:30 | 439 GH | 4m | - |
| 1920188 | MINED | 2026-01-27 06:10 | 261 GH | 2.6m | - |

## Key Constants

```python
# Mining hardware
HASHRATE_PER_INSTANCE = 846e6      # 846 MH/s per 8x RTX 3090
NUM_INSTANCES = 2                   # 2 mining instances
TOTAL_HASHRATE = 1692e6            # 1692 MH/s combined

# Difficulty algorithm (Homestead EIP-2)
DIFFICULTY_REDUCTION = 0.0483      # ~4.83% reduction per block
START_DIFFICULTY = 59.36e12        # 59.36 TH at block 1920000 (actual)
TARGET_DIFFICULTY = 10e6           # 10 MH = CPU-mineable

# Block numbers
LAST_MAINNET_BLOCK = 1919999       # Last synced from mainnet
RESURRECTION_BLOCK = 1920000       # First new block (mined 2026-01-16)
TARGET_BLOCK = 1920316             # When difficulty reaches 10 MH
```

---

## Status Check Commands

### 1. List All Vast.ai Instances

```bash
resurrection/.venv/bin/vastai show instances
```

### 2. Get Current Block Number

```bash
# Get SSH URL for instance (addresses change!)
resurrection/.venv/bin/vastai ssh-url 30034181

# Then query RPC (replace HOST:PORT with output above)
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p PORT root@HOST \
  "curl -s -X POST -H 'Content-Type: application/json' \
   --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' \
   http://127.0.0.1:8545" | python3 -c 'import sys,json; print(int(json.load(sys.stdin)["result"], 16))'
```

### 3. Get Block Data (timestamp AND difficulty) for Mined Blocks

**CRITICAL:** Always fetch actual difficulty values from the chain, not formula estimates. The actual reduction rate varies slightly from the theoretical 4.83%.

**IMPORTANT:** Also fetch block 1919999 (the last mainnet block) to get the correct pre-resurrection difficulty. Don't assume values like "65 TH" - verify from chain.

```bash
# Fetch actual timestamp and difficulty for all mined blocks (including 1919999)
for block in 1919999 1920000 1920001 1920002 1920003 1920004 1920005 1920006 1920007 1920008 1920009 1920010 1920011 1920012 1920013 1920014 1920015 1920016 1920017 1920018 1920019; do
  hex=$(printf "0x%x" $block)
  result=$(ssh root@ssh1.vast.ai -p 34180 "curl -s -X POST -H 'Content-Type: application/json' \
    --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$hex\",false],\"id\":1}' \
    http://localhost:8545" 2>/dev/null)
  diff_hex=$(echo "$result" | jq -r '.result.difficulty')
  ts_hex=$(echo "$result" | jq -r '.result.timestamp')
  diff_dec=$(printf "%d" $diff_hex)
  ts_dec=$(printf "%d" $ts_hex)
  diff_th=$(echo "scale=2; $diff_dec / 1000000000000" | bc)
  dt=$(date -u -d "@$ts_dec" '+%Y-%m-%d %H:%M:%S')
  echo "$block: diff=$diff_th TH, timestamp=$dt UTC"
done
```

Example output (actual values, not estimates):
```
1919999: diff=62.38 TH, timestamp=2016-07-20 13:20:38 UTC  <-- Last mainnet block
1920000: diff=59.36 TH, timestamp=2026-01-15 07:38:16 UTC  <-- First resurrection block (-4.8%)
1920001: diff=56.49 TH, timestamp=2026-01-16 18:29:23 UTC
1920002: diff=53.76 TH, timestamp=2026-01-17 08:22:25 UTC
...
```

**Note:** The drop from 62.38 TH (1919999) to 59.36 TH (1920000) is a normal ~4.8% reduction per EIP-2, triggered by the 9.5 year timestamp gap which maxes out the -99 adjustment.

### 4. Check GPU Utilization

```bash
# Instance 1 (ID: 30034181)
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p 34180 root@ssh1.vast.ai \
  "nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv"

# Instance 2 (ID: 30034372)
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p 34372 root@ssh2.vast.ai \
  "nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv"
```

### 5. Check Mining Processes

```bash
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p 34180 root@ssh1.vast.ai \
  "ps aux | grep -E 'geth|ethminer' | grep -v grep"
```

### 6. View Mining Logs

```bash
# Geth logs (shows block mining events)
ssh -p 34180 root@ssh1.vast.ai "tail -100 /root/geth.log"

# Ethminer logs (shows hashrate, solutions)
ssh -p 34180 root@ssh1.vast.ai "tail -50 /root/ethminer.log"
```

---

## Restart Procedures

### Restart Sync Node (Instance 29980870)

**IMPORTANT:** If mining instances are on different blocks, restart the sync node first to reconnect them.

```bash
# Restart geth on sync node
ssh -p 20870 root@ssh6.vast.ai 'pkill -f "geth --datadir"; sleep 3; nohup /root/geth --datadir /root/data --networkid 1 --rpc --rpcaddr 0.0.0.0 --rpcapi eth,net,web3,admin --port 30303 > /root/geth.log 2>&1 &'
```

### Restart Mining Instances

**CRITICAL:** Always use `LC_ALL=C` when starting ethminer to avoid locale errors.

```bash
# Instance 1 (30034181)
ssh -p 34180 root@ssh1.vast.ai 'pkill -9 geth; pkill -9 ethminer; sleep 5; cd /root && nohup ./geth --datadir /root/geth-data --cache 16384 --rpc --rpcaddr 0.0.0.0 --rpcport 8545 --rpcapi eth,net,web3,miner,admin,debug --networkid 1 --port 30303 --mine --minerthreads 0 --etherbase 0x3ca943ef871bea7d0dfa34bff047b0e82be441ef --unlock 0x3ca943ef871bea7d0dfa34bff047b0e82be441ef --password /root/miner-password.txt --verbosity 4 > /root/geth-new.log 2>&1 & sleep 5; nohup env LC_ALL=C /root/ethminer-src/build/ethminer/ethminer -G -P getwork://127.0.0.1:8545 --HWMON 1 --report-hr --work-timeout 99999 --farm-recheck 5000 > /root/ethminer.log 2>&1 &'

# Instance 2 (30034372)
ssh -p 34372 root@ssh2.vast.ai 'pkill -9 geth; pkill -9 ethminer; sleep 5; cd /root && nohup ./geth --datadir /root/geth-data --cache 16384 --rpc --rpcaddr 0.0.0.0 --rpcport 8545 --rpcapi eth,net,web3,miner,admin --networkid 1 --port 30303 --mine --minerthreads 0 --etherbase 0x3ca943ef871bea7d0dfa34bff047b0e82be441ef --unlock 0x3ca943ef871bea7d0dfa34bff047b0e82be441ef --password /root/miner-password.txt --verbosity 3 > /root/geth-new.log 2>&1 & sleep 5; nohup env LC_ALL=C /root/ethminer-src/build/ethminer/ethminer -G -P getwork://127.0.0.1:8545 --HWMON 1 --report-hr --work-timeout 99999 --farm-recheck 5000 > /root/ethminer.log 2>&1 &'
```

### Verify All Instances Are Synced

```bash
# Check block numbers on all instances
for port in 34180 34372 20870; do
  name="Instance 1"; [ "$port" = "34372" ] && name="Instance 2"; [ "$port" = "20870" ] && name="Sync"
  ssh_host="ssh1.vast.ai"; [ "$port" = "34372" ] && ssh_host="ssh2.vast.ai"; [ "$port" = "20870" ] && ssh_host="ssh6.vast.ai"
  result=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p $port root@$ssh_host 'curl -s http://127.0.0.1:8545 -X POST -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}"' 2>&1 | grep '^{')
  block_hex=$(echo "$result" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
  block_num=$(printf "%d" $block_hex 2>/dev/null)
  echo "$name: Block $block_num"
done
```

All instances should be on the same block number. If not, wait a few minutes for sync or restart the lagging instance.

---

## Difficulty Calculations

### Calculate Current Difficulty from Block Number

```python
# Note: Use actual chain values when available, formula is approximate
START_DIFFICULTY = 59.36e12  # Actual difficulty at block 1920000
REDUCTION = 0.0483
blocks_mined = current_block - 1920000
current_difficulty = START_DIFFICULTY * ((1 - REDUCTION) ** blocks_mined)
```

### Calculate Time to Mine a Block

```python
HASHRATE = 1692e6  # Combined hashrate
time_hours = difficulty / HASHRATE / 3600
```

### Calculate Remaining Time to Target

```python
TARGET = 10e6
remaining_hours = 0
diff = current_difficulty
while diff > TARGET:
    remaining_hours += diff / HASHRATE / 3600
    diff *= (1 - 0.0483)
```

### Calculate Estimated Date for Future Block

```python
from datetime import timedelta

def calc_estimated_date(target_block, from_block, from_date):
    cumulative_hours = 0
    diff = calc_difficulty(from_block)
    for b in range(from_block, target_block):
        cumulative_hours += diff / HASHRATE / 3600
        diff *= (1 - REDUCTION)
    return from_date + timedelta(hours=cumulative_hours)
```

---

## Milestones

| Block | Difficulty | Significance |
|-------|------------|--------------|
| 1919999 | 62.38 TH | Last mainnet Homestead block |
| 1920000 | 59.36 TH | **RESURRECTION** - First new block |
| 1920050 | ~5.0 TH | 10x reduction |
| 1920100 | ~418 GH | 100x reduction |
| 1920150 | ~35 GH | 1000x reduction |
| 1920200 | ~3.0 GH | GPU-easy |
| 1920250 | ~250 MH | Single GPU feasible |
| 1920316 | ~10 MH | **CPU-MINEABLE** |

---

## Table Generation

Generate a mining progress table image showing mined blocks, current mining block, and future estimates.

**Output files:**
- `resurrection/generated-files/resurrection_table.png`
- `resurrection/generated-files/resurrection_table.svg`

**Python environment:** `resurrection/.venv/` (matplotlib installed via requirements.txt)

### Table Structure

| Column | Description |
|--------|-------------|
| Block | Block number |
| Status | SYNCED, MINED, MINING, pending, CPU! |
| Date/Time | Actual for mined, estimated (~prefix) for pending, `-` for currently mining |
| Difficulty | In TH/GH/MH format |
| Est. Time | Estimated time to mine this block |
| Actual Time | Time since previous block (only for mined blocks) |

### Table Row Types

1. **SYNCED** (gray): Block 1919999 - last mainnet block
2. **MINED** (magenta): Completed blocks with actual timestamps
3. **MINING** (yellow): Currently being mined - NO date/time or actual time shown
4. **pending** (cyan): Future blocks with estimated dates (prefixed with `~`)
5. **CPU!** (yellow): Target block 1920316
6. **...** (gray): Separator rows between sections

### Table Layout

- Mined blocks: 1919999 through last mined block
- MINING row: current block being mined (no date, no actual time)
- Near-term pending: next 1-2 blocks (e.g., 1920009, 1920010)
- `...` separator row
- Milestone pending blocks: 1920020, 1920030, 1920040, 1920050, 1920100, 1920150, 1920200, 1920250, 1920316

### To Generate the Table

```bash
source resurrection/.venv/bin/activate && python3 << 'TABLE_EOF'
import matplotlib.pyplot as plt
from datetime import datetime, timedelta

# Constants
HASHRATE = 1692e6
REDUCTION = 0.0483
TARGET = 10e6
START_DIFF = 59.36e12

# Color scheme
CYAN = '#00F0FF'
MAGENTA = '#FF55CC'
YELLOW = '#FFE739'
BG_DARK = '#1a1a2e'
BG_CELL = '#16213e'
GRAY = '#888888'

# UPDATE THIS: Historical mined blocks with actual timestamps (from chain)
actual_blocks = {
    1919999: {"diff": 62.38e12, "date": datetime(2016, 7, 20, 13, 20, 38)},
    1920000: {"diff": 59.36e12, "date": datetime(2026, 1, 15, 7, 38, 16)},
    1920001: {"diff": 56.49e12, "date": datetime(2026, 1, 16, 18, 29, 23)},
    1920002: {"diff": 53.76e12, "date": datetime(2026, 1, 17, 8, 22, 25)},
    1920003: {"diff": 51.16e12, "date": datetime(2026, 1, 17, 20, 2, 37)},
    1920004: {"diff": 48.69e12, "date": datetime(2026, 1, 18, 5, 16, 57)},
    1920005: {"diff": 46.34e12, "date": datetime(2026, 1, 18, 10, 18, 41)},
    1920006: {"diff": 44.10e12, "date": datetime(2026, 1, 18, 15, 31, 58)},
    1920007: {"diff": 41.96e12, "date": datetime(2026, 1, 18, 16, 5, 32)},
    1920008: {"diff": 39.93e12, "date": datetime(2026, 1, 19, 6, 56, 58)},
    1920009: {"diff": 38.00e12, "date": datetime(2026, 1, 19, 18, 17, 26)},
    1920010: {"diff": 36.17e12, "date": datetime(2026, 1, 19, 22, 57, 8)},
    1920011: {"diff": 34.42e12, "date": datetime(2026, 1, 20, 2, 11, 24)},
    1920012: {"diff": 32.75e12, "date": datetime(2026, 1, 20, 5, 43, 36)},
    1920013: {"diff": 31.17e12, "date": datetime(2026, 1, 20, 8, 8, 2)},
    1920014: {"diff": 30.88e12, "date": datetime(2026, 1, 20, 8, 11, 28)},
    1920015: {"diff": 29.39e12, "date": datetime(2026, 1, 20, 19, 27, 29)},
    1920016: {"diff": 27.97e12, "date": datetime(2026, 1, 21, 1, 29, 35)},
    1920017: {"diff": 26.62e12, "date": datetime(2026, 1, 21, 6, 49, 58)},
    1920018: {"diff": 25.33e12, "date": datetime(2026, 1, 21, 11, 16, 28)},
    1920019: {"diff": 24.10e12, "date": datetime(2026, 1, 21, 15, 57, 34)},
    1920020: {"diff": 22.94e12, "date": datetime(2026, 1, 22, 0, 51, 33)},
    1920021: {"diff": 21.87e12, "date": datetime(2026, 1, 22, 1, 7, 49)},
    1920022: {"diff": 20.81e12, "date": datetime(2026, 1, 22, 20, 20, 54)},
    1920023: {"diff": 19.80e12, "date": datetime(2026, 1, 23, 2, 49, 26)},
    1920024: {"diff": 18.85e12, "date": datetime(2026, 1, 23, 14, 3, 9)},
    1920025: {"diff": 17.94e12, "date": datetime(2026, 1, 23, 17, 0, 7)},
    1920026: {"diff": 17.07e12, "date": datetime(2026, 1, 23, 17, 20, 27)},
    1920027: {"diff": 16.24e12, "date": datetime(2026, 1, 23, 21, 59, 49)},
    1920028: {"diff": 15.46e12, "date": datetime(2026, 1, 24, 0, 10, 22)},
    1920029: {"diff": 14.71e12, "date": datetime(2026, 1, 24, 3, 41, 8)},
    1920030: {"diff": 14.00e12, "date": datetime(2026, 1, 24, 12, 23, 27)},
    1920031: {"diff": 13.32e12, "date": datetime(2026, 1, 24, 15, 58, 4)},
}

# UPDATE THIS: Current block being mined
current_mining_block = 1920032
last_mined_block = 1920031
last_mined_date = actual_blocks[last_mined_block]["date"]

def calc_difficulty(block):
    if block in actual_blocks:
        return actual_blocks[block]["diff"]
    blocks_from_start = block - 1920000
    return START_DIFF * ((1 - REDUCTION) ** blocks_from_start)

def format_diff(d):
    if d >= 1e12: return f"{d/1e12:.1f} TH"
    elif d >= 1e9: return f"{d/1e9:.1f} GH"
    elif d >= 1e6: return f"{d/1e6:.1f} MH"
    return f"{d:.0f} H"

def format_time(hours):
    if hours >= 24: return f"{hours/24:.1f}d"
    elif hours >= 1: return f"{hours:.1f}h"
    elif hours * 60 >= 1: return f"{hours*60:.1f}m"
    else: return f"{hours*3600:.1f}s"

def calc_estimated_date(target_block, from_block, from_date):
    cumulative_hours = 0
    for b in range(from_block, target_block):
        diff = calc_difficulty(b)
        cumulative_hours += diff / HASHRATE / 3600
    return from_date + timedelta(hours=cumulative_hours)

# Build table data
headers = ['Block', 'Status', 'Date/Time', 'Difficulty', 'Est. Time', 'Actual Time']
rows = []

# Block 1919999 (synced from mainnet)
rows.append(['1919999', 'SYNCED', '2016-07-20 13:20', '62.38 TH', '-', '~14s'])

# Block 1920000 (resurrection) - uses actual chain values
rows.append(['1920000', 'MINED', '2026-01-15 07:38', '59.36 TH', '9.7h', '9.5y'])

# Mined blocks with actual times
prev_date = actual_blocks[1920000]["date"]
for b in range(1920001, last_mined_block + 1):
    diff = actual_blocks[b]["diff"]
    date = actual_blocks[b]["date"]
    actual_hours = (date - prev_date).total_seconds() / 3600
    est_time = diff / HASHRATE / 3600
    rows.append([
        str(b), 'MINED', date.strftime('%Y-%m-%d %H:%M'),
        format_diff(diff), format_time(est_time), format_time(actual_hours)
    ])
    prev_date = date

# Currently mining - NO date/time, NO actual time
diff = calc_difficulty(current_mining_block)
est_time = diff / HASHRATE / 3600
rows.append([str(current_mining_block), 'MINING', '-', format_diff(diff), format_time(est_time), '-'])

# Near-term pending blocks - ALWAYS include year in date format (%Y-%m-%d %H:%M)
for b in [current_mining_block + 1, current_mining_block + 2]:
    diff = calc_difficulty(b)
    est_time = diff / HASHRATE / 3600
    est_date = calc_estimated_date(b, current_mining_block, last_mined_date)
    rows.append([str(b), 'pending', f"~{est_date.strftime('%Y-%m-%d %H:%M')}", format_diff(diff), format_time(est_time), '-'])

# Separator
rows.append(['...', '', '', '', '', ''])

# Future milestones - ALWAYS include year in date format (%Y-%m-%d %H:%M)
milestones = [1920020, 1920030, 1920040, 1920050, 1920100, 1920150, 1920200, 1920250, 1920316]
for b in milestones:
    diff = calc_difficulty(b)
    est_time = diff / HASHRATE / 3600
    status = 'CPU!' if b == 1920316 else 'pending'
    est_date = calc_estimated_date(b, current_mining_block, last_mined_date)
    rows.append([str(b), status, f"~{est_date.strftime('%Y-%m-%d %H:%M')}", format_diff(diff), format_time(est_time), '-'])

# Create figure
fig, ax = plt.subplots(figsize=(14, 14))
fig.patch.set_facecolor(BG_DARK)
ax.set_facecolor(BG_DARK)
ax.axis('off')

# Table colors by status
n_rows = len(rows)
cell_colors = [[BG_CELL] * 6 for _ in range(n_rows)]

# Create table
table = ax.table(cellText=rows, colLabels=headers, cellLoc='center', loc='center',
                 colColours=[CYAN] * 6, cellColours=cell_colors)
table.auto_set_font_size(False)
table.set_fontsize(11)
table.scale(1.2, 1.8)

# Style header
for j in range(6):
    table[(0, j)].set_text_props(weight='bold', color=BG_DARK)
    table[(0, j)].set_facecolor(CYAN)

# Style data cells by status
for i in range(1, n_rows + 1):
    row = rows[i-1]
    for j in range(6):
        cell = table[(i, j)]
        cell.set_facecolor(BG_CELL)
        cell.set_edgecolor('#444444')
        if row[1] == 'SYNCED': cell.set_text_props(color=GRAY)
        elif row[1] == 'MINED': cell.set_text_props(color=MAGENTA)
        elif row[1] == 'MINING': cell.set_text_props(color=YELLOW, weight='bold')
        elif row[1] == 'CPU!': cell.set_text_props(color=YELLOW, weight='bold')
        elif row[0] == '...': cell.set_text_props(color=GRAY)
        else: cell.set_text_props(color=CYAN)

plt.title('ETHEREUM TIME MACHINE: Homestead Resurrection\nMining Progress',
          fontsize=18, color=CYAN, fontweight='bold', pad=20)

# Summary
remaining = 1920316 - current_mining_block
diff = calc_difficulty(current_mining_block)
summary = f"Current: Block {current_mining_block} | Difficulty: {format_diff(diff)} | Remaining: ~{remaining} blocks to CPU-mineable"
fig.text(0.5, 0.04, summary, ha='center', fontsize=12, color=YELLOW, fontweight='bold')

plt.tight_layout(rect=[0, 0.06, 1, 0.95])
plt.savefig('resurrection/generated-files/resurrection_table.png', dpi=150, facecolor=BG_DARK, bbox_inches='tight')
plt.savefig('resurrection/generated-files/resurrection_table.svg', facecolor=BG_DARK, bbox_inches='tight')
print("Table saved to resurrection/generated-files/resurrection_table.png and .svg")
TABLE_EOF
```

---

## Chart Generation

Generate two difficulty charts showing the resurrection progress.

**Output files:**
- `resurrection/generated-files/resurrection_chart.png` - Difficulty vs Block Number
- `resurrection/generated-files/resurrection_chart_timeline.png` - Difficulty vs Time

**Python environment:** `resurrection/.venv/` (matplotlib installed)

### Chart Style Requirements

Both charts must follow this exact style:
- **Y-axis:** Difficulty (log scale, 1 MH to 100 TH)
- **Gridlines:** Major only (10 MH, 100 MH, 1 GH, etc.) - no minor gridlines
- **Line:** Cyan (`#00F0FF`) connecting all data points
- **Data points:** Magenta (`#FF55CC`) circle at EVERY block
- **Current block:** Yellow (`#FFE739`) star marker
- **Background:** Dark (`#1a1a2e`)
- **Timeline chart:** Vertical day labels

### Step 1: Fetch ALL Block Data from Chain

Use JSON-RPC batching (100 blocks per request) to fetch all blocks efficiently:

```python
import subprocess, json

all_data = []
batch_size = 100
CURRENT = 1923350  # Update this

for start in range(1920000, CURRENT + 1, batch_size):
    end = min(start + batch_size, CURRENT + 1)
    requests = [{"jsonrpc": "2.0", "method": "eth_getBlockByNumber",
                 "params": [hex(b), False], "id": b} for b in range(start, end)]
    batch_json = json.dumps(requests).replace('"', '\\"')
    cmd = f'''ssh -p 20870 root@ssh6.vast.ai 'curl -s -X POST -H "Content-Type: application/json" --data "{batch_json}" http://127.0.0.1:8545' '''
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=120)
    responses = json.loads(result.stdout)
    for resp in responses:
        if resp.get("result"):
            r = resp["result"]
            all_data.append((int(r["number"], 16), int(r["difficulty"], 16), int(r["timestamp"], 16)))

# Save to CSV
with open('/tmp/all_blocks.csv', 'w') as f:
    for block, diff, ts in sorted(all_data):
        f.write(f"{block},{diff},{ts}\n")
```

### Step 2: Generate Charts

```bash
source resurrection/.venv/bin/activate && python3 << 'CHART_EOF'
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.dates import DayLocator, DateFormatter
from datetime import datetime, timezone

CYAN, MAGENTA, YELLOW = '#00F0FF', '#FF55CC', '#FFE739'
BG_DARK = '#1a1a2e'

# Load all blocks from CSV
data = []
with open('/tmp/all_blocks.csv', 'r') as f:
    for line in f:
        parts = line.strip().split(',')
        if len(parts) == 3:
            data.append((int(parts[0]), int(parts[1]), int(parts[2])))

data.sort()
blocks = [d[0] for d in data]
diffs = [d[1] for d in data]
dates = [datetime.fromtimestamp(d[2], tz=timezone.utc) for d in data]
current_block = blocks[-1]

legend_elements = [
    Line2D([0], [0], color=CYAN, linewidth=2, label='Difficulty curve'),
    Line2D([0], [0], marker='o', color='w', markerfacecolor=MAGENTA, markersize=6, linestyle='None', label='Blocks'),
    Line2D([0], [0], marker='*', color='w', markerfacecolor=YELLOW, markersize=12, linestyle='None', label=f'Current ({current_block})'),
]

# Chart 1: Block Number vs Difficulty
fig1, ax1 = plt.subplots(figsize=(16, 9))
fig1.patch.set_facecolor(BG_DARK)
ax1.set_facecolor('#16213e')
ax1.semilogy(blocks, diffs, color=CYAN, linewidth=1.5, zorder=1)
ax1.scatter(blocks, diffs, color=MAGENTA, s=8, zorder=2, alpha=0.7)
ax1.scatter([current_block], [diffs[-1]], color=YELLOW, s=200, marker='*', zorder=3, edgecolors='white')
ax1.set_xlabel('Block Number', fontsize=14, color='white')
ax1.set_ylabel('Difficulty', fontsize=14, color='white')
ax1.set_title('Resurrection: Difficulty vs Block Number', fontsize=18, color=CYAN, fontweight='bold')
ax1.set_yticks([1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13])
ax1.set_yticklabels(['1 MH', '10 MH', '100 MH', '1 GH', '10 GH', '100 GH', '1 TH', '10 TH'])
ax1.tick_params(colors='white')
ax1.grid(True, alpha=0.3, which='major')
ax1.minorticks_off()
for spine in ax1.spines.values(): spine.set_color(CYAN)
ax1.legend(handles=legend_elements, loc='upper right', facecolor='#16213e', edgecolor=CYAN, labelcolor='white')
plt.tight_layout()
plt.savefig('resurrection/generated-files/resurrection_chart.png', dpi=150, facecolor=BG_DARK, bbox_inches='tight')
plt.close()

# Chart 2: Time vs Difficulty (vertical day labels)
fig2, ax2 = plt.subplots(figsize=(16, 9))
fig2.patch.set_facecolor(BG_DARK)
ax2.set_facecolor('#16213e')
ax2.semilogy(dates, diffs, color=CYAN, linewidth=1.5, zorder=1)
ax2.scatter(dates, diffs, color=MAGENTA, s=8, zorder=2, alpha=0.7)
ax2.scatter([dates[-1]], [diffs[-1]], color=YELLOW, s=200, marker='*', zorder=3, edgecolors='white')
ax2.set_xlabel('Date (UTC)', fontsize=14, color='white')
ax2.set_ylabel('Difficulty', fontsize=14, color='white')
ax2.set_title('Resurrection: Difficulty vs Time', fontsize=18, color=CYAN, fontweight='bold')
ax2.set_yticks([1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13])
ax2.set_yticklabels(['1 MH', '10 MH', '100 MH', '1 GH', '10 GH', '100 GH', '1 TH', '10 TH'])
ax2.tick_params(colors='white')
ax2.grid(True, alpha=0.3, which='major')
ax2.minorticks_off()
ax2.xaxis.set_major_locator(DayLocator())
ax2.xaxis.set_major_formatter(DateFormatter('%b %d'))
plt.setp(ax2.xaxis.get_majorticklabels(), rotation=90, ha='center', color='white')
for spine in ax2.spines.values(): spine.set_color(CYAN)
ax2.legend(handles=legend_elements, loc='upper right', facecolor='#16213e', edgecolor=CYAN, labelcolor='white')
plt.tight_layout()
plt.savefig('resurrection/generated-files/resurrection_chart_timeline.png', dpi=150, facecolor=BG_DARK, bbox_inches='tight')
print(f"Charts saved. Current: Block {current_block}, Difficulty {diffs[-1]/1e6:.2f} MH")
CHART_EOF
```

---

## Status Report Format

When reporting status to the user, use this markdown format:

```markdown
| Block | Status | Date/Time (UTC) | Difficulty | Est. Time | Actual Time |
|-------|--------|-----------------|------------|-----------|-------------|
| 1919999 | SYNCED | 2016-07-20 13:20 | 62.38 TH | - | ~14s |
| 1920000 | MINED | 2026-01-15 07:38 | 59.36 TH | 9.7h | 9.5y |
| ... (mined blocks with actual chain data) ... |
| 1920013 | MINED | 2026-01-20 08:08 | 31.2 TH | 5.1h | 2.4h |
| 1920014 | MINING | - | 29.7 TH | 4.9h | - |
| 1920015 | pending | ~2026-01-20 13:00 | 28.2 TH | 4.6h | - |
| ... |
| 1920316 | CPU! | ~2026-01-24 | 10 MH | instant | - |

**Current:** Block 1920014 | Difficulty: ~29.7 TH
**Target:** Block 1920316 (~10 MH = CPU-mineable)
**Remaining:** ~302 blocks | ~105h (4.4 days)
```

**Important formatting rules:**
- Est. Time column comes BEFORE Actual Time column
- MINING row has `-` for Date/Time and Actual Time (not yet complete)
- Pending dates are prefixed with `~` to indicate estimates
- **ALL dates MUST include the year** (format: `YYYY-MM-DD HH:MM`) - never use `MM-DD` alone
- Include `...` separator between near-term and milestone blocks

### CRITICAL: Calculating "Actual Time" for Sampled Blocks

When generating the progress table with sampled milestone blocks (e.g., 1920010, 1920020, 1920030...):

**WRONG:** Using `timestamp(block N) - timestamp(previous_row_block)` gives time spanning multiple blocks
**RIGHT:** Using `timestamp(block N) - timestamp(block N-1)` gives per-block actual time

For sampled blocks like 1920010, 1920020, etc., you must:
1. Fetch the timestamp for block N (e.g., 1920010)
2. ALSO fetch the timestamp for block N-1 (e.g., 1920009)
3. Calculate: `actual_time = timestamp(N) - timestamp(N-1)`

This ensures "Est. Time" (single block estimate) and "Actual Time" (single block actual) are comparable.

Example:
```python
# For block 1920010, fetch both 1920010 and 1920009 timestamps
blocks_to_fetch = [1920009, 1920010, 1920019, 1920020, ...]  # Include N-1 for each sampled N
actual_time_for_1920010 = timestamp[1920010] - timestamp[1920009]
```

---

## Files

- **Chart 1:** `resurrection/generated-files/resurrection_chart.png` - Difficulty vs Block Number
- **Chart 2:** `resurrection/generated-files/resurrection_chart_timeline.png` - Difficulty vs Time
- **Matrix:** `resurrection/generated-files/sync_mining_status.png` - Last 20 + Next 20 blocks
- **Infographic:** `infographic.html` (open in browser) - **UPDATE when chart/table updated**
- **Logs:** SSH to instances, see `/root/geth.log` and `/root/ethminer.log`
- **Deploy script:** `resurrection/deploy-vast.sh`
- **Mining script:** `resurrection/mining-script.sh`
- **Full docs:** `resurrection/README.md`

### Output Directory

All generated files go into `resurrection/generated-files/` (gitignored). Create if needed:
```bash
mkdir -p resurrection/generated-files
```

---

## Infographic Maintenance

**IMPORTANT:** When updating the table or chart, also update `infographic.html` to keep values consistent.

### Values to Keep in Sync

| Location | Value | Description |
|----------|-------|-------------|
| infographic.html line ~239 | Start Diff | Homestead starting difficulty (~62 TH, rounded from 62.38 TH) |
| infographic.html line ~278 | "At X TH difficulty" | Same as Start Diff (62 TH) |
| infographic.html line ~279 | "~Xs timestamp gaps" | difficulty / hashrate (~72,000s) |
| infographic.html line ~289 | "62T \|###" | ASCII chart Y-axis label |

### Key Constants in Infographic

```html
<!-- TWO RESURRECTION OPTIONS table -->
<td>Start Diff</td>
<td>~62 TH</td>  <!-- Block 1919999 difficulty (62.38 TH), rounded -->

<!-- DIFFICULTY ALGORITHM diagram -->
At 62 TH difficulty, blocks take ~20 hours to find
This creates ~72,000s timestamp gaps between blocks

<!-- ASCII difficulty chart -->
62T |###
```

### Key Difficulty Values

| Block | Difficulty | Description |
|-------|------------|-------------|
| 1919999 | 62.38 TH | Last mainnet Homestead block (July 2016) - **"Start Diff"** |
| 1920000 | 59.36 TH | First resurrection block (Jan 2026) - already reduced by EIP-2 |

The ~4.8% drop from 62.38 → 59.36 TH is the normal EIP-2 reduction triggered by the 9.5 year timestamp gap.

**CRITICAL:** The infographic "Start Diff" refers to block **1919999** (62.38 TH), NOT block 1920000. This is the difficulty we START FROM before mining block 1920000. The difficulty algorithm then reduces it to 59.36 TH for block 1920000.

### Update Checklist

When generating new table/chart images, also:
1. Fetch actual difficulty from chain for BOTH 1919999 and 1920000 - don't assume values
2. Keep infographic.html "Start Diff" at ~62 TH (block 1919999's difficulty, rounded)
3. Keep infographic.html difficulty algorithm section showing "At 62 TH difficulty" (~lines 278-289)
4. Keep ASCII chart Y-axis at 62T (matches block 1919999 start difficulty)
