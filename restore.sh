#!/bin/bash
# =============================================================
# restore.sh - Restauration complète Dolibarr (PRA)
# SAE51 - Projet ERP/CRM
# =============================================================

set -e

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================
# Vérification de l'argument
# =============================================================
if [ -z "$1" ]; then
    echo "Usage: $0 <fichier_backup.tar.gz>"
    echo ""
    echo "Sauvegardes disponibles :"
    ls -lh backups/backup_*.tar.gz 2>/dev/null || echo "  Aucune sauvegarde trouvée."
    exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
    log_error "Fichier de sauvegarde introuvable : $BACKUP_FILE"
    exit 1
fi

echo "============================================================="
echo "   Restauration Dolibarr depuis : $BACKUP_FILE"
echo "============================================================="

# =============================================================
# 1. Confirmation
# =============================================================
log_warn "⚠️  ATTENTION : Cette opération va ÉCRASER toutes les données actuelles !"
read -p "Confirmer la restauration ? (oui/non) : " CONFIRM
if [ "$CONFIRM" != "oui" ]; then
    log_info "Restauration annulée."
    exit 0
fi

# =============================================================
# 2. Extraction de l'archive
# =============================================================
TMP_DIR=$(mktemp -d)
log_info "Extraction de l'archive dans $TMP_DIR..."
tar xzf "$BACKUP_FILE" -C "$TMP_DIR"

# Récupération du nom de base
BACKUP_NAME=$(basename "$BACKUP_FILE" .tar.gz)

log_ok "Archive extraite."

# =============================================================
# 3. Restauration du fichier .env
# =============================================================
if [ -f "${TMP_DIR}/${BACKUP_NAME}_env.bak" ]; then
    log_info "Restauration de la configuration .env..."
    cp "${TMP_DIR}/${BACKUP_NAME}_env.bak" .env
    export $(grep -v '^#' .env | xargs)
    log_ok "Configuration restaurée."
fi

DB_CONTAINER="dolibarr_db"
APP_CONTAINER="dolibarr_app"
DB_NAME="${MYSQL_DATABASE:-dolibarr}"
DB_ROOT_PASS="${MYSQL_ROOT_PASSWORD:-rootpassword}"

# =============================================================
# 4. Arrêt des conteneurs
# =============================================================
log_info "Arrêt des conteneurs..."
docker compose down
log_ok "Conteneurs arrêtés."

# =============================================================
# 5. Redémarrage des conteneurs
# =============================================================
log_info "Redémarrage des conteneurs..."
docker compose up -d

# Attente de MariaDB
log_info "Attente de MariaDB..."
MAX_TRIES=30
TRIES=0
until docker exec "$DB_CONTAINER" healthcheck.sh --connect --innodb_initialized &>/dev/null; do
    TRIES=$((TRIES+1))
    if [ $TRIES -ge $MAX_TRIES ]; then
        log_error "MariaDB n'a pas démarré."
        exit 1
    fi
    echo -n "."
    sleep 2
done
echo ""
log_ok "MariaDB prêt."

# =============================================================
# 6. Restauration de la base de données
# =============================================================
log_info "Restauration de la base de données..."

DB_DUMP="${TMP_DIR}/${BACKUP_NAME}_db.sql.gz"
if [ ! -f "$DB_DUMP" ]; then
    log_error "Fichier de dump introuvable : $DB_DUMP"
    exit 1
fi

gunzip -c "$DB_DUMP" | docker exec -i "$DB_CONTAINER" mysql \
    -u root -p"$DB_ROOT_PASS" "$DB_NAME"

log_ok "Base de données restaurée."

# =============================================================
# 7. Restauration des documents
# =============================================================
log_info "Restauration des documents Dolibarr..."

DOCS_ARCHIVE="${TMP_DIR}/${BACKUP_NAME}_documents.tar.gz"
if [ -f "$DOCS_ARCHIVE" ]; then
    docker run --rm \
        --volumes-from "$APP_CONTAINER" \
        -v "${TMP_DIR}:/backup" \
        alpine \
        tar xzf "/backup/${BACKUP_NAME}_documents.tar.gz" -C /

    log_ok "Documents restaurés."
else
    log_warn "Aucune archive de documents trouvée."
fi

# =============================================================
# 8. Redémarrage final
# =============================================================
log_info "Redémarrage final des services..."
docker compose restart

# =============================================================
# 9. Nettoyage
# =============================================================
rm -rf "$TMP_DIR"
log_ok "Nettoyage effectué."

echo ""
echo "============================================================="
log_ok "Restauration terminée avec succès !"
echo "============================================================="
echo "🌐 Accès Dolibarr : http://localhost:8080"
echo "============================================================="
