#!/bin/bash
# Run on Inference Worker VM
set -e

echo "=== Setting up Inference Worker ==="
export PATH="/home/ubuntu/.local/bin:$PATH"

cd ~
git clone https://github.com/Alchemyst-ai/hiring.git
cd hiring/may-2026/devops/quickstart/workers/inference-worker

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

echo "=== Starting inference worker ==="
nohup iii-worker . > worker.log 2>&1 &
echo "Inference worker started! PID: $!"
