#!/bin/bash
# =============================================================
# import_csv.sh - Import automatisé des données CSV dans Dolibarr
# SAE51 - Projet ERP/CRM
# =============================================================

set -e

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================
# Chargement des variables d'environnement
# =============================================================
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

DB_CONTAINER="dolibarr_db"
DB_NAME="${MYSQL_DATABASE:-dolibarr}"
DB_USER="${MYSQL_USER:-dolibarr}"
DB_PASS="${MYSQL_PASSWORD:-dolibarrpassword}"
DB_ROOT_PASS="${MYSQL_ROOT_PASSWORD:-rootpassword}"

CSV_DIR="./data"

echo "============================================================="
echo "   Import des données CSV dans Dolibarr"
echo "============================================================="

# =============================================================
# Vérification des fichiers CSV
# =============================================================
for file in clients.csv fournisseurs.csv utilisateurs.csv; do
    if [ ! -f "${CSV_DIR}/${file}" ]; then
        log_error "Fichier manquant : ${CSV_DIR}/${file}"
        exit 1
    fi
done
log_ok "Tous les fichiers CSV sont présents."

# =============================================================
# Création du script SQL temporaire
# =============================================================
SQL_SCRIPT="/tmp/import_dolibarr.sql"
> "$SQL_SCRIPT"

log_info "Génération du script SQL..."

# =============================================================
# Import des CLIENTS + FOURNISSEURS (table llx_societe)
# =============================================================
# Type Dolibarr : 1 = Client, 2 = Fournisseur, 3 = Client+Fournisseur

import_tiers() {
    local csv_file="$1"
    local type_id="$2"

    # Sauter la ligne d'en-tête
    tail -n +2 "$csv_file" | while IFS=';' read -r nom type adresse cp ville tel email; do
        # Nettoyage des retours chariot éventuels
        nom=$(echo "$nom" | tr -d '\r')
        adresse=$(echo "$adresse" | tr -d '\r')
        cp=$(echo "$cp" | tr -d '\r')
        ville=$(echo "$ville" | tr -d '\r')
        tel=$(echo "$tel" | tr -d '\r')
        email=$(echo "$email" | tr -d '\r')

        [ -z "$nom" ] && continue

        # Échappement des apostrophes pour SQL
        nom_esc=$(echo "$nom" | sed "s/'/''/g")
        adresse_esc=$(echo "$adresse" | sed "s/'/''/g")
        ville_esc=$(echo "$ville" | sed "s/'/''/g")

        cat >> "$SQL_SCRIPT" <<EOF
INSERT INTO llx_societe (nom, address, zip, town, phone, email, client, status, datec, fk_pays)
VALUES ('$nom_esc', '$adresse_esc', '$cp', '$ville_esc', '$tel', '$email', $type_id, 1, NOW(), 1);
EOF
    done
}

# Import clients (type 1 = Client)
if [ -f "${CSV_DIR}/clients.csv" ]; then
    log_info "Préparation import des clients..."
    import_tiers "${CSV_DIR}/clients.csv" 1
fi

# Import fournisseurs (type 2 = Fournisseur)
if [ -f "${CSV_DIR}/fournisseurs.csv" ]; then
    log_info "Préparation import des fournisseurs..."
    import_tiers "${CSV_DIR}/fournisseurs.csv" 2
fi

# =============================================================
# Import des UTILISATEURS (table llx_user)
# =============================================================
if [ -f "${CSV_DIR}/utilisateurs.csv" ]; then
    log_info "Préparation import des utilisateurs..."

    tail -n +2 "${CSV_DIR}/utilisateurs.csv" | while IFS=';' read -r login nom prenom email role mdp; do
        login=$(echo "$login" | tr -d '\r')
        nom=$(echo "$nom" | tr -d '\r')
        prenom=$(echo "$prenom" | tr -d '\r')
        email=$(echo "$email" | tr -d '\r')
        role=$(echo "$role" | tr -d '\r')
        mdp=$(echo "$mdp" | tr -d '\r')

        [ -z "$login" ] && continue

        # Échappement
        login_esc=$(echo "$login" | sed "s/'/''/g")
        nom_esc=$(echo "$nom" | sed "s/'/''/g")
        prenom_esc=$(echo "$prenom" | sed "s/'/''/g")
        email_esc=$(echo "$email" | sed "s/'/''/g")

        # Hash du mot de passe (Dolibarr utilise password_hash)
        # On utilise une méthode simplifiée : MD5 pour démo, à adapter en prod
        mdp_hash=$(echo -n "$mdp" | md5sum | cut -d' ' -f1)

        # admin = 1 pour superadmin, 0 pour user
        if [ "$role" = "superadmin" ]; then
            admin=1
        else
            admin=0
        fi

        cat >> "$SQL_SCRIPT" <<EOF
INSERT INTO llx_user (login, lastname, firstname, email, admin, pass, pass_crypted, statut, datec)
VALUES ('$login_esc', '$nom_esc', '$prenom_esc', '$email_esc', $admin, '$mdp_hash', '$mdp_hash', 1, NOW());
EOF
    done
fi

# =============================================================
# Exécution du script SQL dans le conteneur MariaDB
# =============================================================
log_info "Exécution de l'import dans la base de données..."

docker exec -i "$DB_CONTAINER" mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" < "$SQL_SCRIPT"

if [ $? -eq 0 ]; then
    log_ok "Import terminé avec succès !"
else
    log_error "Erreur lors de l'import."
    exit 1
fi

# =============================================================
# Statistiques
# =============================================================
NB_CLIENTS=$(docker exec "$DB_CONTAINER" mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -sN -e "SELECT COUNT(*) FROM llx_societe WHERE client=1;")
NB_FOURNISSEURS=$(docker exec "$DB_CONTAINER" mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -sN -e "SELECT COUNT(*) FROM llx_societe WHERE client=2;")
NB_USERS=$(docker exec "$DB_CONTAINER" mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" -sN -e "SELECT COUNT(*) FROM llx_user;")

echo ""
echo "============================================================="
echo "   Résumé de l'import"
echo "============================================================="
echo "👥 Clients importés     : $NB_CLIENTS"
echo "🏭 Fournisseurs importés: $NB_FOURNISSEURS"
echo "👤 Utilisateurs importés: $NB_USERS"
echo "============================================================="

# Nettoyage
rm -f "$SQL_SCRIPT"
log_ok "Fichier temporaire supprimé."
