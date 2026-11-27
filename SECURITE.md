# Sécurité — registre des décisions

## 1. Les secrets et où ils vivent

| Secret | Où il vit | Qui le lit | Jamais dans |
|---|---|---|---|
| Mot de passe applicatif `db_password` (dev et prod, valeurs différentes) | Secret d'environnement GitHub `DB_PASSWORD` (environnements `dev` et `prod`) ; en local, variable `TF_VAR_db_password` | Terraform, uniquement pendant l'`apply` | Code, `terraform.tfvars`, state, plan, `user_data`, historique Git, logs de CI |
| Même mot de passe, une fois déployé | Parameter Store `/novasphere/<env>/db_password`, type `SecureString`, clé KMS `aws/ssm` | L'instance, au démarrage, via son profil IAM | — |
| Même mot de passe, sur l'instance | `/etc/novasphere/app.conf`, mode `0600`, propriétaire root | Le service applicatif | Journaux cloud-init (la sortie est redirigée vers le fichier) |
| Identifiants AWS de session du lab | Secrets de dépôt `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` | `configure-aws-credentials` | Code, historique |

Chaîne de traitement du secret :

1. `scripts/set-db-password.sh` génère un mot de passe aléatoire par environnement et le pousse dans les secrets d'environnement GitHub, sans l'afficher ni l'écrire sur disque.
2. Terraform le reçoit par `TF_VAR_db_password`, variable `ephemeral = true` et `sensitive = true`, sans valeur par défaut, avec une validation de longueur (16 caractères minimum).
3. `aws_ssm_parameter.db_password` l'écrit avec `value_wo` : l'attribut est en écriture seule, il n'est ni dans le plan ni dans le state. `value_wo_version` est obligatoire, car Terraform ne mémorise pas la valeur et ne détecte un changement que par ce compteur.
4. Au démarrage, `bootstrap.sh` lit le paramètre avec le profil d'instance. Le script ne contient que le nom de l'environnement et la région ; avec `set -e`, si la lecture échoue, nginx ne démarre pas, le health check ELB échoue et l'ASG remplace l'instance.
5. La page `/` affiche l'environnement et « secret chargé : oui/non », jamais la valeur.

Rotation : changer la valeur du secret d'environnement GitHub, incrémenter la variable de dépôt `DB_PASSWORD_VERSION`, relancer l'apply. Le tag `SecretVersion` du Launch Template change, l'ASG déclenche un rolling refresh et les nouvelles instances relisent le paramètre.

Aucun plan n'a besoin du vrai secret : `value_wo` n'est jamais comparé. Les jobs de plan en pull request et de détection de dérive utilisent donc une valeur jetable (`openssl rand`, masquée dans les logs). Seuls `apply-dev` et `apply-prod` lisent le vrai secret, et `apply-prod` le lit après approbation de l'environnement protégé `prod`.

## 2. Politique IAM que l'instance devrait avoir

Dans le Learner Lab, la création de rôles IAM est refusée : les instances utilisent le profil précréé `LabInstanceProfile` (rôle `LabRole`), qui peut lire tous les paramètres, y compris ceux de prod. Le moindre privilège n'est donc pas démontrable sur le compte du lab.

Sur un compte classique, il faudrait créer un rôle assumable uniquement par `ec2.amazonaws.com`, avec une seule action, `ssm:GetParameter`, sur la ressource `arn:aws:ssm:<région>:<compte>:parameter/novasphere/<environnement>/*`. Une instance de dev recevrait `AccessDeniedException` en lisant `/novasphere/prod/db_password`. Aucune permission `kms:Decrypt` n'est nécessaire avec la clé gérée `aws/ssm`, dont la politique de clé autorise les principaux du compte via le service SSM. Cette variante n'est pas déployée dans le Learner Lab, où la création de rôles IAM est refusée.

## 3. Durcissement des ressources

- **Aucun SSH** : aucune règle sur le port 22, aucune key pair, pas de `key_name` dans le Launch Template.
- **Security Group des instances** : entrée 80 uniquement depuis le Security Group de l'ALB ; sortie limitée à 443 (API SSM) et 80 (dépôts apt). DNS, IMDS et NTP ne passent pas par les Security Groups.
- **Security Group de l'ALB** : entrée 80 depuis Internet (service public), sortie 80 vers le Security Group des instances seulement.
- **IMDSv2 exigé** : `http_tokens = "required"`, `http_put_response_hop_limit = 1`, `instance_metadata_tags = "disabled"`.
- **Disque racine chiffré** (gp3), nom de périphérique lu depuis l'AMI.
- **ALB** : `drop_invalid_header_fields = true`.
- **Règles de sécurité en ressources séparées**, avec description, `name_prefix` et `create_before_destroy`.

## 4. Résultats du scan checkov

Commande : `checkov --config-file .checkov.yaml` (checkov 3.4.5, cadres `terraform` et `secrets`), exécutée aussi en CI à chaque pull request (job `security-scan`).

Avant durcissement, sur `envs/dev` du dépôt de référence : 23 contrôles passés, 14 échoués. Après : 0 échoué, les exceptions ci-dessous sont portées en ligne (`#checkov:skip=ID:raison`) au plus près de la ressource.

| Contrôle | Traitement |
|---|---|
| CKV_AWS_382 (×2) sortie `0.0.0.0/0` tous ports | **Corrigé** : sorties limitées à 80/443 (instances) et au SG des instances (ALB) |
| CKV_AWS_23 (×2) description des règles | **Corrigé** : toutes les règles ont une description |
| CKV_AWS_131 en-têtes HTTP invalides | **Corrigé** : `drop_invalid_header_fields = true` |
| CKV_AWS_79 IMDSv2 | **Corrigé** (déjà traité au départ), complété par hop limit 1 |
| CKV_AWS_260 entrée 0.0.0.0/0 port 80 (ALB) | **Documenté** : l'ALB est public par conception |
| CKV_AWS_260 sur la règle des instances | **Documenté** : faux positif, la source est le Security Group de l'ALB, pas un CIDR |
| CKV_AWS_2, CKV_AWS_103, CKV2_AWS_20, CKV_AWS_378 (HTTP, TLS, redirection) | **Documenté** : le HTTPS (certificat ACM, listener 443, redirection) est l'extension d'équipe, pas le socle |
| CKV_AWS_91 logs d'accès ALB | **Documenté** : hors périmètre, coût et stockage S3 supplémentaires |
| CKV_AWS_150 protection contre la suppression de l'ALB | **Documenté** : le `destroy` après chaque session du lab est obligatoire |
| CKV2_AWS_28 WAF devant l'ALB | **Documenté** : coût, hors périmètre du socle |
| CKV_AWS_337 paramètre SSM chiffré par une CMK | **Documenté** : clé gérée `aws/ssm` ; une CMK ajouterait une clé à gérer sans gain démontrable dans le lab |
| CKV_TF_1 module épinglé par hash de commit | **Documenté** : module du registre épinglé par contrainte de version (`~> 6.0`) et `.terraform.lock.hcl` |

Le cadre `secrets` de checkov, lancé sur tout le dépôt, ne remonte aucun secret en clair.

## 5. Preuves de non-fuite

Après le premier déploiement, vérifier manuellement que la valeur fournie dans `TF_VAR_db_password` n'apparaît pas dans l'arbre de travail, l'historique Git, `terraform state pull`, le `user_data` des versions du Launch Template ou les logs des dix derniers runs de CI. Reporter les résultats ci-dessous :

- Code et historique Git : ______
- `terraform state pull | grep` : ______ (attendu : 0 occurrence, `value_wo` n'est pas stocké)
- `user_data` : ______
- Logs de CI : ______
- Lecture depuis une instance de `/novasphere/<env>/db_password` : ______ (attendu : succès, et page `/` affichant « secret chargé : oui »)

## 6. Identifiants de la CI

**Learner Lab (utilisé ici).** La CI s'authentifie avec les trois identifiants de session du lab du référent AWS, en secrets du dépôt, remis à jour à chaque Start Lab par `scripts/ci-secrets.sh` (et avant la soutenance). Ils expirent avec la session (environ 4 h), ce qui borne une fuite dans le temps. Risques assumés :

- Une pull request ouverte depuis une branche du dépôt reçoit ces secrets : tout collaborateur avec le droit d'écriture peut les lire en modifiant un workflow dans sa branche. Seuls les membres de l'équipe sont collaborateurs.
- Les workflows déclarent des `permissions:` minimales et n'utilisent pas `pull_request_target`.
- Le secret applicatif `DB_PASSWORD` est un secret d'**environnement** : le secret de prod n'est lisible que par un job qui a passé l'approbation de l'environnement `prod`.

**Compte AWS personnel (version entreprise).** Fédération OIDC, aucun secret stocké : le fournisseur d'identité `token.actions.githubusercontent.com` et un rôle assumable via `sts:AssumeRoleWithWebIdentity`, avec une condition sur `aud` et sur `sub` limitée à ce dépôt (`repo:<organisation>/<dépôt>:*`, idéalement resserrée à `environment:prod` pour le rôle de prod). Le jeton est émis à chaque exécution et dure quelques minutes ; il n'y a rien à renouveler ni à voler dans GitHub. Le code est dans `envs/dev/ci_oidc_compte_classique.tf.exemple`, avec `id-token: write` et `role-to-assume` dans les workflows. La politique `AdministratorAccess` de l'exemple est à remplacer par un rôle limité aux services utilisés.

## 7. Limites connues

- Le state S3 contient des identifiants de ressources et des métadonnées, pas le secret ; le bucket doit rester versionné, chiffré et sans accès public.
- Le HTTP entre Internet et l'ALB est en clair tant que l'extension HTTPS n'est pas réalisée.
- Les instances ont une IP publique (pas de NAT Gateway, imposé par le socle) ; seul l'ALB peut les joindre.

## État de cette implémentation dans le dépôt NovaSphere

- Le module `modules/ec2-server` est local et partagé par `envs/dev` et `envs/prod`.
- Les paramètres SSM `SecureString` sont créés séparément dans chaque state, sous `/novasphere/dev/db_password` et `/novasphere/prod/db_password`. La valeur est transmise par la variable éphémère `TF_VAR_db_password` et écrite avec `value_wo` / `value_wo_version`.
- Le Launch Template transmet uniquement l'environnement, la région et le chemin SSM au script `templatefile`. Le script récupère le secret par le profil d'instance et le stocke dans `/etc/novasphere/app.conf` avec le mode `0600`.
- Le Launch Template impose IMDSv2 (`http_tokens = "required"`, hop limit `1`, tags IMDS désactivés), chiffre le volume racine gp3 et ne configure ni SSH ni key pair.
- Le profil `LabInstanceProfile` reste partagé, conformément à la limitation IAM du Learner Lab ; il n'isole donc pas les chemins dev et prod.
- Les exceptions Checkov relatives à l'ALB public en HTTP, aux logs ALB, à la suppression de l'ALB, au WAF et à la clé gérée `aws/ssm` sont documentées au plus près des ressources par `#checkov:skip`.

Le scan local n'a pas pu être exécuté dans l'environnement de préparation (binaire `checkov` absent et aucune installation disponible). Il est configuré dans `.checkov.yaml` et dans le workflow `.github/workflows/security-scan.yml`. Il reste à vérifier son résultat après push, puis à corriger ou documenter tout contrôle supplémentaire remonté.
