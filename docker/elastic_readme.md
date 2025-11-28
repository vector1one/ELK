# Elastic Stack Docker Deployment

Complete Docker Compose deployment for Elasticsearch, Kibana, and Fleet Server with multi-node support and persistent host-mapped storage.

## Quick Start - Master Node

1. **Create and configure `.env` file** (already provided)

2. **Create host directories for persistent data:**
```bash
# Create directories
mkdir -p data/elasticsearch data/kibana data/fleet-server

# Set correct permissions (Elasticsearch needs UID 1000)
sudo chown -R 1000:1000 data/
```

Or use the provided script:
```bash
chmod +x setup-directories.sh
./setup-directories.sh
```

3. **Start the stack:**
```bash
docker compose up -d
```

4. **Access the services:**
   - Elasticsearch: https://10.3.10.102:9200
   - Kibana: https://10.3.10.102:5601
   - Fleet Server: https://10.3.10.102:8220

5. **Default credentials:**
   - Username: `elastic`
   - Password: `ElasticTESTpassword123`

6. **Verify cluster health:**
```bash
curl -k -u elastic:ElasticTESTpassword123 https://10.3.10.102:9200/_cluster/health?pretty
```

## Data Persistence

All data is stored on the host filesystem for easy backup and portability:

**Master Node:**
- `./data/elasticsearch/` - Elasticsearch indexes and data
- `./data/kibana/` - Kibana saved objects and settings
- `./data/fleet-server/` - Fleet Server state

**Additional Nodes:**
- `./data/elasticsearch-rook2/` - Node 2 data
- `./data/elasticsearch-rook3/` - Node 3 data

### Backup Data
```bash
# Backup all data
tar czf elastic-backup-$(date +%Y%m%d).tar.gz data/

# Backup just Elasticsearch indexes
tar czf elasticsearch-backup-$(date +%Y%m%d).tar.gz data/elasticsearch/
```

### Restore Data
```bash
# Stop services first
docker compose down

# Restore data
tar xzf elastic-backup-YYYYMMDD.tar.gz

# Fix permissions
sudo chown -R 1000:1000 data/

# Start services
docker compose up -d
```

## Adding Additional Nodes (rook2, rook3, etc.)

### Step 1: Export Certificates from Master Node

On the master node server, export the certificates:

```bash
# Export certs from docker volume to local directory
docker run --rm \
  -v clusterofrooks_certs:/from \
  -v $(pwd)/certs:/to \
  alpine sh -c "cd /from && cp -av . /to"
```

This creates a `./certs` directory with all certificates.

### Step 2: Copy Certificates to New Node

Transfer the `certs` directory to your new node server:

```bash
# Using SCP (from master node)
scp -r ./certs user@new-node-ip:/path/to/elastic-stack/

# Or use rsync
rsync -avz ./certs/ user@new-node-ip:/path/to/elastic-stack/certs/
```

### Step 3: Import Certificates on New Node

On the new node server:

```bash
# Create the docker volume
docker volume create clusterofrooks_certs

# Import certs from local directory to docker volume
docker run --rm \
  -v $(pwd)/certs:/from \
  -v clusterofrooks_certs:/to \
  alpine sh -c "cd /from && cp -av . /to"
```

### Step 4: Configure the New Node

Create or update `.env` file on the new node and **create data directory**:

```bash
# For rook2
NODE_NAME=rook2
NODE_IP=10.3.10.103
ES_PORT=9200
ES_TRANSPORT_PORT=9300

# Create data directory
mkdir -p data/elasticsearch-rook2
sudo chown -R 1000:1000 data/

# For rook3
NODE_NAME=rook3
NODE_IP=10.3.10.104
ES_PORT=9200
ES_TRANSPORT_PORT=9300

# Create data directory
mkdir -p data/elasticsearch-rook3
sudo chown -R 1000:1000 data/
```

### Step 5: Start the New Node

```bash
docker compose -f docker-compose-node.yml up -d
```

### Step 6: Verify Node Joined Cluster

From any node or the master:

```bash
curl -k -u elastic:ElasticTESTpassword123 https://10.3.10.102:9200/_cat/nodes?v
```

You should see all nodes (rook1, rook2, rook3) listed.

## Docker Commands Reference

### Master Node

```bash
# Start the stack
docker compose up -d

# View logs
docker compose logs -f

# Check status
docker compose ps

# Stop the stack
docker compose stop

# Remove everything (including data!)
docker compose down -v

# Restart a specific service
docker compose restart rook1
docker compose restart kibana
docker compose restart fleet-server
```

### Additional Nodes

```bash
# Start node
docker compose -f docker-compose-node.yml up -d

# View logs
docker compose -f docker-compose-node.yml logs -f

# Check status
docker compose -f docker-compose-node.yml ps

# Stop node
docker compose -f docker-compose-node.yml stop

# Remove node
docker compose -f docker-compose-node.yml down -v
```

## Certificate Management (Pure Docker)

### Export Certificates from Master
```bash
docker run --rm \
  -v clusterofrooks_certs:/from \
  -v $(pwd)/certs:/to \
  alpine sh -c "cd /from && cp -av . /to"
```

### Import Certificates to New Node
```bash
docker volume create clusterofrooks_certs
docker run --rm \
  -v $(pwd)/certs:/from \
  -v clusterofrooks_certs:/to \
  alpine sh -c "cd /from && cp -av . /to"
```

### View Certificate Contents
```bash
docker run --rm \
  -v clusterofrooks_certs:/certs \
  alpine ls -lah /certs
```

### Backup Certificates
```bash
docker run --rm \
  -v clusterofrooks_certs:/certs \
  -v $(pwd):/backup \
  alpine tar czf /backup/certs-backup-$(date +%Y%m%d).tar.gz -C /certs .
```

### Restore Certificates
```bash
docker run --rm \
  -v clusterofrooks_certs:/certs \
  -v $(pwd):/backup \
  alpine tar xzf /backup/certs-backup-YYYYMMDD.tar.gz -C /certs
```

## Troubleshooting

### Check if services are healthy
```bash
docker compose ps
```

### View Elasticsearch logs
```bash
docker compose logs -f rook1
```

### View Kibana logs
```bash
docker compose logs -f kibana
```

### View Fleet Server logs
```bash
docker compose logs -f fleet-server
```

### Access Elasticsearch container
```bash
docker exec -it rook1 bash
```

### Check cluster health
```bash
docker exec rook1 curl -k -u elastic:ElasticTESTpassword123 https://localhost:9200/_cluster/health?pretty
```

### Check all nodes in cluster
```bash
docker exec rook1 curl -k -u elastic:ElasticTESTpassword123 https://localhost:9200/_cat/nodes?v
```

### Reset if something goes wrong
```bash
# Stop everything
docker compose down
docker compose -f docker-compose-node.yml down

# Remove docker volumes (certs only - data is on host)
docker volume rm clusterofrooks_certs

# Keep or remove host data as needed
# sudo rm -rf data/  # Only if you want to delete all data!

# Start fresh
mkdir -p data/elasticsearch data/kibana data/fleet-server
sudo chown -R 1000:1000 data/
docker compose up -d
```

## Data Management

### Check disk usage
```bash
du -sh data/*
```

### Move data to another location
```bash
# Stop services
docker compose down

# Move data
sudo mv data /new/location/data

# Update docker-compose.yml volume paths or create symlink
ln -s /new/location/data ./data

# Start services
docker compose up -d
```

### Clone node data to another server
```bash
# Stop node first
docker compose -f docker-compose-node.yml down

# Sync data
rsync -avz --progress data/elasticsearch-rook2/ user@new-server:/path/to/data/elasticsearch-rook2/

# On new server, fix permissions
sudo chown -R 1000:1000 data/
```

## Fleet Agent Enrollment

When enrolling agents, use the `--insecure` flag:

```bash
elastic-agent install \
  --url=https://10.3.10.102:8220 \
  --enrollment-token=YOUR_ENROLLMENT_TOKEN \
  --insecure
```

## Architecture

**Master Node (rook1):**
- Elasticsearch (master, data, ingest roles)
- Kibana
- Fleet Server

**Additional Nodes (rook2, rook3, etc.):**
- Elasticsearch (data, ingest roles only)
- Connects to master node for cluster coordination

## Security Notes

- Self-signed certificates are used
- `verification_mode: none` is set for offline environments
- All communication is encrypted with TLS
- Use `--insecure` flag for agent enrollment
- Change default passwords in production!

## Files

- `docker-compose.yml` - Master node stack (Elasticsearch + Kibana + Fleet)
- `docker-compose-node.yml` - Additional node template
- `.env` - Master node configuration
- `.env-node` - Additional node configuration template
- `setup-directories.sh` - Helper script to create host directories with correct permissions
- `README.md` - This file

## Directory Structure

```
.
├── docker-compose.yml
├── docker-compose-node.yml
├── .env
├── .env-node
├── setup-directories.sh
├── README.md
├── certs/                    # Exported certificates (for node deployment)
└── data/                     # Persistent data on host
    ├── elasticsearch/        # Master node Elasticsearch data
    ├── kibana/              # Kibana data
    ├── fleet-server/        # Fleet Server data
    ├── elasticsearch-rook2/ # Node 2 data (if deployed)
    └── elasticsearch-rook3/ # Node 3 data (if deployed)
```
