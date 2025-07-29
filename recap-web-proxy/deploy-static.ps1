# BC Gov Azure Static Web Apps Deployment
# Simpler alternative that doesn't require container registry

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$StaticWebAppName,
    
    [string]$Location = "canadacentral"
)

Write-Host "Deploying RECAP as Azure Static Web App..." -ForegroundColor Green

# Set subscription context
az account set --subscription $SubscriptionId

# Create Static Web App
Write-Host "Creating Static Web App: $StaticWebAppName" -ForegroundColor Yellow
az staticwebapp create `
    --name $StaticWebAppName `
    --resource-group $ResourceGroupName `
    --location $Location `
    --source "." `
    --branch main `
    --app-location "/" `
    --api-location "" `
    --output-location "/"

# Configure API proxy for Azure OpenAI
Write-Host "Configuring API proxy..." -ForegroundColor Yellow
$configContent = @"
{
  "routes": [
    {
      "route": "/api/*",
      "allowedRoles": ["anonymous"],
      "methods": ["GET", "POST", "PUT", "DELETE"],
      "headers": {
        "Cache-Control": "no-cache"
      }
    }
  ],
  "navigationFallback": {
    "rewrite": "/index.html"
  },
  "mimeTypes": {
    ".json": "application/json"
  },
  "globalHeaders": {
    "content-security-policy": "default-src https: 'unsafe-eval' 'unsafe-inline'; object-src 'none'"
  }
}
"@

$configContent | Out-File -FilePath "staticwebapp.config.json" -Encoding UTF8

Write-Host "Deployment completed!" -ForegroundColor Green
Write-Host "Configure your GitHub repository for automatic deployments." -ForegroundColor Cyan