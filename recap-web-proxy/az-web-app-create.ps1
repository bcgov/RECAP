# Azure Web App for Containers deployment script
# This script deploys your Nginx Docker image from ACR to an Azure Web App (Linux) with VNet integration for secure proxying to a private Azure OpenAI endpoint.

# ====== USER CONFIGURATION ======
# Set these variables as needed before running the script. No prompting will occur.
$subscriptionId = "5445292b-8313-4272-96aa-f30efd1e1654"
$resourceGroup = "d837ad-test-networking"
$region = "canadacentral"                    # Adjust this to your region as needed
$acrName = "d837adcontainers"
$containerName = "nginx-container"           # Used for image and web app name
$localImage = "recap-web-proxy:latest"       # Change if your local image name is different
$appServicePlan = "recap-webapp-plan"
$webAppName = "recap-webapp-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
# VNet integration settings (update these for your environment)
$vnetName = "d837ad-test-vwan-spoke"          # Name of your VNet
$webAppSubnetName = "d837ad-test-webapp-subnet" # Name of the dedicated subnet for Web App VNet integration
$webAppNsgName = "d837ad-test-webapp-nsg"        # Name of the NSG for the subnet
$vnetResourceGroup = $resourceGroup           # Change if VNet is in a different resource group

# Find a free /27 subnet within the VNet's address space
Write-Host "Finding a free /27 subnet in VNet $vnetName..." -ForegroundColor Yellow
$vnetAddressSpace = (az network vnet show --resource-group $vnetResourceGroup --name $vnetName --query "addressSpace.addressPrefixes[0]" -o tsv)
$existingSubnets = az network vnet subnet list --resource-group $vnetResourceGroup --vnet-name $vnetName --query "[].addressPrefix" -o tsv | Where-Object { $_ -and $_.Trim() -ne "" }
Write-Host "Existing subnets in VNet $vnetName:" -ForegroundColor Yellow
$existingSubnets | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }

$script:ipToInt = {
    param($ip)
    $parts = $ip.Split('.')
    return ($parts[0] -as [int]) * 16777216 + ($parts[1] -as [int]) * 65536 + ($parts[2] -as [int]) * 256 + ($parts[3] -as [int])
}
$script:cidrRange = {
    param($cidr)
    $split = $cidr.Split('/')
    $ip = $split[0]
    $prefix = [int]$split[1]
    if ($prefix -lt 0 -or $prefix -gt 32) {
        throw "Invalid prefix length in CIDR: $cidr"
    }
    $ipInt = & $script:ipToInt $ip
    $mask = [uint32]([math]::Pow(2,32) - [math]::Pow(2,32-$prefix))
    $start = $ipInt -band $mask
    $end = $start + [math]::Pow(2, 32 - $prefix) - 1
    return @($start, $end)
}
function Find-FreeSubnet {
    param(
        [string]$vnetCidr,
        [string[]]$usedCidrs
    )
    $ip = $vnetCidr.Split('/')[0]
    $prefix = [int]$vnetCidr.Split('/')[1]
    $base = [System.Net.IPAddress]::Parse($ip).GetAddressBytes()
    $subnetPrefix = 27
    $numSubnets = [math]::Pow(2, $subnetPrefix - $prefix)
    $usedRanges = @()
    foreach ($cidr in $usedCidrs) {
        if ($cidr -and $cidr.Trim() -ne "") {
            try {
                $usedRanges += ,(& $script:cidrRange $cidr)
            } catch {
                Write-Host "Skipping invalid CIDR: $cidr" -ForegroundColor Red
            }
        }
    }
    Write-Host "Used subnet ranges (start-end):" -ForegroundColor Yellow
    foreach ($range in $usedRanges) { Write-Host ($range -join "-") -ForegroundColor Yellow }
    for ($i = 0; $i -lt $numSubnets; $i++) {
        $octets = $base.Clone()
        $octets[3] += ($i * 32)
        $candidate = "{0}.{1}.{2}.{3}/27" -f $octets[0],$octets[1],$octets[2],$octets[3]
        $candRange = & $script:cidrRange $candidate
        $overlap = $false
        foreach ($range in $usedRanges) {
            if ($candRange[0] -le $range[1] -and $candRange[1] -ge $range[0]) {
                $overlap = $true
                break
            }
        }
        if (-not $overlap) {
            return $candidate
        }
    }
    return $null
}
$webAppSubnetPrefix = Find-FreeSubnet $vnetAddressSpace $existingSubnets
if (-not $webAppSubnetPrefix) {
    Write-Host "ERROR: Could not find a free /27 subnet in $vnetAddressSpace. Please check your VNet configuration." -ForegroundColor Red
    exit 1
}
Write-Host "Using subnet prefix $webAppSubnetPrefix for $webAppSubnetName." -ForegroundColor Green
# Create NSG for the subnet if it doesn't exist
Write-Host "Checking for Network Security Group $webAppNsgName..." -ForegroundColor Yellow
$nsgCheck = az network nsg show --resource-group $vnetResourceGroup --name $webAppNsgName 2>$null
if (-not $nsgCheck) {
    Write-Host "Creating Network Security Group $webAppNsgName..." -ForegroundColor Yellow
    az network nsg create --resource-group $vnetResourceGroup --name $webAppNsgName
    if ($LASTEXITCODE -eq 0) {
        Write-Host "NSG $webAppNsgName created successfully." -ForegroundColor Green
    } else {
        Write-Host "Failed to create NSG $webAppNsgName. Exiting script." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "NSG $webAppNsgName already exists." -ForegroundColor Green
}
# Delete existing subnet if it exists (to avoid overlap or reuse address space)
Write-Host "Checking for subnet $webAppSubnetName in VNet $vnetName..." -ForegroundColor Yellow
$subnetCheck = az network vnet subnet show --resource-group $vnetResourceGroup --vnet-name $vnetName --name $webAppSubnetName 2>$null
if ($subnetCheck) {
    Write-Host "Deleting existing subnet $webAppSubnetName..." -ForegroundColor Yellow
    az network vnet subnet delete --resource-group $vnetResourceGroup --vnet-name $vnetName --name $webAppSubnetName
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Subnet $webAppSubnetName deleted successfully." -ForegroundColor Green
    } else {
        Write-Host "Failed to delete subnet $webAppSubnetName. Exiting script." -ForegroundColor Red
        exit 1
    }
}
# Now create the dedicated subnet for Web App VNet integration
Write-Host "Creating subnet $webAppSubnetName with delegation to Microsoft.Web/serverFarms..." -ForegroundColor Yellow
az network vnet subnet create --resource-group $vnetResourceGroup --vnet-name $vnetName --name $webAppSubnetName --address-prefixes $webAppSubnetPrefix --delegations Microsoft.Web/serverFarms --network-security-group $webAppNsgName
if ($LASTEXITCODE -eq 0) {
    Write-Host "Subnet $webAppSubnetName created and delegated successfully." -ForegroundColor Green
} else {
    Write-Host "Failed to create subnet $webAppSubnetName. Exiting script." -ForegroundColor Red
    exit 1
}
# =================================

# Set the subscription if specified
if ($subscriptionId -and $subscriptionId -notmatch '^<.*>$') {
    az account set --subscription $subscriptionId
}
az account show --query "{name:name, id:id, state:state, isDefault:isDefault, user:user}" --output json

$acrLoginServer = "$acrName.azurecr.io"
$acrImage = "$acrLoginServer/$localImage"

# Check if ACR exists
Write-Host "Checking for Azure Container Registry $acrName..." -ForegroundColor Yellow
$acrCheck = az acr show --name $acrName --resource-group $resourceGroup 2>$null
if (-not $acrCheck) {
    Write-Host "ACR $acrName does not exist. Exiting script." -ForegroundColor Red
    exit 1
} else {
    Write-Host "ACR $acrName already exists." -ForegroundColor Green
}

# Create App Service Plan if it doesn't exist (Standard S1 for VNet integration)
Write-Host "Checking for App Service Plan $appServicePlan..." -ForegroundColor Yellow
$planCheck = az appservice plan show --name $appServicePlan --resource-group $resourceGroup 2>$null
if (-not $planCheck) {
    Write-Host "Creating App Service Plan $appServicePlan (Standard S1 for VNet integration)..." -ForegroundColor Yellow
    az appservice plan create --name $appServicePlan --resource-group $resourceGroup --is-linux --sku S1 --location $region
    if ($?) {
        Write-Host "App Service Plan $appServicePlan created successfully." -ForegroundColor Green
    } else {
        Write-Host "Failed to create App Service Plan $appServicePlan. Exiting script." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "App Service Plan $appServicePlan already exists." -ForegroundColor Green
}



# Validate App Service Plan is Linux (robust check)
$planInfo = az appservice plan show --name $appServicePlan --resource-group $resourceGroup | ConvertFrom-Json
if ((-not $planInfo.isLinux -or $planInfo.isLinux -ne $true) -and ($planInfo.kind -notmatch 'linux')) {
    Write-Host "ERROR: App Service Plan $appServicePlan is not a Linux plan (isLinux is null/false and kind does not contain 'linux'). Please delete and recreate it with --is-linux." -ForegroundColor Red
    exit 1
}

# Create Web App (Linux, built-in Node.js runtime)
Write-Host "Creating Web App $webAppName (Linux, built-in Node.js runtime)..." -ForegroundColor Yellow
az webapp create --resource-group $resourceGroup --plan $appServicePlan --name $webAppName --runtime "NODE:22-lts" --https-only true
if ($LASTEXITCODE -eq 0) {
    Write-Host "Web App $webAppName created successfully." -ForegroundColor Green
} else {
    Write-Host "Failed to create Web App $webAppName. Exiting script." -ForegroundColor Red
    exit 1
}

# HTTPS-only is enforced by policy; no need to set explicitly

# Get ACR admin credentials
Write-Host "Fetching ACR admin credentials..." -ForegroundColor Yellow
$acrCreds = az acr credential show --name $acrName | ConvertFrom-Json
$acrUsername = $acrCreds.username
$acrPassword = $acrCreds.passwords[0].value

# Configure Web App to use ACR credentials
Write-Host "Configuring Web App to use ACR image..." -ForegroundColor Yellow
az webapp config container set --name $webAppName --resource-group $resourceGroup --container-image-name $acrImage --container-registry-url https://$acrLoginServer --container-registry-user $acrUsername --container-registry-password $acrPassword
if ($?) {
    Write-Host "Web App container configuration set successfully." -ForegroundColor Green
} else {
    Write-Host "Failed to configure Web App container. Exiting script." -ForegroundColor Red
    exit 1
}

# Enable VNet integration
Write-Host "Enabling VNet integration for Web App..." -ForegroundColor Yellow
$webAppSubnetId = az network vnet subnet show --resource-group $vnetResourceGroup --vnet-name $vnetName --name $webAppSubnetName --query id -o tsv
if ($webAppSubnetId) {
    az webapp vnet-integration add --name $webAppName --resource-group $resourceGroup --vnet $vnetName --subnet $webAppSubnetName
    if ($?) {
        Write-Host "VNet integration enabled for $webAppName on subnet $webAppSubnetName." -ForegroundColor Green
    } else {
        Write-Host "Failed to enable VNet integration. Exiting script." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Could not find subnet $webAppSubnetName in VNet $vnetName. Please check your configuration." -ForegroundColor Red
    exit 1
}

# Output the HTTPS endpoint
$webAppUrl = "https://$webAppName.azurewebsites.net"
Write-Host "Web App deployed and available at: $webAppUrl" -ForegroundColor Cyan

# --- NGINX CONFIGURATION ---
# Write a default nginx.conf to the current directory (customize as needed)
$nginxConfPath = "nginx.conf"
$nginxConfContent = @"
user  nginx;
worker_processes  auto;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;

    server {
        listen       80;
        server_name  localhost;

        location /openai/ {
            proxy_pass https://<your-openai-endpoint>/;
            proxy_set_header Host <your-openai-endpoint>;
            proxy_set_header api-key <your-openai-api-key>;
            proxy_set_header Content-Type application/json;
        }
    }
}
"@
Set-Content -Path $nginxConfPath -Value $nginxConfContent -Force
Write-Host "nginx.conf written to $nginxConfPath. Customize as needed before building/pushing your container." -ForegroundColor Yellow

# Reminder for user to mount or COPY nginx.conf in Dockerfile
Write-Host "\n--- NGINX CONFIGURATION REMINDER ---" -ForegroundColor Yellow
Write-Host "If using a custom Nginx image, ensure you COPY or mount nginx.conf to /etc/nginx/nginx.conf in your Dockerfile." -ForegroundColor Yellow
Write-Host "Example Dockerfile line: COPY nginx.conf /etc/nginx/nginx.conf" -ForegroundColor Yellow
Write-Host "Update your Nginx config and redeploy the container if needed." -ForegroundColor Yellow
