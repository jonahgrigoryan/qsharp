# RD-Agent Environment Setup Script
# Run this script before using RD-Agent: .\setup-rdagent.ps1

Write-Host "🚀 Setting up RD-Agent environment..." -ForegroundColor Green

# Check if Colima is running
$colimaStatus = colima status 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠️  Colima is not running. Starting Colima..." -ForegroundColor Yellow
    colima start
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Colima started successfully" -ForegroundColor Green
    } else {
        Write-Host "❌ Failed to start Colima" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "✅ Colima is already running" -ForegroundColor Green
}

# Set Docker Host environment variable
$env:DOCKER_HOST = "unix:///Users/jonahkesoyan/.colima/default/docker.sock"
Write-Host "✅ DOCKER_HOST set to: $env:DOCKER_HOST" -ForegroundColor Green

# Test Docker connection
Write-Host "🔍 Testing Docker connection..." -ForegroundColor Blue
docker ps > $null 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Docker is accessible" -ForegroundColor Green
} else {
    Write-Host "❌ Docker connection failed" -ForegroundColor Red
    exit 1
}

# Test RD-Agent
Write-Host "🔍 Testing RD-Agent..." -ForegroundColor Blue
$rdagentTest = ./rdagent-env/bin/python -c "import rdagent; print('RD-Agent imported successfully')" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ RD-Agent is ready" -ForegroundColor Green
} else {
    Write-Host "❌ RD-Agent test failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🎉 Environment setup complete!" -ForegroundColor Green
Write-Host "You can now run: ./rdagent-env/bin/rdagent health_check" -ForegroundColor Cyan
Write-Host ""
Write-Host "💡 Tip: Run this script (.\setup-rdagent.ps1) whenever you open a new terminal" -ForegroundColor Yellow 