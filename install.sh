#!/bin/bash
# =============================================================
# install.sh - Installation automatisée de Dolibarr + MariaDB
# SAE51 - Projet ERP/CRM
# =============================================================

set -e  # Arrêt en cas d'erreur

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonctions de log
log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Bannière
echo "============================================================="
echo "   Installation Dolibarr + MariaDB (Docker) - SAE51"
echo "============================================================="

# =============================================================
# 1. Vérification des prérequis
# =============================================================
log_info "Vérification des prérequis..."

if ! command -v docker &> /dev/null; then
    log_error "Docker n'est pas installé. Veuillez l'installer."
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    log_error "Docker Compose n'est pas installé."
    exit 1
fi

log_ok "Docker et Docker Compose sont installés."

# =============================================================
# 2. Vérification du fichier .env
# =============================================================
if [ ! -f .env ]; then
    log_error "Fichier .env introuvable."
    exit 1
fi
log_ok "Fichier .env trouvé."

# =============================================================
# 3. Création des dossiers nécessaires
# =============================================================
log_info "Création des dossiers..."
mkdir -p backups
mkdir -p logs
log_ok "Dossiers créés."

# =============================================================
# 4. Arrêt des conteneurs existants
# =============================================================
log_info "Arrêt des conteneurs existants (si présents)..."
docker compose down 2>/dev/null || true
log_ok "Nettoyage terminé."

# =============================================================
# 5. Build et démarrage des conteneurs
# =============================================================
log_info "Démarrage des conteneurs Docker..."
docker compose up -d

# =============================================================
# 6. Attente de la disponibilité de MariaDB
# =============================================================
log_info "Attente de la disponibilité de MariaDB..."
MAX_TRIES=30
TRIES=0
until docker exec dolibarr_db healthcheck.sh --connect --innodb_initialized &>/dev/null; do
    TRIES=$((TRIES+1))
    if [ $TRIES -ge $MAX_TRIES ]; then
        log_error "MariaDB n'a pas démarré dans le temps imparti."
        exit 1
    fi
    echo -n "."
    sleep 2
done
echo ""
log_ok "MariaDB est prêt."

# =============================================================
# 7. Attente de la disponibilité de Dolibarr
# =============================================================
log_info "Attente de la disponibilité de Dolibarr..."
TRIES=0
until curl -s http://localhost:8080 > /dev/null; do
    TRIES=$((TRIES+1))
    if [ $TRIES -ge $MAX_TRIES ]; then
        log_error "Dolibarr n'a pas démarré dans le temps imparti."
        exit 1
    fi
    echo -n "."
    sleep 2
done
echo ""
log_ok "Dolibarr est prêt."

# =============================================================
# 8. Affichage des informations
# =============================================================
echo ""
echo "============================================================="
log_ok "Installation terminée avec succès !"
echo "============================================================="
echo ""
echo "🌐 Accès Dolibarr : http://localhost:8080"
echo "👤 Login admin    : ${DOLI_ADMIN_LOGIN:-superadmin}"
echo "🔑 Mot de passe   : ${DOLI_ADMIN_PASSWORD:-Admin123!}"
echo ""
echo "Pour importer les données CSV, lancez : ./import_csv.sh"
echo "Pour sauvegarder, lancez : ./backup.sh"
echo "============================================================="
