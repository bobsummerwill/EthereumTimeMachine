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
import subprocess
import json
import os

# Color palette
CYAN = '#00F0FF'
YELLOW = '#FFE739'
PINK = '#FF55CC'
PURPLE = '#6245EB'
BACKGROUND = '#1a1a2e'
TEXT = '#e8e8e8'
GRID = '#888888'
BORDER = '#2a2a4a'

# Sync node connection
SYNC_HOST = '1.208.108.242'
SYNC_PORT = '46761'

def get_block(block_num):
    """Fetch block data from sync node."""
    if block_num == "latest":
        hex_num = "latest"
    else:
        hex_num = hex(block_num)

    cmd = f'''ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p {SYNC_PORT} root@{SYNC_HOST} 'curl -s -X POST -H "Content-Type: application/json" --data "{{\\"jsonrpc\\":\\"2.0\\",\\"method\\":\\"eth_getBlockByNumber\\",\\"params\\":[\\"{hex_num}\\", false],\\"id\\":1}}" http://127.0.0.1:8545' 2>/dev/null'''

    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    data = json.loads(result.stdout)
    block = data["result"]

    return {
        "number": int(block["number"], 16),
        "difficulty": int(block["difficulty"], 16),
        "timestamp": int(block["timestamp"], 16)
    }

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

def generate_chart(blocks_data, output_dir):
    """Generate the difficulty vs time chart."""
    times = [datetime.fromtimestamp(b['timestamp']) for b in blocks_data]
    diffs = [b['difficulty'] for b in blocks_data]

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

def main():
    # Ensure output directory exists
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.join(script_dir, 'generated-files')
    os.makedirs(output_dir, exist_ok=True)

    print("Fetching latest block from sync node...")
    latest = get_block("latest")
    print(f"Latest: Block {latest['number']:,}, Difficulty {latest['difficulty']/1e9:.3f} GH")
    print()

    # Sample blocks for chart
    sample_blocks = [
        1920000, 1920001, 1920003, 1920007, 1920010, 1920015, 1920019,
        1920022, 1920027, 1920031, 1920044, 1920074, 1920200, 1920400,
        1920538, 1920581, 1920700, 1920810, 1920850, 1920900, latest['number']
    ]

    print("Fetching block data for chart...")
    blocks_data = []
    for bn in sample_blocks:
        if bn <= latest['number']:
            try:
                b = get_block(bn)
                blocks_data.append(b)
            except Exception as e:
                print(f"Error fetching block {bn}: {e}")

    print(f"\nGenerating chart with {len(blocks_data)} data points...")
    generate_chart(blocks_data, output_dir)

    # Daily blocks for table (last block of each day)
    daily_blocks = [
        (1920000, "Jan 15"),
        (1920001, "Jan 16"),
        (1920003, "Jan 17"),
        (1920007, "Jan 18"),
        (1920010, "Jan 19"),
        (1920015, "Jan 20"),
        (1920019, "Jan 21"),
        (1920022, "Jan 22"),
        (1920027, "Jan 23"),
        (1920031, "Jan 24"),
        (1920044, "Jan 25"),
        (1920074, "Jan 26"),
        (1920538, "Jan 27"),
        (1920581, "Jan 28"),
        (latest['number'], "Jan 29"),
    ]

    print("\nGenerating table...")
    generate_table(daily_blocks, output_dir)

    print("\nDone!")

if __name__ == "__main__":
    main()
