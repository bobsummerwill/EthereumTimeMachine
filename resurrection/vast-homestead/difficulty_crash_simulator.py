#!/usr/bin/env python3
"""
Simulate difficulty crash for Frontier/Homestead chain resurrection.

Models the time and cost to reduce difficulty from ~18 trillion to CPU-mineable
levels using GPU mining with manipulated timestamps.
"""

import math

# Starting conditions
HOMESTEAD_DIFFICULTY = 18_000_000_000_000  # ~18 trillion at block 1,919,999
FRONTIER_DIFFICULTY = 17_500_000_000_000   # ~17.5 trillion at block 1,149,999

# Target: CPU-mineable (single modern CPU can do ~1 MH/s)
# At 1 MH/s, we want blocks in <1 minute, so difficulty < 60 * 1_000_000 = 60M
TARGET_DIFFICULTY = 50_000_000  # 50 million - easily CPU mineable

# Difficulty adjustment: max 1/2048 reduction per block
ADJUSTMENT_FACTOR = 1 / 2048

# GPU hashrates (MH/s for Ethash)
GPUS = {
    "RTX 3090": 120,
    "RTX 4090": 130,
    "RTX 3090 x2": 240,
    "RTX 3090 x4": 480,
    "RTX 4090 x4": 520,
    "RTX 3090 x8": 960,
    "A100 (40GB)": 65,  # Not great for Ethash
}

# Vast.ai approximate costs ($/hr)
COSTS = {
    "RTX 3090": 0.16,
    "RTX 4090": 0.35,
    "RTX 3090 x2": 0.32,
    "RTX 3090 x4": 0.64,
    "RTX 4090 x4": 1.40,
    "RTX 3090 x8": 1.28,
    "A100 (40GB)": 1.50,
}


def expected_time_to_mine_block(difficulty: int, hashrate_mhs: float) -> float:
    """
    Expected time in seconds to mine a block.

    For Ethash: time = difficulty / hashrate
    """
    hashrate_hs = hashrate_mhs * 1_000_000  # Convert MH/s to H/s
    return difficulty / hashrate_hs


def simulate_crash(start_difficulty: int, hashrate_mhs: float, label: str = "") -> dict:
    """
    Simulate mining until difficulty drops to target.

    Returns dict with blocks mined, total time, and difficulty progression.
    """
    difficulty = start_difficulty
    total_time_seconds = 0
    blocks = 0

    # Track milestones
    milestones = []
    milestone_factors = [10, 100, 1000, 10000, 100000, 1000000]
    next_milestone_idx = 0

    while difficulty > TARGET_DIFFICULTY:
        # Time to mine this block
        block_time = expected_time_to_mine_block(difficulty, hashrate_mhs)
        total_time_seconds += block_time
        blocks += 1

        # Check milestones
        reduction_factor = start_difficulty / difficulty
        while (next_milestone_idx < len(milestone_factors) and
               reduction_factor >= milestone_factors[next_milestone_idx]):
            milestones.append({
                "factor": milestone_factors[next_milestone_idx],
                "blocks": blocks,
                "time_hours": total_time_seconds / 3600,
                "difficulty": difficulty,
            })
            next_milestone_idx += 1

        # Reduce difficulty by 1/2048
        difficulty = int(difficulty * (1 - ADJUSTMENT_FACTOR))

    return {
        "blocks": blocks,
        "total_seconds": total_time_seconds,
        "total_hours": total_time_seconds / 3600,
        "total_days": total_time_seconds / 86400,
        "final_difficulty": difficulty,
        "milestones": milestones,
    }


def format_time(hours: float) -> str:
    """Format hours into human-readable string."""
    if hours < 1:
        return f"{hours * 60:.0f} minutes"
    elif hours < 24:
        return f"{hours:.1f} hours"
    else:
        days = hours / 24
        return f"{days:.1f} days"


def main():
    print("=" * 70)
    print("DIFFICULTY CRASH SIMULATION")
    print("=" * 70)
    print(f"\nTarget difficulty: {TARGET_DIFFICULTY:,} (CPU-mineable)")
    print(f"Max reduction per block: 1/2048 = {ADJUSTMENT_FACTOR*100:.4f}%")

    for chain_name, start_diff in [("Homestead", HOMESTEAD_DIFFICULTY),
                                    ("Frontier", FRONTIER_DIFFICULTY)]:
        print(f"\n{'=' * 70}")
        print(f"{chain_name.upper()} (starting difficulty: {start_diff:,})")
        print("=" * 70)

        reduction_needed = start_diff / TARGET_DIFFICULTY
        blocks_needed = math.log(reduction_needed) / math.log(1 / (1 - ADJUSTMENT_FACTOR))
        print(f"\nBlocks needed (theoretical): {blocks_needed:,.0f}")

        print(f"\n{'GPU Config':<20} {'Hashrate':<12} {'Time':<15} {'Blocks':<10} {'Cost':<10}")
        print("-" * 70)

        for gpu_name, hashrate in sorted(GPUS.items(), key=lambda x: x[1]):
            result = simulate_crash(start_diff, hashrate, gpu_name)
            cost = result["total_hours"] * COSTS.get(gpu_name, 0.20)

            print(f"{gpu_name:<20} {hashrate:>6} MH/s   "
                  f"{format_time(result['total_hours']):<15} "
                  f"{result['blocks']:<10,} "
                  f"${cost:,.0f}")

        # Detailed breakdown for RTX 3090
        print(f"\n--- Detailed progression (RTX 3090, 120 MH/s) ---")
        result = simulate_crash(start_diff, 120)
        print(f"\n{'Reduction':<12} {'Blocks':<10} {'Time':<15} {'Difficulty':<20}")
        print("-" * 60)
        for m in result["milestones"]:
            print(f"{m['factor']:>10}x   {m['blocks']:<10,} "
                  f"{format_time(m['time_hours']):<15} {m['difficulty']:>18,}")
        print(f"{'FINAL':<12} {result['blocks']:<10,} "
              f"{format_time(result['total_hours']):<15} {result['final_difficulty']:>18,}")

    print("\n" + "=" * 70)
    print("RECOMMENDATIONS")
    print("=" * 70)
    print("""
1. BUDGET OPTION: Single RTX 3090 ($0.16/hr)
   - Time: ~2 weeks per chain
   - Cost: ~$50-60 per chain
   - Good for: Set it and forget it

2. BALANCED OPTION: 4x RTX 3090 ($0.64/hr)
   - Time: ~3-4 days per chain
   - Cost: ~$50-60 per chain (similar total cost, faster)
   - Good for: Faster results, same budget

3. FAST OPTION: 8x RTX 3090 ($1.28/hr)
   - Time: ~1.5-2 days per chain
   - Cost: ~$50-60 per chain
   - Good for: Maximum speed

Note: Multi-GPU requires running multiple ethminer instances or
using a mining pool setup. Single GPU is simplest.
""")


if __name__ == "__main__":
    main()
