#!/usr/bin/env bash
# ============================================
# Script de setup rapide TopBudget
# ============================================
# Installation et configuration initiale du projet
# Corrections appliquées:
# - activation du mode strict: set -euo pipefail
# - ajout d'un wrapper 'run_compose' pour supporter 'docker compose' et 'docker-compose'
# - gestion non-interactive si $CI ou --yes

# Empêcher l'exécution avec /bin/sh (p.ex. 'sh setup.sh') qui ne supporte pas
# certaines options et syntaxes bash (ex: pipefail, [[ ... ]], functions avec () ).
if [ -z "${BASH_VERSION-}" ]; then
    echo "Ce script nécessite Bash. Lancez-le avec : bash setup.sh" >&2
    exit 1
fi

# Mode strict (ne s'exécute que si nous sommes bien sous bash)
set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PROJECT_NAME="TopBudget"
REQUIRED_DOCKER_VERSION="20.0.0"
REQUIRED_COMPOSE_VERSION="2.0.0"

# Fonction de log
log() {
    echo -e "[$(date '+%H:%M:%S')] $1"
}

# Wrapper pour docker compose : préfère 'docker compose' (v2), sinon 'docker-compose' (v1)
run_compose() {
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        docker compose "$@"
    elif command -v docker-compose &> /dev/null; then
        docker-compose "$@"
    else
        log "${RED}❌ Ni 'docker compose' ni 'docker-compose' disponibles${NC}"
        exit 1
    fi
}

# Fonction d'aide
show_help() {
    echo -e "${BLUE}${PROJECT_NAME} - Setup rapide${NC}"
    echo ""
    echo "Usage: $0 [ENVIRONNEMENT]"
    echo ""
    echo "Environnements:"
    echo "  dev      Configuration développement (par défaut)"
    echo "  prod     Configuration production"  
    echo "  test     Configuration tests"
    echo ""
    echo "Ce script va:"
    echo "  ✅ Vérifier les prérequis (Docker, Docker Compose)"
    echo "  ✅ Créer le fichier .env"
    echo "  ✅ Construire les images Docker"
    echo "  ✅ Lancer les services"
    echo ""
}

# Vérification de Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        log "${RED}❌ Docker n'est pas installé${NC}"
        log "${YELLOW}Installez Docker: https://docs.docker.com/get-docker/${NC}"
        exit 1
    fi

    local docker_version
    docker_version=$(docker --version | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
    log "${GREEN}✅ Docker ${docker_version} détecté${NC}"
}

# Vérification de Docker Compose
check_docker_compose() {
    if ! docker compose version &> /dev/null; then
        log "${RED}❌ Docker Compose n'est pas installé ou version trop ancienne${NC}"
        log "${YELLOW}Mettez à jour Docker Desktop ou installez Docker Compose v2+${NC}"
        exit 1
    fi

    local compose_version
    compose_version=$(docker compose version --short)
    log "${GREEN}✅ Docker Compose ${compose_version} détecté${NC}"
}

# Création du fichier .env
setup_env() {
    local env=${1:-dev}

    # if running in CI or --yes, don't prompt
    if [[ -f .env ]]; then
        log "${YELLOW}⚠️  Le fichier .env existe déjà${NC}"
        if [[ -n "${CI-}" || "${AUTO_YES-}" == "1" ]]; then
            log "${BLUE}Mode non-interactif: remplacement du .env existant${NC}"
        else
            read -p "Voulez-vous le remplacer ? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "${BLUE}Conservation du .env existant${NC}"
                return 0
            fi
        fi
    fi

    if [[ -f .env.example ]]; then
        cp .env.example .env
        log "${GREEN}✅ Fichier .env créé depuis .env.example${NC}"
    else
        log "${YELLOW}⚠️  .env.example non trouvé, création d'un .env minimal${NC}"
        cat > .env << EOF
NODE_ENV=${env}
JWT_SECRET=change_me_in_production_$(openssl rand -base64 32)
MONGO_URI=mongodb://mongo:27017/topbudget_${env}
PORT=5001
ME_CONFIG_BASICAUTH_USERNAME=admin
ME_CONFIG_BASICAUTH_PASSWORD=devpassword
EOF
        log "${GREEN}✅ Fichier .env minimal créé${NC}"
    fi
}

# Construction des images
build_images() {
    local env=$1

    log "${BLUE}🔨 Construction des images Docker...${NC}"

    case $env in
        "dev")
            run_compose -f docker-compose.yml -f docker/docker-compose.dev.yml build
            ;;
        "prod")
            run_compose -f docker-compose.yml -f docker/docker-compose.prod.yml build
            ;;
        "test")
            run_compose -f docker-compose.yml -f docker/docker-compose.test.yml build
            ;;
    esac

    log "${GREEN}✅ Images construites${NC}"
}

# Lancement des services
start_services() {
    local env=$1

    log "${BLUE}🚀 Lancement des services...${NC}"

    case $env in
        "dev")
            run_compose -f docker-compose.yml -f docker/docker-compose.dev.yml up -d
            ;;
        "prod")
            log "${YELLOW}⚠️  Production nécessite la création des secrets Docker${NC}"
            log "${BLUE}Exécutez: npm run secrets:create${NC}"
            return 0
            ;;
        "test")
            log "${BLUE}Mode test - lancement ponctuel${NC}"
            run_compose -f docker-compose.yml -f docker/docker-compose.test.yml up --abort-on-container-exit
            return 0
            ;;
    esac

    log "${GREEN}✅ Services démarrés${NC}"
}

# Vérification post-installation
post_install_check() {
    local env=$1
    
    if [[ $env == "test" || $env == "prod" ]]; then
        return 0
    fi
    
    log "${BLUE}🔍 Vérification des services...${NC}"
    sleep 10  # Attendre que les services démarrent
    
    # Check frontend
    if curl -sf http://localhost:3000 > /dev/null 2>&1; then
        log "${GREEN}✅ Frontend disponible sur http://localhost:3000${NC}"
    else
        log "${YELLOW}⚠️  Frontend pas encore prêt (normal au premier démarrage)${NC}"
    fi
    
    # Check backend
    if curl -sf http://localhost:5001/health > /dev/null 2>&1; then
        log "${GREEN}✅ Backend API disponible sur http://localhost:5001${NC}"
    else
        log "${YELLOW}⚠️  Backend pas encore prêt (normal au premier démarrage)${NC}"
    fi
    
    # Check mongo-express
    if curl -sf http://localhost:8081 > /dev/null 2>&1; then
        log "${GREEN}✅ Mongo Express disponible sur http://localhost:8081${NC}"
    else
        log "${YELLOW}ℹ️  Mongo Express non activé (utilisez le profil 'tools')${NC}"
    fi
}

# Affichage des informations finales
show_final_info() {
    local env=$1
    
    echo ""
    log "${GREEN}🎉 Setup terminé !${NC}"
    echo ""
    
    case $env in
        "dev")
            echo -e "${BLUE}📝 Commandes utiles:${NC}"
            echo "  - Voir les logs: npm run docker:dev:logs"
            echo "  - Arrêter: npm run docker:dev:down"  
            echo "  - Monitoring: npm run monitor:dev"
            echo ""
            echo -e "${BLUE}🌐 URLs locales:${NC}"
            echo "  - Application: http://localhost:3000"
            echo "  - API Backend: http://localhost:5001"  
            echo "  - Mongo Express: http://localhost:8081 (avec profil tools)"
            echo "  - Health checks: npm run health:all"
            ;;
        "prod")
            echo -e "${BLUE}📝 Prochaines étapes:${NC}"
            echo "  1. Créer les secrets: npm run secrets:create"
            echo "  2. Configurer SSL/domaines dans docker/nginx/"
            echo "  3. Lancer: npm run docker:prod"
            echo "  4. Monitoring: npm run monitor:prod"
            ;;
        "test")
            echo -e "${BLUE}📝 Tests terminés${NC}"
            echo "  - Relancer: npm run docker:test"
            echo "  - Avec rebuild: npm run docker:test:build"
            ;;
    esac
}

# Programme principal
main() {
    local env=${1:-dev}
    
    # Validation de l'environnement
    if [[ ! "$env" =~ ^(dev|prod|test)$ ]]; then
        log "${RED}❌ Environnement invalide: $env${NC}"
        show_help
        exit 1
    fi
    
    log "${BLUE}🚀 Setup ${PROJECT_NAME} - Environnement: ${env}${NC}"
    echo ""
    
    # Vérifications
    check_docker
    check_docker_compose
    
    # Configuration
    setup_env "$env"
    
    # Construction et lancement
    build_images "$env"
    start_services "$env"
    
    # Vérifications finales
    post_install_check "$env"
    show_final_info "$env"
}

# Gestion des arguments (n'exécute main que si le script est lancé directement)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-help}" in
        "dev"|"prod"|"test")
            main "$1"
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            main "dev"  # Par défaut
            ;;
    esac
fi