# Règles d'équipe novasphere-infra

## Workflow Git

- Une branche par changement, nommée `feat/…` ou `fix/…`, ouverte depuis `main`.
- Pull request relue par un autre membre que son auteur avant merge sur `main`, puis branche supprimée.
- Jamais commité : `*.tfstate*`, `*.tfvars`, `*.pem`, `.env`, `ansible/inventory*.ini`.

## Règles d'exploitation

- `terraform plan` lu intégralement avant tout `apply`.
- Avant de quitter : `terraform destroy`, ou `scripts/stop-evening.sh prod` si l'infra sert demain.
- `force-unlock` seulement après avoir vérifié que personne n'a d'opération en cours (voir ci-dessous).

## Le state partagé et son verrou

### Où est le state

Le state de chaque environnement est un objet du bucket S3 d'équipe (versionné, chiffré), sous une clé distincte :

- `novasphere/dev/terraform.tfstate`
- `novasphere/prod/terraform.tfstate`

Deux environnements, deux states : un `apply` sur dev ne peut pas toucher au state de prod.

### Rôle du verrou

Le state est la mémoire de Terraform : il lit ce fichier avant chaque `plan`, puis le réécrit après chaque `apply`. Si deux opérations s'exécutent en même temps, la seconde peut partir d'un state déjà périmé et écraser les changements de la première : le state ne décrit plus l'infrastructure réelle (ressources en double, ressources « oubliées »).

Le verrou garantit qu'**une seule opération qui modifie ou lit le state pour agir dessus s'exécute à la fois** sur un même state :

1. Au début de `plan`, `apply` ou `destroy`, Terraform tente de poser le verrou.
2. S'il y parvient, il travaille, puis le libère à la fin.
3. S'il n'y parvient pas parce que quelqu'un le tient, il s'arrête avec `Error acquiring the state lock`.

Le verrou n'est donc pas une panne, c'est la protection qui a fonctionné.

### Comment il est implémenté chez nous

Le backend est configuré avec `use_lockfile = true`. Terraform crée à côté du state un objet `<clé>.tflock` (par exemple `novasphere/dev/terraform.tfstate.tflock`) en utilisant une **écriture conditionnelle de S3** : la création n'aboutit que si l'objet n'existe pas déjà. Si le fichier existe, S3 répond `412 PreconditionFailed` et Terraform affiche l'erreur de verrou avec un bloc `Lock Info` :

| Champ | Contenu |
|---|---|
| `ID` | Identifiant du verrou, à passer à `force-unlock` |
| `Who` | Utilisateur et machine qui le tiennent |
| `Created` | Heure de création |
| `Operation` | `OperationTypePlan`, `OperationTypeApply`… |

À la fin normale de l'opération, Terraform supprime le fichier `.tflock`.

Pourquoi pas DynamoDB : la documentation du backend S3 indique que `dynamodb_table` est **déprécié** au profit de `use_lockfile`. Il n'y a donc pas de table à créer ni à payer, et le verrou vit dans le même bucket que le state.

### Que faire face à `Error acquiring the state lock`

1. **Lire le bloc `Lock Info`** : qui, depuis quand, quelle opération.
2. **Chercher le porteur du verrou** :
   - un coéquipier a un `plan` ou un `apply` en cours (le demander) ;
   - un workflow GitHub Actions tourne (onglet *Actions* du dépôt) ;
   - un autre de vos terminaux est encore ouvert.
3. **Si une opération est en cours : attendre.** C'est le cas normal, il n'y a rien à corriger.
4. **Si rien ne tourne** (terminal fermé, Ctrl+C brutal, session du lab expirée, run CI annulé), le verrou est orphelin : voir `force-unlock`.
5. **Si l'erreur n'est pas un `412`** (`AccessDenied`, `ExpiredToken`, `NoSuchBucket`), ce n'est pas un verrou tenu : relancer le Learner Lab, vérifier `aws sts get-caller-identity` et le nom du bucket dans `backend.tf`.

### `force-unlock`

```
terraform force-unlock <ID>
```

**Ce que c'est** : une commande qui supprime le verrou d'un state, en lui donnant l'`ID` affiché dans l'erreur. Elle ne répare pas le state et n'annule rien : elle ne fait qu'enlever le verrou. L'`ID` protège d'une erreur de cible : on ne peut débloquer que le verrou qu'on a identifié.

**Quand l'utiliser** : uniquement quand on a **vérifié que personne n'a d'opération en cours** et que le verrou est resté après un arrêt anormal.

**Quand l'éviter** :

- si un coéquipier ou la CI a un `plan` ou un `apply` en cours : retirer le verrou laisse deux opérations écrire le state en même temps, et le state peut être corrompu ;
- tant qu'on n'a pas comparé `Who` et `Created` avec ce qu'on sait de l'équipe ;
- pour « aller plus vite » quand un autre membre est simplement en train de travailler ;
- sans en avoir prévenu l'équipe.

**Procédure** :

1. Lire `Who`, `Created` et `Operation` dans l'erreur.
2. Demander dans le canal d'équipe si quelqu'un lance une opération sur cet environnement, et vérifier l'onglet *Actions*.
3. Confirmer que `Created` est ancien et que la machine citée dans `Who` n'exécute plus rien.
4. Lancer `terraform force-unlock <ID>`.
5. Relancer `terraform plan` : il doit être cohérent. Si le run interrompu était un `apply`, relire attentivement le plan avant de continuer, car il a pu s'arrêter à mi-chemin.
6. Si `force-unlock` échoue, supprimer l'objet `.tflock` du bucket est un dernier recours, avec les mêmes vérifications :
   `aws s3 rm s3://<bucket>/<projet>/<env>/terraform.tfstate.tflock`

### Reproduire le conflit (pour comprendre et pour la démo)

1. Terminal A : `terraform apply` dans `envs/dev`, sans répondre à la confirmation (le verrou est tenu).
2. Terminal B, même dossier : `terraform plan` échoue avec `Error acquiring the state lock` et un `412`.
3. Terminal A : répondre `yes` ou `no`. Le verrou est libéré, B peut réessayer.

### Récupérer un state abîmé

Le bucket est **versionné** : en cas de state corrompu ou écrasé, on peut retrouver une version antérieure de l'objet (`aws s3api list-object-versions`) et la restaurer. C'est la raison pour laquelle le versioning est obligatoire.
