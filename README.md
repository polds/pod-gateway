# pod-gateway

This container includes scripts used to route trafic from pods through another gateway pod. Typically
the gateway pod then runs a openvpn client to forward the traffic.

This container is injected by the [gateway-admision-controller](../../../gateway-admision-controller)
so that existing K8S PODs can be extended to route their trafic through a VPN. Check the
[README](../../../gateway-admision-controller/blob/main/README.md) to learn how to use it.

The connection between the pods is done via a vxlan. The gatway provides a DHCP server to let client
pods to get automatically an IP.

Outgoing traffic is masqueraded (SNAT). It is also possible to define port forwardind so ports of client
pods can be reached from the outside.

The [.github](.github) folder will get PRs from this template so you can apply the latest workflows.

## Design

Client PODs are connected through a tunnel to the gateway POD and route default traffic and DNS queries
through it. The tunnel is implemented as VXLAN overlay.

This container provides the required init/sidecar containers for clients and gateway PODs:

- client PODs connecting through gateway POD:
  - [client_init.sh](bin/client_init.sh): starts the VXLAN tunnel and change the default gateway
     in the POD. It can get its IP via DHCP or use an static IP within the VXLAN (needed for port)
     forwarding.
  - [client_sidecar.sh](bin/client_sidecar.sh): periodically checks connection to the gateway is still
     working. Reset the vxlan if this is not the case. This happens, for example, when the gateway POD
     is restarted and it gets a new IP from K8S.
- gateway POD:
  - [gateway_init.sh](bin/gateway_init.sh): creates the VXLAN tunnel and set traffic forwading rules.
     Optionally, if a VPN is used in the gateway, blocks non VPN outbound traffic.
   - [gateway_sidecar.sh](bin/gateway_sidecar.sh): deploys a DHCP and DNS server

Settings are expected in the `/config` folder - see examples under [config](config):

- [config/settings.sh](config/settings.sh): variables used by all helper scripts
- [config/nat.conf](config/nat.conf): static IP and nat rules for PODs exposing ports through the gateway (and optional VPN) POD
Default settings might be overwritten by attachin a container volume with the new values to the helper pods.

## Prereqs

You need to create the following secrets (not needed within the k8s-at-home org - there we use org-wide secrets):

- WORKFLOW_REPO_SYNC_TOKEN # Needed to do PRs that update the workflows
- GHCR_USERNAME # Needed to upload container to the Github Container Registry
- GHCR_TOKEN # Needed to upload container to the Github Container Registry

## How to build

1. Build the container

   ```bash
   make
   ```

Testing requires multiple containers - see the [gateway-admision-controller](../../../gateway-admision-controller)
and check the [Makefile](Makefile) for other build targets.


![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/polds/pod-gateway?utm_source=oss&utm_medium=github&utm_campaign=polds%2Fpod-gateway&labelColor=171717&color=FF570A&link=https%3A%2F%2Fcoderabbit.ai&label=CodeRabbit+Reviews)