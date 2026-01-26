# Running Instances List

Quick check of all running Vast.ai mining instances.

## Instructions

1. List all instances:
   ```bash
   resurrection/.venv/bin/vastai show instances
   ```

2. For each running instance, get the current block:
   ```bash
   for port in 34180 34372 20870; do
     ssh_host="ssh1.vast.ai"
     [ "$port" = "34372" ] && ssh_host="ssh2.vast.ai"
     [ "$port" = "20870" ] && ssh_host="ssh6.vast.ai"
     result=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p $port root@$ssh_host \
       'curl -s http://127.0.0.1:8545 -X POST -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}"' 2>&1 | grep '^{')
     block_hex=$(echo "$result" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
     block_num=$(printf "%d" $block_hex 2>/dev/null)
     echo "Port $port ($ssh_host): Block $block_num"
   done
   ```

3. Check GPU utilization on mining instances:
   ```bash
   ssh -o ConnectTimeout=10 -p PORT root@HOST "nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv"
   ```

## Output Format

Present results as a table:

| ID | GPU | Host | Port | Block | GPU Util |
|----|-----|------|------|-------|----------|

## Notes

- Instance IDs and ports may change - check `resurrection/STATUS.md` for current values
- Use vastai CLI output to get current instance details before SSH
