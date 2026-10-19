# emplois-cnav-ops

Manifests Kubernetes et charts Helm pour le projet emplois-cnav (interconnexion Emplois <> CNAV).

## Structure du repository

```
emplois-cnav-ops/
├── .github/                        # Workflows GitHub Actions et leurs scripts
├── charts/
│   ├── api-relay/                  # Applicatif Django (API REST + backoffice publics)
│   ├── argocd/                     # ArgoCD + argocd-apps (gère toutes les Applications)
│   ├── authentik/                  # Authentik (SSO forward-auth via le SSO de la PDI)
│   ├── external-secrets/           # External Secrets Operator (gestion des secrets)
│   ├── ihm-web/                    # Interface d'administration
│   ├── interops-a/                 # Traitement et envoi vers CNAV
│   ├── interops-infra/             # Namespace + PVCs + NetworkPolicies + ExternalSecrets
│   ├── jetonv3/                    # Signature des messages SOAP
│   ├── reloader/                   # Stakater Reloader (rolling update au changement de secret)
│   └── traefik/                    # Traefik (wrapper du chart officiel)
└── README.md
```

## Namespaces

| Namespace | Contenu |
|-----------|---------|
| `argocd` | ArgoCD (GitOps) |
| `authentik` | Authentik (SSO, forward-auth) |
| `external-secrets` | External Secrets Operator |
| `reloader` | Stakater Reloader |
| `ingress` | Traefik (Ingress Controller) |
| `interops-integration` | Stack InterOPS integration |
| `interops-production` | Stack InterOPS production (après la VABF) |

## Valeurs sensibles

Ce repository est **public**. Les valeurs sensibles (IPs, credentials) ne doivent pas être commitées.

### Gestion via External Secrets Operator

Les secrets sensibles sont stockés dans **Scaleway Secret Manager** et synchronisés automatiquement dans Kubernetes
via **External Secrets Operator**.

- `cnav-vpn-config` : secret `vpn-config` dans chaque namespace `interops-*` (IPs strongswan).
- `api-relay-database-<env>` : credentials de la base PostgreSQL managée du backoffice.
- `api-relay-database-connection-<env>` : endpoint de la base PostgreSQL managée du backoffice.
- `api-relay-django-<env>` : env vars Django sensibles (`SECRET_KEY`, `SECRET_KEY_FALLBACKS`).

Tous ces secrets sont générés/gérés dans le repo [infrastructure](https://github.com/gip-inclusion/infrastructure).

### Valeurs sensibles chiffrées via SOPS

Les valeurs sensibles mais **non-secrètes** (ex: les ranges d'IPs de l'`ipAllowList` de l'API) sont chiffrées dans
le repo via **SOPS** (age) : `charts/*/values-<env>.enc.yaml`.

helm-secrets les déchiffre au moment où Helm rend le chart : tout fichier de values passé sous la forme
`-f secrets://<fichier>` est déchiffré à la volée. C'est le cas pour un déploiement manuel comme pour ArgoCD,
configuré ainsi :
- Le **repo-server** d'ArgoCD embarque sops + helm-secrets (init container) et l'ApplicationSet `api-relay` référence
  le fichier chiffré en `secrets://values-<env>.enc.yaml`
- Il déchiffre avec la **clé AGE du cluster** : sa clé publique est un recipient de `.sops.yaml` (`&argocd`), la clé
  privée ne vit que dans Scaleway Secret Manager (`argocd-sops-age-key`) et arrive sur le repo-server via
  l'ExternalSecret `helm-secrets-private-keys`

Après tout ajout/retrait de recipient : `make sops-rotate-keys`. La CI vérifie sans déchiffrer que chaque fichier est
bien chiffré, pour exactement les recipients de `.sops.yaml` (`.github/scripts/check_sops_files.py`).

#### Recréer ou faire tourner la clé AGE du cluster

Pour un nouveau cluster, ou si la clé privée a fuité.
La clé privée reste dans une variable du shell, jamais dans un fichier :

```bash
secret_id=$(scw secret secret list project-id=<emplois-cnav-project-id> name=argocd-sops-age-key -o json | jq -r '.[0].id')
key=$(age-keygen 2>/dev/null | grep '^AGE-SECRET-KEY-')
echo "$key" | age-keygen -y    # clé publique : remplace celle de `&argocd` dans .sops.yaml
scw secret version create secret-id="$secret_id" data="$(jq -nc --arg key "$key" '{age_key: $key}')"
unset key
make sops-rotate-keys
```

Ouvrir une PR avec `.sops.yaml` et les `*.enc.yaml` rechiffrés.
Une fois mergée, forcer la mise à jour du Secret (`refreshInterval` d'une heure) :
`kubectl -n argocd annotate externalsecret helm-secrets-private-keys force-sync=$(date +%s) --overwrite`.

Désactiver ensuite l'ancienne version : `scw secret version disable secret-id="$secret_id" revision=<n>`

Vérifier que la clé privée du secret correspond au recipient `&argocd` de `.sops.yaml` :

```bash
secret_id=$(scw secret secret list project-id=<emplois-cnav-project-id> name=argocd-sops-age-key -o json | jq -r '.[0].id')
scw secret version access secret-id="$secret_id" revision=latest_enabled -o json \
  | jq -r '.data' | base64 -d | jq -r '.age_key' | age-keygen -y
```

## Identifiants de ressources Scaleway

Certains charts référencent en dur des ressources Scaleway provisionnées **hors de ce repo** (Terraform,
repo [infrastructure](https://github.com/gip-inclusion/infrastructure)). Ce ne sont **pas des secrets**
(des identifiants, pas des credentials) : les committer est sans risque. Ils sont stables et figés en clair
faute de pouvoir être résolus au déploiement (ArgoCD rend les charts sans accès au state Terraform).

| Identifiant | Utilisé par | Source (repo `infrastructure`) |
|---|---|---|
| LB `fr-par-1/06893cb9-d7bc-4b9b-b477-b037d2ae45b0` | `traefik` (annotation `scw-loadbalancer-id`) | `emplois-cnav/network` → `scaleway_lb.traefik_lb` |
| Projet `183e4da2-b8da-480b-91ab-72a46e998a25` | `external-secrets` (ClusterSecretStore) | projet `emplois-cnav` |
| Secret `a79ba102-264a-40df-99b4-59447cfc514b` (cnav-vpn-config) | `interops-infra` (ExternalSecret VPN) | `emplois-cnav/secret-manager` |
| Secret `1433c432-475f-48c9-b38a-7da12faaf89d` (authentik) | `authentik` (ExternalSecret) | `emplois-cnav/secret-manager` |
| CIDR `10.252.0.0/20` | `interops-infra` (NetworkPolicy egress PostgreSQL) + `traefik` (`proxyProtocol.trustedIPs`) | `emplois-cnav/network` (subnet du Private Network) |

## Prérequis

- Accès au cluster Kubernetes `emplois-cnav-cluster`
- `kubectl` configuré avec le bon contexte
- `helm` >= 3.0
- `sops` + le plugin `helm-secrets` + la clé privée age (déchiffrement des `values-*.enc.yaml`, cf. section SOPS)

### Optionnels

- `kubie` pour gérer les contextes (https://github.com/kubie-org/kubie)
- `k9s` pour se balader sur le cluster (https://github.com/derailed/k9s)

## Installation

### 1. Configurer le kubeconfig

```bash
scw k8s kubeconfig get <cluster-id> > ~/.kube/emplois-cnav.yaml
export KUBECONFIG=~/.kube/emplois-cnav.yaml
```

Si vous avez un vault, préférez l'utilisation de sa CLI et/ou ses intégrations pour récupérer les valeurs sensibles
et ne pas les stocker en clair sur le disque.

### 2. Créer l'API key Scaleway pour le cluster

Une seule API key est utilisée pour :
- **External Secrets Operator** : lecture des secrets depuis Scaleway Secret Manager
- **Container Registry** : pull des images depuis le registry Scaleway

L'application IAM et la policy sont créées via Terraform, mais **l'API key elle-même est créée à la main**,
volontairement. Deux raisons :

1. **Pas de secret dans le state.** Le repo `infrastructure` s'interdit tout secret en clair dans le state Terraform.
   Or la ressource `scaleway_iam_api_key` y persiste sa `secret_key` et la variante *ephemeral* ne convient pas
   non plus puisqu'elle régénère une clé à chaque `apply`.
2. **C'est le credential *racine* du pipeline de secrets.** C'est cette clé qui permet à ESO de lire tous les autres
   secrets. Elle ne peut donc pas être livrée *via* ESO / Secret Manager (dépendance circulaire), et doit arriver en
   Secret Kubernetes brut, avant même qu'ESO tourne.

#### a) Créer l'API key via la console Scaleway

1. Aller sur [console.scaleway.com](https://console.scaleway.com) > IAM > Applications
2. Trouver l'application `emplois-cnav-kubernetes`
3. Créer une nouvelle API key pour cette application
4. Sauver temporairement l'Access Key et la Secret Key

#### b) Créer les secrets Kubernetes

```bash
# Secret pour External Secrets Operator
kubectl create namespace external-secrets
kubectl create secret generic scaleway-credentials \
  --namespace external-secrets \
  --from-literal=access-key=<SCW_ACCESS_KEY> \
  --from-literal=secret-key=<SCW_SECRET_KEY>

# Secret pour le Container Registry (dans chaque namespace applicatif ; interops-production après la VABF)
for ns in interops-integration; do
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret docker-registry scaleway-registry \
    --namespace=$ns \
    --docker-server=rg.fr-par.scw.cloud \
    --docker-username=nologin \
    --docker-password=<SCW_SECRET_KEY>
done
```

### 3. Bootstrap des composants d'infrastructure

Le chart ArgoCD dépend de CRDs installés par d'autres charts (ExternalSecret, IngressRoute).
Il faut donc installer les composants dans l'ordre suivant :

#### a) External Secrets Operator

```bash
helm dependency update ./charts/external-secrets
helm upgrade --install external-secrets ./charts/external-secrets --namespace external-secrets --create-namespace --wait
```

Il reste en attente que tout soit prêt (`--wait`). Dans un autre shell, rajouter les API keys Scaleway afin que
le secret store passe à l'état `READY` :

```bash
kubectl create secret generic scaleway-credentials \
  --namespace external-secrets \
  --from-literal=access-key=<ACCESS_KEY> \
  --from-literal=secret-key=<SECRET_KEY>
```

Possible de vérifier l'état avec `kubectl get clustersecretstore`


#### b) Traefik (Ingress Controller)

```bash
helm dependency update ./charts/traefik
helm upgrade --install traefik ./charts/traefik --namespace ingress --create-namespace --wait
```

#### c) Authentik (Identity Provider)

```bash
helm dependency update ./charts/authentik
helm upgrade --install authentik ./charts/authentik --namespace authentik --create-namespace --wait
```

#### d) ArgoCD

Prérequis : le secret `argocd-sops-age-key` doit avoir une version activée dans Secret Manager (cf.
[Recréer ou faire tourner la clé AGE du cluster](#recréer-ou-faire-tourner-la-clé-age-du-cluster)).
Sans elle, l'ExternalSecret `helm-secrets-private-keys` ne crée pas le Secret monté par le repo-server : le pod reste
en `ContainerCreating` et `helm upgrade --wait` finit en timeout.

La branche suivie par toutes les Applications est l'ancre `targetRevision` de `charts/argocd/values.yaml` : c'est
l'**unique** endroit où la changer.

Avant l'install, vérifier ce que la première synchronisation changera sur les ressources déjà déployées à la main
(`kubectl diff` fait un dry-run côté serveur, rien n'est appliqué) :

```bash
helm template api-relay ./charts/api-relay -n interops-integration \
  -f ./charts/api-relay/values-integration.yaml \
  -f secrets://./charts/api-relay/values-integration.enc.yaml | kubectl diff -n interops-integration -f -
```

```bash
helm dependency update ./charts/argocd

# 1. ArgoCD et ses CRD, sans les AppProject / Application / ApplicationSet d'argocd-apps : Helm vérifie que tous
#    les types de la release existent avant de créer quoi que ce soit, or les CRD du chart argo-cd sont des
#    templates de cette même release (pas un dossier crds/)
helm upgrade --install argocd ./charts/argocd --namespace argocd --create-namespace --wait \
  --set argocdapps.projects=null --set argocdapps.applications=null --set argocdapps.applicationsets=null

# 2. Les projets et les Applications, une fois les CRD présents. --reset-values : sans values en argument, Helm
#    reprendrait celles de l'étape 1
helm upgrade argocd ./charts/argocd --namespace argocd --reset-values --wait

# Récupérer le mot de passe admin initial
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Accéder à l'UI ArgoCD (optionnel, en attendant que l'Ingress soit configuré)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Ouvrir https://localhost:8080
```

ArgoCD se synchronisera automatiquement et déploiera :
- Lui-même (self-managed)
- Les composants d'infra restants (Reloader)
- Le namespace `interops-integration` avec ses PVCs, NetworkPolicies et ExternalSecrets
- Tous les composants applicatifs (ihm-web, jetonv3, interops-a, api-relay) en intégration

Rien n'est déployé en production avant la VABF (namespace `interops-production` compris).

### 4. Configuration Authentik (post-déploiement)

La configuration est **entièrement automatisée** via un Blueprint (`templates/blueprint-configmap.yaml`).

Le Blueprint crée automatiquement :
- La source OAuth/OIDC du **SSO de la PDI (Authentik également)** (avec property mapping + re-synchro à chaque login)
- Le Provider Proxy "Forward Auth Domain" (mode domain-level)
- Les Applications / tuiles de lancement (Interops Admin, API relay backoffice)
- La politique d'accès `@inclusion.gouv.fr`
- La configuration de l'Outpost embedded

Les credentials du SSO de la PDI (well-known URL, client id/secret) et le compte administrateur par défaut sont
injectés via le secret `authentik` (Secret Manager).

> Note : Authentik protège les **applications** (ihm-web, backoffice api-relay…) via forward-auth + le SSO de la PDI.
> Le login de l'**interface ArgoCD** est pour l'instant le compte admin local (`argocd-initial-admin-secret`).

#### a) Accéder à Authentik

1. Ouvrir https://auth.interops-a.inclusion.gouv.fr/

#### b) Vérifier la configuration automatique (Blueprint)

Le Blueprint a créé automatiquement :
- **Répertoire > Fédération & Connection Sociale** : `PDI SSO`
- **Applications > Fournisseurs** : `Forward Auth Domain`
- **Applications > Applications** : `Interops Admin`, `API relay backoffice`
- **Applications > Outposts** : `authentik Embedded Outpost` (lié au provider)

Si ces éléments n'apparaissent pas, aller dans **Système > Blueprints** et vérifier que "Forward Auth Setup"
est bien appliqué.

#### c) Protéger un service via annotation Traefik

Pour protéger n'importe quel service, ajouter cette annotation sur l'Ingress :

```yaml
annotations:
  traefik.ingress.kubernetes.io/router.middlewares: authentik-authentik-forwardauth@kubernetescrd
```

Le format est `<namespace>-<middleware-name>@kubernetescrd`.

**Services déjà configurés :**
- `traefik/templates/dashboard-ingressroute.yaml` : Traefik Dashboard
- `ihm-web/values.yaml` : ihm-web (integration et production)
- `api-relay` : backoffice (integration et production)

#### d) Vérification

```bash
# Authentik accessible
curl -I https://auth.interops-a.inclusion.gouv.fr

# Traefik dashboard redirige vers Authentik
curl -I https://traefik.interops-a.inclusion.gouv.fr
# Attendu : 302 redirect vers auth.interops-a.inclusion.gouv.fr
```

#### e) Ajouter un nouveau service protégé (résumé)

1. Ajouter l'annotation `traefik.ingress.kubernetes.io/router.middlewares: authentik-authentik-forwardauth@kubernetescrd`
   sur l'Ingress
2. C'est tout ! Le service se retrouve protégé par le SSO de la PDI

## Déploiement continu (api-relay)

Le cluster n'est pas joignable depuis la CI : elle ne déploie pas, elle **propose** le déploiement dans Git et
ArgoCD l'applique. La relecture de la pull request est le déclencheur.

1. Merge sur `main` de [api-relay-cnav](https://github.com/gip-inclusion/api-relay-cnav) → une fois sa CI verte, son
   workflow *Build image* pousse l'image `rg.fr-par.scw.cloud/emplois-cnav-registry/api-relay:<sha court>` (+ `latest`)
   et envoie un `repository_dispatch` (`api-relay-image`) à ce repo
2. Le workflow *Bump image* ouvre, ou met à jour, **une unique** pull request `bot/bump-api-relay-integration` qui
   épingle ce sha dans `charts/api-relay/values-integration.yaml`
   (`image.tag`, toujours entre guillemets : un sha comme `12e4567` est un float en YAML)
3. Relecture + merge → ArgoCD synchronise : le Job de migrations puis le rollout

La production sera promue dans un second temps.

Configuration GitHub :

| Où | Nom | Rôle |
|---|---|---|
| api-relay-cnav | secret `SCW_REGISTRY_SECRET_KEY` | API key de l'application IAM `emplois-cnav-api-relay-ci` |
| api-relay-cnav, emplois-cnav-ops | variable `DEPLOY_BOT_CLIENT_ID` (Client ID de l'App, pas son App ID), secret `DEPLOY_BOT_PRIVATE_KEY` | GitHub App installée sur emplois-cnav-ops seulement (Contents + Pull requests en écriture) |
| emplois-cnav-ops | variable `ARGOCD_TARGET_REVISION` | Branche de base des pull requests : doit valoir l'ancre `targetRevision` (vérifié par le workflow) |

## Mise à jour des images InterOPS (ihm-web, jetonv3, interops-a)

Les images InterOPS ne sont pas disponibles sur un registry mais sous la forme d'archives ZIP mises à disposition par
le GIP MDS, chacune contenant un `.tar.gz` dont l'image est nommée `sj:GIPMDS-2022-sj-<module>-<version>`.
On les republie dans notre registry avec la date de la version comme tag (`AAAA-MM-JJ`), puis on procède à la MAJ en
ouvrant une PR qui pin ce tag.

| Module livré | Image sur notre registry |
|---|---|
| `sj-ihm-web` | `sj-ihm-web` |
| `sj-jetonv3` | `sj-jetonv3` |
| `sj-passerelle-interops-a` | `sj-interops-a` |

```bash
archives=~/Downloads      # Là où les ZIP ont été décompressés
version=2026.10.14-1014   # Version livrée, utilisée dans le nom des archives
tag=2026-10-14            # Tag dans notre registry : calver comme eux (mais au format ISO et sans l'heure)

for module in ihm-web:ihm-web jetonv3:jetonv3 passerelle-interops-a:interops-a; do
  archive=sj-GIPMDS-2022-sj-${module%%:*}-$version
  image=rg.fr-par.scw.cloud/emplois-cnav-registry/sj-${module##*:}
  docker load < $archives/$archive/$archive.tar.gz
  docker tag sj:${archive#sj-} $image:$tag
  docker tag sj:${archive#sj-} $image:latest
  docker push $image:$tag
  docker push $image:latest
done
```

Puis, via une PR, épingler le tag dans `charts/<module-interops>/values-integration.yaml`.
`latest` suit la dernière livraison mais ne déploie rien : chaque environnement épingle sa version, la production
rattrape supposément le même tag une fois le déploiement validé en intégration.

## Charts Helm

### interops-infra

Crée le namespace, les PVCs, les ExternalSecrets et les NetworkPolicies pour un environnement.

```bash
# Integration
helm upgrade --install interops-integration ./charts/interops-infra \
  -f ./charts/interops-infra/values-integration.yaml

# Production (après la VABF)
helm upgrade --install interops-production ./charts/interops-infra \
  -f ./charts/interops-infra/values-production.yaml
```

### ihm-web

Interface web d'administration permettant de configurer les échanges InterOPS.
- **Exposition** : Via Traefik (HTTPS avec Let's Encrypt), forward-auth
- **Domaines** :
  - Integration : `admin.integration.interops-a.inclusion.gouv.fr`
  - Production : `admin.production.interops-a.inclusion.gouv.fr`
- **Volumes** : Config (RW), Logs (RW)

### jetonv3

Service de signature et d'encapsulation des messages SOAP.
- **Exposition** : Interne uniquement (appelé par interops-a)
- **Volumes** : Config (RO), Logs (RW)

### interops-a

Service principal qui reçoit les messages, les fait signer par jetonv3, et les transmet à la CNAV via le tunnel IPsec.
- **Exposition** : Interne uniquement (appelé par api-relay)
- **Volumes** : Config (RO), Logs (RW)
- **Egress** : Uniquement vers strongswan (IP spécifique par environnement)

### api-relay

Une seule image Django. `DJANGO_SERVICE` choisit le service servi par chaque pod.

#### Backoffice : derrière Traefik + Authentik forward-auth (admin Django uniquement pour l'instant)
- **Domaines** : `backoffice.relay.<env>.interops-a.inclusion.gouv.fr`
- **Exposition** : ClusterIP (Traefik termine le TLS, forward-auth Authentik)
- **Sondes** : `/healthcheck/live/` et `/healthcheck/ready/`
- **Secrets** : credentials DB (user DML-only) et `SECRET_KEY` via les ExternalSecrets `api-relay-database` / `api-relay-django`

#### API : API REST publique
- **Domaines** : `relay.<env>.interops-a.inclusion.gouv.fr`
- **Exposition** : ClusterIP derrière Traefik (LB partagé), filtrée par un middleware Traefik `ipAllowList`
- **Filtrage IP** : l'`ipAllowList` s'appuie sur le PROXY protocol (activé sur le LB + entrypoints Traefik, `trustedIPs`)
  pour voir l'IP client réelle. Les ranges autorisés sont **chiffrés via SOPS**.
- **Auth** : token applicatif (contrôle primaire ; l'`ipAllowList` n'est qu'un pré-filtre réseau)
- **Sondes** : `/healthcheck/live/` et `/healthcheck/ready/`
- **Secrets** : credentials DB (user DML-only), `SECRET_KEY` et le **hash** du token API (`HASHED_API_TOKEN`) via
  `api-relay-database` / `api-relay-django` / `api-relay-api-token`

#### Migrations : Job ArgoCD PreSync (`migrate` + `grant_app_privileges` avec l'utilisateur DDL `jobs`)

## NetworkPolicies

Chaque namespace `interops-*` applique des **CiliumNetworkPolicies** en moindre privilège.
Subtilité Cilium à connaître : un pod ne passe en *default-deny* que dès qu'une policy le sélectionne,
or `allow-dns` les sélectionne tous, donc **tout le trafic egress est bloqué par défaut**, et seul les flux
explicitement déclarés passent (Traefik → apps, api-relay → PostgreSQL / interops-a, interops-a → jetonv3 / strongswan).

Le détail fait foi dans `charts/interops-infra/templates/networkpolicies.yaml`.

## Retirer un composant ou un environnement

Les ApplicationSets `interops-apps` et `api-relay` ont `preserveResourcesOnDeletion: true` : supprimer un
ApplicationSet, ou retirer un élément de son générateur, supprime les Applications générées mais laisse leurs
ressources sur le cluster.
Une fausse manipulation (réinstallation d'ArgoCD, clé d'ApplicationSet renommée) ne supprime donc rien. ArgoCD réécrit
les finalizers des Applications qu'il génère : en ajouter un à la main ne change rien.

Pour un retrait voulu, retirer l'élément par une pull request, puis supprimer à la main ce qui reste :
- un environnement entier : son namespace
- un composant : ses ressources

Le projet `apps` signale ces ressources restantes (`orphanedResources`) : un avertissement sur les Applications du
namespace, et la liste dans l'interface. ArgoCD ne les supprime jamais lui-même.

## Déploiement manuel (sans ArgoCD)

```bash
# Traefik (Ingress Controller)
helm dependency update ./charts/traefik
helm upgrade --install traefik ./charts/traefik \
  --namespace ingress \
  --create-namespace

# Authentik (Identity Provider)
helm dependency update ./charts/authentik
helm upgrade --install authentik ./charts/authentik \
  --namespace authentik \
  --create-namespace

# Reloader
helm dependency update ./charts/reloader
helm upgrade --install reloader ./charts/reloader \
  --namespace reloader \
  --create-namespace

# Namespaces + PVCs + NetworkPolicies + ExternalSecrets
helm upgrade --install interops-integration ./charts/interops-infra \
  -f ./charts/interops-infra/values-integration.yaml

# Production (après la VABF)
helm upgrade --install interops-production ./charts/interops-infra \
  -f ./charts/interops-infra/values-production.yaml

# Applications (exemple pour integration, --create-namespace au besoin)
helm upgrade --install ihm-web ./charts/ihm-web \
  -n interops-integration \
  -f ./charts/ihm-web/values-integration.yaml

helm upgrade --install jetonv3 ./charts/jetonv3 \
  -n interops-integration \
  -f ./charts/jetonv3/values-integration.yaml

helm upgrade --install interops-a ./charts/interops-a \
  -n interops-integration \
  -f ./charts/interops-a/values-integration.yaml

helm upgrade --install api-relay ./charts/api-relay \
  -n interops-integration \
  -f ./charts/api-relay/values-integration.yaml \
  -f secrets://./charts/api-relay/values-integration.enc.yaml
```
