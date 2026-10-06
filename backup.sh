#!/bin/bash
# =============================================================
# backup.sh - Sauvegarde complète Dolibarr + MariaDB
# SAE51 - Projet ERP/CRM (contexte PRA)
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
# Chargement des variables
# =============================================================
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

DB_CONTAINER="dolibarr_db"
APP_CONTAINER="dolibarr_app"
DB_NAME="${MYSQL_DATABASE:-dolibarr}"
DB_ROOT_PASS="${MYSQL_ROOT_PASSWORD:-rootpassword}"

# Répertoire de sauvegarde
BACKUP_DIR="./backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="backup_${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"

echo "============================================================="
echo "   Sauvegarde Dolibarr - $TIMESTAMP"
echo "============================================================="

# =============================================================
# 1. Vérification que les conteneurs tournent
# =============================================================
if ! docker ps --format '{{.Names}}' | grep -q "$DB_CONTAINER"; then
    log_error "Le conteneur $DB_CONTAINER n'est pas démarré."
    exit 1
fi
log_ok "Conteneurs actifs."

# =============================================================
# 2. Sauvegarde de la base de données
# =============================================================
log_info "Sauvegarde de la base de données..."
docker exec "$DB_CONTAINER" mysqldump \
    -u root -p"$DB_ROOT_PASS" \
    --single-transaction \
    --routines \
    --triggers \
    "$DB_NAME" > "${BACKUP_DIR}/${BACKUP_NAME}_db.sql"

gzip -f "${BACKUP_DIR}/${BACKUP_NAME}_db.sql"
log_ok "Base de données sauvegardée : ${BACKUP_NAME}_db.sql.gz"

# =============================================================
# 3. Sauvegarde des documents Dolibarr
# =============================================================
log_info "Sauvegarde des documents Dolibarr..."
docker run --rm \
    --volumes-from "$APP_CONTAINER" \
    -v "$(pwd)/${BACKUP_DIR}:/backup" \
    alpine \
    tar czf "/backup/${BACKUP_NAME}_documents.tar.gz" -C /var/www documents

log_ok "Documents sauvegardés : ${BACKUP_NAME}_documents.tar.gz"

# =============================================================
# 4. Sauvegarde du fichier .env (configuration)
# =============================================================
cp .env "${BACKUP_DIR}/${BACKUP_NAME}_env.bak"
log_ok "Configuration sauvegardée."

# =============================================================
# 5. Création d'une archive globale
# =============================================================
log_info "Création de l'archive globale..."
tar czf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" \
    -C "$BACKUP_DIR" \
    "${BACKUP_NAME}_db.sql.gz" \
    "${BACKUP_NAME}_documents.tar.gz" \
    "${BACKUP_NAME}_env.bak"

# Nettoyage des fichiers intermédiaires
rm -f "${BACKUP_DIR}/${BACKUP_NAME}_db.sql.gz"
rm -f "${BACKUP_DIR}/${BACKUP_NAME}_documents.tar.gz"
rm -f "${BACKUP_DIR}/${BACKUP_NAME}_env.bak"

log_ok "Archive globale créée : ${BACKUP_NAME}.tar.gz"

# =============================================================
# 6. Rotation des sauvegardes (garder les 7 dernières)
# =============================================================
log_info "Rotation des sauvegardes (conservation des 7 dernières)..."
cd "$BACKUP_DIR"
ls -t backup_*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm -f
cd - > /dev/null
log_ok "Rotation effectuée."

# =============================================================
# 7. Résumé
# =============================================================
BACKUP_SIZE=$(du -h "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" | cut -f1)

echo ""
echo "============================================================="
echo "   Sauvegarde terminée"
echo "============================================================="
echo "📦 Fichier : ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
echo "📊 Taille  : $BACKUP_SIZE"
echo "============================================================="
