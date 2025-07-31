# RECAP
RECAP LLM Responsible Evaluation And Consolidated Analytics Platform

[![Lifecycle:Experimental](https://img.shields.io/badge/Lifecycle-Experimental-339999)](https://github.com/bcgov/repomountie/blob/master/doc/lifecycle-badges.m)

The project is in the very early stages of development. The codebase will be changing frequently.

## Architecture Separation

This repository is organized into separate deployment concerns:

### `recap-llm/` - Azure OpenAI Service Only
Handles **only** the Azure OpenAI service creation (Cognitive Services account and model deployment).

**Scripts:**
- `deploy-azure-openai.ps1` - Creates Azure OpenAI service with public access disabled
  - **When to use:** First step in any environment deployment
  - **Usage:** `.\deploy-azure-openai.ps1 -Environment test`
  - **Creates:** `d837ad-{Environment}-econ-llm-east` with GPT-4o deployment

### `recap-web-proxy/` - Networking and Proxy Infrastructure
Handles all networking, private endpoints, and nginx proxy deployment.

**Scripts:**
- Private endpoint deployment scripts
- `nginx.conf` with connection pooling configuration  
- `az-web-app-create.ps1` - Azure Web App deployment
- `az-container-create.ps1` - nginx proxy container deployment
- `basic-test.ps1` - End-to-end connectivity testing

**When to use:** After OpenAI service is created, deploy networking components

## Deployment Sequence

1. **Deploy Azure OpenAI Service:** Use `recap-llm/deploy-azure-openai.ps1`
2. **Deploy private endpoint:** Use scripts in `recap-web-proxy/`
3. **Deploy nginx proxy container:** With connection pooling for reliability
4. **Configure web app:** With OpenAI endpoint and API key
5. **Test connectivity:** Using `recap-web-proxy/basic-test.ps1`