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
        ('ThinkPad T410 — Intel Core i5, 4 GB', 'Released 7 January 2010'),
        ('Windows 7', 'Released 22 October 2009'),
        ('Mist Wallet 0.7.4', 'Released 17 May 2016'),
        ('Geth 1.3.6', 'Released 25 March 2016'),
    ]

    y = specs_title_y - 0.05
    for label, desc in specs:
        ax.text(0.07, y, '›', fontsize=18, color=CYAN, ha='left', va='top',
                transform=ax.transAxes, fontfamily='monospace', fontweight='bold')
        ax.text(0.11, y, f'{label}  ', fontsize=16, color=TEXT, ha='left', va='top',
                transform=ax.transAxes, fontfamily='monospace', fontweight='bold')
        ax.text(0.11, y - 0.035, desc, fontsize=13, color=DIM, ha='left', va='top',
                transform=ax.transAxes, fontfamily='monospace')
        y -= 0.075

    # What can you do - right column
    ax.text(0.55, specs_title_y, 'TRY IT YOURSELF', fontsize=12, fontweight='bold',
            color=PURPLE, ha='left', va='top', transform=ax.transAxes,
            fontfamily='monospace')

    steps = [
        ('1.', 'Click Send'),
        ('2.', 'Choose an amount of ETH'),
        ('3.', 'Paste address from Addresses.txt file'),
        ('4.', 'Scroll down and click Send'),
        ('5.', 'Enter password: museum'),
        ('6.', 'Scroll down to see transactions'),
    ]

    y = specs_title_y - 0.05
    for num, text in steps:
        ax.text(0.57, y, num, fontsize=18, color=CYAN, ha='left', va='top',
                transform=ax.transAxes, fontfamily='monospace', fontweight='bold')
        ax.text(0.63, y, text, fontsize=16, color=TEXT, ha='left', va='top',
                transform=ax.transAxes, fontfamily='monospace')
        y -= 0.075

    # Divider line
    ax.plot([0.05, 0.95], [0.26, 0.26], color=BORDER, linewidth=1,
            transform=ax.transAxes)

    # Password reminder — large centered yellow text
    ax.text(0.5, 0.17, 'All passwords are "museum"',
            fontsize=28, color=YELLOW, ha='center', va='center', transform=ax.transAxes,
            fontfamily='monospace', fontweight='bold')

    # Footer with repo link
    ax.plot([0.05, 0.95], [0.09, 0.09], color=BORDER, linewidth=1,
            transform=ax.transAxes)

    ax.text(0.5, 0.05, 'Try this at home    https://github.com/bobsummerwill/EthereumTimeMachine',
            fontsize=12, color=CYAN, ha='center', va='top', transform=ax.transAxes,
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
