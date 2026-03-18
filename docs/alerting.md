# Alertmanager — Discord webhook setup

Alertmanager is deployed via kube-prometheus-stack. The routing config is in
`apps/monitoring/application.yaml` under `alertmanager.config`. Alerts are
routed to a Discord webhook via the `alertmanager-discord` bridge.

---

## Architecture

```
Prometheus → fires alert → Alertmanager → HTTP POST → alertmanager-discord → Discord webhook → Discord channel
```

The `alertmanager-discord` bridge (image: `benjojo/alertmanager-discord`) translates
Alertmanager's webhook payload into Discord embeds.

---

## Setup steps

### 1. Create a Discord webhook

1. Open your Discord server → channel settings → Integrations → Webhooks
2. Click **New Webhook**, give it a name (e.g. `Homelab Alerts`)
3. Copy the webhook URL

### 2. Store the webhook URL as a sops secret

Add the webhook URL to `secrets/secrets.yaml`:

```bash
# Edit secrets (Windows — Git Bash):
SOPS_AGE_KEY_FILE="/c/Users/DavidD/.config/sops/age/keys.txt" \
  /c/Users/DavidD/AppData/Local/Temp/sops.exe secrets/secrets.yaml
```

Add under the existing keys:

```yaml
discord:
  webhookUrl: https://discord.com/api/webhooks/YOUR_WEBHOOK_URL
```

### 3. Create the alertmanager-discord Kubernetes Secret

Create `apps/monitoring/manifests/discord-secret.yaml` and encrypt it:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-discord-secret
  namespace: monitoring
stringData:
  webhook-url: REPLACE_WITH_WEBHOOK_URL
```

Encrypt after creation:

```bash
SOPS_AGE_KEY_FILE="/c/Users/DavidD/.config/sops/age/keys.txt" \
  /c/Users/DavidD/AppData/Local/Temp/sops.exe --encrypt --in-place \
  apps/monitoring/manifests/discord-secret.yaml
```

### 4. Deploy the alertmanager-discord bridge

Create `apps/monitoring/manifests/alertmanager-discord.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alertmanager-discord
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: alertmanager-discord
  template:
    metadata:
      labels:
        app: alertmanager-discord
    spec:
      containers:
        - name: alertmanager-discord
          image: benjojo/alertmanager-discord:latest
          ports:
            - containerPort: 9094
          env:
            - name: DISCORD_WEBHOOK
              valueFrom:
                secretKeyRef:
                  name: alertmanager-discord-secret
                  key: webhook-url
          resources:
            requests:
              cpu: 10m
              memory: 32Mi
            limits:
              cpu: 50m
              memory: 64Mi
---
apiVersion: v1
kind: Service
metadata:
  name: alertmanager-discord
  namespace: monitoring
spec:
  selector:
    app: alertmanager-discord
  ports:
    - port: 9094
      targetPort: 9094
```

### 5. Commit and push

ArgoCD will automatically deploy the bridge. Alertmanager will route
`critical` and `warning` alerts to the Discord channel.

---

## Testing

Send a test alert manually:

```bash
# Port-forward Alertmanager
kubectl -n monitoring port-forward svc/alertmanager-operated 9093

# Trigger a test alert (in another terminal)
curl -XPOST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {"alertname": "TestAlert", "severity": "warning"},
    "annotations": {"summary": "Test alert from curl"}
  }]'
```

---

## Current status

- Alertmanager: deployed, routing config set
- alertmanager-discord bridge: **TODO — deploy before first boot (issue #18)**
- Discord webhook URL: **TODO — add to secrets/secrets.yaml (issue #18)**
