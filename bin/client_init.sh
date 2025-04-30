#!/bin/bash
set -e

# Load settings
. /default_config/settings.sh
. /config/settings.sh

# Setup variables
K8S_DNS_IP="$(cut -d ' ' -f 1 <<< "$K8S_DNS_IPS")"
GATEWAY_IP="$(dig +short "$GATEWAY_NAME" "@${K8S_DNS_IP}")"
VXLAN_GATEWAY_IP="${VXLAN_IP_NETWORK}.1"

echo "Setting up vxlan interface and routes"

# Setup routing rules for local traffic
K8S_GW_IP=$(/sbin/ip route | awk '/default/ { print $3 }')
for local_cidr in $NOT_ROUTED_TO_GATEWAY_CIDRS; do
    ip route add "$local_cidr" via "$K8S_GW_IP" || true
done

# Delete default routes
ip route del 0/0 || true
ip route -6 del default || true

# Add gateway route
ip route add "$GATEWAY_IP" via "$K8S_GW_IP" || true

# Create and configure vxlan interface
ip link add vxlan0 type vxlan id "$VXLAN_ID" group 239.1.1.1 dev eth0 dstport "${VXLAN_PORT:-0}" || true
bridge fdb append to 00:00:00:00:00:00 dst "$GATEWAY_IP" dev vxlan0
ip link set up dev vxlan0

# Set MTU if needed
if [[ -n "$VPN_INTERFACE_MTU" ]]; then
    ETH0_INTERFACE_MTU=$(cat /sys/class/net/eth0/mtu)
    VXLAN0_INTERFACE_MAX_MTU=$((ETH0_INTERFACE_MTU-50))
    if [ ${VPN_INTERFACE_MTU} -ge ${VXLAN0_INTERFACE_MAX_MTU} ]; then
        ip link set mtu "${VXLAN0_INTERFACE_MAX_MTU}" dev vxlan0
    else
        ip link set mtu "${VPN_INTERFACE_MTU}" dev vxlan0
    fi
fi

# Get initial IP configuration
NAT_ENTRY="$(grep "^$(hostname) " /config/nat.conf || true)"
if [[ -z "$NAT_ENTRY" ]]; then
    echo "Setting up dynamic IP via DHCP (one-time)"
    # Get initial IP address using foreground mode (exit after lease)
    if ! udhcpc -i vxlan0 -n -q -f; then
        echo "ERROR: Failed to obtain initial IP lease" >&2
        exit 1
    fi
else
    # Static IP configuration
    IP=$(cut -d' ' -f2 <<< "$NAT_ENTRY")
    VXLAN_IP="${VXLAN_IP_NETWORK}.${IP}"
    echo "Using static IP $VXLAN_IP"
    ip addr add "${VXLAN_IP}/24" dev vxlan0 || true
    route add default gw "$VXLAN_GATEWAY_IP" || true
fi

# Test connectivity before allowing pod to start
echo "Testing gateway connectivity"
if ! ping -c "${CONNECTION_RETRY_COUNT}" "$VXLAN_GATEWAY_IP"; then
    echo "ERROR: Gateway not reachable" >&2
    exit 1
fi

echo "Network setup complete - pod can start"
exit 0