## Learnings / Design Decisions
- Chose multi-node kind cluster over single-node to observe real pod scheduling and node-failure behavior
- Tested livenessProbe failure scenario live: broke the probe intentionally (bad port),
  observed CrashLoopBackOff with exponential backoff, then fixed it
- Verified HPA scale-up/scale-down behavior under synthetic load; confirmed the
  replica calculation formula: ceil(currentReplicas × currentMetric/targetMetric)
- minReplicas=2 chosen for HA — but confirmed via testing that pod anti-affinity
  (topologySpreadConstraints) is still needed for a real node-failure guarantee