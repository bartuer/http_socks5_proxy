function FindProxyForURL(url, host) {
    // Normalize host to lower-case for matching
    host = host.toLowerCase();

    // Bypass proxy for local names and private networks
    if (isPlainHostName(host) ||
        dnsDomainIs(host, "localhost") ||
        shExpMatch(host, "localhost.*") ||
        isInNet(host, "127.0.0.0", "255.0.0.0") ||
        isInNet(host, "10.0.0.0", "255.0.0.0") ||
        isInNet(host, "172.16.0.0", "255.240.0.0") ||
        isInNet(host, "192.168.0.0", "255.255.0.0") ||
        isInNet(host, "169.254.0.0", "255.255.0.0")) {
        return "DIRECT";
    }

    // Only these domains go through the proxy
    var proxy = "PROXY 172.22.173.132:8081"; // Update if your WSL IP changes

    var domains = [
        // YouTube
        "youtube.com", "googlevideo.com", "ytimg.com", "youtu.be",
        // Google & Gemini
        "google.com", "gstatic.com", "googleusercontent.com", "ai.googleusercontent.com",
        "googleapis.com", "gemini.google.com"
    ];

    // Match exact domain or any subdomain
    for (var i = 0; i < domains.length; i++) {
        var d = domains[i];
        if (host === d || shExpMatch(host, "*." + d)) {
            return proxy;
        }
    }

    // Everything else connects directly
    return "DIRECT";
}
