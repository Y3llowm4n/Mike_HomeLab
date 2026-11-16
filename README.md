# Mike_HomeLab

This repository contains my Talos Kubernetes homelab.

The cluster is deployed with GitOps using Argo CD. The top-level Helm chart in `chart/` contains the list of
all applications deployed on the cluster, so `chart/values.yaml` is the overview of everything that runs.
For every enabled app, the chart generates an Argo CD `Application` that points to that app's chart in
`products/`. Apps are organized in groups (core, connectivity, storage, media, apps) to easily distinguish
their function.

The Talos nodes are configured by applying patches on top of the default Talos configuration. The
`talos/render.sh` script builds the full machine config per node from the defaults, the cluster secrets
and these patches.

## Cluster

| Node     | IP             | Role          | Kubernetes node name |
|----------|----------------|---------------|----------------------|
| chimchar | 192.168.178.66 | control plane | talos-wtc-thh        |
| piplup   | 192.168.178.67 | worker        | talos-k9k-j4c        |

- Talos v1.13.6, Kubernetes v1.35.0
- Image factory schematic `613e1592…` (extensions: `iscsi-tools`, `util-linux-tools`, required for Longhorn)
- Storage: Longhorn, data in `/var/mnt/longhorn` on the EPHEMERAL partition

## Repository structure

```
bootstrap/
  root-app.yaml            # root Argo CD app ("homelab"), applied manually once; renders chart/
chart/                     # generates one Argo CD Application per product
  values.yaml              # the list of all products: group, deploy, namespace, serverSideApply
  templates/applications.yaml
products/
  <group>/<product>/       # Helm chart + values of one application
talos/
  cluster.yaml             # patches for every node
  controlplane.yaml        # patches for control plane nodes only
  longhorn.yaml            # kubelet mount for Longhorn (every node)
  nodes/<node>.yaml        # node-specific patches (install disk, ...)
  render.sh                # renders talos/rendered/<node>.yaml
```

## Adding an application

1. Create a chart in `products/<group>/<product>/` (`Chart.yaml`, `values.yaml`, optional `templates/`).
2. Add it to `chart/values.yaml`:

   ```yaml
   products:
     media:
       my-app:
         deploy: true
         namespace: media          # optional, defaults to the product name
         serverSideApply: true     # optional, needed for charts with large CRDs
   ```

3. Merge to `main`. Argo CD creates the Application automatically.

The Application path defaults to `products/<group>/<product>`; set `path:` only for exceptions.
### Removing an application

Set `deploy: false` (or remove the entry). This only deletes the Argo CD Application: the generated
Applications have no `resources-finalizer`, so the app's resources keep running as orphans. Clean them
up manually:

```bash
kubectl delete namespace <namespace>                       # everything, including PVCs and their data
kubectl -n <namespace> delete deployment,service --all     # stop the app, keep the PVCs
```

This is deliberate: with a finalizer, a typo in an app name would delete all of that app's resources.

**Be careful with namespaces:** changing an app's `namespace` makes Argo CD create everything in the new
namespace and prune the old one, including PVCs (data loss). SealedSecrets must also be resealed for the
new namespace.

## Changing the Talos configuration

```bash
cd talos
./render.sh                                                               # render all nodes
talosctl -n <ip> apply-config -f rendered/<node>.yaml --dry-run           # review diff + reboot yes/no
talosctl -n <ip> apply-config -f rendered/<node>.yaml --mode=no-reboot    # apply (worker first)
```

`--mode=no-reboot` refuses the change if it needs a reboot instead of rebooting the node.

## Not in Git

| File                   | What                                          | Where it lives                    |
|------------------------|-----------------------------------------------|-----------------------------------|
| `talos/secrets.yaml`   | cluster CAs, keys and tokens                  | password manager + backup         |
| `talos/live/`          | configs pulled from the nodes (contain keys)  | local only                        |
| `talos/rendered/`      | generated configs (contain keys)              | local only, regenerate with `render.sh` |
| `talosconfig`, `kubeconfig` | admin credentials                        | `Documents/KubeHost`              |
| sealed-secrets key     | decrypts all SealedSecrets in this repo       | password manager + backup         |

## Rebuilding the cluster

> Not tested end-to-end yet.

1. **Talos:** restore `talos/secrets.yaml`, run `./render.sh`, then install each node:
   `talosctl apply-config --insecure -n <ip> -f rendered/<node>.yaml`
2. **Bootstrap etcd** (once, on chimchar): `talosctl bootstrap -n 192.168.178.66`, then
   `talosctl kubeconfig -n 192.168.178.66`
3. **Sealed-secrets key:** `kubectl create namespace sealed-secrets` and
   `kubectl apply -f sealed-secrets-key.yaml`, before the controller starts, so existing SealedSecrets
   can be decrypted
4. **Argo CD:** install it once by hand:
   `helm dependency build products/core/argocd && helm install argocd products/core/argocd -n argocd --create-namespace`
5. **Root app:** `kubectl apply -f bootstrap/root-app.yaml`. Argo CD now deploys everything else,
   including itself.
6. **Data:** restore Longhorn volumes from backup.
