# Rapport de sécurité — fretly-api

**Outil :** Trivy (`trivy fs --scanners vuln,secret,misconfig .`)
**Date du scan :** 28/10/2026
**Périmètre :** failles de sévérité **HIGH** et **CRITICAL**

## Synthèse

| #   | Cible                     | Type       | Problème                                  | Sévérité |
| --- | ------------------------- | ---------- | ----------------------------------------- | -------- |
| 1   | `requirements.txt`        | Dépendance | `python-multipart` 0.0.6 — CVE-2024-24762 | HIGH     |
| 2   | `requirements.txt`        | Dépendance | `python-multipart` 0.0.6 — CVE-2024-53981 | HIGH     |
| 3   | `requirements.txt`        | Dépendance | `python-multipart` 0.0.6 — CVE-2026-24486 | HIGH     |
| 4   | `requirements.txt`        | Dépendance | `python-multipart` 0.0.6 — CVE-2026-42561 | HIGH     |
| 5   | `requirements.txt`        | Dépendance | `python-multipart` 0.0.6 — CVE-2026-53539 | HIGH     |
| 6   | `legacy/deploy_manuel.sh` | Secret     | Clé privée RSA écrite en clair            | HIGH     |

**Total : 6 failles HIGH**, issues de deux causes : une dépendance obsolète et un secret présent dans le code.

---

## 1. Dépendance obsolète : `python-multipart` 0.0.6

`python-multipart` analyse les formulaires et les fichiers envoyés à l'API (`Form(...)`, `UploadFile` avec FastAPI/Starlette). La version installée, 0.0.6, date de 2023 et accumule cinq failles HIGH, toutes corrigées depuis.

| CVE            | Corrigée en | Description                                                                                           | Impact                                            |
| -------------- | ----------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| CVE-2024-24762 | 0.0.7       | ReDoS : un en-tête `Content-Type` forgé fait tourner l'expression régulière de parsing très longtemps | Déni de service (CPU bloqué)                      |
| CVE-2024-53981 | 0.0.18      | Données parasites autour de la « boundary » multipart, traitées octet par octet                       | Déni de service (CPU et logs saturés)             |
| CVE-2026-24486 | 0.0.22      | Path traversal : un nom de fichier du type `../../` permet d'écrire hors du dossier prévu             | **Écriture de fichier arbitraire sur le serveur** |
| CVE-2026-42561 | 0.0.27      | Nombre excessif d'en-têtes dans les parties d'un formulaire                                           | Déni de service (mémoire/CPU)                     |
| CVE-2026-53539 | 0.0.30      | Corps de formulaire `x-www-form-urlencoded` piégé                                                     | Déni de service                                   |

La faille la plus critique est **CVE-2026-24486**, car elle permet d'écrire des fichiers sur le serveur. Les quatre autres permettent de rendre l'API indisponible.

### Correction

La version **0.0.30** corrige les cinq failles HIGH. Les failles LOW du rapport sont corrigées jusqu'en 0.0.31 ; viser la dernière version règle donc tout le paquet.

```bash
pip install -U "python-multipart>=0.0.30"
```

Dans `requirements.txt` :

```
python-multipart>=0.0.30
```

Si la version est bloquée par FastAPI :

```bash
pip install -U fastapi python-multipart
pip freeze > requirements.txt
```

### Vérification

- Tester les routes qui reçoivent des formulaires ou des fichiers, car le saut de version est important (0.0.6 → 0.0.30+).
- Relancer le scan (voir la dernière section).

---

## 2. Secret exposé : clé privée RSA dans `legacy/deploy_manuel.sh`

**Emplacement :** `legacy/deploy_manuel.sh`, lignes 10 à 36

Le script contient une clé privée RSA complète, recopiée dans `/tmp/fretly_key` pour une connexion SSH lors du déploiement manuel.

### Risque

- Toute personne ayant accès au dépôt peut se connecter au serveur associé avec les droits de cette clé.
- Supprimer le fichier ne suffit pas : **la clé reste dans l'historique Git**.
- La clé doit donc être considérée comme **compromise**.

### Correction (dans cet ordre)

**1. Révoquer et remplacer la clé (priorité absolue)**

```bash
ssh-keygen -t ed25519 -f ~/.ssh/fretly_deploy -C "deploy fretly"
```

- Ajouter la nouvelle clé publique dans `~/.ssh/authorized_keys` sur le serveur.
- **Supprimer l'ancienne clé publique** de ce même fichier.

**2. Retirer la clé du code**

Si le script legacy n'est plus utilisé (remplacé par la pipeline CI/CD) :

```bash
git rm legacy/deploy_manuel.sh
git commit -m "Suppression du script legacy contenant une clé privée"
```

S'il est encore utilisé, remplacer le bloc `cat > /tmp/fretly_key <<'KEY' ... KEY` par un chemin de clé passé en paramètre :

```bash
ssh -i "$DEPLOY_KEY_PATH" ...
```

**3. Stocker la clé de manière sécurisée**

Pour la pipeline GitHub Actions, enregistrer la clé dans **Settings → Secrets and variables → Actions** (par exemple `EC2_SSH_KEY`) et l'utiliser via `${{ secrets.EC2_SSH_KEY }}`. Aucune clé ne doit figurer dans le code.

**4. Nettoyer l'historique Git (facultatif)**

```bash
pip install git-filter-repo
git filter-repo --path legacy/deploy_manuel.sh --invert-paths
git push --force
```

Cette commande réécrit l'historique, donc il faut prévenir les autres contributeurs. Une fois l'étape 1 faite, l'ancienne clé est inutilisable et ce nettoyage devient secondaire.

---

## Vérification finale

```bash
# Code source et dépendances
trivy fs --severity HIGH,CRITICAL --scanners vuln,secret,misconfig .
```

**Objectif :** 0 faille HIGH ou CRITICAL.

## Prévention

- Ajouter un scan Trivy bloquant dans la pipeline CI/CD (`exit-code: 1` sur `HIGH,CRITICAL`).
- Mettre à jour régulièrement les dépendances (Dependabot ou Renovate).
- Ne jamais committer de secrets ; utiliser les secrets GitHub ou des variables d'environnement.
- Ajouter les fichiers sensibles (`.env`, `*.pem`, `*_key`) au `.gitignore`.

## Avant / Après

### Avant correction

| Target | Type | Vulnerabilities | Secrets | Misconfigurations |
|--------|------|:---:|:---:|:---:|
| `requirements.txt` | pip | 9 | - | - |
| `legacy/deploy_manuel.sh` | text | - | 1 | - |

**Total : 6 failles HIGH**

### Après correction

| Target | Type | Vulnerabilities | Secrets | Misconfigurations |
|--------|------|:---:|:---:|:---:|
| `requirements.txt` | pip | 0 | - | - |

**Total : 0 faille HIGH**

---

## Hors Trivy : fichier `.env` non ignoré

Trivy ne détecte que des formats de secrets connus (clés AWS, tokens GitHub, clés PEM…). Le fichier `.env` à la racine contient pourtant des secrets réels :

- `API_KEY` : clé qui protège les routes d'écriture ;
- `POSTGRES_PASSWORD`, repris dans `DATABASE_URL` : mot de passe de la base.

Le projet n'a **aucun `.gitignore`**, donc un `git add .` enverrait ce fichier sur GitHub.

### Correction

1. Créer un `.gitignore` :

```
.env
*.db
.venv/
__pycache__/
```

2. Fournir un `.env.example` avec des valeurs factices.
3. Si le `.env` a déjà été commité, changer la clé d'API et le mot de passe PostgreSQL.
