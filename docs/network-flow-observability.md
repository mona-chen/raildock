# Service connection activity

RailDock measures sampled direct TCP traffic between linked services on the same Docker host. Open **Servers → a server → Service connections** to configure collection. Collection is enabled by default with live-only retention; an explicitly disabled server stays disabled. Historical minute aggregates can be retained for 1–30 days. Changing to live-only deletes retained samples at cleanup; cleanup still runs while collection is off.

The canvas **Network flow** control changes animation independently from collection and links to server settings. Pulses indicate a byte increase in the last sample, not individual packets. Green travels from source to target; blue travels back. Reduced-motion preferences suppress movement. Hidden browser tabs stop live polling and movement. Motion is limited to 40 edges; other edges still expose counters. Selecting an edge shows counts, timing, last observed activity and recent retained minute history.

## Measurement and limitations

The host script inventories running Docker containers, including app replicas and worker processes and Dokku datastores. It maps unique container IPs to services and reads TCP_INFO via `nsenter --net -- ss -HtinOe state established` from each source namespace. TCP `bytes_sent` and `bytes_received` deltas determine direction. A socket cookie combined with container identity prevents socket/IP/port reuse from being counted as new activity. The first observation only establishes a baseline; old lifetime byte counts never create pulses.

This is sampled TCP visibility, not packet capture or a complete flow ledger. Connections that open and close between samples can be missed. UDP, Unix-domain sockets, host/shared namespaces, indirect proxy/NAT addresses and ambiguous container IP mappings are not covered. Missing permissions, tools or containers produce unavailable telemetry, not measured zero. An idle socket can remain connected without transferring data. Traffic is not evidence that an application request or query succeeded.

Live canvases request a sample about every 10 seconds; background sampling runs every minute. Samples older than 25 seconds never animate. Root SSH, Linux 5+, Python 3, nsenter and a modern ss/iproute2 are required. No packages, agents, kernel programs, firewall rules or sysctls are installed or modified. Disabling collection stops host sampling, including canvas-triggered sampling. The last host counter baseline contains hashed socket identities and counts, not addresses or payloads, and is replaced on subsequent collection.

## Resource bounds and privacy

One Docker inventory per host, up to 32 linked source containers, 500 links, 10,000 retained socket counters, a four-MiB subprocess output limit and an eight-second namespace traversal budget. A PostgreSQL advisory lock and nine-second freshness window coalesce concurrent canvases. Exceeded budgets are unavailable. History uses minute aggregates, not per-request records; storage grows with links, sampling windows and retention. Defaults produce no historical rows. The canvas pauses queries in hidden tabs.

A small isolated Linux smoke test with two existing-image containers detected traffic, then stopped reporting activity when the sender paused; the baseline sample took about 35 ms wall time on that host. This is a functional smoke result, not a production overhead guarantee. Larger socket tables and many source namespaces cost more; the time/output limits cap the work and failures remain explicit. Payloads, raw socket IPs and ports never leave the host or enter the control database.

## Research

- [ss manual](https://www.man7.org/linux/man-pages/man8/ss.8.html): internal TCP information and socket counters.
- [Linux TCP_INFO definition](https://github.com/torvalds/linux/blob/master/include/uapi/linux/tcp.h): per-connection byte counters.
- [Conntrack accounting](https://docs.kernel.org/6.2/networking/nf_conntrack-sysctl.html): an alternative requiring host accounting configuration; not silently enabled.
- [Hubble internals](https://docs.cilium.io/en/stable/internals/hubble/): continuous eBPF visibility integrated with Cilium. Adding that networking stack would be disproportionate for this first Docker/Dokku implementation. A future optional event-based collector could cover short-lived TCP and UDP flows; this sampler must not claim that coverage.
