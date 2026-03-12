# RECAP GitHub Actions Configuration

This document provides complete setup instructions for GitHub Actions CI/CD workflows in the RECAP project.

## Overview

RECAP uses GitHub Actions for automated build and deployment of the nginx web proxy container to Azure App Service. The workflows are configured for three environments:

- **`dev`**: Build-only for local development (no Azure deployment)
- **`test`**: Full CI/CD pipeline for test environment
- **`main`**: Full CI/CD pipeline for production environment

## Workflow Files

### `.github/workflows/docker-build-dev.yml`
- **Purpose**: Build-only for local development
- **Triggers**: Push to `dev` branch + manual dispatch
- **Actions**: Build container, test nginx config, validate image
- **No Azure deployment** (no dev Azure environment currently)

### `.github/workflows/docker-build-test.yml`
- **Purpose**: Full CI/CD for test environment
- **Triggers**: Push to `test` branch + manual dispatch
- **Actions**: Build → ACR Login → Push → Deploy → Health Check
- **Resources**: `d837ad-test-recap-webapp` + `d837adtestcontainers`

### `.github/workflows/docker-build-main.yml`
- **Purpose**: Full CI/CD for production environment
- **Triggers**: Push to `main` branch + manual dispatch
- **Actions**: Build → ACR Login → Push → Deploy → Health Check
- **Resources**: `d837ad-prod-recap-webapp` + `d837adprodcontainers`

## Authentication Method

The workflows use **OpenID Connect (OIDC)** authentication to Azure, which is more secure than storing service principal secrets.

### Benefits of OIDC:
- ✅ **No client secrets** stored in GitHub
- ✅ **More secure** - uses short-lived JWT tokens
- ✅ **Better compliance** with security practices
- ✅ **No secret rotation** required

### OIDC Configuration in Workflows:
```yaml
permissions:
  contents: read
  id-token: write

- name: Login to Azure using OIDC
  uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

## Required GitHub Secrets

Configure these secrets in **Settings → Secrets and variables → Actions**:

### Azure OIDC Authentication
- **`AZURE_CLIENT_ID`**: The Application (client) ID of your Entra ID app
- **`AZURE_TENANT_ID`**: `6fdb5200-3d0d-4a8a-b036-d3685e359adc`
- **`AZURE_SUBSCRIPTION_ID`**: `5445292b-8313-4272-96aa-f30efd1e1654`

### Optional Secrets
- **`OPENAI_API_KEY`**: Azure OpenAI API key for testing model connectivity (production workflow only)

## Azure OIDC Setup Instructions

### 1. Create Entra ID Application

```bash
# Create the application
az ad app create --display-name "recap-github-actions" --query "appId" --output tsv

# Note the Application (Client) ID returned
```

### 2. Create Service Principal

```bash
# Replace APP_ID with the Application ID from step 1
az ad sp create --id <APP_ID>

# Assign Contributor role to both subscriptions
az role assignment create --role contributor --assignee <APP_ID> --scope /subscriptions/5445292b-8313-4272-96aa-f30efd1e1654
```

### 3. Add Federated Credentials

For each environment, create federated credentials:

**Test Environment:**
```bash
az ad app federated-credential create \
  --id <APP_ID> \
  --parameters '{
    "name": "recap-test-environment",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR_GITHUB_ORG/RECAP:environment:test",
    "description": "RECAP Test Environment",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

**Production Environment:**
```bash
az ad app federated-credential create \
  --id <APP_ID> \
  --parameters '{
    "name": "recap-prod-environment", 
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR_GITHUB_ORG/RECAP:environment:prod",
    "description": "RECAP Production Environment",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

**Replace** `YOUR_GITHUB_ORG` with your actual GitHub organization/username.

## GitHub Environments

Create these environments in **Settings → Environments**:

### 1. `dev` Environment
- **Purpose**: Development builds
- **Protection**: None required
- **Secrets**: None required (no Azure deployment)

### 2. `test` Environment  
- **Purpose**: Test environment deployment
- **Protection**: Optional - require reviewers
- **Secrets**: Azure OIDC credentials

### 3. `prod` Environment
- **Purpose**: Production deployment
- **Protection**: **Recommended** - require reviewers and delay
- **Secrets**: Azure OIDC credentials + OpenAI API key

## Workflow Triggers

### Automatic Triggers
Workflows only trigger on changes to application code:

**Included Paths:**
- `recap-web-proxy/**` (application code)

**Excluded Paths:**
- `.github/**` (workflow changes)
- `.gitignore`
- `documentation/**` (documentation changes)
- `COMPLIANCE.yaml`
- `LICENSE`
- `README.md`
- `SECURITY.md`

### Manual Triggers
All workflows support manual triggering via **Actions → [Workflow Name] → Run workflow**.

## Workflow Steps

### Common Steps (All Workflows)
1. **Checkout repository**
2. **Setup Azure CLI**
3. **Get commit SHA** (for tagging)
4. **Build Docker image**

### Test/Production Additional Steps
5. **Login to Azure** (OIDC)
6. **Login to Azure Container Registry**
7. **Tag images** (latest, stable, SHA)
8. **Push images to ACR**
9. **Update Azure Web App** container image
10. **Restart Azure Web App**
11. **Verify deployment** (health check)
12. **Test OpenAI connectivity** (production only)

## Container Tagging Strategy

Each successful build creates three tags:

- **`latest`**: Current build
- **`stable`**: Production-ready version
- **`SHA`**: Specific commit identifier (e.g., `abc1234`)

Example tags for test environment:
- `d837adtestcontainers.azurecr.io/test-recap-web-proxy:latest`
- `d837adtestcontainers.azurecr.io/test-recap-web-proxy:stable`
- `d837adtestcontainers.azurecr.io/test-recap-web-proxy:abc1234`

## Health Check Verification

Workflows automatically verify deployment success by:

1. **Waiting 30 seconds** for deployment stabilization
2. **Calling health endpoint**: `https://{webapp-name}.azurewebsites.net/healthz`
3. **Expecting HTTP 200** response
4. **Failing workflow** if health check fails

## Troubleshooting

### Common Issues

**1. OIDC Authentication Failure**
- Verify Entra ID application exists
- Check federated credential configuration
- Ensure GitHub environment names match federated credential subjects

**2. Azure Container Registry Login Failure**
- Verify service principal has `AcrPush` role on ACR
- Check ACR names in workflow match actual resources

**3. Docker Build Failure**
- Check Dockerfile syntax in `recap-web-proxy/`
- Verify base image `nginx:1.26-alpine` is accessible
- Review build logs for specific error messages

**4. Health Check Failure**
- Verify nginx configuration is valid
- Check Azure Web App logs: `az webapp log tail --name {webapp-name} --resource-group {resource-group}`
- Ensure `/healthz` endpoint is configured correctly

### Manual Deployment Fallback

If workflows fail, use manual deployment commands from:
- [`documentation/recap-docker-build-tag-push-update-restart-test.md`](./recap-docker-build-tag-push-update-restart-test.md)
- [`documentation/recap-docker-build-tag-push-update-restart-prod.md`](./recap-docker-build-tag-push-update-restart-prod.md)

## Security Considerations

### Access Control
- **Production environment** should require approval
- **Service principal** has minimal required permissions (Contributor)
- **No secrets** stored in GitHub (OIDC authentication)

### Resource Isolation
- **Test and production** use separate:
  - Azure Container Registries
  - Resource Groups  
  - Web Apps
  - GitHub Environments

### Audit Trail
- **All deployments** logged in GitHub Actions
- **Azure activity logs** track resource changes
- **Container tags** provide deployment history

## Monitoring and Alerts

### GitHub Actions
- Monitor workflow runs in **Actions** tab
- Set up notifications for failed workflows
- Review deployment logs regularly

### Azure Monitoring
- **Application Insights** for web app performance
- **Azure Monitor** for resource health
- **Container Registry** webhook notifications

## Future Enhancements

### Planned Improvements
1. **Automated testing** of OpenAI connectivity
2. **Blue-green deployments** for zero downtime
3. **Slack/Teams notifications** for deployment status
4. **Rollback capabilities** for failed deployments
5. **Security scanning** of container images

### Configuration as Code
Consider moving to **Azure Resource Manager (ARM)** or **Terraform** for infrastructure management to ensure consistency between environments.

## Support and Documentation

### Related Documentation
- [Azure OIDC Guide](https://learn.microsoft.com/azure/developer/github/connect-from-azure)
- [GitHub Actions Documentation](https://docs.github.com/actions)
- [Azure Container Registry](https://docs.microsoft.com/azure/container-registry/)

### Contact Information
For GitHub Actions issues, refer to the RECAP project maintainers and Azure subscription administrators.