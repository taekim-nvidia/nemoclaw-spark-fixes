#!/usr/bin/env bash
set -euo pipefail

NEMOCLAW_SRC="${HOME}/.nemoclaw/source"

if [ ! -d "$NEMOCLAW_SRC" ]; then
  echo "ERROR: NemoClaw source not found at $NEMOCLAW_SRC"
  echo "Run 'nemoclaw onboard' first to install NemoClaw."
  exit 1
fi

echo "Applying NemoClaw Spark fixes to $NEMOCLAW_SRC..."

# --- Patch 1: .bashrc Landlock fix ---
echo "[1/3] Patching export_gateway_token .bashrc writes..."
sed -i 's/cat "\$tmp" >"$rc_file"$/cat "$tmp" >"$rc_file" 2>\/dev\/null || true/' \
  "$NEMOCLAW_SRC/scripts/nemoclaw-start.sh"
sed -i "s/printf '\\\\n%s\\\\n' \"\\\$snippet\" >>\"\\\$rc_file\"\$/printf '\\\\n%s\\\\n' \"\$snippet\" >>\"\$rc_file\" 2>\/dev\/null || true/" \
  "$NEMOCLAW_SRC/scripts/nemoclaw-start.sh"

# --- Patch 2: NODE_OPTIONS placement ---
echo "[2/3] Moving NODE_OPTIONS ENV to after build steps in Dockerfile..."
# Remove from ENV block
sed -i 's/ \\\n    NODE_OPTIONS="--unhandled-rejections=warn"//' \
  "$NEMOCLAW_SRC/Dockerfile" 2>/dev/null || true
# Add before ENTRYPOINT if not already there
if ! grep -q 'ENV NODE_OPTIONS="--unhandled-rejections=warn"' "$NEMOCLAW_SRC/Dockerfile"; then
  sed -i 's/^ENTRYPOINT \["\/usr\/local\/bin\/nemoclaw-start"\]/ENV NODE_OPTIONS="--unhandled-rejections=warn"\n\nENTRYPOINT ["\/usr\/local\/bin\/nemoclaw-start"]/' \
    "$NEMOCLAW_SRC/Dockerfile"
fi

# --- Patch 3: mDNS fix preload ---
echo "[3/3] Adding mDNS netns fix preload to nemoclaw-start.sh..."
MDNS_MARKER='# mDNS/ciao netns fix'
if ! grep -q "$MDNS_MARKER" "$NEMOCLAW_SRC/scripts/nemoclaw-start.sh"; then
  MDNS_JS='(function(){'"'"'use strict'"'"';var os=require('"'"'os'"'"');var _ni=os.networkInterfaces;os.networkInterfaces=function(){try{return _ni.call(os);}catch(e){if(e.code==='"'"'ERR_SYSTEM_ERROR'"'"'||String(e).indexOf('"'"'uv_interface_addresses'"'"')!==-1){process.stderr.write('"'"'[nemoclaw-mdns-fix] netns patch active\n'"'"');return {};}throw e;}};})();'
  INSERT='# mDNS/ciao netns fix\n_MDNS_FIX_SCRIPT="/tmp/nemoclaw-mdns-fix.js"\ncat > "$_MDNS_FIX_SCRIPT" << '"'"'MDNS_FIX_EOF'"'"'\n'"$MDNS_JS"'\nMDNS_FIX_EOF\nchmod 444 "$_MDNS_FIX_SCRIPT" 2>/dev/null || true\nexport NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--require $_MDNS_FIX_SCRIPT"'
  sed -i "/export NODE_OPTIONS=\"\${NODE_OPTIONS:+\$NODE_OPTIONS }--require \$_NEMOTRON_FIX_SCRIPT\"/a\\
$INSERT" "$NEMOCLAW_SRC/scripts/nemoclaw-start.sh"
fi

echo ""
echo "All patches applied. Now run:"
echo "  NEMOCLAW_PROVIDER=ollama NEMOCLAW_DASHBOARD_PORT=18789 NEMOCLAW_NON_INTERACTIVE=1 \\"
echo "    nemoclaw onboard --agent openclaw --recreate-sandbox --yes-i-accept-third-party-software"
