# Homestead Resurrection Status

GPU mining operation to extend the historical Ethereum Homestead chain beyond block 1,919,999, reducing difficulty from ~62 TH to CPU-mineable levels (~10 MH).

**For Claude:** When user asks about vast.ai instances, mining status, current block, difficulty, or resurrection progress, use this file as the reference. Run the status check commands below to get current data, then generate the table and/or chart as needed.

---

## Current Status

**Last Updated:** 2026-01-18

| Metric | Value |
|--------|-------|
| Current Block | 1920008 (mining) |
| Target Block | 1920316 |
| Blocks Remaining | ~308 |
| Current Difficulty | ~41.7 TH |
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

| Block | Status | Date/Time | Difficulty | Est. Time | Actual Time |
|-------|--------|-----------|------------|-----------|-------------|
| 1919999 | SYNCED | 2016-07-20 13:20 | 65.1 TH | - | ~14s |
| 1920000 | MINED | 2026-01-16 05:39 | 62.0 TH | 10.2h | 9.5y |
| 1920001 | MINED | 2026-01-16 08:39 | 59.0 TH | 9.7h | 3.0h |
| 1920002 | MINED | 2026-01-16 22:33 | 56.2 TH | 9.2h | 13.9h |
| 1920003 | MINED | 2026-01-17 10:15 | 53.5 TH | 8.8h | 11.7h |
| 1920004 | MINED | 2026-01-18 05:16 | 50.9 TH | 8.4h | 19.0h |
| 1920005 | MINED | 2026-01-18 10:18 | 48.4 TH | 7.9h | 5.0h |
| 1920006 | MINED | 2026-01-18 15:31 | 46.1 TH | 7.6h | 5.2h |
| 1920007 | MINED | 2026-01-18 16:05 | 43.8 TH | 7.2h | 34m |

## Key Constants

```python
# Mining hardware
HASHRATE_PER_INSTANCE = 846e6      # 846 MH/s per 8x RTX 3090
NUM_INSTANCES = 2                   # 2 mining instances
TOTAL_HASHRATE = 1692e6            # 1692 MH/s combined

# Difficulty algorithm (Homestead EIP-2)
DIFFICULTY_REDUCTION = 0.0483      # ~4.83% reduction per block
START_DIFFICULTY = 62.0e12         # 62 TH at block 1920000
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

### 3. Get Block Timestamps (for newly mined blocks)

```bash
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p 34180 root@ssh1.vast.ai '
for block in 1920004 1920005 1920006 1920007; do
  hex=$(printf "0x%x" $block)
  result=$(curl -s -X POST -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$hex\", false],\"id\":1}" \
    http://127.0.0.1:8545)
  timestamp=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[\"result\"][\"timestamp\"] if d.get(\"result\") else \"null\")" 2>/dev/null)
  if [ "$timestamp" != "null" ] && [ -n "$timestamp" ]; then
    ts_dec=$(python3 -c "print(int(\"$timestamp\", 16))")
    date=$(date -d @$ts_dec "+%Y-%m-%d %H:%M:%S")
    echo "$block: $date (ts: $ts_dec)"
  else
    echo "$block: not yet mined"
  fi
done
'
```

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
START_DIFFICULTY = 62.0e12
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
| 1919999 | 65.1 TH | Last mainnet Homestead block |
| 1920000 | 62.0 TH | **RESURRECTION** - First new block |
| 1920050 | ~5.2 TH | 10x reduction |
| 1920100 | ~439 GH | 100x reduction |
| 1920150 | ~37 GH | 1000x reduction |
| 1920200 | ~3.1 GH | GPU-easy |
| 1920250 | ~262 MH | Single GPU feasible |
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
START_DIFF = 62.0e12

# Color scheme
CYAN = '#00F0FF'
MAGENTA = '#FF55CC'
YELLOW = '#FFE739'
BG_DARK = '#1a1a2e'
BG_CELL = '#16213e'
GRAY = '#888888'

# UPDATE THIS: Historical mined blocks with actual timestamps
actual_blocks = {
    1919999: {"diff": 65.1e12, "date": datetime(2016, 7, 20, 13, 20, 39)},
    1920000: {"diff": 62.0e12, "date": datetime(2026, 1, 16, 5, 39, 0)},
    1920001: {"diff": 59.0e12, "date": datetime(2026, 1, 16, 8, 39, 0)},
    1920002: {"diff": 56.2e12, "date": datetime(2026, 1, 16, 22, 33, 0)},
    1920003: {"diff": 53.5e12, "date": datetime(2026, 1, 17, 10, 15, 0)},
    1920004: {"diff": 50.9e12, "date": datetime(2026, 1, 18, 5, 16, 57)},
    1920005: {"diff": 48.4e12, "date": datetime(2026, 1, 18, 10, 18, 41)},
    1920006: {"diff": 46.1e12, "date": datetime(2026, 1, 18, 15, 31, 58)},
    1920007: {"diff": 43.8e12, "date": datetime(2026, 1, 18, 16, 5, 32)},
}

# UPDATE THIS: Current block being mined
current_mining_block = 1920008
last_mined_block = 1920007
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
rows.append(['1919999', 'SYNCED', '2016-07-20 13:20', '65.1 TH', '-', '~14s'])

# Block 1920000 (resurrection)
rows.append(['1920000', 'MINED', '2026-01-16 05:39', '62.0 TH', '10.2h', '9.5y'])

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

# Near-term pending blocks
for b in [current_mining_block + 1, current_mining_block + 2]:
    diff = calc_difficulty(b)
    est_time = diff / HASHRATE / 3600
    est_date = calc_estimated_date(b, current_mining_block, last_mined_date)
    rows.append([str(b), 'pending', f"~{est_date.strftime('%Y-%m-%d %H:%M')}", format_diff(diff), format_time(est_time), '-'])

# Separator
rows.append(['...', '', '', '', '', ''])

# Future milestones
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

Generate a difficulty curve chart showing the exponential reduction from 62 TH to 10 MH.

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
START_DIFF = 62.0e12

# Color scheme (matches infographic)
CYAN, MAGENTA, YELLOW = '#00F0FF', '#FF55CC', '#FFE739'
BG_DARK = '#1a1a2e'

# UPDATE THIS: Historical mined blocks
actual_blocks = {
    1920000: {"diff": 62.0e12, "date": datetime(2026, 1, 16, 5, 39), "label": "RESURRECTION!"},
    1920001: {"diff": 59.0e12, "date": datetime(2026, 1, 16, 8, 39)},
    1920002: {"diff": 56.2e12, "date": datetime(2026, 1, 16, 22, 33)},
    1920003: {"diff": 53.5e12, "date": datetime(2026, 1, 17, 10, 15)},
    1920004: {"diff": 50.9e12, "date": datetime(2026, 1, 18, 5, 16)},
    1920005: {"diff": 48.4e12, "date": datetime(2026, 1, 18, 10, 18)},
    1920006: {"diff": 46.1e12, "date": datetime(2026, 1, 18, 15, 31)},
    1920007: {"diff": 43.8e12, "date": datetime(2026, 1, 18, 16, 5)},
}

# UPDATE THIS: Current block being mined
current_mining_block = 1920008

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
ax1.annotate('RESURRECTION!\nBlock 1920000', xy=(1920000, 62.0e12),
             xytext=(1920030, 62.0e12), fontsize=10, color=MAGENTA, fontweight='bold',
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

# Bottom: Time per block bars - SAME BLOCKS AS TABLE
ax2.set_facecolor('#16213e')
times = [d / HASHRATE / 3600 for d in difficulties]

# Exact same blocks as table: mined (0-7), mining (8), near-term (9,10), milestones (20,30,40,50,100,150,200,250,316)
num_mined = len(actual_blocks)
mined_indices = list(range(num_mined))
mining_idx = current_mining_block - 1920000
near_term_indices = [mining_idx + 1, mining_idx + 2]
milestone_blocks = [1920020, 1920030, 1920040, 1920050, 1920100, 1920150, 1920200, 1920250, 1920316]
milestone_indices = [b - 1920000 for b in milestone_blocks]

show_idx = mined_indices + [mining_idx] + near_term_indices + milestone_indices

# Colors: mined=magenta, mining=yellow, pending=cyan, target=yellow
colors = []
for i in show_idx:
    block = blocks[i]
    if block in actual_blocks:
        colors.append(MAGENTA)
    elif block == current_mining_block:
        colors.append(YELLOW)
    elif block == target_block:
        colors.append(YELLOW)
    else:
        colors.append(CYAN)

ax2.bar(range(len(show_idx)), [times[i] for i in show_idx], color=colors, alpha=0.8)
ax2.set_xticks(range(len(show_idx)))
ax2.set_xticklabels([str(blocks[i]) for i in show_idx], rotation=45, ha='right', fontsize=8)
ax2.set_xlabel('Block Number', fontsize=12, color='white')
ax2.set_ylabel('Hours to Mine', fontsize=12, color='white')
ax2.set_title('Estimated Mining Time per Block (2x 8x RTX 3090 = 1692 MH/s)', fontsize=12, color=CYAN)
ax2.tick_params(colors='white')
ax2.grid(True, alpha=0.3, axis='y')
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
| Block | Status | Date/Time | Difficulty | Est. Time | Actual Time |
|-------|--------|-----------|------------|-----------|-------------|
| 1919999 | SYNCED | 2016-07-20 13:20 | 65.1 TH | - | ~14s |
| 1920000 | MINED | 2026-01-16 05:39 | 62.0 TH | 10.2h | 9.5y |
| ... (mined blocks) ... |
| 1920008 | MINING | - | 41.7 TH | 6.8h | - |
| 1920009 | pending | ~2026-01-18 22:56 | 39.7 TH | 6.5h | - |
| 1920010 | pending | ~2026-01-19 05:27 | 37.8 TH | 6.2h | - |
| ... |
| 1920316 | pending | ~2026-01-24 13:54 | 10 MH | instant | - | **<<< CPU!**

**Current:** Block 1920008 | Difficulty: 41.7 TH
**Target:** Block 1920316 (~10 MH = CPU-mineable)
**Remaining:** ~308 blocks | ~142h (5.9 days)
```

**Important formatting rules:**
- Est. Time column comes BEFORE Actual Time column
- MINING row has `-` for Date/Time and Actual Time (not yet complete)
- Pending dates are prefixed with `~` to indicate estimates
- Include `...` separator between near-term and milestone blocks

---

## Files

- **Table image:** `~/Downloads/ethereum_resurrection_table.png` and `.svg`
- **Chart image:** `~/Downloads/ethereum_resurrection_chart.png` and `.svg`
- **Logs:** SSH to instances, see `/root/geth.log` and `/root/ethminer.log`
- **Deploy script:** `resurrection/deploy-vast.sh`
- **Mining script:** `resurrection/mining-script.sh`
- **Infographic:** `infographic.html` (open in browser)
- **Full docs:** `resurrection/README.md`
