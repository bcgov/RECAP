# Generate environment-specific nginx.conf from template
# This script processes the nginx.conf.template and substitutes environment-specific values

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("test", "prod")]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "d837ad-$Environment-networking",
    
    [Parameter(Mandatory=$false)]
    [string]$PrivateEndpointName = "d837ad-$Environment-econ-llm-east-pe"
)

Write-Host "=== Generating nginx.conf for $Environment environment ===" -ForegroundColor Cyan

# Get script directory and check if template exists
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$templatePath = Join-Path $scriptDir "nginx.conf.template"
if (-not (Test-Path $templatePath)) {
    Write-Host "ERROR: nginx.conf.template not found at $templatePath" -ForegroundColor Red
    exit 1
}

# Get private endpoint IP address
Write-Host "Getting private endpoint IP for $PrivateEndpointName..." -ForegroundColor Yellow

# First try customDnsConfigs, fallback to network interface method
$privateEndpointIP = az network private-endpoint show --name $PrivateEndpointName --resource-group $ResourceGroup --query "customDnsConfigs[0].ipAddresses[0]" --output tsv

if (-not $privateEndpointIP -or $privateEndpointIP.Trim() -eq "" -or $privateEndpointIP -eq "null") {
    Write-Host "Custom DNS configs not found, trying network interface method..." -ForegroundColor Yellow
    
    # Get the network interface ID from the private endpoint
    $nicId = az network private-endpoint show --name $PrivateEndpointName --resource-group $ResourceGroup --query "networkInterfaces[0].id" --output tsv
    if ($nicId) {
        Write-Host "Found NIC ID: $nicId" -ForegroundColor Yellow
        $privateEndpointIP = az network nic show --ids $nicId --query "ipConfigurations[0].privateIPAddress" --output tsv
    }
}

if (-not $privateEndpointIP -or $privateEndpointIP.Trim() -eq "") {
    Write-Host "ERROR: Could not retrieve private endpoint IP for $PrivateEndpointName" -ForegroundColor Red
    Write-Host "Please ensure the private endpoint exists and is properly configured." -ForegroundColor Red
    exit 1
}

Write-Host "✅ Private endpoint IP: $privateEndpointIP" -ForegroundColor Green

# Set OpenAI service hostname
$openAIServiceHost = "d837ad-$Environment-econ-llm-east.openai.azure.com"
Write-Host "✅ OpenAI service host: $openAIServiceHost" -ForegroundColor Green

# Read template and substitute values
Write-Host "Processing template..." -ForegroundColor Yellow
try {
    $templateContent = Get-Content $templatePath -Raw
    
    # Perform substitutions
    $processedContent = $templateContent `
        -replace '\{\{PRIVATE_ENDPOINT_IP\}\}', $privateEndpointIP `
        -replace '\{\{OPENAI_SERVICE_HOST\}\}', $openAIServiceHost
    
    # Create timestamped backup file name
    $dateString = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupFileName = Join-Path (Split-Path $scriptDir -Parent) "deploy-$Environment-nginx-conf-$dateString.log"
    $nginxConfPath = Join-Path $scriptDir "nginx.conf"
    
    # Write processed nginx.conf
    $processedContent | Set-Content $nginxConfPath -NoNewline
    Write-Host "✅ Generated nginx.conf for $Environment environment" -ForegroundColor Green
    
    # Always create timestamped backup copy of the generated config
    Copy-Item $nginxConfPath $backupFileName -Force
    Write-Host "✅ Created timestamped backup: $backupFileName" -ForegroundColor Green
    
} catch {
    Write-Host "ERROR: Failed to process template: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Display generated configuration summary
Write-Host "`n=== Generated Configuration Summary ===" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "Private Endpoint IP: $privateEndpointIP" -ForegroundColor Yellow  
Write-Host "OpenAI Service Host: $openAIServiceHost" -ForegroundColor Yellow
Write-Host "Output File: $nginxConfPath" -ForegroundColor Yellow
Write-Host "Backup File: $backupFileName" -ForegroundColor Yellow

Write-Host "`n✅ Configuration generated successfully!" -ForegroundColor Green
Write-Host "You can now build and deploy the Docker container with the environment-specific nginx.conf" -ForegroundColor White