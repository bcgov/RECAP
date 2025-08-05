# Test script to verify Azure OpenAI authentication through proxy
# Usage: .\test-auth.ps1 -ApiKey "your-api-key-here"

param(
    [Parameter(Mandatory=$true)]
    [string]$ApiKey,
    [string]$ProxyUrl = "https://d837ad-test-recap-webapp.azurewebsites.net",
    [int]$Tests = 5,
    [ValidateSet("gpt-4o", "gpt-4o-mini", "both")]
    [string]$Model = "both"
)

# Function to test a specific model
function Test-ModelLoad {
    param(
        [string]$ModelName,
        [string]$ProxyUrl,
        [string]$ApiKey,
        [int]$Tests
    )
    
    Write-Host "`n=== Testing $ModelName model ===" -ForegroundColor Cyan
    
    $modelSuccessCount = 0
    $modelFailCount = 0

    for ($i = 1; $i -le $Tests; $i++) {
        Write-Host "Test $i of $Tests ($ModelName)..." -ForegroundColor Yellow
        
        try {
            $headers = @{
                "Authorization" = $ApiKey
                "Content-Type" = "application/json"
            }
            
            $body = @{
                "messages" = @(
                    @{
                        "role" = "user"
                        "content" = "Say 'Hello from $ModelName test $i'"
                    }
                )
                "max_tokens" = 50
                "temperature" = 0.7
            } | ConvertTo-Json -Depth 10
            
            $response = Invoke-RestMethod -Uri "$ProxyUrl/openai/openai/deployments/$ModelName/chat/completions?api-version=2024-02-01" `
                -Method POST `
                -Headers $headers `
                -Body $body `
                -TimeoutSec 30
            
            if ($response.choices -and $response.choices[0].message.content) {
                Write-Host "✅ SUCCESS: $($response.choices[0].message.content.Trim())" -ForegroundColor Green
                
                # Check for usage data
                if ($response.usage) {
                    Write-Host "   Token Usage: $($response.usage.total_tokens) total ($($response.usage.prompt_tokens) + $($response.usage.completion_tokens))" -ForegroundColor Cyan
                }
                
                $modelSuccessCount++
            } else {
                Write-Host "❌ FAILED: No content in response" -ForegroundColor Red
                $modelFailCount++
            }
        }
        catch {
            Write-Host "❌ FAILED: $($_.Exception.Message)" -ForegroundColor Red
            $modelFailCount++
        }
        
        if ($i -lt $Tests) {
            Start-Sleep -Seconds 2
        }
    }
    
    return @{
        Success = $modelSuccessCount
        Failed = $modelFailCount
        Model = $ModelName
    }
}

Write-Host "Testing RECAP Web Proxy Authentication" -ForegroundColor Green
Write-Host "Proxy URL: $ProxyUrl" -ForegroundColor Cyan
Write-Host "Model(s): $Model" -ForegroundColor Cyan
Write-Host "Running $Tests tests per model..." -ForegroundColor Cyan

$totalSuccessCount = 0
$totalFailCount = 0
$modelResults = @()

if ($Model -eq "both") {
    $modelsToTest = @("gpt-4o", "gpt-4o-mini")
} else {
    $modelsToTest = @($Model)
}

foreach ($modelName in $modelsToTest) {
    $result = Test-ModelLoad -ModelName $modelName -ProxyUrl $ProxyUrl -ApiKey $ApiKey -Tests $Tests
    $modelResults += $result
    $totalSuccessCount += $result.Success
    $totalFailCount += $result.Failed
}

Write-Host ""
Write-Host "=== Overall Test Results ===" -ForegroundColor Yellow

foreach ($result in $modelResults) {
    $modelSuccessRate = ($result.Success / $Tests) * 100
    Write-Host "$($result.Model):" -ForegroundColor Cyan
    Write-Host "  ✅ Successful: $($result.Success)/$Tests" -ForegroundColor Green
    Write-Host "  ❌ Failed: $($result.Failed)/$Tests" -ForegroundColor Red
    Write-Host "  Success Rate: $modelSuccessRate%" -ForegroundColor $(if ($modelSuccessRate -ge 80) { "Green" } else { "Red" })
}

$totalTests = $totalSuccessCount + $totalFailCount
$overallSuccessRate = if ($totalTests -gt 0) { ($totalSuccessCount / $totalTests) * 100 } else { 0 }

Write-Host "`nOverall Summary:" -ForegroundColor Yellow
Write-Host "✅ Total Successful: $totalSuccessCount/$totalTests" -ForegroundColor Green
Write-Host "❌ Total Failed: $totalFailCount/$totalTests" -ForegroundColor Red
Write-Host "Overall Success Rate: $overallSuccessRate%" -ForegroundColor $(if ($overallSuccessRate -ge 80) { "Green" } else { "Red" })

if ($overallSuccessRate -lt 100) {
    Write-Host ""
    Write-Host "Authentication reliability issues detected!" -ForegroundColor Red
    Write-Host "Expected: 100% success rate" -ForegroundColor Yellow
    Write-Host "Actual: $overallSuccessRate% success rate" -ForegroundColor Yellow
}