# Homestead Resurrection Status

GPU mining operation to extend the historical Ethereum Homestead chain beyond block 1,919,999, reducing difficulty from 62.38 TH to CPU-mineable levels (~10 MH).

**For Claude:** When user asks about vast.ai instances, mining status, current block, difficulty, or resurrection progress, use this file as the reference. Run the status check commands below to get current data, then generate the table and/or chart as needed. **ALWAYS fetch actual block data from the chain** - don't rely on formula estimates which can drift from actual values.

---

## Current Status

**Last Updated:** 2026-01-23

| Metric | Value |
|--------|-------|
| Current Block | 1920024 (mining) |
| Target Block | 1920316 |
| Blocks Remaining | ~292 |
| Current Difficulty | ~18.8 TH |
| Target Difficulty | 10 MH (CPU-mineable) |
| Est. Completion | ~2026-01-24 |

## Mining Instances (Vast.ai)

| ID | GPU | Status | Utilization | Role | SSH |
|----|-----|--------|-------------|------|-----|
| 30034181 | 8x RTX 3090 | Running | 100% | Mining | `ssh -p 34180 root@ssh1.vast.ai` |
| 30034372 | 8x RTX 3090 | Running | 100% | Mining | `ssh -p 34372 root@ssh2.vast.ai` |
| 29980870 | 1x GTX 1080 | Running | 0% | Idle sync | `ssh -p 20870 root@ssh6.vast.ai` |

**Combined Hashrate:** ~1692 MH/s (2 × 846 MH/s)

**Vastai CLI:** `/home/icetiger/Projects/EthereumTimeMachine/resurrection/.venv/bin/vastai`

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
/home/icetiger/Projects/EthereumTimeMachine/resurrection/.venv/bin/vastai show instances
```

### 2. Get Current Block Number

```bash
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p 34180 root@ssh1.vast.ai \
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
- `~/Downloads/ethereum_resurrection_table.png`
- `~/Downloads/ethereum_resurrection_table.svg`

**Python environment:** `~/Downloads/chart_venv` (matplotlib installed)

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
source ~/Downloads/chart_venv/bin/activate && python3 << 'TABLE_EOF'
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
}

# UPDATE THIS: Current block being mined
current_mining_block = 1920024
last_mined_block = 1920023
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
plt.savefig('/home/icetiger/Downloads/ethereum_resurrection_table.png', dpi=150, facecolor=BG_DARK, bbox_inches='tight')
plt.savefig('/home/icetiger/Downloads/ethereum_resurrection_table.svg', facecolor=BG_DARK, bbox_inches='tight')
print("Table saved to ~/Downloads/ethereum_resurrection_table.png and .svg")
TABLE_EOF
```

---

## Chart Generation

Generate a difficulty curve chart showing the exponential reduction from ~59 TH to 10 MH.

**Output files:**
- `~/Downloads/ethereum_resurrection_chart.png`
- `~/Downloads/ethereum_resurrection_chart.svg`

**Python environment:** `~/Downloads/chart_venv` (matplotlib installed)

### Color Scheme (matches infographic.html)

```python
CYAN = '#00F0FF'      # Primary accent, difficulty curve
MAGENTA = '#FF55CC'   # Mined blocks
YELLOW = '#FFE739'    # Highlights, current/target markers
PURPLE = '#6245EB'    # Secondary accent
BG_DARK = '#1a1a2e'   # Background
BG_CELL = '#16213e'   # Cell/panel background
GRAY = '#888888'      # Grid lines, separator rows
```

### Chart Layout

- **Top chart:** Difficulty vs Block (log scale)
  - X-axis: Block number (1919995 to 1920325)
  - Y-axis: Difficulty (log scale, 1 MH to 100 TH)
  - Markers: Pink dots for mined, yellow star for current, yellow diamond for target

- **Bottom chart:** Time per block (bar chart)
  - Show subset of blocks (every 20th + key blocks)
  - Pink bars: mined, Yellow: current/target, Cyan: pending

### Key Annotations

| Block | Label | Color |
|-------|-------|-------|
| 1919999 | "Last Homestead Block" | Gray |
| 1920000 | "RESURRECTION!" | Magenta |
| Current | "MINING NOW" | Yellow |
| 1920316 | "CPU-MINEABLE!" | Yellow |

### To Generate the Chart

```bash
source ~/Downloads/chart_venv/bin/activate && python3 << 'CHART_EOF'
import matplotlib.pyplot as plt
import numpy as np
from datetime import datetime, timedelta

# Constants
HASHRATE = 1692e6  # 2x 8x RTX 3090
REDUCTION = 0.0483
TARGET = 10e6
START_DIFF = 59.36e12

# Color scheme (matches infographic)
CYAN, MAGENTA, YELLOW = '#00F0FF', '#FF55CC', '#FFE739'
BG_DARK = '#1a1a2e'

# UPDATE THIS: Historical mined blocks (actual values from chain)
actual_blocks = {
    1920000: {"diff": 59.36e12, "date": datetime(2026, 1, 15, 7, 38), "label": "RESURRECTION!"},
    1920001: {"diff": 56.49e12, "date": datetime(2026, 1, 16, 18, 29)},
    1920002: {"diff": 53.76e12, "date": datetime(2026, 1, 17, 8, 22)},
    1920003: {"diff": 51.16e12, "date": datetime(2026, 1, 17, 20, 3)},
    1920004: {"diff": 48.69e12, "date": datetime(2026, 1, 18, 5, 17)},
    1920005: {"diff": 46.34e12, "date": datetime(2026, 1, 18, 10, 19)},
    1920006: {"diff": 44.10e12, "date": datetime(2026, 1, 18, 15, 32)},
    1920007: {"diff": 41.96e12, "date": datetime(2026, 1, 18, 16, 6)},
    1920008: {"diff": 39.93e12, "date": datetime(2026, 1, 19, 6, 57)},
    1920009: {"diff": 38.00e12, "date": datetime(2026, 1, 19, 18, 17)},
    1920010: {"diff": 36.17e12, "date": datetime(2026, 1, 19, 22, 57)},
    1920011: {"diff": 34.42e12, "date": datetime(2026, 1, 20, 2, 11)},
    1920012: {"diff": 32.75e12, "date": datetime(2026, 1, 20, 5, 44)},
    1920013: {"diff": 31.17e12, "date": datetime(2026, 1, 20, 8, 8)},
    1920014: {"diff": 30.88e12, "date": datetime(2026, 1, 20, 8, 11)},
    1920015: {"diff": 29.39e12, "date": datetime(2026, 1, 20, 19, 27)},
    1920016: {"diff": 27.97e12, "date": datetime(2026, 1, 21, 1, 30)},
    1920017: {"diff": 26.62e12, "date": datetime(2026, 1, 21, 6, 50)},
    1920018: {"diff": 25.33e12, "date": datetime(2026, 1, 21, 11, 16)},
    1920019: {"diff": 24.10e12, "date": datetime(2026, 1, 21, 15, 58)},
    1920020: {"diff": 22.94e12, "date": datetime(2026, 1, 22, 0, 52)},
    1920021: {"diff": 21.87e12, "date": datetime(2026, 1, 22, 1, 8)},
    1920022: {"diff": 20.81e12, "date": datetime(2026, 1, 22, 20, 21)},
    1920023: {"diff": 19.80e12, "date": datetime(2026, 1, 23, 2, 49)},
}

# UPDATE THIS: Current block being mined
current_mining_block = 1920024

# Generate difficulty curve
blocks, difficulties = [], []
diff = START_DIFF
for b in range(1920000, 1920320):
    blocks.append(b)
    difficulties.append(actual_blocks[b]["diff"] if b in actual_blocks else diff)
    diff *= (1 - REDUCTION)

target_idx = next(i for i, d in enumerate(difficulties) if d <= TARGET)
target_block = blocks[target_idx]

# Create figure
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(16, 12), gridspec_kw={'height_ratios': [2, 1]})
fig.patch.set_facecolor(BG_DARK)

# Top: Log-scale difficulty curve
ax1.set_facecolor('#16213e')
ax1.semilogy(blocks, difficulties, color=CYAN, linewidth=2.5)
ax1.axhline(y=TARGET, color=YELLOW, linestyle='--', linewidth=2, alpha=0.8)
ax1.scatter([target_block], [TARGET], color=YELLOW, s=200, marker='D', edgecolors='white', zorder=6)

# Mark mined blocks
mined = [b for b in blocks if b in actual_blocks]
ax1.scatter(mined, [actual_blocks[b]["diff"] for b in mined], color=MAGENTA, s=120, zorder=5, edgecolors='white')

# Add annotations
ax1.annotate('RESURRECTION!\nBlock 1920000', xy=(1920000, 59.36e12),
             xytext=(1920030, 59.36e12), fontsize=10, color=MAGENTA, fontweight='bold',
             arrowprops=dict(arrowstyle='->', color=MAGENTA, lw=1.5),
             bbox=dict(boxstyle='round,pad=0.3', facecolor='#16213e', edgecolor=MAGENTA, alpha=0.9))

ax1.annotate(f'CPU-MINEABLE!\nBlock {target_block}\n10 MH', xy=(target_block, TARGET),
             xytext=(target_block - 60, 1e8), fontsize=10, color=YELLOW, fontweight='bold',
             arrowprops=dict(arrowstyle='->', color=YELLOW, lw=1.5),
             bbox=dict(boxstyle='round,pad=0.3', facecolor='#16213e', edgecolor=YELLOW, alpha=0.9))

ax1.set_xlabel('Block Number', fontsize=12, color='white')
ax1.set_ylabel('Difficulty', fontsize=12, color='white')
ax1.set_title('ETHEREUM TIME MACHINE: Homestead Resurrection\nDifficulty Reduction Progress',
              fontsize=16, color=CYAN, fontweight='bold')
ax1.tick_params(colors='white')
ax1.grid(True, alpha=0.3)
ax1.set_xlim(1919995, 1920325)
ax1.set_ylim(1e6, 1e14)
ax1.set_yticks([1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13])
ax1.set_yticklabels(['1 MH', '10 MH', '100 MH', '1 GH', '10 GH', '100 GH', '1 TH', '10 TH'])
for spine in ax1.spines.values(): spine.set_color(CYAN)

# Legend
legend_elements = [
    plt.Line2D([0], [0], color=CYAN, linewidth=2.5, label='Difficulty Curve'),
    plt.Line2D([0], [0], marker='o', color='w', markerfacecolor=MAGENTA, markersize=10, label='Mined Blocks', linestyle='None'),
    plt.Line2D([0], [0], marker='D', color='w', markerfacecolor=YELLOW, markersize=10, label='Target (CPU-mineable)', linestyle='None'),
]
ax1.legend(handles=legend_elements, loc='upper right', facecolor='#16213e', edgecolor=CYAN,
           labelcolor='white', fontsize=9)

# Bottom: Time per block line graph
ax2.set_facecolor('#16213e')
times = [d / HASHRATE / 3600 for d in difficulties]

# Plot continuous line for all blocks
ax2.plot(blocks, times, color=CYAN, linewidth=2, label='Est. Mining Time')

# Mark mined blocks
mined_blocks_list = [b for b in blocks if b in actual_blocks]
mined_times = [times[b - 1920000] for b in mined_blocks_list]
ax2.scatter(mined_blocks_list, mined_times, color=MAGENTA, s=60, zorder=5, edgecolors='white', label='Mined')

# Mark current mining block
ax2.scatter([current_mining_block], [times[current_mining_block - 1920000]],
            color=YELLOW, s=120, marker='*', zorder=6, edgecolors='white', label='Mining Now')

# Mark target block
ax2.scatter([target_block], [times[target_block - 1920000]],
            color=YELLOW, s=120, marker='D', zorder=6, edgecolors='white', label='CPU Target')

ax2.set_xlabel('Block Number', fontsize=12, color='white')
ax2.set_ylabel('Hours to Mine', fontsize=12, color='white')
ax2.set_title('Estimated Mining Time per Block (2x 8x RTX 3090 = 1692 MH/s)', fontsize=12, color=CYAN)
ax2.tick_params(colors='white')
ax2.grid(True, alpha=0.3)
ax2.set_xlim(1919995, 1920325)
ax2.legend(loc='upper right', facecolor='#16213e', edgecolor=CYAN, labelcolor='white', fontsize=9)
for spine in ax2.spines.values(): spine.set_color(CYAN)

# Summary stats at bottom
total_hours = sum(times[:target_idx])
total_days = total_hours / 24
stats_text = f"Total blocks: {target_block - 1920000} | Est. total time: {total_hours:.0f}h ({total_days:.1f} days) | Target: ~Jan 24, 2026"
fig.text(0.5, 0.02, stats_text, ha='center', fontsize=11, color=YELLOW,
         fontweight='bold', bbox=dict(boxstyle='round,pad=0.5', facecolor='#16213e', edgecolor=YELLOW))

plt.tight_layout(rect=[0, 0.05, 1, 1])
plt.savefig('/home/icetiger/Downloads/ethereum_resurrection_chart.png', dpi=150, facecolor=BG_DARK, bbox_inches='tight')
plt.savefig('/home/icetiger/Downloads/ethereum_resurrection_chart.svg', facecolor=BG_DARK, bbox_inches='tight')
print(f"Chart saved. Target: block {target_block}")
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

---

## Files

- **Table image:** `~/Downloads/ethereum_resurrection_table.png` and `.svg`
- **Chart image:** `~/Downloads/ethereum_resurrection_chart.png` and `.svg`
- **Infographic:** `infographic.html` (open in browser) - **UPDATE when chart/table updated**
- **Logs:** SSH to instances, see `/root/geth.log` and `/root/ethminer.log`
- **Deploy script:** `resurrection/deploy-vast.sh`
- **Mining script:** `resurrection/mining-script.sh`
- **Full docs:** `resurrection/README.md`

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
