#!/bin/bash
# Run on Caller Worker VM
set -e

echo "=== Setting up Caller Worker ==="
export PATH="/home/ubuntu/.local/bin:$PATH"

cd ~
git clone https://github.com/Alchemyst-ai/hiring.git
cd hiring/may-2026/devops/quickstart/workers/caller-worker

npm install

echo "=== Starting caller worker ==="
nohup iii-worker . > worker.log 2>&1 &
echo "Caller worker started! PID: $!"
