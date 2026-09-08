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

## Setup

1. Create the cluster (default CNI disabled — required for NetworkPolicy support):
   kind create cluster --name devops-lab --config kind-config.yaml

2. Install Calico CNI (kind's default `kindnet` does NOT enforce NetworkPolicy):
   kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.0/manifests/calico.yaml
   kubectl get nodes -w   # wait for all nodes Ready

3. Deploy the app stack:
   kubectl create namespace lab-app
   kubectl apply -f deployment.yaml
   kubectl apply -f service.yaml
   kubectl apply -f hpa.yaml

4. Install Ingress controller (pinned to control-plane node — see incident notes):
   kubectl apply -f ingress-nginx-controller.yaml
   kubectl apply -f ingress.yaml

5. Apply NetworkPolicy (requires step 2 — Calico):
   kubectl apply -f networkpolicy.yaml

6. Verify:
   curl http://localhost:8080 -H "Host: hello-app.local"

## Notes
- Host port 8080/8443 used instead of 80/443 — Docker Desktop on Windows/WSL2
  binds 80 internally (com.docker.backend.exe, wslrelay.exe)
- NetworkPolicy requires Calico — default kindnet CNI silently no-ops NetworkPolicy objects