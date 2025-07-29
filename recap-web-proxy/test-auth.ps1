# Test script to verify Azure OpenAI authentication through proxy
# Usage: .\test-auth.ps1 -ApiKey "your-api-key-here"

param(
    [Parameter(Mandatory=$true)]
    [string]$ApiKey,
    [string]$ProxyUrl = "https://d837ad-test-recap-webapp.azurewebsites.net",
    [int]$Tests = 5
)

Write-Host "Testing RECAP Web Proxy Authentication" -ForegroundColor Green
Write-Host "Proxy URL: $ProxyUrl" -ForegroundColor Cyan
Write-Host "Running $Tests tests..." -ForegroundColor Cyan
Write-Host ""

$successCount = 0
$failCount = 0

for ($i = 1; $i -le $Tests; $i++) {
    Write-Host "Test $i of $Tests..." -ForegroundColor Yellow
    
    try {
        $headers = @{
            "Authorization" = $ApiKey
            "Content-Type" = "application/json"
        }
        
        $body = @{
            "messages" = @(
                @{
                    "role" = "user"
                    "content" = "Say 'Hello from test $i'"
                }
            )
            "max_tokens" = 50
            "temperature" = 0.7
        } | ConvertTo-Json -Depth 10
        
        $response = Invoke-RestMethod -Uri "$ProxyUrl/openai/openai/deployments/gpt-4o/chat/completions?api-version=2024-02-01" `
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
            
            $successCount++
        } else {
            Write-Host "❌ FAILED: No content in response" -ForegroundColor Red
            $failCount++
        }
    }
    catch {
        Write-Host "❌ FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
    
    if ($i -lt $Tests) {
        Start-Sleep -Seconds 2
    }
}

Write-Host ""
Write-Host "Test Results:" -ForegroundColor Yellow
Write-Host "✅ Successful: $successCount/$Tests" -ForegroundColor Green
Write-Host "❌ Failed: $failCount/$Tests" -ForegroundColor Red

$successRate = ($successCount / $Tests) * 100
Write-Host "Success Rate: $successRate%" -ForegroundColor $(if ($successRate -ge 80) { "Green" } else { "Red" })

if ($successRate -lt 100) {
    Write-Host ""
    Write-Host "Authentication reliability issues detected!" -ForegroundColor Red
    Write-Host "Expected: 100% success rate" -ForegroundColor Yellow
    Write-Host "Actual: $successRate% success rate" -ForegroundColor Yellow
}