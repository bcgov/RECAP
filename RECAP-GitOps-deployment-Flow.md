# RECAP GitOps Deployment Flow

## Overview
This document outlines the repeatable GitOps workflow for deploying the **RECAP (Responsible Evaluation And Consolidated Analytics Platform)** to BC Gov Azure Landing Zones.

## Architecture Components
- **recap-llm**: Azure OpenAI service deployment (gpt-4o and gpt-4o-mini models)
- **recap-web-proxy**: Nginx proxy with VNet integration for secure access
- **Private Endpoint**: Secure connectivity within BC Gov network
- **SPANBC Network Integration**: Access from BC Gov network IPs (142.22.0.0/16)

## Prerequisites

### 1. Azure CLI Authentication
```powershell
az login
az account set --subscription "d837ad-prod"  # or d837ad-test
```

### 2. Required Permissions
- Contributor access to target subscription
- Network Contributor for VNet operations
- Permission to create Azure OpenAI services

### 3. Environment Variables
- Target environment: `test`, `prod`, or `dev`
- BC Gov subscription naming: `d837ad-{environment}-networking`

## PowerShell Scripts Overview

| Script | Purpose | Order | Environment-Aware |
|--------|---------|-------|-------------------|
| `openai-deploy.ps1` | Deploy Azure OpenAI service with models | 1st | ✅ Yes |
| `nginx-generate-config.ps1` | Generate environment-specific nginx config | 2nd | ✅ Yes |
| `acr-container-push.ps1` | **ACR operations only**: create, tag, push container | 3rd | ✅ Yes |
| `webapp-deploy.ps1` | **Web app deployment**: create app service, VNet integration | 4th | ✅ Yes |
| `proxy-llm-basic-test.ps1` | Test AI models through proxy | 5th | ✅ Yes |
| `proxy-auth-load-test.ps1` | Load testing (optional) | Optional | ⚠️ Manual config |

## Deployment Workflow

### Step 1: Deploy Azure OpenAI Service
**Script:** `recap-llm/openai-deploy.ps1`
**Purpose:** Foundation infrastructure with AI models

```powershell
# Navigate to project root
cd C:\opt\Repository\RECAP

# Deploy Azure OpenAI service
.\recap-llm\openai-deploy.ps1 -Environment "prod"
```

**What it creates:**
- ✅ Azure OpenAI service: `d837ad-prod-econ-llm-east`
- ✅ Model deployments: `gpt-4o` and `gpt-4o-mini`
- ✅ VNet with optimized subnets:
  - Private endpoint subnet: `/27` (27 usable IPs)  
  - Web app integration subnet: `/28` (11 usable IPs)
- ✅ Private endpoint: `d837ad-prod-econ-llm-east-pe`
- ✅ Network ACL: SPANBC IPs allowed (142.22.0.0/16)
- ✅ BC Gov policy compliance (public access disabled)

### Step 2: Generate Environment Configuration
**Script:** `recap-web-proxy/nginx-generate-config.ps1`
**Purpose:** Create environment-specific nginx configuration

```powershell
# Generate nginx configuration for target environment
.\recap-web-proxy\nginx-generate-config.ps1 -Environment "prod"
```

**What it does:**
- ✅ Reads `nginx.conf.template`
- ✅ Substitutes `{{PRIVATE_ENDPOINT_IP}}` with actual private endpoint IP
- ✅ Substitutes `{{OPENAI_SERVICE_HOST}}` with environment-specific hostname
- ✅ Creates `nginx.conf` ready for container build

**Example output:**
```
Private endpoint IP: 10.46.76.4
OpenAI service host: d837ad-prod-econ-llm-east.openai.azure.com
Generated nginx.conf for prod environment
```

### Step 3: Build and Push Container to ACR
**Script:** `recap-web-proxy/acr-container-push.ps1`
**Purpose:** ACR operations only - build, tag, and push container image

```powershell
# Build and push container to Azure Container Registry
.\acr-container-push.ps1 -Environment "prod"

# Or with custom parameters
.\acr-container-push.ps1 -Environment "prod" -Repository "recap-web-proxy" -Tag "v1.0.0"
```

**What it creates:**
- ✅ Azure Container Registry: `d837adprodcontainers.azurecr.io`
- ✅ Docker image tagged and pushed: `recap-web-proxy:latest`
- ✅ Image ready for GitOps deployment or JFrog Artifactory sync

### Step 4: Deploy Web App
**Script:** `recap-web-proxy/webapp-deploy.ps1`
**Purpose:** Web app deployment with container integration

```powershell
# Deploy web app with default ACR image
.\webapp-deploy.ps1 -Environment "prod"

# Or specify custom image registry (for JFrog integration)
.\webapp-deploy.ps1 -Environment "prod" -ImageRegistry "your-jfrog-registry.com" -Repository "recap-web-proxy" -Tag "v1.0.0"
```

**What it creates:**
- ✅ App Service Plan: `d837ad-prod-recap-asp`
- ✅ Web App: `d837ad-prod-recap-webapp`
- ✅ Container configuration pointing to specified registry
- ✅ VNet integration for secure OpenAI access
- ✅ ACR authentication (when using Azure Container Registry)

### Step 5: Verify Deployment
**Script:** `recap-web-proxy/proxy-llm-basic-test.ps1`
**Purpose:** End-to-end testing of both AI models

```powershell
# Get API key for testing
$apiKey = az cognitiveservices account keys list --name "d837ad-prod-econ-llm-east" --resource-group "d837ad-prod-networking" --query "key1" --output tsv

# Test gpt-4o-mini model (reasoning model)
.\proxy-llm-basic-test.ps1 -ApiKey $apiKey -Environment "prod" -Model "gpt-4o-mini" -Question "Hello"

# Test gpt-4o model (standard model)  
.\proxy-llm-basic-test.ps1 -ApiKey $apiKey -Environment "prod" -Model "gpt-4o" -Question "Hello"

# Test with custom questions
.\proxy-llm-basic-test.ps1 -ApiKey $apiKey -Environment "prod" -Model "gpt-4o-mini" -Question "Write a joke"
.\proxy-llm-basic-test.ps1 -ApiKey $apiKey -Environment "prod" -Model "gpt-4o" -Question "Explain Azure OpenAI"
```

## Environment-Specific Deployment

### Production Environment
```powershell
# Complete production deployment
.\recap-llm\openai-deploy.ps1 -Environment "prod"
.\recap-web-proxy\nginx-generate-config.ps1 -Environment "prod"
.\recap-web-proxy\acr-container-push.ps1 -Environment "prod"
.\recap-web-proxy\webapp-deploy.ps1 -Environment "prod"

# Test deployment
$apiKey = az cognitiveservices account keys list --name "d837ad-prod-econ-llm-east" --resource-group "d837ad-prod-networking" --query "key1" --output tsv
.\recap-web-proxy\proxy-llm-basic-test.ps1 -ApiKey $apiKey -Environment "prod" -Model "gpt-4o-mini"
```

### Test Environment
```powershell
# Complete test deployment
.\recap-llm\openai-deploy.ps1 -Environment "test"
.\recap-web-proxy\nginx-generate-config.ps1 -Environment "test"
.\recap-web-proxy\acr-container-push.ps1 -Environment "test"
.\recap-web-proxy\webapp-deploy.ps1 -Environment "test"

# Test deployment
$apiKey = az cognitiveservices account keys list --name "d837ad-test-econ-llm-east" --resource-group "d837ad-test-networking" --query "key1" --output tsv
.\recap-web-proxy\proxy-llm-basic-test.ps1 -ApiKey $apiKey -Environment "test" -Model "gpt-4o-mini"
```

## Resource Naming Convention
All resources follow BC Gov naming: `d837ad-{environment}-{service}-{location}`

| Resource Type | Naming Pattern | Example (prod) |
|---------------|----------------|----------------|
| Azure OpenAI | `d837ad-{env}-econ-llm-east` | `d837ad-prod-econ-llm-east` |
| Resource Group | `d837ad-{env}-networking` | `d837ad-prod-networking` |
| Private Endpoint | `d837ad-{env}-econ-llm-east-pe` | `d837ad-prod-econ-llm-east-pe` |
| Web App | `d837ad-{env}-recap-webapp` | `d837ad-prod-recap-webapp` |
| Container Registry | `d837ad{env}containers` | `d837adprodcontainers` |

## Model-Specific Configuration

### gpt-4o-mini (Reasoning Model)
- **API Version:** `2024-12-01-preview`
- **Token Parameter:** `max_completion_tokens`
- **Recommended Tokens:** 1000+ for creative prompts, 200 for simple prompts
- **Behavior:** Uses tokens for internal reasoning before generating output

### gpt-4o (Standard Model)  
- **API Version:** `2024-02-15-preview`
- **Token Parameter:** `max_tokens`
- **Recommended Tokens:** 50-100 for most prompts
- **Behavior:** Direct response generation

## Network Security

### SPANBC Network Access
- **Allowed IP Range:** `142.22.0.0/16`
- **Access Method:** Network ACL rules (BC Gov policy compliant)
- **Public Access:** Disabled (BC Gov policy requirement)
- **Private Endpoint:** Enabled for VNet access

### Proxy URLs
- **Production:** `https://d837ad-prod-recap-webapp.azurewebsites.net`
- **Test:** `https://d837ad-test-recap-webapp.azurewebsites.net`

### API Endpoint Format
```
https://{webapp-url}/openai/deployments/{model-name}/chat/completions?api-version={version}
```

## Troubleshooting

### Common Issues

#### 1. Empty Response from gpt-4o-mini
**Problem:** `Response: [EMPTY OR NULL RESPONSE]`
**Solution:** Increase `max_completion_tokens` to 1000+ for complex prompts

#### 2. 403 Forbidden Errors
**Problem:** `Traffic is not from an approved private endpoint`
**Solution:** Verify SPANBC IP (142.22.0.0/16) is in network ACL

#### 3. BC Gov Policy Violations
**Problem:** `RequestDisallowedByPolicy`
**Solution:** Ensure `publicNetworkAccess: Disabled` and use ARM templates

#### 4. Model API Version Errors
**Problem:** `Model gpt-4o-mini is enabled only for api versions 2024-12-01-preview and later`
**Solution:** Use correct API versions per model type

## Maintenance Commands

### Update Configuration Only
```powershell
# Regenerate configuration and redeploy
.\recap-web-proxy\nginx-generate-config.ps1 -Environment "prod"
.\recap-web-proxy\acr-container-push.ps1 -Environment "prod"
.\recap-web-proxy\webapp-deploy.ps1 -Environment "prod"
```

### Check Resource Status
```powershell
# List all resources in environment
az resource list --resource-group "d837ad-prod-networking" --output table

# Check private endpoint IP
az network private-endpoint show --name "d837ad-prod-econ-llm-east-pe" --resource-group "d837ad-prod-networking" --query "customDnsConfigs[0].ipAddresses[0]" --output tsv

# Verify model deployments
az cognitiveservices account deployment list --name "d837ad-prod-econ-llm-east" --resource-group "d837ad-prod-networking" --output table
```

## Multi-Client Scaling

For scaling to support multiple clients, see `RECAP-multi-client-solution.md` for:
- Path-based routing (`/client1/openai/`, `/client2/openai/`)
- Separate OpenAI services per client
- Advanced load balancing configurations

## Security Best Practices

1. **API Key Management:** Store API keys in Azure Key Vault
2. **Network Isolation:** Use private endpoints exclusively
3. **Access Control:** Limit SPANBC IP ranges as needed  
4. **Monitoring:** Enable Application Insights for web app
5. **Updates:** Regular container updates for security patches

## Success Criteria

✅ **Deployment Complete When:**
- Azure OpenAI service responds to API calls
- Both gpt-4o and gpt-4o-mini models return successful responses
- Network access restricted to SPANBC IPs only
- All resources follow BC Gov naming conventions
- End-to-end testing passes for both models

## Support Information

- **Repository:** https://github.com/bcgov/RECAP
- **Issues:** Report deployment issues via GitHub Issues
- **Documentation:** All deployment scripts include inline help
- **Testing:** Use `proxy-llm-basic-test.ps1` for validation after any changes

---

**Last Updated:** 2025-08-01  
**Version:** 2.0  
**Environment Tested:** d837ad-prod (complete), d837ad-test (ready)  
**GitOps Ready:** ✅ Separated ACR and Web App deployment for CI/CD integration  
**File Naming:** ✅ Consistent service-specific naming convention