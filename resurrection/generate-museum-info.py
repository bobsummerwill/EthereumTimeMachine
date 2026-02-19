#!/usr/bin/env python3
"""Generate museum info graphic for the slideshow."""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

# Color palette (matches sync-ui / resurrection charts)
CYAN = '#00F0FF'
YELLOW = '#FFE739'
PINK = '#FF55CC'
PURPLE = '#6245EB'
BACKGROUND = '#1a1a2e'
TEXT = '#e8e8e8'
DIM = '#999999'
CARD_BG = '#242445'
BORDER = '#3a3a5a'

def generate():
    fig, ax = plt.subplots(figsize=(16, 10))
    fig.patch.set_facecolor(BACKGROUND)
    ax.set_facecolor(BACKGROUND)
    ax.axis('off')

    # Title
    ax.text(0.5, 0.95, 'Homestead Resurrected', fontsize=32, fontweight='bold',
            color=CYAN, ha='center', va='top', transform=ax.transAxes,
            fontfamily='monospace')

    ax.text(0.5, 0.89, 'These ThinkPads are running on a resurrected Homestead chain.',
            fontsize=14, color=TEXT, ha='center', va='top', transform=ax.transAxes,
            fontfamily='monospace')
    ax.text(0.5, 0.855, 'Not a fork. Not a testnet. The real chain, extended.',
            fontsize=14, color=YELLOW, ha='center', va='top', transform=ax.transAxes,
            fontfamily='monospace', fontweight='bold')

    # Hardware/Software specs - left column
    specs_title_y = 0.78
    ax.text(0.05, specs_title_y, 'HARDWARE & SOFTWARE', fontsize=12, fontweight='bold',
            color=PURPLE, ha='left', va='top', transform=ax.transAxes,
            fontfamily='monospace')

    specs = [
        ('ThinkPad T410', 'Intel Core i5, 4 GB memory'),
        ('Windows 7', 'Authentic 2010-era hardware'),
        ('Mist Wallet 0.7.4', 'Beta 18 — released 17 May 2016'),
        ('Geth 1.3.6', 'Released 25 March 2016'),
    ]

    y = specs_title_y - 0.05
    for label, desc in specs:
        ax.text(0.07, y, '›', fontsize=14, color=CYAN, ha='left', va='top',
                transform=ax.transAxes, fontfamily='monospace', fontweight='bold')
        ax.text(0.10, y, label, fontsize=13, color=TEXT, ha='left', va='top',
                transform=ax.transAxes, fontfamily='monospace', fontweight='bold')
        ax.text(0.10, y - 0.030, desc, fontsize=11, color=DIM, ha='left', va='top',
                transform=ax.transAxes, fontfamily='monospace')
        y -= 0.070

    # What can you do - right column
    ax.text(0.55, specs_title_y, 'TRY IT YOURSELF', fontsize=12, fontweight='bold',
            color=PURPLE, ha='left', va='top', transform=ax.transAxes,
            fontfamily='monospace')

    steps = [
        ('1.', 'Click', 'Send'),
        ('2.', 'Choose an amount of ETH to send', ''),
        ('3.', 'Paste the receiver address from', 'Addresses.txt on the desktop'),
        ('4.', 'Scroll to the bottom and click', 'Send'),
        ('5.', 'Enter the password:', 'museum'),
    ]

    y = specs_title_y - 0.05
    for num, line1, line2 in steps:
        ax.text(0.57, y, num, fontsize=13, color=CYAN, ha='left', va='top',
                transform=ax.transAxes, fontfamily='monospace', fontweight='bold')
        ax.text(0.61, y, line1, fontsize=12, color=TEXT, ha='left', va='top',
                transform=ax.transAxes, fontfamily='monospace')
        if line2:
            ax.text(0.61, y - 0.030, line2, fontsize=12, color=YELLOW, ha='left', va='top',
                    transform=ax.transAxes, fontfamily='monospace', fontweight='bold')
        y -= 0.070

    # Pending transactions note
    ax.text(0.55, 0.355, 'Pending and completed transactions are shown',
            fontsize=10, color=DIM, ha='left', va='top', transform=ax.transAxes,
            fontfamily='monospace')
    ax.text(0.55, 0.325, 'at the very bottom of the page if you scroll down.',
            fontsize=10, color=DIM, ha='left', va='top', transform=ax.transAxes,
            fontfamily='monospace')

    # Divider line
    ax.plot([0.05, 0.95], [0.26, 0.26], color=BORDER, linewidth=1,
            transform=ax.transAxes)

    # MacBooks section
    ax.text(0.05, 0.22, 'WHITE MACBOOKS', fontsize=12, fontweight='bold',
            color=PURPLE, ha='left', va='top', transform=ax.transAxes,
            fontfamily='monospace')
    ax.text(0.05, 0.18, 'Browse the early history of Ethereum at',
            fontsize=12, color=TEXT, ha='left', va='top', transform=ax.transAxes,
            fontfamily='monospace')
    ax.text(0.05, 0.145, 'earlydaysofeth.org',
            fontsize=14, color=CYAN, ha='left', va='top', transform=ax.transAxes,
            fontfamily='monospace', fontweight='bold')

    # Footer with repo link
    ax.plot([0.05, 0.95], [0.09, 0.09], color=BORDER, linewidth=1,
            transform=ax.transAxes)

    ax.text(0.5, 0.05, 'Try this at home    github.com/bobsummerwill/EthereumTimeMachine',
            fontsize=12, color=DIM, ha='center', va='top', transform=ax.transAxes,
            fontfamily='monospace')

    plt.tight_layout(pad=1.0)

    import os
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.join(script_dir, 'generated-files')
    os.makedirs(output_dir, exist_ok=True)

    out_png = os.path.join(output_dir, 'museum_info.png')
    out_svg = os.path.join(output_dir, 'museum_info.svg')
    plt.savefig(out_png, dpi=150, facecolor=BACKGROUND, bbox_inches='tight')
    plt.savefig(out_svg, facecolor=BACKGROUND, bbox_inches='tight')
    plt.close()
    print(f"Saved to {out_png} and {out_svg}")

if __name__ == '__main__':
    generate()
