#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

echo_success() {
    echo -e "${CYAN}[SUCCESS]${NC} $1"
}

print_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║     Elastic Stack Docker Deployment Manager              ║
║     Cluster: clusterofrooks                              ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

check_docker() {
    echo_step "Checking Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        echo_error "Docker is not installed. Please install Docker first."
        exit 1
    fi

    if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
        echo_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi

    echo_info "Docker and Docker Compose are installed ✓"
}

check_env_file() {
    local env_file=$1
    if [ ! -f "$env_file" ]; then
        echo_error "$env_file file not found."
        return 1
    fi
    return 0
}

create_master_directories() {
    echo_step "Creating host directories for persistent data..."
    
    mkdir -p data/elasticsearch
    mkdir -p data/kibana
    mkdir -p data/fleet-server
    
    echo_step "Setting correct permissions (UID 1000 for Elasticsearch)..."
    sudo chown -R 1000:1000 data/
    
    echo_info "Directories created and permissions set ✓"
    echo "  - data/elasticsearch/"
    echo "  - data/kibana/"
    echo "  - data/fleet-server/"
    echo
}

create_node_directory() {
    local node_name=$1
    
    echo_step "Creating data directory for $node_name..."
    
    mkdir -p "data/elasticsearch-${node_name}"
    sudo chown -R 1000:1000 "data/elasticsearch-${node_name}"
    
    echo_info "Directory created: data/elasticsearch-${node_name}/ ✓"
    echo
}

deploy_master() {
    print_banner
    echo_step "Deploying Elastic Stack Master Node..."
    echo
    
    if ! check_env_file ".env"; then
        echo_error "Please create .env file first. See .env.example"
        exit 1
    fi

    # Load environment variables
    source .env

    echo_info "Configuration:"
    echo "  Cluster Name: ${CLUSTER_NAME}"
    echo "  Node Name: rook1"
    echo "  Node IP: ${NODE_IP}"
    echo "  Elasticsearch Port: ${ES_PORT}"
    echo "  Kibana Port: ${KIBANA_PORT}"
    echo "  Fleet Port: ${FLEET_PORT}"
    echo

    # Create directories
    create_master_directories

    # Start the stack
    echo_step "Starting Docker containers..."
    docker compose up -d

    echo_step "Waiting for Elasticsearch to initialize..."
    sleep 30

    # Wait for Elasticsearch
    echo_info "Checking Elasticsearch health..."
    local max_attempts=30
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if docker exec rook1 curl -s --cacert config/certs/ca/ca.crt https://localhost:9200 -u elastic:${ELASTIC_PASSWORD} > /dev/null 2>&1; then
            echo_success "Elasticsearch is ready!"
            break
        fi
        echo -n "."
        sleep 10
        attempt=$((attempt+1))
    done
    echo

    if [ $attempt -eq $max_attempts ]; then
        echo_error "Elasticsearch failed to start within the expected time."
        echo_info "Check logs with: docker compose logs rook1"
        exit 1
    fi

    echo_step "Waiting for Kibana to initialize..."
    sleep 20

    echo_info "Checking Kibana health..."
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if docker exec kibana curl -s --cacert config/certs/ca/ca.crt https://localhost:5601/api/status > /dev/null 2>&1; then
            echo_success "Kibana is ready!"
            break
        fi
        echo -n "."
        sleep 10
        attempt=$((attempt+1))
    done
    echo

    echo_step "Waiting for Fleet Server to initialize..."
    sleep 30

    # Get cluster health
    echo_step "Checking cluster health..."
    docker exec rook1 curl -s --cacert config/certs/ca/ca.crt https://localhost:9200/_cluster/health?pretty -u elastic:${ELASTIC_PASSWORD} | grep -E "cluster_name|status|number_of_nodes"

    echo
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}║           Master Node Deployment Complete! ✓             ║${NC}"
    echo -e "${GREEN}║                                                           ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "Access URLs:"
    echo "  🔍 Elasticsearch: https://${NODE_IP}:${ES_PORT}"
    echo "  📊 Kibana: https://${NODE_IP}:${KIBANA_PORT}"
    echo "  🚀 Fleet Server: https://${NODE_IP}:${FLEET_PORT}"
    echo
    echo "Credentials:"
    echo "  👤 Username: elastic"
    echo "  🔑 Password: ${ELASTIC_PASSWORD}"
    echo
    echo "Data Locations:"
    echo "  📁 Elasticsearch: $(pwd)/data/elasticsearch/"
    echo "  📁 Kibana: $(pwd)/data/kibana/"
    echo "  📁 Fleet: $(pwd)/data/fleet-server/"
    echo
    echo "Useful Commands:"
    echo "  📋 View logs: docker compose logs -f"
    echo "  📊 Check status: docker compose ps"
    echo "  🔄 Restart: docker compose restart"
    echo "  🛑 Stop: docker compose stop"
    echo "  🗑️  Remove: docker compose down"
    echo
    echo "Next Steps:"
    echo "  🔐 Export certs for additional nodes: $0 export-certs"
    echo "  ➕ Add a new node: $0 add-node"
    echo
}

export_certs() {
    echo_step "Exporting certificates from master node..."
    echo
    
    if ! docker volume inspect clusterofrooks_certs &> /dev/null; then
        echo_error "Certificates volume not found. Is the master node running?"
        exit 1
    fi

    # Create certs directory
    mkdir -p ./certs-export
    
    echo_info "Extracting certificates from Docker volume..."
    docker run --rm \
        -v clusterofrooks_certs:/from \
        -v $(pwd)/certs-export:/to \
        alpine sh -c "cd /from && cp -av . /to"
    
    echo_success "Certificates exported to ./certs-export/"
    echo
    echo "📦 To deploy a new node on another server:"
    echo "  1. Copy the certs-export directory to the new server"
    echo "     scp -r ./certs-export user@new-server:/path/to/elastic/"
    echo
    echo "  2. On the new server, run:"
    echo "     $0 import-certs /path/to/certs-export"
    echo
    echo "  3. Then deploy the node:"
    echo "     $0 add-node"
    echo
}

import_certs() {
    if [ -z "$1" ]; then
        echo_error "Please provide the path to the certs directory."
        echo "Usage: $0 import-certs /path/to/certs-export"
        exit 1
    fi

    local certs_path=$1

    if [ ! -d "$certs_path" ]; then
        echo_error "Certs directory not found: $certs_path"
        exit 1
    fi

    echo_step "Importing certificates..."
    
    # Create the volume first
    echo_info "Creating Docker volume for certificates..."
    docker volume create clusterofrooks_certs
    
    # Import certs to docker volume
    echo_info "Copying certificates to Docker volume..."
    docker run --rm \
        -v $certs_path:/from \
        -v clusterofrooks_certs:/to \
        alpine sh -c "cd /from && cp -av . /to"
    
    echo_success "Certificates imported successfully!"
    echo
    echo "✅ You can now deploy a node with: $0 add-node"
    echo
}

add_node() {
    print_banner
    echo_step "Deploying Additional Elasticsearch Node..."
    echo
    
    if ! check_env_file ".env"; then
        echo_error "Please create .env file first with NODE_NAME and NODE_IP"
        echo "Example .env content:"
        echo "  STACK_VERSION=8.11.1"
        echo "  CLUSTER_NAME=clusterofrooks"
        echo "  NODE_NAME=rook2"
        echo "  NODE_IP=10.3.10.103"
        echo "  MASTER_NODE_IP=10.3.10.102"
        echo "  ES_PORT=9200"
        echo "  ES_TRANSPORT_PORT=9300"
        echo "  LICENSE=trial"
        echo "  MEM_LIMIT=2GB"
        exit 1
    fi

    # Load environment variables
    source .env

    if [ -z "$NODE_NAME" ] || [ -z "$NODE_IP" ]; then
        echo_error "NODE_NAME and NODE_IP must be set in .env file"
        exit 1
    fi

    echo_info "Configuration:"
    echo "  Cluster Name: ${CLUSTER_NAME}"
    echo "  Node Name: ${NODE_NAME}"
    echo "  Node IP: ${NODE_IP}"
    echo "  Master Node: ${MASTER_NODE_IP}"
    echo

    # Check if certs exist
    if ! docker volume inspect clusterofrooks_certs &> /dev/null; then
        echo_error "Certificates not found!"
        echo
        echo "Please import certificates first:"
        echo "  1. On master node: $0 export-certs"
        echo "  2. Copy certs-export to this server"
        echo "  3. Import: $0 import-certs /path/to/certs-export"
        exit 1
    fi

    # Create node data directory
    create_node_directory "$NODE_NAME"

    # Start the node
    echo_step "Starting ${NODE_NAME} container..."
    docker compose -f docker-compose-node.yml up -d

    echo_step "Waiting for node to join cluster..."
    sleep 30

    echo_success "Node deployment complete!"
    echo
    echo "📊 Verify node joined cluster:"
    echo "  curl -k -u elastic:ElasticTESTpassword123 https://${MASTER_NODE_IP}:9200/_cat/nodes?v"
    echo
    echo "Or run: $0 status"
    echo
    echo "Data Location:"
    echo "  📁 ${NODE_NAME}: $(pwd)/data/elasticsearch-${NODE_NAME}/"
    echo
}

show_status() {
    print_banner
    echo_step "Checking Elastic Stack Status..."
    echo
    
    local has_master=false
    local has_nodes=false
    
    if docker ps --format '{{.Names}}' | grep -q "^rook1$"; then
        has_master=true
        echo -e "${GREEN}Master Node (docker-compose.yml):${NC}"
        docker compose ps
        echo
        
        # Try to get cluster info
        if docker exec rook1 curl -s --cacert config/certs/ca/ca.crt https://localhost:9200 -u elastic:ElasticTESTpassword123 > /dev/null 2>&1; then
            echo -e "${GREEN}Cluster Health:${NC}"
            docker exec rook1 curl -s --cacert config/certs/ca/ca.crt https://localhost:9200/_cluster/health?pretty -u elastic:ElasticTESTpassword123 | grep -E "cluster_name|status|number_of_nodes|active_primary_shards"
            echo
            echo -e "${GREEN}Cluster Nodes:${NC}"
            docker exec rook1 curl -s --cacert config/certs/ca/ca.crt https://localhost:9200/_cat/nodes?v -u elastic:ElasticTESTpassword123
            echo
        fi
    fi
    
    # Check for any additional nodes
    if docker ps --format '{{.Names}}' | grep -qE "^rook[2-9]"; then
        has_nodes=true
        echo -e "${GREEN}Additional Nodes:${NC}"
        docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E "^rook[2-9]|^NAMES"
        echo
    fi

    if [ "$has_master" = false ] && [ "$has_nodes" = false ]; then
        echo_warn "No Elastic Stack containers are running."
        echo
        echo "To deploy:"
        echo "  Master node: $0 deploy-master"
        echo "  Additional node: $0 add-node"
    fi
}

stop_master() {
    echo_step "Stopping master node containers..."
    docker compose stop
    echo_success "Master node stopped."
    echo_info "Data is preserved in ./data/"
    echo_info "To start again: docker compose up -d"
    echo
}

stop_node() {
    echo_step "Stopping additional node..."
    docker compose -f docker-compose-node.yml stop
    echo_success "Node stopped."
    echo_info "Data is preserved in ./data/"
    echo_info "To start again: docker compose -f docker-compose-node.yml up -d"
    echo
}

remove_master() {
    echo_warn "This will remove all master node containers."
    echo_warn "Data in ./data/ will be preserved."
    read -p "Are you sure? (yes/no): " confirm
    
    if [ "$confirm" = "yes" ]; then
        echo_step "Removing master node containers..."
        docker compose down
        docker volume rm clusterofrooks_certs 2>/dev/null || true
        echo_success "Master node removed."
        echo_info "Data preserved in ./data/"
        echo_warn "To completely remove data: sudo rm -rf ./data/"
    else
        echo_info "Cancelled."
    fi
    echo
}

remove_node() {
    echo_warn "This will remove the node container."
    echo_warn "Data in ./data/ will be preserved."
    read -p "Are you sure? (yes/no): " confirm
    
    if [ "$confirm" = "yes" ]; then
        echo_step "Removing node container..."
        docker compose -f docker-compose-node.yml down
        echo_success "Node removed."
        echo_info "Data preserved in ./data/"
    else
        echo_info "Cancelled."
    fi
    echo
}

backup_data() {
    local backup_name="elastic-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    echo_step "Creating backup of all data..."
    echo_info "Backup file: $backup_name"
    
    if [ ! -d "data" ]; then
        echo_error "No data directory found."
        exit 1
    fi
    
    tar czf "$backup_name" data/
    
    local size=$(du -h "$backup_name" | cut -f1)
    echo_success "Backup created: $backup_name ($size)"
    echo
}

show_logs() {
    local service=$1
    
    if [ -z "$service" ]; then
        echo "Available services:"
        echo "  - rook1 (Elasticsearch master)"
        echo "  - kibana"
        echo "  - fleet-server"
        echo "  - all (all master services)"
        echo
        read -p "Which service logs do you want to view? " service
    fi
    
    case "$service" in
        rook1|kibana|fleet-server)
            echo_info "Showing logs for $service (Ctrl+C to exit)..."
            docker compose logs -f "$service"
            ;;
        all)
            echo_info "Showing all master node logs (Ctrl+C to exit)..."
            docker compose logs -f
            ;;
        *)
            echo_error "Unknown service: $service"
            ;;
    esac
}

usage() {
    print_banner
    cat <<EOF
${GREEN}Usage:${NC} $0 [COMMAND]

${CYAN}Deployment Commands:${NC}
  ${YELLOW}deploy-master${NC}       Deploy master node (Elasticsearch + Kibana + Fleet)
  ${YELLOW}add-node${NC}            Deploy additional Elasticsearch data node
  
${CYAN}Certificate Management:${NC}
  ${YELLOW}export-certs${NC}        Export certificates from master node for new nodes
  ${YELLOW}import-certs PATH${NC}   Import certificates on new node server
  
${CYAN}Monitoring:${NC}
  ${YELLOW}status${NC}              Show status of all containers and cluster health
  ${YELLOW}logs [SERVICE]${NC}      View logs (service: rook1, kibana, fleet-server, all)
  
${CYAN}Management:${NC}
  ${YELLOW}stop-master${NC}         Stop master node containers (preserves data)
  ${YELLOW}stop-node${NC}           Stop additional node (preserves data)
  ${YELLOW}remove-master${NC}       Remove master node containers (preserves data)
  ${YELLOW}remove-node${NC}         Remove additional node (preserves data)
  ${YELLOW}backup${NC}              Create backup of all data directories
  
${CYAN}Help:${NC}
  ${YELLOW}help${NC}                Show this help message

${CYAN}Examples:${NC}
  ${GREEN}# Deploy master node${NC}
  $0 deploy-master

  ${GREEN}# Check cluster status${NC}
  $0 status

  ${GREEN}# Export certificates for additional nodes${NC}
  $0 export-certs

  ${GREEN}# On new server: import certificates${NC}
  $0 import-certs ./certs-export

  ${GREEN}# Deploy additional node (after importing certs)${NC}
  $0 add-node

  ${GREEN}# View Elasticsearch logs${NC}
  $0 logs rook1

  ${GREEN}# Create backup${NC}
  $0 backup

${CYAN}Data Locations:${NC}
  ./data/elasticsearch/        - Master node Elasticsearch data
  ./data/kibana/              - Kibana saved objects
  ./data/fleet-server/        - Fleet Server state
  ./data/elasticsearch-rook2/ - Additional node data (if deployed)

${CYAN}Quick Start:${NC}
  1. Edit .env file with your settings
  2. Run: $0 deploy-master
  3. Access Kibana at https://your-ip:5601

EOF
}

# Main execution
main() {
    case "${1:-help}" in
        deploy-master)
            check_docker
            deploy_master
            ;;
        add-node)
            check_docker
            add_node
            ;;
        export-certs)
            export_certs
            ;;
        import-certs)
            import_certs "${2:-}"
            ;;
        status)
            show_status
            ;;
        stop-master)
            stop_master
            ;;
        stop-node)
            stop_node
            ;;
        remove-master)
            remove_master
            ;;
        remove-node)
            remove_node
            ;;
        backup)
            backup_data
            ;;
        logs)
            show_logs "${2:-}"
            ;;
        help|*)
            usage
            ;;
    esac
}

main "$@"
