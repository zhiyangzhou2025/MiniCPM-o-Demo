#!/usr/bin/env bash
#
# Remote worker 容器入口。
#
# 校验必要环境变量，确保 config.json 存在，启动 worker.py（纯转发模式）。
#
# 环境变量：
#   BACKEND_SERVER_URL  外部推理服务地址（必填）
#   WORKER_PORT         worker 监听端口（默认 22400）
#   GPU_ID              逻辑 GPU ID（默认 0）
#   WAIT_BACKEND        是否等待 backend 可达后再启动（默认 1）
#   WAIT_TIMEOUT_S      等待超时秒数（默认 60）

set -euo pipefail

BACKEND_SERVER_URL="${BACKEND_SERVER_URL:-}"
WORKER_PORT="${WORKER_PORT:-22400}"
GPU_ID="${GPU_ID:-0}"
WAIT_BACKEND="${WAIT_BACKEND:-1}"
WAIT_TIMEOUT_S="${WAIT_TIMEOUT_S:-60}"

cd /app

# ---- 校验 ----
if [ -z "$BACKEND_SERVER_URL" ]; then
    echo "[entrypoint] BACKEND_SERVER_URL is required" >&2
    exit 1
fi

# ---- config.json ----
if [ ! -f /app/config.json ]; then
    if [ -f /app/config.example.json ]; then
        cp /app/config.example.json /app/config.json
        echo "[entrypoint] config.json generated from config.example.json"
    fi
fi

echo "=================================================="
echo "  remote worker"
echo "  backend  = $BACKEND_SERVER_URL"
echo "  worker   = 0.0.0.0:$WORKER_PORT (gpu-id=$GPU_ID)"
echo "=================================================="

# ---- 等待 backend 可达 ----
if [ "$WAIT_BACKEND" = "1" ]; then
    echo "[entrypoint] waiting for backend..."
    max_retries=$((WAIT_TIMEOUT_S / 2))
    for i in $(seq 1 "$max_retries"); do
        if curl -sf "${BACKEND_SERVER_URL}/health" >/dev/null 2>&1; then
            echo "[entrypoint] backend reachable after ~$((i * 2))s"
            break
        fi
        if [ "$i" -eq "$max_retries" ]; then
            echo "[entrypoint] warning: backend not reachable within ${WAIT_TIMEOUT_S}s, starting anyway"
        fi
        sleep 2
    done
fi

# ---- 启动 worker ----
exec python worker.py \
    --host 0.0.0.0 \
    --port "$WORKER_PORT" \
    --gpu-id "$GPU_ID" \
    --backend-server-url "$BACKEND_SERVER_URL"
