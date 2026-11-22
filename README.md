# novasphere-5src-gr1

## Prerequis
```bash
git clone <ce depot> && cd novasphere-infra
git checkout fin-S3            # etat attendu en debut de S4
```

- Terraform >= 1.14, AWS CLI v2 configure (`aws sts get-caller-identity` repond), ansible-core 2.21 (Python 3.12+), Git
- Une paire de cles SSH : `ssh-keygen -t ed25519 -f ~/.ssh/novasphere -N ""`

## Demarrage

### Premier lancement

On crée le bucket avec:

$TRI_REF_AWS=jul
$REGION=us-east-1

```bash
aws s3api create-bucket --bucket novasphere-tfstate-$TRI_REF_AWS --region $REGION
```

On active le versinoning sur le bucket:
```bash
aws s3api put-bucket-versioning --bucket novasphere-tfstate-$TRI_REF_AWS --versioning-configuration Status=Enabled
```

Vérifier le versioning:
```bash
aws s3api get-bucket-versioning --bucket novasphere-tfstate-$TRI_REF_AWS
```


```bash
cd envs/<dev/prod>
```

```bash
tofu init -migrate-state
```

Avant tout `apply` sur un tag : remplacer `<trigramme>` dans les blocs backend, copier `terraform.tfvars.example` en `terraform.tfvars`, et repartir d'un state vide : `terraform destroy` sur l'ancien tag avant d'en changer (un `init -migrate-state` dans un dossier neuf ne migre rien).

Le module `ec2-server` est référencé en chemin local (`../../modules/ec2-server`) pour que le dépôt soit autonome ; en équipe, la source devient un dépôt Git épinglé sur un tag, comme indiqué en commentaire dans `envs/prod/main.tf`.

## Version AWS Academy Learner Lab

Le dépôt tourne tel quel dans le Learner Lab (région `us-east-1`). Deux adaptations, imposées par le verrouillage d'IAM :

| Séance | Dans un compte classique | Dans le Learner Lab |
|---|---|---|
| S5 | Rôle d'instance au moindre privilège | Profil précréé `LabInstanceProfile` (variable `instance_profile_name`) ; la version entreprise est dans `envs/dev/iam_compte_classique.tf.exemple` |
| S7 | Fédération OIDC, aucune clé dans GitHub | Secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` copiés depuis AWS Details, à renouveler à chaque session ; la version entreprise est dans `envs/dev/ci_oidc_compte_classique.tf.exemple` |

À chaque début de session : `Start Lab`, recopier les trois identifiants dans `~/.aws/credentials` (et dans les secrets GitHub en S7), puis `terraform apply`. Les instances ont redémarré avec une nouvelle IP publique, et l'apply de `envs/prod` régénère l'inventaire Ansible (`ansible/inventory-prod.ini`, lu par `ansible.cfg`).

## Variables et secrets GitHub à créer (S7)

Les workflows ne lisent pas `terraform.tfvars` (ignoré par Git) ni `~/.ssh` : tout vient des réglages du dépôt, `Settings > Secrets and variables > Actions`.

Onglet Variables :

| Nom | Contenu | Utilisé par |
|---|---|---|
| `OWNER` | Trigramme, 3 lettres minuscules, le même que dans `terraform.tfvars` | `TF_VAR_owner`, dev et prod |
| `ADMIN_CIDR` | IP publique fixe de l'administrateur en `/32` (ex. `203.0.113.10/32`) | `TF_VAR_admin_cidr`, règle SSH de prod. Laissée vide, la règle s'ouvrirait à l'IP du runner |
| `SSH_PUBLIC_KEY` | Contenu de `~/.ssh/novasphere.pub`, la même clé qu'en local (sinon la key pair est remplacée) | étape qui écrit `~/.ssh/novasphere.pub` sur le runner |

Onglet Secrets :

| Nom | Contenu | Utilisé par |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | AWS Details du lab, à recopier à chaque Start Lab | `configure-aws-credentials` |
| `AWS_SECRET_ACCESS_KEY` | idem | idem |
| `AWS_SESSION_TOKEN` | idem | idem |
| `DB_PASSWORD` | Mot de passe applicatif de dev | `TF_VAR_db_password` (variable éphémère de `envs/dev`) |

Fixés dans les workflows : `TF_VAR_environment` (dev ou prod) et `TF_VAR_generate_inventory = "false"` en prod (le runner ne génère pas d'inventaire Ansible). En local, `admin_cidr` vide reprend l'IP du poste : pour que le plan local et celui de la CI soient identiques, renseigner `admin_cidr` dans `envs/prod/terraform.tfvars` avec la valeur de `ADMIN_CIDR`.
