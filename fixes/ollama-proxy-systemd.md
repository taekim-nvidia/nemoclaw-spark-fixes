# Ollama Auth Proxy — Systemd Service Fix

NemoClaw starts an Ollama auth proxy on port 11435 during onboarding but
doesn't supervise it. If it dies, inference returns HTTP 401.

## Setup

```bash
# Create env file with the proxy token
TOKEN=$(cat ~/.nemoclaw/ollama-proxy-token | tr -d '[:space:]')
echo "OLLAMA_PROXY_TOKEN=$TOKEN" > ~/.nemoclaw/ollama-proxy-env
chmod 600 ~/.nemoclaw/ollama-proxy-env

# Create service
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/ollama-auth-proxy.service << 'SERVICE'
[Unit]
Description=NemoClaw Ollama Auth Proxy
After=network.target

[Service]
Type=simple
EnvironmentFile=%h/.nemoclaw/ollama-proxy-env
ExecStart=/usr/bin/node %h/.nemoclaw/source/scripts/ollama-auth-proxy.js
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
SERVICE

# Enable and start
systemctl --user daemon-reload
systemctl --user enable --now ollama-auth-proxy
```

## Verify

```bash
systemctl --user status ollama-auth-proxy
TOKEN=$(cat ~/.nemoclaw/ollama-proxy-token | tr -d '[:space:]')
curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:11435/v1/models | python3 -m json.tool
```
