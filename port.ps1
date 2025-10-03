# Run as Administrator on Windows

$wsl_ip = (wsl hostname -I).Split(" ")[0]
# 1) Forward host → WSL loopback for all three ports
netsh interface portproxy add v4tov4 listenport=80   listenaddress=0.0.0.0 connectport=80   connectaddress=$wsl_ip
netsh interface portproxy add v4tov4 listenport=8081 listenaddress=0.0.0.0 connectport=8081 connectaddress=$wsl_ip
netsh interface portproxy add v4tov4 listenport=8080 listenaddress=0.0.0.0 connectport=8080 connectaddress=$wsl_ip

# 2) Allow inbound traffic on those ports
New-NetFirewallRule -DisplayName "Allow OpenResty 80"   -Direction Inbound -LocalPort 80   -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "Allow Privoxy 8081" -Direction Inbound -LocalPort 8081 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "Allow SSHSOCKS 8080"-Direction Inbound -LocalPort 8080 -Protocol TCP -Action Allow
