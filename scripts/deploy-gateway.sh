#!/bin/bash
# Run on API Gateway VM
set -e

echo "=== Setting up API Gateway ==="
export PATH="/home/ubuntu/.local/bin:$PATH"

cd ~
git clone https://github.com/Alchemyst-ai/hiring.git
cd hiring/may-2026/devops/quickstart

# Fix config - point workers to their private IPs
# Replace with actual private IPs from terraform output
INFERENCE_IP=${1:-"10.0.2.x"}
CALLER_IP=${2:-"10.0.2.y"}

cat > config.yaml << YAML
workers:
  - name: iii-observability
    config:
      enabled: true
      service_name: iii
      exporter: memory
      logs_console_output: true
      sampling_ratio: 1.0

  - name: iii-queue
    config:
      adapter:
        name: builtin

  - name: iii-state
    config:
      adapter:
        name: kv
        config:
          store_method: file_based
          file_path: ./data/state_store.db

  - name: iii-http
    config:
      port: 3111
      host: 0.0.0.0
      default_timeout: 30000

  - name: inference-worker
    worker_address: "ws://${INFERENCE_IP}:49134"

  - name: caller-worker
    worker_address: "ws://${CALLER_IP}:49134"
YAML

echo "=== Starting iii engine ==="
nohup iii --config config.yaml > engine.log 2>&1 &
echo "Gateway started! PID: $!"
