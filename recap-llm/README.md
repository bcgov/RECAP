# RECAP Azure OpenAI Service Deployment

This folder contains scripts for deploying **only** the Azure OpenAI service (Cognitive Services account and GPT-4o model deployment).

## Scripts

### `deploy-azure-openai.ps1`
Deploys the Azure OpenAI service with public access disabled, ready for private endpoint integration.

**Usage:**
```powershell
# Basic usage with defaults
.\deploy-azure-openai.ps1 -Environment test

# Override default resource group and location
.\deploy-azure-openai.ps1 -Environment prod -ResourceGroup "d837ad-prod-networking" -Location "canadacentral"
```

**Parameters:**
- `Environment` (required): test, prod, or dev
- `ResourceGroup` (optional): defaults to `d837ad-{Environment}-networking`
- `Location` (optional): defaults to `canadaeast`

**Creates:**
- Azure OpenAI service: `d837ad-{Environment}-econ-llm-east`
- GPT-4o deployment with Standard SKU and capacity 10

## Architecture

This folder is part of the RECAP deployment architecture. See the main [README.md](../README.md#architecture-separation) for complete deployment sequence and architectural separation details.