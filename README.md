## Learnings / Design Decisions
- Chose multi-node kind cluster over single-node to observe real pod scheduling and node-failure behavior
- Tested livenessProbe failure scenario live: broke the probe intentionally (bad port),
  observed CrashLoopBackOff with exponential backoff, then fixed it
- Verified HPA scale-up/scale-down behavior under synthetic load; confirmed the
  replica calculation formula: ceil(currentReplicas × currentMetric/targetMetric)
- minReplicas=2 chosen for HA — but confirmed via testing that pod anti-affinity
  (topologySpreadConstraints) is still needed for a real node-failure guarantee
- Hit a scheduling deadlock combining topologySpreadConstraints (DoNotSchedule) with
  RollingUpdate's default maxSurge: during the transient window where surge pods
  temporarily exceed the skew limit, the new pod stayed Pending indefinitely.
  Switched to whenUnsatisfiable: ScheduleAnyway — tolerates the rollout's temporary
  imbalance while still preferring even distribution, self-corrects once surge resolves.
- Port 80 was already bound by Docker Desktop's own processes (com.docker.backend.exe,
  wslrelay.exe) on Windows/WSL2 — remapped kind's extraPortMappings to 8080/8443 instead
  of fighting the OS-level conflict
- Observed ingress-nginx-controller scheduling is non-deterministic between control-plane
  and worker nodes — the kind manifest only tolerates the control-plane taint, it doesn't
  force placement there
