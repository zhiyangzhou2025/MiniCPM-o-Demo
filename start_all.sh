#!/usr/bin/env bash
#
# 一键启动 Omni Demo（gateway + workers）。
#
# 用法：
#   # 单 endpoint
#   BACKEND_SERVER_URL=http://127.0.0.1:18900 ./start_all.sh
#   BACKEND_SERVER_URL=http://127.0.0.1:18900 NUM_WORKERS=3 ./start_all.sh
#
#   # 多 endpoints（逗号分隔，格式 url:并发数）
#   ENDPOINTS="http://bridge-a:18900:3,http://bridge-b:18900:2" ./start_all.sh
#
# 环境变量：
#   BACKEND_SERVER_URL  单 endpoint 地址（与 ENDPOINTS 二选一）
#   NUM_WORKERS         单 endpoint 并发数（默认 1）
#   ENDPOINTS           多 endpoint 声明，格式: url1:n1,url2:n2,...
#   GATEWAY_PORT        gateway 端口（默认 8006）
#   WORKER_BASE_PORT    worker 起始端口（默认 22400）
#   PROTO               --http 或 --https（默认 --http）
#
# 停止：
#   kill $(cat tmp/*.pid 2>/dev/null) 2>/dev/null

set -euo pipefail

BACKEND_SERVER_URL="${BACKEND_SERVER_URL:-}"
NUM_WORKERS="${NUM_WORKERS:-1}"
ENDPOINTS="${ENDPOINTS:-}"
GATEWAY_PORT="${GATEWAY_PORT:-8006}"
WORKER_BASE_PORT="${WORKER_BASE_PORT:-22400}"
PROTO="${PROTO:---http}"

if [ -z "$ENDPOINTS" ] && [ -z "$BACKEND_SERVER_URL" ]; then
    echo "错误：请设置 BACKEND_SERVER_URL 或 ENDPOINTS" >&2
    echo "" >&2
    echo "单 endpoint：" >&2
    echo "  BACKEND_SERVER_URL=http://host:port ./start_all.sh" >&2
    echo "" >&2
    echo "多 endpoints：" >&2
    echo "  ENDPOINTS=\"http://a:18900:3,http://b:18900:2\" ./start_all.sh" >&2
    exit 1
fi

cd "$(dirname "$0")"
mkdir -p tmp

# ---- 解析 endpoints ----
# 格式：每项 "url:concurrency"，存入两个数组
declare -a ep_urls=()
declare -a ep_counts=()

if [ -n "$ENDPOINTS" ]; then
    IFS=',' read -ra entries <<< "$ENDPOINTS"
    for entry in "${entries[@]}"; do
        # 从末尾取最后一个 : 后面的数字作为并发数
        count="${entry##*:}"
        url="${entry%:$count}"
        if ! [[ "$count" =~ ^[0-9]+$ ]]; then
            echo "错误：无法解析 '$entry'，格式应为 url:并发数" >&2
            exit 1
        fi
        ep_urls+=("$url")
        ep_counts+=("$count")
    done
else
    ep_urls+=("$BACKEND_SERVER_URL")
    ep_counts+=("$NUM_WORKERS")
fi

# ---- 启动 workers ----
worker_addrs=""
worker_idx=0

for ep_i in "${!ep_urls[@]}"; do
    url="${ep_urls[$ep_i]}"
    count="${ep_counts[$ep_i]}"
    for j in $(seq 1 "$count"); do
        port=$((WORKER_BASE_PORT + worker_idx))
        echo "[start_all.sh] worker $worker_idx  port=$port -> $url  log=tmp/worker_${worker_idx}.log"
        nohup python worker.py \
            --host 0.0.0.0 \
            --port "$port" \
            --worker-index "$worker_idx" \
            --backend-server-url "$url" \
            > "tmp/worker_${worker_idx}.log" 2>&1 &
        echo $! > "tmp/worker_${worker_idx}.pid"

        if [ -z "$worker_addrs" ]; then
            worker_addrs="localhost:$port"
        else
            worker_addrs="$worker_addrs,localhost:$port"
        fi
        worker_idx=$((worker_idx + 1))
    done
done

total_workers=$worker_idx
sleep 2

# ---- 启动 gateway ----
echo "[start_all.sh] gateway port=$GATEWAY_PORT  workers=$worker_addrs  log=tmp/gateway.log"
nohup python gateway.py \
    --port "$GATEWAY_PORT" \
    --workers "$worker_addrs" \
    "$PROTO" \
    > "tmp/gateway.log" 2>&1 &
echo $! > "tmp/gateway.pid"

echo ""
echo "=================================================="
echo "  Omni Demo running"
echo "  Gateway:  http://localhost:$GATEWAY_PORT"
echo "  Workers:  $total_workers total"
for ep_i in "${!ep_urls[@]}"; do
    echo "    ${ep_urls[$ep_i]}  x${ep_counts[$ep_i]}"
done
echo "  Logs:"
echo "    Gateway:  tmp/gateway.log"
echo "    Workers:  tmp/worker_*.log"
echo "  Stop:"
echo "    kill \$(cat tmp/*.pid 2>/dev/null) 2>/dev/null"
echo "=================================================="
