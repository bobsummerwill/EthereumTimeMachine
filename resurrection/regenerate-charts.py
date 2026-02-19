#!/usr/bin/env python3
"""
Regenerate resurrection charts with current data from the sync node.

Usage:
    cd resurrection
    source .venv/bin/activate
    python3 regenerate-charts.py

Color palette:
    - Cyan (#00F0FF): Data line, TODO status
    - Yellow (#FFE739): Current point star, IN PROGRESS, 1 GH target
    - Pink (#FF55CC): 46 MH target, DONE status
    - Purple (#6245EB): Headers/accents
    - Background (#1a1a2e): Dark theme
"""

import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from matplotlib.ticker import FuncFormatter
from datetime import datetime
import csv
import json
import os
import subprocess

# Color palette
CYAN = '#00F0FF'
YELLOW = '#FFE739'
PINK = '#FF55CC'
PURPLE = '#6245EB'
BACKGROUND = '#1a1a2e'
TEXT = '#e8e8e8'
GRID = '#888888'
BORDER = '#2a2a4a'

# Sync node connection (override via env)
SYNC_HOST = os.environ.get('SYNC_HOST', '1.208.108.242')
SYNC_PORT = os.environ.get('SYNC_PORT', '46761')
SYNC_USER = os.environ.get('SYNC_USER', 'root')

# Mining constants (override via env)
HASHRATE = float(os.environ.get('HASHRATE', '1692000000'))  # 2 x 8x RTX 3090
REDUCTION = float(os.environ.get('REDUCTION', '0.0483'))

def _rpc_call(method, params):
    payload = {"jsonrpc": "2.0", "method": method, "params": params, "id": 1}
    cmd = [
        "ssh",
        "-o",
        "ConnectTimeout=10",
        "-o",
        "StrictHostKeyChecking=no",
        "-p",
        str(SYNC_PORT),
        f"{SYNC_USER}@{SYNC_HOST}",
        "curl",
        "-s",
        "-X",
        "POST",
        "-H",
        "Content-Type: application/json",
        "--data-binary",
        "@-",
        "http://127.0.0.1:8545",
    ]
    result = subprocess.run(cmd, input=json.dumps(payload), capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "RPC call failed")
    raw = result.stdout.strip()
    if not raw:
        raise RuntimeError("Empty RPC response")
    start = raw.find("{")
    if start == -1:
        raise RuntimeError(f"Non-JSON RPC response: {raw[:200]}")
    data = json.loads(raw[start:])
    if "error" in data:
        raise RuntimeError(f"RPC error: {data['error']}")
    return data.get("result")


def get_block(block_num):
    """Fetch block data from sync node."""
    hex_num = "latest" if block_num == "latest" else hex(block_num)
    block = _rpc_call("eth_getBlockByNumber", [hex_num, False])
    if not block:
        raise RuntimeError(f"Missing block data for {block_num}")
    txs = block.get("transactions") or []
    return {
        "number": int(block["number"], 16),
        "difficulty": int(block["difficulty"], 16),
        "total_difficulty": int(block.get("totalDifficulty") or "0x0", 16),
        "timestamp": int(block["timestamp"], 16),
        "hash": block.get("hash") or "",
        "miner": block.get("miner") or "",
        "gas_used": int(block.get("gasUsed") or "0x0", 16),
        "gas_limit": int(block.get("gasLimit") or "0x0", 16),
        "size": int(block.get("size") or "0x0", 16),
        "tx_count": len(txs),
    }


def get_latest_block_number():
    raw = _rpc_call("eth_blockNumber", [])
    return int(raw, 16)

def fetch_block_range(start_block, end_block):
    """Fetch block number + difficulty (and timestamp) in a single SSH session."""
    remote_py = r'''
import json, urllib.request, sys

def rpc(method, params):
    payload={"jsonrpc":"2.0","method":method,"params":params,"id":1}
    data=json.dumps(payload).encode()
    resp=urllib.request.urlopen("http://127.0.0.1:8545", data=data).read()
    obj=json.loads(resp)
    return obj.get("result")

start=int(sys.argv[1]); end=int(sys.argv[2])
for n in range(start, end + 1):
    b = rpc("eth_getBlockByNumber", [hex(n), False])
    if not b:
        continue
    out = {
        "number": int(b["number"], 16),
        "difficulty": int(b["difficulty"], 16),
        "timestamp": int(b["timestamp"], 16),
    }
    print(json.dumps(out))
'''
    cmd = [
        "ssh",
        "-o",
        "ConnectTimeout=10",
        "-o",
        "StrictHostKeyChecking=no",
        "-p",
        str(SYNC_PORT),
        f"{SYNC_USER}@{SYNC_HOST}",
        "python3",
        "-",
        str(start_block),
        str(end_block),
    ]
    result = subprocess.run(cmd, input=remote_py, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "RPC call failed")
    blocks = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            blocks.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return blocks

def format_difficulty(x, pos):
    """Format difficulty for Y-axis labels."""
    if x >= 1e12:
        return f'{x/1e12:.1f} TH'
    elif x >= 1e9:
        return f'{x/1e9:.1f} GH'
    elif x >= 1e6:
        return f'{x/1e6:.0f} MH'
    else:
        return f'{x:.0f}'


def format_diff_value(value):
    if value >= 1e12:
        return f'{value/1e12:.2f} TH'
    if value >= 1e9:
        return f'{value/1e9:.2f} GH'
    if value >= 1e6:
        return f'{value/1e6:.2f} MH'
    return f'{value:.0f} H'


def format_int(value):
    return f"{int(value):,}"


def format_time_hours(hours):
    if hours is None:
        return "-"
    if hours >= 24:
        return f"{hours/24:.1f}d"
    if hours >= 1:
        return f"{hours:.1f}h"
    minutes = hours * 60
    if minutes >= 1:
        return f"{minutes:.1f}m"
    return f"{hours*3600:.1f}s"


def short_hash(value):
    if not value:
        return "-"
    if len(value) <= 12:
        return value
    return f"{value[:10]}...{value[-6:]}"

def generate_chart(blocks_data, output_dir):
    """Generate the difficulty vs time chart."""
    # Filter to resurrection-era blocks only (1920000+) to avoid 10-year gap from pre-fork block
    resurrection_data = [b for b in blocks_data if b['number'] >= 1920000]
    times = [datetime.fromtimestamp(b['timestamp']) for b in resurrection_data]
    diffs = [b['difficulty'] for b in resurrection_data]

    plt.style.use('dark_background')
    fig, ax = plt.subplots(figsize=(14, 10))
    fig.patch.set_facecolor(BACKGROUND)
    ax.set_facecolor(BACKGROUND)

    # Plot difficulty line (all but last point)
    ax.semilogy(times[:-1], diffs[:-1], color=CYAN, linewidth=2.5, marker='o', markersize=6)

    # Plot latest point with yellow star
    ax.semilogy(times[-1], diffs[-1], color=YELLOW, marker='*', markersize=20,
                markeredgecolor=YELLOW, markeredgewidth=1, zorder=10,
                label=f'Current: {diffs[-1]/1e9:.2f} GH')

    # Target lines
    ax.axhline(y=1e9, color=YELLOW, linestyle='--', linewidth=1.5, label='1 GH (GPU target)')
    ax.axhline(y=46e6, color=PINK, linestyle='--', linewidth=1.5, label='46 MH (CPU equilibrium)')

    # --- Mining phase annotations ---
    from datetime import timedelta

    arrow_style = dict(arrowstyle='->', color=YELLOW, lw=1.5)
    bbox_style = dict(boxstyle='round,pad=0.3', facecolor=BACKGROUND, edgecolor=YELLOW, alpha=0.9)
    label_kwargs = dict(fontsize=9, color=YELLOW, fontfamily='monospace', fontweight='bold',
                        ha='center', va='center', bbox=bbox_style)

    # Helper: find the data point closest to a given date
    def _closest(target_date):
        best_idx = 0
        best_delta = abs(times[0] - target_date)
        for i, t in enumerate(times):
            d = abs(t - target_date)
            if d < best_delta:
                best_delta = d
                best_idx = i
        return times[best_idx], diffs[best_idx]

    # Phase 1: 16 x 3090 GPUs — up to ~Jan 28
    p1_x, p1_y = _closest(datetime(2026, 1, 22))
    ax.annotate('16 x 3090 GPUs', xy=(p1_x, p1_y),
                xytext=(p1_x - timedelta(days=5), p1_y * 0.02),
                arrowprops=arrow_style, **label_kwargs)

    # Phase 2: 8 x 3090 GPUs — ~Jan 28 to ~Jan 30
    p2_x, p2_y = _closest(datetime(2026, 1, 29))
    ax.annotate('8 x 3090 GPUs', xy=(p2_x, p2_y),
                xytext=(p2_x - timedelta(days=7), p2_y * 0.15),
                arrowprops=arrow_style, **label_kwargs)

    # Phase 3: 1 x GTX 1080 GPU — ~Jan 30 to ~Feb 9
    p3_x, p3_y = _closest(datetime(2026, 2, 4))
    ax.annotate('1 x GTX 1080 GPU', xy=(p3_x, p3_y),
                xytext=(p3_x - timedelta(days=3), p3_y * 50),
                arrowprops=arrow_style, **label_kwargs)

    # Phase 4: 1 x Xeon 12-core CPU — ~Feb 9 to ~Feb 13
    p4_x, p4_y = _closest(datetime(2026, 2, 11))
    ax.annotate('1 x Xeon 12-core CPU', xy=(p4_x, p4_y),
                xytext=(p4_x - timedelta(days=5), p4_y * 0.1),
                arrowprops=arrow_style, **label_kwargs)

    # Phase 5: 1 x GTX 1080 GPU — from ~Feb 17
    p5_x, p5_y = _closest(datetime(2026, 2, 18))
    ax.annotate('1 x GTX 1080 GPU (current)', xy=(p5_x, p5_y),
                xytext=(p5_x - timedelta(days=5), p5_y * 30),
                arrowprops=arrow_style, **label_kwargs)

    # Formatting
    ax.set_ylabel('Difficulty', color=TEXT, fontsize=14)
    ax.set_xlabel('Date', color=TEXT, fontsize=14)
    ax.set_title('Ethereum Homestead Resurrection - Difficulty Reduction',
                 color=CYAN, fontsize=16, fontweight='bold')

    # Date formatting - day over month
    ax.xaxis.set_major_formatter(mdates.DateFormatter('%d\n%b'))
    ax.xaxis.set_major_locator(mdates.DayLocator(interval=2))

    # Grid
    ax.grid(True, alpha=0.3, color=GRID)
    ax.tick_params(colors=TEXT)

    # Legend
    ax.legend(loc='upper right', facecolor=BACKGROUND, edgecolor=BORDER)

    # Y-axis formatting
    ax.yaxis.set_major_formatter(FuncFormatter(format_difficulty))

    plt.tight_layout()
    plt.savefig(f'{output_dir}/resurrection_chart.png', dpi=150, facecolor=BACKGROUND)
    plt.savefig(f'{output_dir}/resurrection_chart.svg', facecolor=BACKGROUND)
    plt.close()

    print(f"Chart saved to {output_dir}/resurrection_chart.png and .svg")

def generate_block_chart(blocks_data, output_dir):
    """Generate difficulty vs block number chart."""
    numbers = [b['number'] for b in blocks_data]
    diffs = [b['difficulty'] for b in blocks_data]

    plt.style.use('dark_background')
    fig, ax = plt.subplots(figsize=(14, 10))
    fig.patch.set_facecolor(BACKGROUND)
    ax.set_facecolor(BACKGROUND)

    ax.semilogy(numbers, diffs, color=CYAN, linewidth=2.0)

    # Latest point
    ax.semilogy(numbers[-1], diffs[-1], color=YELLOW, marker='*', markersize=18,
                markeredgecolor=YELLOW, markeredgewidth=1, zorder=10,
                label=f'Current: {diffs[-1]/1e6:.2f} MH')

    # Target lines
    ax.axhline(y=1e9, color=YELLOW, linestyle='--', linewidth=1.5, label='1 GH (GPU target)')
    ax.axhline(y=46e6, color=PINK, linestyle='--', linewidth=1.5, label='46 MH (CPU equilibrium)')

    ax.set_ylabel('Difficulty', color=TEXT, fontsize=14)
    ax.set_xlabel('Block Number', color=TEXT, fontsize=14)
    ax.set_title('Ethereum Homestead Resurrection - Difficulty vs Block Number',
                 color=CYAN, fontsize=16, fontweight='bold')

    ax.grid(True, alpha=0.3, color=GRID)
    ax.tick_params(colors=TEXT)
    ax.legend(loc='upper right', facecolor=BACKGROUND, edgecolor=BORDER)
    ax.yaxis.set_major_formatter(FuncFormatter(format_difficulty))
    ax.xaxis.set_major_formatter(FuncFormatter(lambda x, pos: f'{int(x):,}'))
    ax.tick_params(axis='x', rotation=30)

    plt.tight_layout()
    plt.savefig(f'{output_dir}/resurrection_chart_blocks.png', dpi=150, facecolor=BACKGROUND)
    plt.savefig(f'{output_dir}/resurrection_chart_blocks.svg', facecolor=BACKGROUND)
    plt.close()

    print(f"Chart saved to {output_dir}/resurrection_chart_blocks.png and .svg")

def generate_table(daily_blocks, output_dir):
    """Generate the daily progress table."""
    # Fetch all block data
    table_data = []
    for block_num, date in daily_blocks:
        b = get_block(block_num)
        diff = b['difficulty']
        if diff >= 1e12:
            diff_str = f"{diff/1e12:.1f} TH"
        elif diff >= 1e9:
            diff_str = f"{diff/1e9:.2f} GH"
        else:
            diff_str = f"{diff/1e6:.1f} MH"
        reduction = 100 * (1 - diff / 59_400_000_000_000)
        table_data.append({
            'date': date,
            'block': f"{b['number']:,}",
            'difficulty': diff_str,
            'reduction': f"{reduction:.1f}%" if reduction < 99.9 else f"{reduction:.3f}%"
        })
        print(f"{date}: Block {b['number']:,}, {diff_str}, {reduction:.3f}%")

    # Create table figure
    fig, ax = plt.subplots(figsize=(10, 8))
    fig.patch.set_facecolor(BACKGROUND)
    ax.set_facecolor(BACKGROUND)
    ax.axis('off')

    # Table data
    columns = ['Date', 'Block', 'Difficulty', 'Reduction']
    cell_text = [[d['date'], d['block'], d['difficulty'], d['reduction']] for d in table_data]

    table = ax.table(
        cellText=cell_text,
        colLabels=columns,
        loc='center',
        cellLoc='center'
    )

    # Style table
    table.auto_set_font_size(False)
    table.set_fontsize(11)
    table.scale(1.2, 1.8)

    # Color header cells
    for i in range(len(columns)):
        table[(0, i)].set_facecolor(PURPLE)
        table[(0, i)].set_text_props(color='white', fontweight='bold')

    # Color data cells
    for i in range(1, len(table_data) + 1):
        for j in range(len(columns)):
            table[(i, j)].set_facecolor(BACKGROUND)
            table[(i, j)].set_text_props(color=TEXT)
            table[(i, j)].set_edgecolor(BORDER)

    # Highlight current day (last row)
    for j in range(len(columns)):
        table[(len(table_data), j)].set_facecolor('#2a2a4a')
        table[(len(table_data), j)].set_text_props(color=CYAN, fontweight='bold')

    ax.set_title('Ethereum Homestead Resurrection - Daily Progress',
                 color=CYAN, fontsize=14, fontweight='bold', pad=20)

    plt.tight_layout()
    plt.savefig(f'{output_dir}/resurrection_table.png', dpi=150, facecolor=BACKGROUND, bbox_inches='tight')
    plt.savefig(f'{output_dir}/resurrection_table.svg', facecolor=BACKGROUND, bbox_inches='tight')
    plt.close()

    print(f"\nTable saved to {output_dir}/resurrection_table.png and .svg")


def generate_matrix(output_dir, last_blocks, latest_block):
    last_start = min(last_blocks)
    needed_blocks = set(last_blocks)
    needed_blocks.add(last_start - 1)

    blocks = {}
    for bn in sorted(needed_blocks):
        if bn < 0:
            continue
        blocks[bn] = get_block(bn)

    latest = blocks[latest_block]
    last_mined_ts = latest["timestamp"]
    last_mined_diff = latest["difficulty"]
    current_mining_block = latest_block + 1

    rows = []
    for bn in last_blocks:
        block = blocks.get(bn)
        prev = blocks.get(bn - 1)
        actual_hours = None
        if block and prev:
            actual_hours = (block["timestamp"] - prev["timestamp"]) / 3600
        est_hours = block["difficulty"] / HASHRATE / 3600 if block else None
        dt = datetime.utcfromtimestamp(block["timestamp"]).strftime("%Y-%m-%d %H:%M") if block else "-"
        rows.append({
            "block": bn,
            "status": "MINED",
            "datetime": dt,
            "difficulty": format_diff_value(block["difficulty"]) if block else "-",
            "total_difficulty": format_diff_value(block["total_difficulty"]) if block else "-",
            "tx_count": format_int(block["tx_count"]) if block else "-",
            "gas_used": format_int(block["gas_used"]) if block else "-",
            "gas_limit": format_int(block["gas_limit"]) if block else "-",
            "size": format_int(block["size"]) if block else "-",
            "miner": block["miner"] if block else "-",
            "hash": short_hash(block["hash"]) if block else "-",
            "est_time": format_time_hours(est_hours),
            "actual_time": format_time_hours(actual_hours),
        })

    rows.append({
        "block": "...",
        "status": "",
        "datetime": "",
        "difficulty": "",
        "total_difficulty": "",
        "tx_count": "",
        "gas_used": "",
        "gas_limit": "",
        "size": "",
        "miner": "",
        "hash": "",
        "est_time": "",
        "actual_time": "",
    })

    cumulative_hours = 0.0
    prev_diff = last_mined_diff
    for i in range(1, 21):
        bn = latest_block + i
        diff = prev_diff * (1 - REDUCTION)
        prev_diff = diff
        est_hours = diff / HASHRATE / 3600
        cumulative_hours += est_hours
        est_dt = datetime.utcfromtimestamp(last_mined_ts + int(cumulative_hours * 3600))
        status = "MINING" if bn == current_mining_block else "pending"
        dt_str = "-" if status == "MINING" else f"~{est_dt.strftime('%Y-%m-%d %H:%M')}"
        rows.append({
            "block": bn,
            "status": status,
            "datetime": dt_str,
            "difficulty": format_diff_value(diff),
            "total_difficulty": "-",
            "tx_count": "-",
            "gas_used": "-",
            "gas_limit": "-",
            "size": "-",
            "miner": "-",
            "hash": "-",
            "est_time": format_time_hours(est_hours),
            "actual_time": "-",
        })

    md_path = os.path.join(output_dir, "mining_matrix.md")
    csv_path = os.path.join(output_dir, "mining_matrix.csv")

    headers = [
        "Block",
        "Status",
        "Date/Time (UTC)",
        "Difficulty",
        "Total Difficulty",
        "Tx Count",
        "Gas Used",
        "Gas Limit",
        "Size (bytes)",
        "Miner",
        "Hash",
        "Est. Time",
        "Actual Time",
    ]

    with open(md_path, "w", encoding="utf-8") as md:
        md.write("| " + " | ".join(headers) + " |\n")
        md.write("|" + "|".join(["---"] * len(headers)) + "|\n")
        for row in rows:
            md.write(
                "| {block} | {status} | {datetime} | {difficulty} | {total_difficulty} | {tx_count} | "
                "{gas_used} | {gas_limit} | {size} | {miner} | {hash} | {est_time} | {actual_time} |\n".format(
                    block=row["block"],
                    status=row["status"],
                    datetime=row["datetime"],
                    difficulty=row["difficulty"],
                    total_difficulty=row["total_difficulty"],
                    tx_count=row["tx_count"],
                    gas_used=row["gas_used"],
                    gas_limit=row["gas_limit"],
                    size=row["size"],
                    miner=row["miner"],
                    hash=row["hash"],
                    est_time=row["est_time"],
                    actual_time=row["actual_time"],
                )
            )

    with open(csv_path, "w", newline="", encoding="utf-8") as csv_file:
        writer = csv.writer(csv_file)
        writer.writerow(headers)
        for row in rows:
            writer.writerow([
                row["block"],
                row["status"],
                row["datetime"],
                row["difficulty"],
                row["total_difficulty"],
                row["tx_count"],
                row["gas_used"],
                row["gas_limit"],
                row["size"],
                row["miner"],
                row["hash"],
                row["est_time"],
                row["actual_time"],
            ])

    print(f"\nMatrix saved to {md_path} and {csv_path}")

def main():
    # Ensure output directory exists
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.join(script_dir, 'generated-files')
    os.makedirs(output_dir, exist_ok=True)

    only_block_chart = os.environ.get("ONLY_BLOCK_CHART", "").lower() in {"1", "true", "yes"}

    print("Fetching latest block from sync node...")
    latest_number = get_latest_block_number()
    latest = get_block(latest_number)
    print(f"Latest: Block {latest['number']:,}, Difficulty {latest['difficulty']/1e9:.3f} GH")
    print()

    start_block = int(os.environ.get("START_BLOCK", "1919999"))
    if start_block < 0:
        start_block = 0

    print("\nFetching block data for full-range charts...")
    use_bulk = os.environ.get("BLOCK_CHART_BULK", "1") not in {"0", "false", "no"}
    if use_bulk:
        block_chart_data = fetch_block_range(start_block, latest['number'])
    else:
        block_chart_data = []
        for bn in range(start_block, latest['number'] + 1):
            try:
                b = get_block(bn)
                block_chart_data.append(b)
            except Exception as e:
                print(f"Error fetching block {bn}: {e}")
    if block_chart_data:
        if not only_block_chart:
            print(f"\nGenerating time chart with {len(block_chart_data)} data points...")
            generate_chart(block_chart_data, output_dir)

        print(f"Generating block-number chart with {len(block_chart_data)} data points...")
        generate_block_chart(block_chart_data, output_dir)
    else:
        print("No block data available for charts.")

    if not only_block_chart:
        # Daily blocks for table (last block of each UTC day, last 15 days)
        daily_blocks = []
        if block_chart_data:
            by_day = {}
            for b in block_chart_data:
                day = datetime.utcfromtimestamp(b["timestamp"]).strftime("%Y-%m-%d")
                by_day[day] = b["number"]
            days = sorted(by_day.keys())
            for day in days[-15:]:
                daily_blocks.append((by_day[day], day))
        else:
            daily_blocks = [(latest['number'], datetime.utcfromtimestamp(latest["timestamp"]).strftime("%Y-%m-%d"))]

        print("\nGenerating table...")
        generate_table(daily_blocks, output_dir)

        print("\nGenerating last/next 20 block matrix...")
        last_blocks = list(range(max(0, latest['number'] - 19), latest['number'] + 1))
        generate_matrix(output_dir, last_blocks, latest['number'])

    print("\nDone!")

if __name__ == "__main__":
    main()
