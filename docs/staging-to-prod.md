# Switching from Staging to Production TLS

## Current state

All ingresses use `letsencrypt-staging` as their `cert-manager.io/cluster-issuer`.
Staging certificates are issued by the Let's Encrypt Staging CA — browsers show
an "untrusted certificate" warning but the TLS handshake works. This lets us
verify the full cert-issuance flow without hitting Let's Encrypt rate limits.

## When to switch

Switch to production **after** all of these are true:

- [ ] All nodes deployed and Ready
- [ ] ArgoCD syncing all apps (no red apps in UI)
- [ ] All ingresses reachable (HTTP → HTTPS redirect works)
- [ ] Staging certificates issued successfully for all domains
- [ ] DNS pointing to your MetalLB IP for all domains
- [ ] No rate-limit concerns (you haven't failed many cert requests)

## How to verify staging certs are working

```bash
# Check all Certificate resources
kubectl get certificates -A

# All should show READY=True
# NAME                    READY   SECRET               AGE
# vaultwarden-tls         True    vaultwarden-tls      5m
# ghost-tls               True    ghost-tls            5m
# ...

# Check a specific cert
kubectl describe certificate vaultwarden-tls -n vaultwarden

# Verify the cert issuer is staging
kubectl get secret vaultwarden-tls -n vaultwarden -o jsonpath='{.data.tls\.crt}' \
  | base64 -d | openssl x509 -noout -issuer
# Should show: issuer=CN=(STAGING) Let's Encrypt ...
```

## Switching to production

### Option A — Per-app (recommended, one at a time)

Edit each app's ingress or Helm values to change the cluster-issuer:

```yaml
# In each app's Helm values or Ingress annotation:
cert-manager.io/cluster-issuer: letsencrypt-prod  # was: letsencrypt-staging
```

Start with a low-traffic app to verify the flow, then switch the rest.

### Option B — Global sed (all at once)

```bash
# In the repo root:
grep -rl "letsencrypt-staging" apps/ | xargs sed -i 's/letsencrypt-staging/letsencrypt-prod/g'

# Verify the changes
grep -r "letsencrypt-" apps/

# Commit and push — ArgoCD will sync and cert-manager will re-issue
git add apps/
git commit -m "feat: switch all ingresses to letsencrypt-prod"
git push
```

### After switching

ArgoCD will sync the updated ingresses. cert-manager will:
1. Detect the issuer changed
2. Delete the old staging certificate
3. Request a new certificate from Let's Encrypt production
4. Store the new cert in the same Kubernetes Secret

This takes ~30-120 seconds per certificate. Monitor with:

```bash
# Watch certificate issuance
kubectl get certificates -A -w

# Check cert-manager logs if a cert fails
kubectl logs -n cert-manager deploy/cert-manager -f

# Check CertificateRequest status
kubectl get certificaterequests -A
```

## Reverting to staging

If something goes wrong with production certs:

```bash
grep -rl "letsencrypt-prod" apps/ | xargs sed -i 's/letsencrypt-prod/letsencrypt-staging/g'
git add apps/ && git commit -m "revert: switch back to letsencrypt-staging" && git push
```

## Let's Encrypt rate limits

Production issuer is subject to [Let's Encrypt rate limits](https://letsencrypt.org/docs/rate-limits/):
- 50 certificates per registered domain per week
- 5 duplicate certificates per week

For a homelab with ~10 subdomains this is not a concern.
Staging has much higher limits — use it freely for testing.

## DNS-01 challenge (Cloudflare)

cert-manager uses DNS-01 via Cloudflare for wildcard support and private IP ranges.
The Cloudflare API token is in `secrets/secrets.yaml` under `cloudflare.apiToken`.

If DNS-01 challenges fail:
```bash
# Check ClusterIssuer status
kubectl describe clusterissuer letsencrypt-prod

# Check ACME challenges
kubectl get challenges -A

# Check cert-manager can reach Cloudflare API
kubectl logs -n cert-manager deploy/cert-manager | grep -i cloudflare
```
