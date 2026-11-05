# SAE52 : Installation Dolibarr ERP/CRM

Projet réalisé dans le cadre de la SAE51 (IUT de Rouen - R&T BUT3).  
**Binôme** : Ivan ZATUROSKI & Yanaël DESOMBRES

---

## 1. Déploiement rapide

### Prérequis
- Docker & Docker Compose installés sur la machine.

### Commandes de lancement
```bash
# 1. Lancer l'installation (démarrage MariaDB + Dolibarr)
./install.sh

# 2. Importer les données (clients, fournisseurs, utilisateurs)
./import_csv.sh
```

---

## 2. Accès à l'application

- **URL** : [http://localhost:8080](http://localhost:8080)
- **Identifiant** : `superadmin`
- **Mot de passe** : `Admin123!`

---

## 3. Sauvegarde et Restauration (PRA)

- **Créer une sauvegarde complète** (base de données + documents + configuration) :
  ```bash
  ./backup.sh
  ```
  *(L'archive est générée dans le dossier `./backups/`)*

- **Restaurer après incident (reprise de zéro)** :
  ```bash
  ./restore.sh backups/backup_NOM_ARCHIVE.tar.gz
  ```

---

## 4. Structure des données
- `data/clients.csv` : liste des clients importés dans Dolibarr.
- `data/fournisseurs.csv` : liste des fournisseurs importés dans Dolibarr.
- `data/utilisateurs.csv` : liste des collaborateurs et administrateurs.
