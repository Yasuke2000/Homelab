# TLS / cert-manager setup

## Overzicht

cert-manager v1.20 beheert automatisch TLS-certificaten via Let's Encrypt.
De cluster heeft twee ClusterIssuers:

| Issuer | Gebruik | Rate limit |
|--------|---------|------------|
| `letsencrypt-staging` | Testen — niet vertrouwd door browsers | Vrijwel onbeperkt |
| `letsencrypt-prod` | Productie — vertrouwd door browsers | **5 certificaten per domein per week** |

**Regel: altijd eerst staging, dan pas overstappen op prod.**

---

## HTTP-01 vs DNS-01 — kies de juiste voor jouw setup

De cluster-issuer gebruikt nu **HTTP-01**. Dit heeft consequenties:

### HTTP-01 (huidige config)
- Let's Encrypt plaatst een challenge-token op `http://jouwdomein.com/.well-known/acme-challenge/...`
- **Vereist**: poort 80 toegankelijk vanaf het internet → port forwarding op je router naar `10.0.20.100`
- **Werkt niet** voor wildcard certs (`*.jouwdomein.com`)
- **Werkt niet** als je geen publiek IP hebt (CGNAT) of poort 80 geblokkeerd is door je ISP

### DNS-01 (aanbevolen voor homelab)
- Let's Encrypt valideert via een TXT-record in je DNS
- **Vereist** poort 80/443 **NIET** — perfect voor interne services
- **Ondersteunt wildcards**: één certificaat voor `*.jouwdomein.com` → alle subdomains gedekt
- Werkt met Cloudflare (gratis DNS + API), Route53, Hetzner DNS, etc.

### Aanbeveling: koop je domein bij Cloudflare
Cloudflare biedt gratis DNS-beheer en heeft een native cert-manager integratie:
- Geen port forwarding nodig
- Wildcard cert voor alle services in één keer
- Goedkoop: `.com` ~$10/jaar, `.be` ~$7/jaar, `.nl` ~$5/jaar

**Als je Cloudflare kiest, zie [Overstap naar DNS-01](#overstap-naar-dns-01-cloudflare) onderaan.**

---

## Vereisten voor HTTP-01 (huidige setup)

1. **Publiek domein gekocht** (bv. via Namecheap, Cloudflare, TransIP)
2. **A-record** aangemaakt: `*.jouwdomein.com → jouw publiek IP`
   - Of aparte A-records per subdomain
3. **Port forwarding** op je UniFi gateway:
   - Extern poort 80 → `10.0.20.100` (MetalLB Traefik IP) poort 80
   - Extern poort 443 → `10.0.20.100` poort 443
4. **Email** ingevuld in `apps/cert-manager/cluster-issuer.yaml`

---

## Setup stappen

### Stap 1 — Email invullen

```bash
# apps/cert-manager/cluster-issuer.yaml — vervang op BEIDE issuers:
email: jij@jouwdomein.com
```

Commit en push. ArgoCD past de ClusterIssuers automatisch aan.

### Stap 2 — Domein instellen in alle manifests

```bash
# Vervang daviddelporte.com door jouw domein in de hele repo (eenmalig):
find apps -name "*.yaml" -exec sed -i 's/yourdomain\.com/JOUWDOMEIN.com/g' {} +

# Controleer wat er veranderd is:
git diff --stat
git diff
```

### Stap 3 — DNS records aanmaken

Maak A-records aan bij je DNS-provider:

```
# Optie A: wildcard (één record voor alles)
*.jouwdomein.com    A    JOUW_PUBLIEK_IP

# Optie B: individuele records
jouwdomein.com          A    JOUW_PUBLIEK_IP
vault.jouwdomein.com    A    JOUW_PUBLIEK_IP
argocd.jouwdomein.com   A    JOUW_PUBLIEK_IP
grafana.jouwdomein.com  A    JOUW_PUBLIEK_IP
# ... enzovoort voor alle services
```

Verifieer propagatie (kan tot 24u duren, meestal < 5 min bij Cloudflare):
```bash
dig +short jouwdomein.com
dig +short vault.jouwdomein.com
```

### Stap 4 — Port forwarding (HTTP-01 only)

Op je UniFi controller:
- **Destination**: `10.0.20.100` (MetalLB IP van Traefik)
- Poort 80 → 80 (nodig voor ACME HTTP-01 challenge en HTTP→HTTPS redirect)
- Poort 443 → 443

### Stap 5 — Testen met staging

Alle ingresses staan al op `letsencrypt-staging`. Deploy de cluster en controleer:

```bash
# Certificaat status bekijken
kubectl get certificate -A

# Gedetailleerde status (zoek naar Ready: True of foutmelding)
kubectl describe certificate -A

# Als het lang duurt: bekijk de CertificateRequest en Order
kubectl get certificaterequest -A
kubectl get order -A
kubectl describe order -A | tail -30

# Logs van cert-manager zelf
kubectl -n cert-manager logs -l app=cert-manager --tail=50
```

Een staging cert ziet er zo uit in de browser: "niet vertrouwd" met issuer
`(STAGING) Let's Encrypt`. Dat is correct — het validatieproces werkt.

### Stap 6 — Overstappen op productie

Zodra staging-certs aangemaakt worden (alle certificaten `READY: True`):

```bash
# Wissel ALLE ingresses van staging naar prod:
find apps -name "*.yaml" -exec sed -i \
  's|letsencrypt-staging|letsencrypt-prod|g' {} +

git add -A
git commit -m "feat: switch all ingresses to letsencrypt-prod"
git push
```

ArgoCD past alles automatisch aan. cert-manager vraagt nieuwe certificaten aan.

```bash
# Verifieer prod-certs (duurt 1-2 minuten per cert):
watch kubectl get certificate -A
```

---

## Overstap naar DNS-01 (Cloudflare)

Als je domein bij Cloudflare staat, is dit de betere aanpak voor een homelab.

### 1. Cloudflare API token aanmaken

In Cloudflare dashboard → My Profile → API Tokens → Create Token:
- Template: "Edit zone DNS"
- Zone Resources: Include → Specific zone → jouwdomein.com
- Kopieer de token

### 2. Token als K8s secret opslaan

```bash
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token=CF_TOKEN_HIER
```

Voeg ook toe aan `secrets/secrets.yaml`:
```yaml
cloudflare:
  apiToken: REPLACE_WITH_CF_API_TOKEN
```

En aan `scripts/create-k8s-secrets.sh`:
```bash
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token="$(get 'cloudflare.apiToken')" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 3. ClusterIssuers aanpassen voor DNS-01

```yaml
# apps/cert-manager/cluster-issuer.yaml — vervang de solvers sectie:
solvers:
  - dns01:
      cloudflare:
        apiTokenSecretRef:
          name: cloudflare-api-token
          key: api-token
```

### 4. Wildcard certificaat toevoegen (optioneel maar handig)

```yaml
# apps/cert-manager/wildcard-certificate.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-tls
  namespace: cert-manager
spec:
  secretName: wildcard-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - "jouwdomein.com"
    - "*.jouwdomein.com"
```

Dan in elke Ingress:
```yaml
tls:
  - secretName: wildcard-tls   # centraal cert, één voor alle subdomains
    hosts:
      - "*.jouwdomein.com"
```

---

## Veelvoorkomende fouten

### Certificate blijft op `False` / `False`

```bash
kubectl describe certificate <naam> -n <namespace>
kubectl describe order <naam> -n <namespace>
```

Oorzaken:
- DNS-record bestaat nog niet → wacht op propagatie, check met `dig`
- Poort 80 niet open → test met `curl http://jouwdomein.com`
- Email niet ingevuld in cluster-issuer → check `kubectl get clusterissuer -o yaml`

### `too many certificates already issued`

Je zit op de Let's Encrypt prod rate limit (5/week).
Oplossing: gebruik staging totdat alles werkt.

### `certificate not yet due for renewal`

cert-manager verlengt certificaten automatisch 30 dagen voor verlopen.
Dit is geen fout — het werkt zoals bedoeld.

### Staging-cert verwijderen na overstap naar prod

```bash
# cert-manager maakt automatisch nieuwe prod-certs aan na de annotatie-wissel
# Oude staging secrets kun je handmatig opruimen:
kubectl delete secret <cert-secretname> -n <namespace>
# cert-manager maakt ze opnieuw aan met prod-cert
```

---

## Huidige staat van de repo

- Alle ingresses: `letsencrypt-staging` ✅ (veilig voor eerste deploy)
- Email: `you@daviddelporte.com` — **TODO: aanpassen**
- Domein: `daviddelporte.com` — **TODO: vervangen zodra domein gekocht**
- Challenge methode: HTTP-01 — **overweeg DNS-01 als je Cloudflare gebruikt**
