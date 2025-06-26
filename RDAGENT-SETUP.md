# RD-Agent Environment Setup

## The Problem
When you open a new terminal, RD-Agent health check fails with Docker connection errors because:
1. Colima (Docker daemon) might not be running
2. `DOCKER_HOST` environment variable is not set

## The Solution
Use the provided setup scripts to automatically configure your environment.

## Quick Setup

### For PowerShell (Windows/macOS)
```powershell
.\setup-rdagent.ps1
```

### For Bash/Zsh (macOS/Linux)
```bash
source setup-rdagent.sh
```

## What the Scripts Do
1. ✅ Check if Colima is running (start it if needed)
2. ✅ Set `DOCKER_HOST` environment variable
3. ✅ Test Docker connection
4. ✅ Verify RD-Agent installation
5. ✅ Create helpful aliases (bash/zsh only)

## Manual Setup (if scripts don't work)

### Step 1: Start Colima
```bash
colima start
```

### Step 2: Set Docker Host
**PowerShell:**
```powershell
$env:DOCKER_HOST = "unix:///Users/jonahkesoyan/.colima/default/docker.sock"
```

**Bash/Zsh:**
```bash
export DOCKER_HOST="unix:///Users/jonahkesoyan/.colima/default/docker.sock"
```

### Step 3: Test
```bash
./rdagent-env/bin/rdagent health_check
```

## Helpful Aliases (after running bash setup)
- `rdagent-health` - Run health check
- `rdagent-ui` - Start RD-Agent UI
- `rdagent-python` - Use RD-Agent Python environment

## Troubleshooting

### "Colima is not running"
```bash
colima start
```

### "Docker connection failed"
1. Check if Colima is running: `colima status`
2. Restart Colima: `colima restart`
3. Check Docker context: `docker context ls`

### "RD-Agent test failed"
1. Check virtual environment: `ls rdagent-env/bin/`
2. Test Python: `./rdagent-env/bin/python --version`
3. Reinstall if needed: `pip install rdagent`

## Daily Workflow
1. Open terminal
2. Navigate to project: `cd /Users/jonahkesoyan/qsharp`
3. Run setup: `.\setup-rdagent.ps1` (PowerShell) or `source setup-rdagent.sh` (bash/zsh)
4. Start working with RD-Agent! 🚀 