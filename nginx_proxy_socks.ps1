# This PowerShell script forwards port 80 on Windows to WSL (nginx) and sets a firewall rule for inbound connections on port 80
# Run as Administrator
# Run as Administrator on Windows

# 1) Forward host → WSL loopback for all three ports
netsh interface portproxy add v4tov4 listenport=80   listenaddress=0.0.0.0 connectport=80   connectaddress=172.22.173.132
netsh interface portproxy add v4tov4 listenport=8081 listenaddress=0.0.0.0 connectport=8081 connectaddress=172.22.173.132
netsh interface portproxy add v4tov4 listenport=8080 listenaddress=0.0.0.0 connectport=8080 connectaddress=172.22.173.132

# 2) Allow inbound traffic on those ports
New-NetFirewallRule -DisplayName "Allow HTTP 80"   -Direction Inbound -LocalPort 80   -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "Allow Privoxy 8081" -Direction Inbound -LocalPort 8081 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "Allow SSHSOCKS 8080"-Direction Inbound -LocalPort 8080 -Protocol TCP -Action Allow
