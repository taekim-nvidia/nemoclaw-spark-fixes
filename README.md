# nemoclaw-spark-fixes

Bug fixes and workarounds for running [NemoClaw](https://github.com/NVIDIA/NemoClaw) on DGX Spark (aarch64 GB10).

Discovered while setting up a sandboxed Nemotron-3-Super agent on Spark in April 2026. All bugs filed/documented here for upstream reference.

## Quick Start

Apply all patches to your local NemoClaw source (`~/.nemoclaw/source/`):

```bash
git clone https://github.com/taekim-nvidia/nemoclaw-spark-fixes
cd nemoclaw-spark-fixes
./apply-patches.sh
```

Then re-onboard:

```bash
NEMOCLAW_PROVIDER=ollama NEMOCLAW_DASHBOARD_PORT=18789 NEMOCLAW_NON_INTERACTIVE=1 \
  nemoclaw onboard --agent openclaw --yes-i-accept-third-party-software
```

## Bugs & Fixes

| # | Bug | Fix |
|---|-----|-----|
| 1 | Port 18789 hardcoded — conflicts with native OpenClaw | Use `NEMOCLAW_DASHBOARD_PORT` env var |
| 2 | `--from` Dockerfile replaces full 53-step build | Not fixed; avoid `--from` for simple customizations |
| 3 | `/tmp` as Dockerfile path self-copy crash | Place Dockerfile outside `/tmp/` |
| 4 | `export_gateway_token` crashes under Landlock | Patch: `\|\| true` on `.bashrc` writes |
| 5 | `NODE_OPTIONS` ENV before Step 45 breaks `openclaw doctor` | Patch: move `ENV NODE_OPTIONS` after all build steps |
| 6 | Ollama auth proxy dies silently | Fix: systemd user service |
| 7 | `homebridge/ciao` crashes gateway in restricted netns | Patch: monkey-patch `os.networkInterfaces` |
| 8 | Sandbox image pinned to old OpenClaw (2026.4.2) | Upstream issue; monitor ghcr.io for updates |

---

## Detailed Bug Reports

### Bug 1 — Port 18789 hardcoded

**Symptom:** `!! Port 18789 is not available. NemoClaw dashboard needs this port.`

**Root cause:** NemoClaw's preflight check hardcodes port 18789. If a native OpenClaw gateway is already running there, onboarding fails.

**Fix:** Use the undocumented `NEMOCLAW_DASHBOARD_PORT` env var:

```bash
NEMOCLAW_DASHBOARD_PORT=18790 nemoclaw onboard ...
```

Or move your native OpenClaw to a different port first (`gateway.port` in `~/.openclaw/openclaw.json`).

---

### Bug 2 — `--from` Dockerfile replaces full build

**Symptom:** Custom `--from` Dockerfile results in a 4-step image missing `nemoclaw-start`, credential injection, and all NemoClaw setup.

**Root cause:** `nemoclaw onboard --from file.Dockerfile` uses the provided Dockerfile as-is, not as an extension of the 53-step NemoClaw build. The `ARG BASE_IMAGE` substitution works, but all 53 build steps are lost.

**Fix:** Modify `~/.nemoclaw/source/Dockerfile` directly instead of using `--from`.

---

### Bug 3 — `/tmp` Dockerfile path self-copy crash

**Symptom:** `Error: Cannot copy /tmp/ to a subdirectory of self /tmp/nemoclaw-build-XXXXX`

**Root cause:** NemoClaw creates its build context in `/tmp/`. Providing a Dockerfile from `/tmp/` causes Docker to try to copy the parent directory into itself.

**Fix:** Place the Dockerfile anywhere outside `/tmp/`, e.g. `~/nemoclaw-custom/Dockerfile`.

---

### Bug 4 — `export_gateway_token` crashes under Landlock

**Symptom:** Gateway never starts. No `/tmp/gateway.log` created. Proxy fix scripts exist but are owned by the sandbox user, not root.

**Root cause:** `nemoclaw-start.sh` tries to write the gateway auth token to `/sandbox/.bashrc`. OpenShell's Landlock policy blocks writes to `/sandbox/` even when UNIX permissions (mode 644, owner sandbox) allow it. With `set -euo pipefail`, the failed `printf >> .bashrc` exits the entire startup script before the gateway launches.

**Fix:** See `patches/01-bashrc-landlock.patch`

---

### Bug 5 — `NODE_OPTIONS` ENV before Step 45 breaks `openclaw doctor`

**Symptom:** Gateway doesn't start; `/sandbox/.bashrc` has mode 644 instead of expected 444.

**Root cause:** Adding `ENV NODE_OPTIONS=--unhandled-rejections=warn` in the Dockerfile before Step 45 (`RUN openclaw doctor --fix`) causes the doctor command to run with that env. The doctor skips or alters its `.bashrc` hardening step, leaving the file writable (644). At runtime, Bug 4 then triggers because Landlock blocks the write.

**Fix:** See `patches/02-node-options-placement.patch`. The `ENV NODE_OPTIONS=...` must come **after** Step 45.

---

### Bug 6 — Ollama auth proxy dies silently

**Symptom:** Inference calls return `HTTP 401: Unauthorized` after sandbox restart.

**Root cause:** NemoClaw starts an Ollama auth proxy (`ollama-auth-proxy.js`) on port 11435 during onboarding but doesn't supervise it. If the process dies (e.g. on host restart), inference fails with 401 and there's no auto-recovery.

**Fix:** Create a systemd user service. See `fixes/ollama-proxy-systemd.md`.

---

### Bug 7 — `homebridge/ciao` crashes gateway in restricted network namespace

**Symptom:** Gateway starts, logs `[gateway] listening on ws://127.0.0.1:18789`, then dies 20–30ms later.

**Root cause:** OpenClaw 2026.4.2 uses `homebridge/ciao` for mDNS service discovery. On startup, it calls `os.networkInterfaces()` which invokes `uv_interface_addresses`. This syscall fails with `ERR_SYSTEM_ERROR` (`Unknown system error 1`) inside OpenShell's restricted network namespace. The resulting unhandled rejection hits OpenClaw's global error handler, which re-throws it as an uncaughtException, crashing the process.

**Why `--unhandled-rejections=warn` isn't enough:** OpenClaw's own `process.on('unhandledRejection', ...)` handler runs after any preload handler and re-throws the error. The fix must prevent the rejection from being raised at all.

**Fix:** Monkey-patch `os.networkInterfaces` in a Node.js preload to return `{}` on failure. See `fixes/mdns-fix.js` and `patches/03-mdns-netns.patch`.

---

### Bug 8 — Sandbox image pinned to old OpenClaw

**Symptom:** `nemoclaw my-assistant status` shows `Agent: OpenClaw v2026.4.2` while host has `v2026.4.23`.

**Root cause:** The NemoClaw blueprint pins the sandbox base image by digest (`sha256:b3d832b...`). The `ghcr.io/nvidia/openshell-community/sandboxes/openclaw:latest` tag hasn't been updated.

**Workaround:** None currently. Upstream needs to push an updated sandbox base image. Bug 7 is fixed in newer OpenClaw versions.

---

## Environment

- **Hardware:** DGX Spark GB10 (aarch64, 120 GiB unified memory)
- **OS:** Linux 6.17.0 (aarch64)
- **NemoClaw:** v0.1.0
- **OpenShell:** v0.0.36
- **OpenClaw (host):** v2026.4.23
- **OpenClaw (sandbox):** v2026.4.2
- **Ollama:** local, `nemotron-3-super:latest` + `gemma4:31b`
- **Date:** April 2026

## License

Apache 2.0
