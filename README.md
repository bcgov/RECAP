# RECAP
RECAP LLM Responsible Evaluation And Consolidated Analytics Platform

[![Lifecycle:Experimental](https://img.shields.io/badge/Lifecycle-Experimental-339999)](https://github.com/bcgov/repomountie/blob/master/doc/lifecycle-badges.m)

The project is in the very early stages of development. The codebase will be changing frequently.

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
- Supports model deployments (GPT-4o, gpt-4o-mini)

**Model Cost Comparison (2025 Pricing):**
- **GPT-4o**: $2.50 input / $10.00 output per million tokens (Standard SKU)
- **GPT-4o-mini**: $0.15 input / $0.60 output per million tokens (GlobalStandard SKU)
- **Cost savings**: gpt-4o-mini is ~94% cheaper than gpt-4o (16x cheaper per token)

**SKU Requirements:**
- GPT-4o uses Standard SKU (regional data residency)
- GPT-4o-mini requires GlobalStandard SKU in Canada East for better load balancing and availability

### `recap-web-proxy/` - Application Layer
**Manages the proxy application and web app deployment:**
- Nginx proxy with connection pooling and SSL termination
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
.\recap-web-proxy\proxy-llm-basic-test.ps1 -Environment "prod" -Model "both"
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