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
- Migrated raw manifests to a Helm chart (hello-app) as the final Faz 2 step:
  values.yaml now drives replicas, image, resources, probes, ingress host,
  HPA thresholds, and NetworkPolicy scope — no more hardcoded YAML
- Hit a chart-breaking bug: helm create's default NOTES.txt referenced
  .Values.httpRoute.enabled (Gateway API scaffold), which isn't defined in
  our values.yaml -> nil pointer error on `helm lint`. Rewrote NOTES.txt to
  match our actual Ingress-based setup and dropped the unused httproute.yaml
  template (Gateway API is out of scope for this phase)
- Learned the toYaml/nindent pattern for templatizing resource blocks: `with`
  changes template context to `.`, `toYaml` serializes the values.yaml map,
  `nindent N` re-indents it under the parent key without manual newline math
- Verified the migration didn't break anything: deleted the manually
  kubectl-applied resources, ran `helm install`, confirmed all objects came
  up under `app.kubernetes.io/managed-by: Helm`, and re-ran the curl test
  through ingress-nginx successfully

## Setup

1. Create the cluster (default CNI disabled — required for NetworkPolicy support):
   kind create cluster --name devops-lab --config kind-config.yaml

2. Install Calico CNI (kind's default `kindnet` does NOT enforce NetworkPolicy):
   kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.0/manifests/calico.yaml
   kubectl get nodes -w   # wait for all nodes Ready

3. Install the Ingress controller (pinned to control-plane node — see incident notes):
   kubectl apply -f ingress-nginx-controller.yaml

4. Deploy the app stack via Helm (deployment, service, HPA, ingress, and
   NetworkPolicy are all templated in this chart — see hello-app/values.yaml):
   helm install hello-app ./hello-app --namespace lab-app --create-namespace

5. Verify:
   helm status hello-app -n lab-app
   kubectl get all -n lab-app
   curl http://localhost:8080 -H "Host: hello-app.local"

### Upgrading / changing config
   # edit hello-app/values.yaml, then:
   helm upgrade hello-app ./hello-app -n lab-app

### Uninstalling
   helm uninstall hello-app -n lab-app

## Provisioning AWS EKS with Terraform
- State: S3 backend with native Terraform 1.10+ locking (`use_lockfile = true`), no DynamoDB table needed.
- Module structure: separate `modules/vpc` and `modules/eks`, composed from a root `main.tf`.
- Networking: 2 public + 2 private subnets across 2 AZs, worker nodes in private subnets, single NAT Gateway (cost trade-off — one NAT instead of per-AZ).
- EKS managed node group (t3.medium x2) instead of self-managed nodes or Fargate.
- NetworkPolicy enforcement via the VPC CNI's native support (`configuration_values = { enableNetworkPolicy = "true" }` on the `vpc-cni` addon) instead of installing Calico — but note the addon's config schema key is `enableNetworkPolicy` at the top level, **not** `env.ENABLE_NETWORK_POLICY` as older docs/examples suggest; also required pinning a recent `addon_version` since the account's default vpc-cni version predated the option entirely.
- Infra/app split: Terraform provisions only infrastructure (VPC, EKS, node group, IAM, addons). `ingress-nginx` and the `hello-app` Helm chart are installed separately via `helm install`, same as on kind.
- Hit an AWS account-level restriction blocking all Elastic Load Balancer creation (`OperationNotPermitted: This AWS account currently does not support creating load balancers`) — unrelated to Terraform/K8s config, needs an AWS Support case to lift. Worked around it for verification by setting the ingress-nginx Service to `ClusterIP` and using `kubectl port-forward` (tunnels through the EKS API server, not a direct network path — no LB required to validate the Ingress → Service → Pod chain).
- EKS Console's "Resources" tab uses a separate authorization layer (Access Entries), independent of `kubectl`'s access (which works via the classic cluster-creator grant). Needed `aws eks update-cluster-config --access-config authenticationMode=API_AND_CONFIG_MAP` plus an explicit access entry + `AmazonEKSClusterAdminPolicy` association to unlock it. Also: the AWS root user is a different IAM principal from an IAM user for this purpose — console access must be granted to whichever identity is actually logged in.
- Full stack verified end-to-end on real EKS infra: 2 nodes Ready, ingress-nginx + hello-app deployed via Helm, `curl -H "Host: hello-app.local"` returning 200 through the ingress controller.

## Notes
- Host port 8080/8443 used instead of 80/443 — Docker Desktop on Windows/WSL2
  binds 80 internally (com.docker.backend.exe, wslrelay.exe)
- NetworkPolicy requires Calico — default kindnet CNI silently no-ops NetworkPolicy objects
- App stack (deployment/service/hpa/ingress/networkpolicy) is Helm-managed as of
  this commit — don't `kubectl apply` the files under legacy-manifests/, they'll
  conflict with Helm's ownership of those resources
- Ingress controller itself is still raw-applied (kubectl), not part of the
  Helm chart — it's cluster infrastructure, not application config

