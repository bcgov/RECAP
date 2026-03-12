# RECAP Docker Build, Tag, Push, Update, Restart Process

## Overview

This document provides the exact commands and process for updating the RECAP test webapp container image.

## Current Status Analysis

### Webapp Status
```bash
az webapp show --name "d837ad-test-recap-webapp" --resource-group "d837ad-test-networking" --query "{state: state, availabilityState: availabilityState, containerSettings: siteConfig.linuxFxVersion}" --output table
```

**Result**: 
- State: Running
- AvailabilityState: Normal
- Container: `DOCKER|d837adtestcontainers.azurecr.io/test-recap-web-proxy:v2026-03-12`

### Health Check
```bash
curl.exe -I https://d837ad-test-recap-webapp.azurewebsites.net/healthz --max-time 10
```

**Result**: HTTP/1.1 200 OK - healthy nginx proxy responding

### ACR Repository Tags
```bash
az acr repository show-tags --name d837adtestcontainers --repository test-recap-web-proxy
# Get digest/hash for a specific tag
az acr repository show --name d837adtestcontainers --image test-recap-web-proxy:latest
az acr repository show --name d837adtestcontainers --image test-recap-web-proxy:stable
```

**Recommended Tags**: `["latest", "stable"]`
- **`stable`**: Production deployment tag (normal operations)
- **`latest`**: Release deployment tag (for releases and updates)

## Complete Docker Build, Tag, Push, Update, Restart Sequence

### 1. Navigate to Project Directory
```bash
cd "C:\opt\Repository\RECAP\recap-web-proxy"
```

### 2. Build Docker Image
```bash
docker build --no-cache --pull -t test-recap-web-proxy:latest .
```

**Output**: Successfully built with nginx:1.26-alpine base image, copying nginx.conf and index.html

### 3. Tag Image for ACR
```bash
# For releases (like today) - use latest tag
docker tag test-recap-web-proxy:latest d837adtestcontainers.azurecr.io/test-recap-web-proxy:latest

# For normal operations - use stable tag  
docker tag test-recap-web-proxy:latest d837adtestcontainers.azurecr.io/test-recap-web-proxy:stable
```

### 4. Login to Azure Container Registry
```bash
az acr login --name d837adtestcontainers
```

**Output**: Login Succeeded

### 5. Push Image to Azure Container Registry
```bash
# For releases (like today) - push latest tag
docker push d837adtestcontainers.azurecr.io/test-recap-web-proxy:latest

# For normal operations - push stable tag
docker push d837adtestcontainers.azurecr.io/test-recap-web-proxy:stable
```

### 6. Update Webapp Container Image
```bash
# For releases (like today) - use latest tag
az webapp config container set --name "d837ad-test-recap-webapp" --resource-group "d837ad-test-networking" --container-image-name "d837adtestcontainers.azurecr.io/test-recap-web-proxy:latest"

# For normal operations - use stable tag  
az webapp config container set --name "d837ad-test-recap-webapp" --resource-group "d837ad-test-networking" --container-image-name "d837adtestcontainers.azurecr.io/test-recap-web-proxy:stable"
```

**Note**: Use `--container-image-name` instead of deprecated `--docker-custom-image-name`

### 7. Restart Webapp
```bash
az webapp restart --name "d837ad-test-recap-webapp" --resource-group "d837ad-test-networking"
```

### 8. Verify Deployment
```bash
# Check health endpoint
curl.exe -I https://d837ad-test-recap-webapp.azurewebsites.net/healthz --max-time 10

# Verify container image update
az webapp show --name "d837ad-test-recap-webapp" --resource-group "d837ad-test-networking" --query "{state: state, availabilityState: availabilityState, containerSettings: siteConfig.linuxFxVersion}" --output table
```

## Key Configuration Details

### nginx.conf Configuration
- **Private Endpoint IP**: `10.46.76.4:443`
- **OpenAI Service Host**: `d837ad-test-econ-llm-east.openai.azure.com`
- **Health Check Endpoint**: `/healthz`
- **API Proxy Endpoint**: `/openai/`

### Azure Resources
- **Resource Group**: `d837ad-test-networking`
- **Container Registry**: `d837adtestcontainers.azurecr.io`
- **Web App**: `d837ad-test-recap-webapp`
- **ACR Repository**: `test-recap-web-proxy`

### Docker Configuration
- **Base Image**: `nginx:1.26-alpine`
- **Exposed Port**: `80`
- **Config Files**: 
  - `/etc/nginx/nginx.conf`
  - `/usr/share/nginx/html/index.html`

## Webapp Analysis Results

### Application Status
- **URL**: https://d837ad-test-recap-webapp.azurewebsites.net/
- **State**: Running and healthy
- **Content**: BC Government-compliant RECAP LLM landing page
- **Lifecycle**: Stable
- **Health Endpoint**: Responding with 200 OK
- **Server**: nginx proxy with BC Gov security headers

### Container Image Update
- **Normal Operations**: `d837adtestcontainers.azurecr.io/test-recap-web-proxy:stable`
- **Release Deployments**: `d837adtestcontainers.azurecr.io/test-recap-web-proxy:latest`
- **Current Status**: Successfully updated and running

### Tag Strategy
- **`stable`**: Used for normal production operations, represents the last known good release
- **`latest`**: Used during releases and updates, becomes `stable` after successful deployment

## Security and Compliance

### BC Government Standards
- Private endpoint connectivity for Azure OpenAI services
- SPANBC network access (142.22.0.0/16)
- Security headers: HSTS, CSP, X-Frame-Options, Content-Type-Options
- Rate limiting and cookie security controls

### SSL/TLS Configuration
- TLS termination at nginx level
- Private endpoint SSL verification disabled for internal routing
- Protocols: TLSv1.2, TLSv1.3

## Troubleshooting Commands

### Container Debugging
```bash
# Check local images
docker images --format "table {{.Repository}}:{{.Tag}}" | grep -E "(test-recap-web-proxy|recap-web-proxy)"

# Run container locally for testing
docker run --rm -d --name test-container -p 8080:80 test-recap-web-proxy:latest

# Check container logs
docker logs test-container

# Exec into container
docker run --rm --entrypoint=sh test-recap-web-proxy:latest -c "cat /etc/nginx/nginx.conf"
```

### Azure Debugging
```bash
# Check webapp logs
az webapp log tail --name "d837ad-test-recap-webapp" --resource-group "d837ad-test-networking"

# Check ACR repository
az acr repository show --name d837adtestcontainers --repository test-recap-web-proxy

# List all tags in repository
az acr repository show-tags --name d837adtestcontainers --repository test-recap-web-proxy
```

### ACR Image Management
```bash
# Clean up old versioned tags (keep only latest and stable)
az acr repository delete --name d837adtestcontainers --image test-recap-web-proxy:v2026-03-12 --yes
az acr repository delete --name d837adtestcontainers --image test-recap-web-proxy:v2026-03-12-fixed --yes
az acr repository delete --name d837adtestcontainers --image test-recap-web-proxy:v2026-03-12-minimal --yes

# Promote stable to latest (during releases)
docker pull d837adtestcontainers.azurecr.io/test-recap-web-proxy:stable
docker tag d837adtestcontainers.azurecr.io/test-recap-web-proxy:stable d837adtestcontainers.azurecr.io/test-recap-web-proxy:latest
docker push d837adtestcontainers.azurecr.io/test-recap-web-proxy:latest

# Promote latest to stable (after successful release)
docker pull d837adtestcontainers.azurecr.io/test-recap-web-proxy:latest
docker tag d837adtestcontainers.azurecr.io/test-recap-web-proxy:latest d837adtestcontainers.azurecr.io/test-recap-web-proxy:stable
docker push d837adtestcontainers.azurecr.io/test-recap-web-proxy:stable

# Remove entire repository (use with extreme caution)
az acr repository delete --name d837adtestcontainers --repository test-recap-web-proxy --yes
```

## Deployment Verification Checklist

- [x] Docker image built successfully
- [x] Image tagged for ACR
- [x] Image pushed to Azure Container Registry
- [x] Webapp container image updated
- [x] Webapp restarted
- [x] Health endpoint responding (200 OK)
- [x] Main page loading with BC Gov styling
- [x] nginx proxy configuration verified
- [x] Private endpoint connectivity maintained