#!/usr/bin/env python3
"""Generate QR codes graphic for the slideshow."""

import matplotlib.pyplot as plt
import matplotlib.image as mpimg
import qrcode
import io
import os

# Color palette (matches sync-ui / resurrection charts)
CYAN = '#00F0FF'
YELLOW = '#FFE739'
PINK = '#FF55CC'
PURPLE = '#6245EB'
BACKGROUND = '#1a1a2e'
TEXT = '#e8e8e8'
DIM = '#999999'
BORDER = '#3a3a5a'

def make_qr(url, fg_color, bg_color):
    """Generate a QR code image as a numpy array."""
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_H,
        box_size=10,
        border=2,
    )
    qr.add_data(url)
    qr.make(fit=True)
    img = qr.make_image(fill_color=fg_color, back_color=bg_color)
    return img.convert('RGB')

def generate():
    fig, ax = plt.subplots(figsize=(16, 10))
    fig.patch.set_facecolor(BACKGROUND)
    ax.set_facecolor(BACKGROUND)
    ax.axis('off')

    # Title
    ax.text(0.5, 0.93, 'Learn More', fontsize=36, fontweight='bold',
            color=CYAN, ha='center', va='top', transform=ax.transAxes,
            fontfamily='monospace')

    # QR code 1 - earlydaysofeth.org
    qr1 = make_qr('https://earlydaysofeth.org', CYAN, BACKGROUND)
    # QR code 2 - strato.nexus
    qr2 = make_qr('https://strato.nexus', YELLOW, BACKGROUND)

    # Place QR codes as inset axes
    # Left QR
    ax_qr1 = fig.add_axes([0.08, 0.18, 0.38, 0.60])
    ax_qr1.imshow(qr1)
    ax_qr1.axis('off')

    # Right QR
    ax_qr2 = fig.add_axes([0.54, 0.18, 0.38, 0.60])
    ax_qr2.imshow(qr2)
    ax_qr2.axis('off')

    # Labels under QR codes
    ax.text(0.27, 0.14, 'earlydaysofeth.org', fontsize=20, fontweight='bold',
            color=CYAN, ha='center', va='top', transform=ax.transAxes,
            fontfamily='monospace')
    ax.text(0.27, 0.09, 'Early Days of Ethereum', fontsize=14,
            color=TEXT, ha='center', va='top', transform=ax.transAxes,
            fontfamily='monospace')

    ax.text(0.73, 0.14, 'strato.nexus', fontsize=20, fontweight='bold',
            color=YELLOW, ha='center', va='top', transform=ax.transAxes,
            fontfamily='monospace')
    ax.text(0.73, 0.09, 'STRATO Blockchain Platform', fontsize=14,
            color=TEXT, ha='center', va='top', transform=ax.transAxes,
            fontfamily='monospace')

    # Footer
    ax.plot([0.05, 0.95], [0.05, 0.05], color=BORDER, linewidth=1,
            transform=ax.transAxes)
    ax.text(0.5, 0.02, 'https://github.com/bobsummerwill/EthereumTimeMachine',
            fontsize=12, color=CYAN, ha='center', va='top', transform=ax.transAxes,
            fontfamily='monospace')

    plt.tight_layout(pad=1.0)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.join(script_dir, 'generated-files')
    os.makedirs(output_dir, exist_ok=True)

    out_png = os.path.join(output_dir, 'qr_codes.png')
    plt.savefig(out_png, dpi=150, facecolor=BACKGROUND, bbox_inches='tight')
    plt.close()
    print(f"Saved to {out_png}")

    # Also copy to resurrection/ root for deployment
    import shutil
    root_copy = os.path.join(script_dir, 'qr_codes.png')
    shutil.copy2(out_png, root_copy)
    print(f"Copied to {root_copy}")

if __name__ == '__main__':
    generate()
