# RECAP
RECAP LLM Responsible Evaluation And Consolidated Analytics Platform

[![Lifecycle:Stable](https://img.shields.io/badge/Lifecycle-Stable-97ca00)](https://github.com/bcgov/repomountie/blob/master/doc/lifecycle-badges.md)

The project is in a reliable state and major changes are unlikely to happen.

## Documentation

📚 **Complete documentation is available in the [`documentation/`](./documentation/) folder:**

- **[Azure Landing Zone Documentation](./documentation/RECAP-Azure-LandingZone.md)** - Comprehensive Azure infrastructure architecture, cost analysis, and deployment details
- **[Architecture Diagram](./documentation/RECAP-Architecture-Diagram.md)** - System architecture overview and component relationships  
- **[VNet Solution](./documentation/RECAP-VNet-Solution.md)** - Virtual network configuration and security implementation
- **[Connection Pooling Solution](./documentation/RECAP-Connection-Pooling-Solution.md)** - Optimized connection management for Azure OpenAI
- **[Multi-Client Solution](./documentation/RECAP-multi-client-solution.md)** - Multi-tenant architecture and client isolation
- **[GitOps Deployment Flow](./documentation/RECAP-GitOps-deployment-Flow.md)** - CI/CD pipeline and automated deployment processes

## Repository Structure

This repository is organized with clear separation of concerns:

```
RECAP/
├── recap-subnet-nsg/                    ← Networking infrastructure
│   ├── networking-config.ps1            ← Subnets, NSGs, security rules
│   └── private-endpoint-deploy.ps1      ← Private endpoints
├── recap-llm/                           ← OpenAI service only
│   └── openai-deploy.ps1                ← Azure OpenAI service deployment
└── recap-web-proxy/                     ← Web app and proxy
    ├── nginx-generate-config.ps1        ← Environment-specific nginx config
    ├── acr-container-push.ps1            ← Container build and ACR push
    ├── webapp-deploy.ps1                 ← Azure Web App deployment
    └── proxy-llm-basic-test.ps1          ← End-to-end connectivity testing
```

### `recap-subnet-nsg/` - Networking Foundation
**Creates the network infrastructure that everything else depends on:**
- Virtual network subnets with optimized IP allocation
- Network Security Groups with BC Gov compliant security rules
- Private endpoints for secure Azure service connectivity
- SPANBC network access (142.22.0.0/16)

### `recap-llm/` - Azure OpenAI Service
**Handles Azure OpenAI service deployment only:**
- Creates Cognitive Services account with BC Gov policy compliance
- Configures public access disabled and network ACLs
- Supports four model deployments: GPT-4o, GPT-4o-mini, GPT-5-mini, text-embedding-3-large
- Enhanced rate limits with capacity 150-250 based on model requirements

**Model Cost Comparison (2025 Pricing):**
- **GPT-4o**: $2.50 input / $10.00 output per million tokens (Standard SKU, capacity 150)
- **GPT-4o-mini**: $0.15 input / $0.60 output per million tokens (GlobalStandard SKU, capacity 250)
- **GPT-5-mini**: Next-generation model with enhanced capabilities (GlobalStandard SKU, capacity 250)
- **text-embedding-3-large**: High-quality embeddings (Standard SKU, capacity 150)
- **Cost savings**: gpt-4o-mini is ~94% cheaper than gpt-4o (16x cheaper per token)

**Rate Limit Configuration:**
Azure OpenAI rate limits are determined by the `--sku-capacity` parameter:
- **Tokens per minute** = sku-capacity × 1,000
- **Requests per minute** = sku-capacity × 10

**Current RECAP Rate Limits:**
- **GPT-4o** (capacity 150): 150,000 tokens/min, 1,500 requests/min
- **GPT-4o-mini** (capacity 250): 250,000 tokens/min, 2,500 requests/min  
- **GPT-5-mini** (capacity 250): 250,000 tokens/min, 2,500 requests/min
- **text-embedding-3-large** (capacity 150): 150,000 tokens/min, 1,500 requests/min

**Model Strategy:**
- GPT-4o and GPT-4o-mini remain primary models for production workloads
- GPT-5-mini provides next-generation capabilities alongside existing models
- text-embedding-3-large provides enhanced embedding capabilities with higher rate limits

**SKU Requirements:**
- GPT-4o uses Standard SKU (regional data residency)
- GPT-4o-mini and GPT-5-mini require GlobalStandard SKU in Canada East for better load balancing
- text-embedding-3-large uses Standard SKU for consistent performance

### `recap-web-proxy/` - Application Layer
**Manages the proxy application and web app deployment:**
- Nginx proxy with connection pooling, SSL termination, and BCgov security controls
  - IP whitelisting for BC government networks
  - Security headers (HSTS, CSP, X-Frame-Options, etc.)
  - Health monitoring endpoint (`/healthz`) for Azure App Service
- Docker container build and Azure Container Registry operations
- Azure Web App with VNet integration
- End-to-end testing and validation

## Quick Start Deployment

**Complete deployment sequence:**

```powershell
# Step 1: Create networking foundation
.\recap-subnet-nsg\networking-config.ps1 -Environment "prod"
.\recap-subnet-nsg\private-endpoint-deploy.ps1 -Environment "prod"

# Step 2: Deploy OpenAI service
.\recap-llm\openai-deploy.ps1 -Environment "prod"

# Step 3: Build and deploy web application
.\recap-web-proxy\nginx-generate-config.ps1 -Environment "prod"
.\recap-web-proxy\acr-container-push.ps1 -Environment "prod"
.\recap-web-proxy\webapp-deploy.ps1 -Environment "prod"

# Step 4: Test deployment
.\recap-web-proxy\proxy-llm-basic-test.ps1 -Environment "prod" -Model "all"
```

**Prerequisites:**
- Azure CLI installed and authenticated (`az login`)
- Docker Desktop running (for container operations)
- PowerShell execution policy allows script execution
- Contributor access to target Azure subscription

## Troubleshooting

### OpenAI Service Name Already Exists
If you encounter an error that the OpenAI service name is already in use due to a previous deletion, you need to purge the soft-deleted service first:

```powershell
# Check for soft-deleted OpenAI services
az cognitiveservices account list-deleted --query "[?contains(name, 'd837ad') && contains(name, 'econ-llm-east')]"

# Purge the soft-deleted service to free up the name
az cognitiveservices account purge --name "d837ad-{Environment}-econ-llm-east" --resource-group "d837ad-{Environment}-networking" --location "canadaeast"

# Example for prod environment:
az cognitiveservices account purge --name "d837ad-prod-econ-llm-east" --resource-group "d837ad-prod-networking" --location "canadaeast"
```

This immediately frees up the service name for reuse instead of waiting 30+ days for automatic purging.