# Fiche de cadrage d'équipe (séance 8)

> Module « Terraform et Automatisation du déploiement d'infrastructures dans le cloud », Master SRC, Bac+5.
> Fiche remise à l'intervenant avant le premier `terraform plan`, puis versionnée dans le dépôt sous `CADRAGE.md`.
> Une fiche non validée n'autorise pas à dépasser le socle.

**Équipe :** `gr1`  **Classe :** `5SRC2`

## Membres et rôles

| Membre | Rôle | Compte GitHub |
|---|---|---|
| `Julien ZEYBEL` | Référent AWS/GIT | `https://github.com/h-ok-o` |
| `Miguel FERREIRA` | Suppléant du référent AWS | `https://github.com/GringoElPepito` |
| `Soratha LIM--OUK` | Membre | `https://github.com/STR4Z` |
| `Selahaddin TIRYAKI` | Membre | `https://github.com/SeloTir` |

- **Learner Lab de l'équipe (référent AWS) :** ``Julien ZEYBEL``
- **Suppléant :** `Miguel FERREIRA`. Si le référent manque, il crée son propre bucket de state, redéploie depuis le code dans son lab et remplace les secrets du dépôt par les siens.
- **Dépôts publics :**
  - projet : `https://github.com/h-ok-o/novasphere-5src-gr1`
  - module : `https://github.com/h-ok-o/terraform-aws-ec2-server`
- **Collaborateurs :** les 4 membres et l'intervenant (Hemerson KOFFI), personne d'autre (les collaborateurs accèdent aux secrets de la CI).

## Le contexte

- **Application :** `NOVA`, plateforme SaaS de l'entreprise fictive NovaSphere, une startup dont l'équipe reprend l'infrastructure pour la faire grandir.
- **Ce que servent les instances :** page statique via nginx, derrière un Application Load Balancer. La page `/` affiche le nom de l'environnement (`dev` ou `prod`) et l'état du secret (`secret chargé : oui`), jamais sa valeur.
- **Environnements :** `dev` et `prod`, deux répertoires (`envs/dev`, `envs/prod`) qui appellent le même module au même tag, avec un state par environnement dans le bucket S3 d'équipe (`novasphere/dev/…` et `novasphere/prod/…`).

## L'extension choisie (une seule)

- [X] HTTPS (certificat importé dans ACM, listener 443)
- [ ] Administration sans SSH (SSM Run Command, sans paire de clés)
- [ ] Base de données (RDS)
- [ ] Image préconstruite (Packer)
- [ ] Configuration par Ansible (ansible-pull ou SSM Run Command)
- [ ] Second service derrière l'ALB
- [ ] Tests de module (`terraform test`)

**Ce qu'elle exige en plus du socle** (ressources, coût horaire, temps estimé) : `N/A`

**Plan de repli** si le lab refuse une ressource de l'extension : `Administration sans SSH` (à documenter dans `ARCHITECTURE.md` et à proposer en séance 9).

## Ce que l'équipe écarte, et pourquoi

| Écarté | Raison |
|---|---|
| NAT Gateway | Facturée à l'heure, inutile : les instances sont en subnets publics, fermées par leurs Security Groups. |
| Verrouillage par table DynamoDB | Approche dépréciée, remplacée par `use_lockfile = true`. |
| Fédération OIDC GitHub vers AWS | Impossible dans le Learner Lab (IAM verrouillé) : écrite dans un fichier `.exemple` et expliquée dans `SECURITE.md`. |
| Rôle IAM dédié aux instances | Création de rôles refusée dans le lab : `LabInstanceProfile` utilisé, politique idéale rédigée dans `SECURITE.md`. |
| Seconde extension | Non notée et coûteuse en temps : le socle passe d'abord. |

## Validation

Validée par l'intervenant le `<DATE>` :  [ ] telle quelle  [ ] réduite à : `<A_COMPLETER>`

