# Windows HTTP→SOCKS Proxy Setup:

[简体中文版本](README.zh.md)

## Why redsocks is not an HTTP front proxy
- Redsocks is designed for transparent TCP redirection using iptables (Linux NAT), not as a direct HTTP proxy front.
- In WSL2, iptables rules only affect Linux-side traffic; they do not make Windows Firewall forward ports or perform NAT for Windows applications.
- Therefore, using redsocks to convert HTTP proxy requests from Windows to SOCKS5 (via -x) does not work unless traffic is transparently redirected inside Linux.

## PAC file must be served via HTTP, not file://
- Windows proxy settings often ignore or fail to load PAC files from file:// URLs due to permissions, service context, or caching issues.
- Solution: Serve the PAC file via a local web server [http://play.local/proxy-google-youtube-gemini.pac](http://play.local/proxy-google-youtube-gemini.pac).

### Windows proxy configuration walkthrough

![Windows proxy script settings](windows-proxy-settings.png)

1. Open **Settings → Network & Internet → Proxy**.
2. Turn **Use setup script** **on** under *Automatic proxy setup*.
3. Enter the PAC URL exactly as `http://play.local/proxy-google-youtube-gemini.pac`.
4. Press **Save**.
5. Ensure *Automatically detect settings* and every option under *Manual proxy setup* remain **off**.
6. Re-open the proxy page or visit `edge://net-internals/#proxy` to confirm the PAC URL is applied.

## Proxy chain overview
```
play.local:80
   ↓
PAC file (served via HTTP)
   ↓
HTTP Proxy (Privoxy) :8081
   ↓
SOCKS5 Proxy (azuresshproxy) :8080
```
- Windows apps use the PAC to selectively route traffic via Privoxy (HTTP proxy on 8081), which forwards to the SOCKS5 proxy (8080).


- Open [http://p.p](http://p.p) or [http://config.privoxy.org](http://config.privoxy.org) in your browser. If Privoxy is active, you will see its status/config page.
- If these pages do not load, check your PAC, proxy settings, and Privoxy status.

## How to check browser proxy diagnostics

- Open [edge://net-internals/#proxy](edge://net-internals/#proxy) in Edge to view and re-apply proxy settings.

## How to check proxy ports are listening
- In WSL, run:
```bash
ss -ltnp | grep -E ':8080|:8081'
ps -ax|grep privoxy
```
- You should see Privoxy listening on 8081 and ssh/azure-proxy on 8080.

## Future improvements
- Add health checks for both proxy ports (8080, 8081) to nginx for monitoring.
- Privoxy already runs as a daemon; wrap the `ssh -D` SOCKS5 process as a daemon for reliability (e.g., systemd service or supervisor script).

## Service supervision and health checks

- A systemd unit named `azuresshproxy.service` keeps the SOCKS5 tunnel (`/bin/azure-proxy`) alive. Enable it with:

   ```bash
   sudo systemctl enable --now azuresshproxy.service
   ```

- Nginx exposes `http://play.local/check` which probes:
   - `privoxy` on `127.0.0.1:8081`
   - `azuresshproxy` on `127.0.0.1:8080`

   When a service is down, the endpoint attempts a restart (`systemctl restart …`) and reports the outcome in JSON. Use `curl --noproxy '*' http://play.local/check` or open [http://play.local/check](http://play.local/check) in your browser to verify the current status.

---
This setup ensures reliable HTTP→SOCKS proxying for Windows via WSL2, with PAC-based selective routing and easy diagnostics.
