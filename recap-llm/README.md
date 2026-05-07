# RECAP Azure OpenAI Service Deployment

This folder contains scripts for deploying **only** the Azure OpenAI service (Cognitive Services account with five AI model deployments).

## Scripts

### `openai-deploy.ps1`
Deploys the Azure OpenAI service with public access disabled, ready for private endpoint integration.

**Usage:**
```powershell
# Basic usage with defaults
.\openai-deploy.ps1 -Environment test

# Override default resource group and location
.\openai-deploy.ps1 -Environment prod -ResourceGroup "d837ad-prod-networking" -Location "canadacentral"
```

**Parameters:**
- `Environment` (required): test, prod, or dev
- `ResourceGroup` (optional): defaults to `d837ad-{Environment}-networking`
- `Location` (optional): defaults to `canadaeast`

**Creates:**
- Azure OpenAI service: `d837ad-{Environment}-econ-llm-east`
- **Five model deployments:**
  - **GPT-4o** (Standard SKU, capacity 150): Primary model for complex tasks
  - **GPT-4o-mini** (GlobalStandard SKU, capacity 250): Cost-optimized model (94% savings)
  - **GPT-5-mini** (GlobalStandard SKU, capacity 250): Enhanced reasoning capabilities
  - **GPT-5-nano** (GlobalStandard SKU, capacity 250): Ultra-fast for simple tasks
  - **text-embedding-3-large** (Standard SKU, capacity 150): High-quality embeddings

## Architecture

This folder is part of the RECAP deployment architecture. See the main [README.md](../README.md#architecture-separation) for complete deployment sequence and architectural separation details.