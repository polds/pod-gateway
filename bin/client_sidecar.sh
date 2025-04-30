#!/bin/bash
set -e

# Load settings
. /default_config/settings.sh
. /config/settings.sh

VXLAN_GATEWAY_IP="${VXLAN_IP_NETWORK}.1"
DHCP_PID_FILE="/var/run/udhcpc.vxlan0.pid"
NAT_ENTRY="$(grep "^$(hostname) " /config/nat.conf || true)"

# Function to check gateway connectivity
check_gateway() {
    ping -c "${CONNECTION_RETRY_COUNT}" "$VXLAN_GATEWAY_IP" > /dev/null 2>&1
    return $?
}

# Function to verify and start DHCP client if needed
ensure_dhcp_client() {
    if [[ -n "$NAT_ENTRY" ]]; then
        # Using static IP, no DHCP needed
        return 0
    fi

    # Check if DHCP client is running
    if [ -f "$DHCP_PID_FILE" ] && kill -0 $(cat "$DHCP_PID_FILE") 2>/dev/null; then
        return 0
    fi

    echo "Starting DHCP client daemon"
    # Use background mode (-b) which handles renewals automatically
    udhcpc -b -i vxlan0 -p "$DHCP_PID_FILE" -O subnet -O router

    # Verify we got an IP
    if ! ip addr show dev vxlan0 | grep -q "inet ${VXLAN_IP_NETWORK}"; then
        echo "ERROR: Failed to get IP address for vxlan0" >&2
        return 1
    fi
    return 0
}

# Initial startup check
echo "Sidecar starting - verifying network configuration"
ensure_dhcp_client

# Main monitoring loop
while true; do
    # Check interface exists with IP
    if ! ip link show vxlan0 &>/dev/null; then
        echo "ERROR: vxlan0 interface missing, attempting recovery" >&2
        ip link add vxlan0 type vxlan id "$VXLAN_ID" group 239.1.1.1 dev eth0 dstport 0 || true
        ip link set up dev vxlan0
    fi

    if ! ip addr show dev vxlan0 | grep -q "inet ${VXLAN_IP_NETWORK}"; then
        echo "ERROR: vxlan0 has no valid IP address" >&2
        ensure_dhcp_client
    fi

    # Check gateway connectivity
    if ! check_gateway; then
        echo "ERROR: Gateway connectivity lost" >&2

        # Check DHCP client status for dynamic IPs
        if [[ -z "$NAT_ENTRY" ]]; then
            if ! ensure_dhcp_client; then
                echo "Failed to restart DHCP client"
            fi
        else
            # For static IPs, just ensure the route exists
            echo "Ensuring route for static IP"
            route add default gw "$VXLAN_GATEWAY_IP" || true
        fi
    else
        echo "Gateway connection OK - $(date)"
    fi

    sleep 10
done