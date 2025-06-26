#!/bin/bash
# RD-Agent Environment Setup Script
# Run this script before using RD-Agent: source setup-rdagent.sh

echo "🚀 Setting up RD-Agent environment..."

# Check if Colima is running
if ! colima status >/dev/null 2>&1; then
    echo "⚠️  Colima is not running. Starting Colima..."
    colima start
    if [ $? -eq 0 ]; then
        echo "✅ Colima started successfully"
    else
        echo "❌ Failed to start Colima"
        return 1
    fi
else
    echo "✅ Colima is already running"
fi

# Set Docker Host environment variable
export DOCKER_HOST="unix:///Users/jonahkesoyan/.colima/default/docker.sock"
echo "✅ DOCKER_HOST set to: $DOCKER_HOST"

# Test Docker connection
echo "🔍 Testing Docker connection..."
if docker ps >/dev/null 2>&1; then
    echo "✅ Docker is accessible"
else
    echo "❌ Docker connection failed"
    return 1
fi

# Test RD-Agent
echo "🔍 Testing RD-Agent..."
if ./rdagent-env/bin/python -c "import rdagent; print('RD-Agent imported successfully')" >/dev/null 2>&1; then
    echo "✅ RD-Agent is ready"
else
    echo "❌ RD-Agent test failed"
    return 1
fi

echo ""
echo "🎉 Environment setup complete!"
echo "You can now run: ./rdagent-env/bin/rdagent health_check"
echo ""
echo "💡 Tip: Run 'source setup-rdagent.sh' whenever you open a new terminal"

# Create helpful aliases
alias rdagent-health='./rdagent-env/bin/rdagent health_check'
alias rdagent-ui='./rdagent-env/bin/rdagent ui --port 19899'
alias rdagent-python='./rdagent-env/bin/python'

echo "✅ Aliases created: rdagent-health, rdagent-ui, rdagent-python" 