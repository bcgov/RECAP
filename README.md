# RECAP
RECAP LLM Responsible Evaluation And Consolidated Analytics Platform

[![Lifecycle:Dormant](https://img.shields.io/badge/Lifecycle-Dormant-ff7f2a)](https://github.com/bcgov/repomountie/blob/master/doc/lifecycle-badges.md)
[![BC Gov Azure](https://img.shields.io/badge/BC_Gov-Azure_Tenant-blue)](https://github.com/bcgov-c/tenant-azure-d837ad)

This project has been archived and is not under active development, work continues under a separate BC Government private repository. This repository's existing implementation provides a foundation for future development efforts focused on responsible AI evaluation and analytics.

## Documentation

**[Complete documentation index available in the `documentation/` folder](./documentation/README.md)**

Key documents:
- **[Architecture & Cost Analysis](./documentation/RECAP-Azure-LandingZone.md)** - Infrastructure details and CA$0.83/day cost breakdown
- **[Cost Control System](./documentation/Cost-Controls-Overview.md)** - Automated budget monitoring and cost protection
- **[Testing Strategy](./cost-control/testing%20strategy.md)** - Comprehensive testing procedures
- **[Setup Guide](./cost-control/setup-guide.md)** - Detailed installation instructions

## Repository Structure

This repository is organized with clear separation of concerns:

```
RECAP/
├── recap-subnet-nsg/                    ← Networking infrastructure
│   ├── networking-config.ps1            ← Subnets, NSGs, security rules
│   └── private-endpoint-deploy.ps1      ← Private endpoints
├── recap-llm/                           ← OpenAI service only
│   └── openai-deploy.ps1                ← Azure OpenAI service deployment
├── recap-web-proxy/                     ← Web app and proxy
│   ├── nginx-generate-config.ps1        ← Environment-specific nginx config
│   ├── acr-container-push.ps1            ← Container build and ACR push
│   ├── webapp-deploy.ps1                 ← Azure Web App deployment
│   └── proxy-llm-basic-test.ps1          ← End-to-end connectivity testing
└── cost-control/                        ← Automated cost management
    ├── azure-deploy-cost-control.ps1     ← Infrastructure deployment
    ├── azure-configure-budget-integration.ps1 ← Budget and webhook setup
    ├── azure-verify-cost-control.ps1     ← System validation and testing
    ├── webapp-control.ps1                ← Manual webapp operations
    └── monitor-costs.ps1                  ← Cost monitoring and reporting
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
- Supports five model deployments: GPT-4o, GPT-4o-mini, GPT-5-mini, GPT-5-nano, text-embedding-3-large
- Enhanced rate limits with capacity 150-250 based on model requirements

**Five AI Models Available:**
- **GPT-4o**: Primary model for complex tasks (Standard SKU, capacity 150)
- **GPT-4o-mini**: Cost-optimized model with 94% savings (GlobalStandard SKU, capacity 250)
- **GPT-5-mini**: Next-generation enhanced reasoning (GlobalStandard SKU, capacity 250)
- **GPT-5-nano**: Ultra-fast for simple operations (GlobalStandard SKU, capacity 250)
- **text-embedding-3-large**: High-quality embeddings (Standard SKU, capacity 150)

*See [Architecture Documentation](./documentation/RECAP-Azure-LandingZone.md) for detailed cost analysis and rate limits.*

### `recap-web-proxy/` - Application Layer
**Manages the proxy application and web app deployment:**
- Nginx proxy with connection pooling, SSL termination, and BCgov security controls
  - IP whitelisting for BC government networks
  - Security headers (HSTS, CSP, X-Frame-Options, etc.)
  - Health monitoring endpoint (`/healthz`) for Azure App Service
- Docker container build and Azure Container Registry operations
- Azure Web App with VNet integration
- End-to-end testing and validation

### `cost-control/` - Automated Cost Management
**Provides budget monitoring and automated cost controls:**
- Azure Automation Account with PowerShell runbooks for webapp lifecycle management
- Budget-triggered automation that stops webapp when spending exceeds thresholds
- Monthly scheduled restart on 1st day of billing cycle
- Comprehensive testing and validation framework
- Manual webapp control capabilities for operations

**Cost Control Features:**
- **Budget Integration**: Links owned budgets to action groups for automated triggers
- **Webhook Automation**: Budget alerts trigger webhook → runbook → webapp shutdown
- **Threshold Configuration**: 30% (warning), 40% (early action), 50% (investigate), 80% (shutdown)
- **Monthly Reset**: Automated webapp restart on 1st day of each billing cycle
- **Managed Identity**: Secure authentication with minimal required permissions (Website Contributor + Reader)

**Budget Strategy:**
- **Owned Budgets**: `budget-for-d837ad-{env}-cost-control-automation` (CA$250/month)
- **Platform Budgets**: `budget-for-d837ad-{env}-from-product-registry` (read-only, do not modify)
- **Cost Optimization**: ~$0.01/day for automation infrastructure

**Deployment:**
```powershell
# Deploy cost control infrastructure
.\cost-control\azure-deploy-cost-control.ps1 -Environment "prod"

# Configure budget integration and webhooks
.\cost-control\azure-configure-budget-integration.ps1 -Environment "prod"

# Validate system configuration
.\cost-control\azure-verify-cost-control.ps1 -Environment "prod" -DryRun
```

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

# Step 4: Deploy cost control automation
.\cost-control\azure-deploy-cost-control.ps1 -Environment "prod"
.\cost-control\azure-configure-budget-integration.ps1 -Environment "prod"

# Step 5: Test complete deployment
.\recap-web-proxy\proxy-llm-basic-test.ps1 -Environment "prod" -Model "all"
.\cost-control\azure-verify-cost-control.ps1 -Environment "prod" -DryRun
```

**Prerequisites:**
- Azure CLI installed and authenticated (`az login`)
- Azure PowerShell modules installed (`Connect-AzAccount` for cost control)
- Docker Desktop running (for container operations)
- PowerShell execution policy allows script execution
- Contributor access to target Azure subscription
