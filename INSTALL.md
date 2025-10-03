# Installation Guide

This project assumes a Windows host with the proxy stack running inside WSL. Follow the steps below to provision both sides and bring the services online.

## 1. Prepare Windows port forwarding

1. Open **PowerShell as Administrator**.
2. Navigate to the repository folder (or wherever `port.ps1` lives).
3. Run:
   ```powershell
   .\port.ps1
   ```

The script performs two tasks:

- Detects the active WSL IPv4 address (`wsl hostname -I`).
- Configures `netsh interface portproxy` to forward the following ports from Windows to WSL:
  - **80** → OpenResty (HTTP)
  - **8081** → Privoxy (HTTP-to-SOCKS bridge)
  - **8080** → SSH dynamic SOCKS tunnel (`azuresshproxy`)
- Adds matching Windows Firewall rules (`New-NetFirewallRule`) so inbound TCP connections on ports 80/8080/8081 are permitted.

> **Tip:** Re-run `port.ps1` whenever your WSL IP changes (for example, after a reboot).

## 2. Install Linux dependencies inside WSL

From a WSL shell, install packages with the provided helper script. It must be run with sudo privileges because it writes to system directories and installs packages.

```bash
cd /path/to/http_socks5_proxy
sudo ./apt.sh
```

`apt.sh` performs the following:

1. Updates APT metadata (`apt-get update`).
2. Installs base prerequisites:
   - `ca-certificates`
   - `curl`
   - `gnupg`
   - `lsb-release`
3. Detects whether you are on Ubuntu or Debian and registers the official OpenResty repository (adds GPG key and `/etc/apt/sources.list.d/openresty.list`).
4. Refreshes the package index and installs the runtime stack:
   - `openresty`
   - `privoxy`
   - `pandoc`
   - `lua-cjson`
   - `curl` (ensures it is present even if removed earlier)

After this step the required daemons and utilities are available in WSL.

## 3. Configure and launch services

`config.sh` is the orchestration script that wires everything together. Run it as **root** (the script enforces this) from the repository root inside WSL:

```bash
sudo ./config.sh
```

### What `config.sh` does

1. **Environment discovery**
   - Confirms the current UNIX user and home directory.
   - Resolves the Windows hostname via `cmd.exe /c hostname`.
   - Verifies the static site directory and required documentation/PAC files.

2. **Configuration updates**
   - Patches `nginx.conf` to set the detected user, server name (Windows host), document root, and log locations.
   - Updates `azuresshproxy.service` so the service runs as the current user with the correct home directory.
   - Rewrites documentation (`static/README.md`, `static/README.zh.md`) and the PAC file to reference the current Windows hostname.

3. **Deployment
   - Packages the repository’s `root/` tree into `proxy.config.tar.gz` and extracts it to `/`, effectively syncing configuration files (OpenResty config, systemd unit, etc.) into place.
   - Installs the `azuresshproxy.service` unit into `/etc/systemd/system/`.

4. **Validation and service restart**
   - Runs `openresty -t` and `privoxy --config-test` to ensure syntax correctness.
   - Executes `systemctl daemon-reload` and restarts/enables the three services:
     - `openresty`
     - `privoxy`
     - `azuresshproxy`
   - Prints a summary table of the service statuses and a prettified view of the listening sockets on ports 80/8080/8081.

When `config.sh` finishes successfully, Windows is forwarding traffic into WSL, the services are running, and the configuration files are deployed to their expected locations.

## 4. Access (http://play.local)[http://play.local] to finish Proxy Configure
Follow instructions on README.md

## 5. Ongoing maintenance

- Re-run `./config.sh` after changing repository configuration files to sync them into the system directories.
- Re-run `./apt.sh` only when you need to refresh or repair package installations.
- Re-run `port.ps1` if the Windows↔WSL networking environment changes (e.g., after disabling/re-enabling WSL networking).

With these three scripts you can consistently reprovision the entire proxy stack across Windows and WSL.
