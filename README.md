# Distributed Inferencing Prototype — DevOps Deployment

A production-style deployment of a distributed inference system running **Gemma-3-270M** across multiple AWS VMs using the **iii framework**. A Python worker hosts the model and exposes inference as an RPC function; a TypeScript worker fans incoming HTTP requests into that RPC and returns the result as JSON.

The two workers are written in different languages, run on different machines, and are composed at runtime — so you can scale the inference tier independently of the API tier, swap implementations without downtime, and extend the mesh with additional workers as the system grows.

---

## Worker Overview

| Worker | Language | Function | Role |
|---|---|---|---|
| inference-worker | Python | `inference::run_inference` | Loads Gemma-3-270M (GGUF, Q8) via transformers, applies the chat template to messages, and returns decoded model output |
| caller-worker | TypeScript | `inference::get_response` | Calls `inference::run_inference` with the incoming messages payload and returns the result |
| caller-worker | TypeScript | `http::run_inference_over_http` | HTTP trigger bound to `POST /v1/chat/completions`; forwards request body to `inference::get_response` and returns a JSON HTTP response |

---

## Architecture

```
                         Internet
                             │
                     ┌───────▼────────────┐
                     │   Public Subnet     │
                     │   10.0.1.0/24      │
                     │                    │
                     │  ┌─────────────┐   │
       Port 3111 ────►  │ api-gateway │   │
       (public)      │  │ 10.0.1.82   │   │
                     │  │ iii engine  │   │
                     │  └──────┬──────┘   │
                     └─────────┼──────────┘
                               │ WebSocket :49134
                               │ (VPC internal only)
                     ┌─────────▼──────────┐
                     │   Private Subnet    │
                     │   10.0.2.0/24      │
                     │                    │
                     │  ┌─────────────┐   │
                     │  │  inference  │   │
                     │  │   -worker   │   │
                     │  │ 10.0.2.71   │   │
                     │  │ Python/     │   │
                     │  │ Gemma-270M  │   │
                     │  └─────────────┘   │
                     │                    │
                     │  ┌─────────────┐   │
                     │  │   caller-   │   │
                     │  │   worker    │   │
                     │  │ 10.0.2.143  │   │
                     │  │ TypeScript  │   │
                     │  └─────────────┘   │
                     └────────────────────┘

RPC Flow:
  curl POST /v1/chat/completions
    → api-gateway:3111 (iii engine)
    → caller-worker: http::run_inference_over_http
    → caller-worker: inference::get_response
    → inference-worker: inference::run_inference (Gemma model)
    → decoded text response → JSON back to caller
```

---

## Infrastructure (Terraform)

All infrastructure is defined as code in `terraform/`. Provisions on a clean AWS account with one command.

### Resources Created
- VPC (`10.0.0.0/16`)
- Public subnet (`10.0.1.0/24`) — gateway
- Private subnet (`10.0.2.0/24`) — workers
- Internet Gateway + NAT Gateway
- Route tables for both subnets
- Security groups:
  - `api-gateway-sg` — port 3111 + 22 open to internet, port 49134 open from private subnet
  - `workers-sg` — port 49134 + 22 open from gateway only (**workers NOT reachable from internet**)
- 3 EC2 instances (t2.micro for gateway + caller, t2.medium for inference)

### EC2 Instances

| VM | Role | Private IP | Public IP | Type |
|---|---|---|---|---|
| api-gateway | iii engine + HTTP API | 10.0.1.82 | 15.206.168.132 | t2.micro |
| inference-worker | Python / Gemma-3-270M | 10.0.2.71 | None | t2.medium |
| caller-worker | TypeScript / HTTP | 10.0.2.143 | None | t2.micro |

---

## API Usage

### Curl Command

```bash
curl -X POST http://15.206.168.132:3111/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages": [{"role": "user", "content": "hello"}]}'
```

### Sample Request

```json
{
  "messages": [
    {"role": "user", "content": "Explain quantum entanglement in simple terms."}
  ]
}
```

### Sample Response 

```json
{
  "result": "Quantum entanglement is a phenomenon where two particles become correlated such that the state of one instantly influences the other, regardless of distance."
}
```
Note that it ws sample responses
---

## Redeploy from Scratch

### Prerequisites
- AWS account + IAM user with AdministratorAccess
- Terraform >= 1.0 installed locally
- SSH key pair: `devops-intern-key.pem`

### Step 1 — Provision Infrastructure

```bash
cd terraform/
terraform init
terraform apply
# Note output IPs for gateway and workers
```

### Step 2 — API Gateway VM

```bash
ssh -i devops-intern-key.pem ubuntu@<gateway-public-ip>

# Install iii engine
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
source ~/.bashrc

# Clone repo
git clone https://github.com/Alchemyst-ai/hiring.git
cd hiring/may-2026/devops/quickstart

# Start engine (config.yaml already has correct worker addresses)
nohup iii --config config.yaml > engine.log 2>&1 &
```

### Step 3 — Inference Worker VM

```bash
ssh -i devops-intern-key.pem -J ubuntu@<gateway-public-ip> ubuntu@<inference-worker-ip>

git clone https://github.com/Alchemyst-ai/hiring.git
cd hiring/may-2026/devops/quickstart/workers/inference-worker

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

export III_URL=ws://<gateway-private-ip>:49134
python inference_worker.py
```

### Step 4 — Caller Worker VM

```bash
ssh -i devops-intern-key.pem -J ubuntu@<gateway-public-ip> ubuntu@<caller-worker-ip>

git clone https://github.com/Alchemyst-ai/hiring.git
cd hiring/may-2026/devops/quickstart/workers/caller-worker

npm install
export III_URL=ws://<gateway-private-ip>:49134
npm run dev
```

### Step 5 — Verify

```bash
# Watch engine logs for worker registrations
tail -f ~/hiring/may-2026/devops/quickstart/engine.log

# End-to-end test
curl -X POST http://<gateway-public-ip>:3111/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages": [{"role": "user", "content": "hello"}]}'
```

---

## Key Issues Encountered & Fixed

| Issue | Fix |
|---|---|
| iii-init KVM error | Used `motia-iii create` instead |
| iii binary not found after install | Fixed PATH in `~/.bashrc` + symlink |
| config.yaml had Mac paths | `sed` replace to EC2 Linux paths |
| Disk full during model download | Extended EBS volume 8GB → 20GB |
| pip externally managed error | Used Python venv |
| websockets version conflict | `pip install websockets==13.0` |
| Workers couldn't reach engine | Port 49134 was missing from `api-gateway-sg` inbound rules — added it |
| Inference worker not registering | Fixed `return result` → `return {"result": result}` in handler |
| SSH to private VMs | Used `-J` jump host flag via gateway as bastion |

---

## Production Hardening

Before putting this system in production I would address:

**Security:**
- Add **HTTPS/TLS** via ACM + ALB in front of port 3111 — currently plain HTTP
- Add **API authentication** (API keys or JWT) to the `/v1/chat/completions` endpoint
- Store the HuggingFace token in **AWS Secrets Manager** instead of env vars
- Use **Elastic IP** for the gateway so the address survives restarts
- Restrict SSH to a dedicated bastion with MFA — not open to `0.0.0.0/0`
- Enable **VPC Flow Logs** + **CloudTrail** for audit and intrusion detection

**Reliability:**
- Run all workers as **systemd services** so they auto-restart on crash
- Add **health check endpoints** on each worker
- Set up **CloudWatch alarms** for CPU, memory, and error rate metrics
- Use **Auto Scaling Groups** for the caller-worker tier under load spikes

**Networking:**
- Put the gateway behind an **Application Load Balancer** for zero-downtime deploys
- Add **VPC endpoints** for S3/ECR to avoid public internet for model/image pulls

---

## Scaling to a 100x Larger Model

If the model were ~27B parameters instead of 270M:

- **GPU instances** — switch inference-worker to `p3.8xlarge` or `p4d.24xlarge` (multi-GPU)
- **Tensor parallelism** — shard the model across GPUs using `accelerate` or `vLLM`
- **Model storage** — store weights on **EFS** or **S3**, load at startup — don't download every time
- **Inference engine** — replace raw `transformers` with **vLLM** for continuous batching and much higher throughput
- **Quantization** — use GPTQ/AWQ 4-bit to cut memory footprint ~4x
- **Autoscaling** — scale inference workers based on queue depth, not CPU
- **Spot Instances** — use EC2 Spot for inference workers with on-demand fallback to cut cost ~70%
- **KV cache** — add response caching for repeated/similar prompts

---

## Repository Structure

```
.
├── terraform/
│   ├── main.tf                      # VPC, subnets, EC2, security groups
│   ├── variables.tf                 # Configurable variables (region, instance types)
│   └── outputs.tf                   # Outputs: public IP, private IPs
├── scripts/
│   ├── deploy-gateway.sh
│   ├── deploy-inference-worker.sh
│   └── deploy-caller-worker.sh
├── quickstart/
│   ├── config.yaml                  # iii engine configuration
│   └── workers/
│       ├── inference-worker/
│       │   ├── inference_worker.py
│       │   └── requirements.txt
│       └── caller-worker/
│           ├── src/worker.ts
│           └── package.json
└── README.md
```
