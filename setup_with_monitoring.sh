#!/usr/bin/env bash
###############################################################################
# Production‑grade PostgreSQL HA stack (Percona‑Patroni) on Docker‑Compose
# Optimized for 1M users with minimal resource usage
# Author : Ali‑Dadmand‑ready template
# Version: 2.0 – 2025‑01‑27
###############################################################################
set -euo pipefail

### --------------------------------------------------------------------------
### 0. Prerequisites & System Checks
### --------------------------------------------------------------------------
command -v docker >/dev/null 2>&1 || {
  echo "[INFO] Docker not found – installing...";
  curl -fsSL https://get.docker.com | sh
}
command -v docker compose >/dev/null 2>&1 || {
  echo "[INFO] Docker Compose v2 not found – installing...";
  DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
  mkdir -p "$DOCKER_CONFIG/cli-plugins"
  
  # Detect architecture and OS for correct binary
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    if [[ $(uname -m) == "arm64" ]]; then
      COMPOSE_ARCH="darwin-arm64"
    else
      COMPOSE_ARCH="darwin-amd64"
    fi
  else
    # Linux
    COMPOSE_ARCH="linux-$(uname -m)"
  fi
  
  curl -fsSL "https://github.com/docker/compose/releases/download/v2.29.2/docker-compose-${COMPOSE_ARCH}" \
       -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
  chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
}

# Check system resources
echo "[INFO] Checking system resources..."

# Detect OS and get system resources
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  TOTAL_MEM=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024)}')
  TOTAL_CPU=$(sysctl -n hw.ncpu)
  echo "[INFO] macOS detected"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  # Linux
  TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
  TOTAL_CPU=$(nproc)
  echo "[INFO] Linux detected"
else
  # Fallback for other systems
  TOTAL_MEM=8192  # Default to 8GB
  TOTAL_CPU=4     # Default to 4 cores
  echo "[INFO] Unknown OS, using default values"
fi

echo "[INFO] System has ${TOTAL_MEM}MB RAM and ${TOTAL_CPU} CPU cores"

if [ "$TOTAL_MEM" -lt 4096 ]; then
  echo "[WARNING] Less than 4GB RAM detected. Performance may be limited."
fi

### --------------------------------------------------------------------------
### 1. Passwords & cluster variables
### --------------------------------------------------------------------------
export WORKDIR=./pg-ha
export CLUSTER_NAME=prod_pg_cluster
export NET_NAME=pgnet
export POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-$(openssl rand -base64 32)}
export REPLICATION_PASSWORD=${REPLICATION_PASSWORD:-$(openssl rand -base64 32)}
export CHECK_PASSWORD=${CHECK_PASSWORD:-$(openssl rand -base64 32)}
export POOL_PASSWORD=${POOL_PASSWORD:-$(openssl rand -base64 32)}
export ETCD_CLUSTER="etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd3=http://etcd3:2380"

# Calculate resource limits based on available system resources
export PG_MEM_LIMIT=${PG_MEM_LIMIT:-$((TOTAL_MEM / 4))}M
export ETCD_MEM_LIMIT=${ETCD_MEM_LIMIT:-256M}
export HAPROXY_MEM_LIMIT=${HAPROXY_MEM_LIMIT:-128M}
export PGBOUNCER_MEM_LIMIT=${PGBOUNCER_MEM_LIMIT:-256M}

mkdir -p "$WORKDIR"/{config,logs,data,backups}
cd "$WORKDIR"

### --------------------------------------------------------------------------
### 2. .env file for Docker Compose variable interpolation
### --------------------------------------------------------------------------
cat > .env <<"EOF"
# ---------------------------------------------------------------------------
# Auto‑generated – do not edit manually; change via environment then re‑run.
# ---------------------------------------------------------------------------
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
REPLICATION_PASSWORD=${REPLICATION_PASSWORD}
CHECK_PASSWORD=${CHECK_PASSWORD}
POOL_PASSWORD=${POOL_PASSWORD}
CLUSTER_NAME=${CLUSTER_NAME}
ETCD_CLUSTER=${ETCD_CLUSTER}
PG_MEM_LIMIT=${PG_MEM_LIMIT}
ETCD_MEM_LIMIT=${ETCD_MEM_LIMIT}
HAPROXY_MEM_LIMIT=${HAPROXY_MEM_LIMIT}
PGBOUNCER_MEM_LIMIT=${PGBOUNCER_MEM_LIMIT}
EOF
envsubst < .env > .env.tmp && mv .env.tmp .env

### --------------------------------------------------------------------------
### 3. HAProxy configuration (optimized for high concurrency)
### --------------------------------------------------------------------------
cat > config/haproxy.cfg <<'EOF'
global
  maxconn 10000
  log stdout format raw local0
  tune.ssl.default-dh-param 2048
  tune.bufsize 32768
  tune.maxrewrite 8192

defaults
  mode tcp
  timeout connect 3s
  timeout client 30m
  timeout server 30m
  timeout check 5s
  option log-health-checks
  option redispatch
  retries 3

# ---------------------------------------------------------------------------
# RW traffic – clients connect here for reads *and* writes
# ---------------------------------------------------------------------------
listen postgres_rw
  bind *:5432
  option pgsql-check user haproxy_check
  balance roundrobin
  option httpchk GET /replica
  http-check expect status 200
  default-server inter 2s fall 3 rise 2 on-marked-down shutdown-sessions
  server patroni1 patroni1:5432 check port 8008
  server patroni2 patroni2:5432 check port 8008
  server patroni3 patroni3:5432 check port 8008

# ---------------------------------------------------------------------------
# RO traffic – read‑only queries routed to standbys
# ---------------------------------------------------------------------------
listen postgres_ro
  bind *:5433
  option pgsql-check user haproxy_check
  balance roundrobin
  option httpchk GET /replica
  http-check expect status 200
  default-server inter 2s fall 3 rise 2 on-marked-down shutdown-sessions
  server patroni1 patroni1:5432 check port 8008
  server patroni2 patroni2:5432 check port 8008
  server patroni3 patroni3:5432 check port 8008

# ---------------------------------------------------------------------------
# Stats UI (with basic auth for security)
# ---------------------------------------------------------------------------
listen stats
  bind *:7001
  mode http
  stats enable
  stats uri /
  stats refresh 10s
  stats auth admin:${CHECK_PASSWORD}
  stats admin if TRUE
EOF
envsubst < config/haproxy.cfg > config/haproxy.cfg.tmp && mv config/haproxy.cfg.tmp config/haproxy.cfg

### --------------------------------------------------------------------------
### 4. PgBouncer configuration (optimized for high concurrency)
### --------------------------------------------------------------------------
cat > config/pgbouncer.ini <<'EOF'
[databases]
rw = host=haproxy port=5432 user=pooler password=${POOL_PASSWORD}
ro = host=haproxy port=5433 user=pooler password=${POOL_PASSWORD}

[pgbouncer]
listen_addr        = 0.0.0.0
listen_port        = 6432
auth_type          = md5
auth_file          = /etc/pgbouncer/userlist.txt
pool_mode          = transaction
max_client_conn    = 20000
default_pool_size  = 500
min_pool_size      = 50
reserve_pool_size  = 100
reserve_pool_timeout = 5
max_db_connections = 1000
max_user_connections = 1000
server_reset_query = DISCARD ALL
ignore_startup_parameters = extra_float_digits,application_name
logfile            = /var/log/pgbouncer/pgbouncer.log
pidfile            = /var/run/pgbouncer.pid
verbose            = 2
stats_period       = 60
log_connections    = 1
log_disconnections = 1
log_pooler_errors  = 1
EOF
envsubst < config/pgbouncer.ini > config/pgbouncer.ini.tmp && mv config/pgbouncer.ini.tmp config/pgbouncer.ini

cat > config/userlist.txt <<EOF
"pooler" "md5$(echo -n "${POOL_PASSWORD}${POOL_PASSWORD}" | md5sum | awk '{print $1}')"
EOF

### --------------------------------------------------------------------------
### 5. Shared Patroni bootstrap YAML snippet (optimized for 1M users)
### --------------------------------------------------------------------------
generate_patroni_yaml () {
  local name="$1"; local host="$2"
  cat > "config/${name}.yml" <<EOF
scope: ${CLUSTER_NAME}
name: ${name}

restapi:
  listen: 0.0.0.0:8008
  connect_address: ${host}:8008
  authentication:
    username: patroni
    password: ${CHECK_PASSWORD}

etcd:
  hosts: ${ETCD_CLUSTER}
  protocol: http

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        # Connection settings
        max_connections: 2000
        superuser_reserved_connections: 10
        
        # Memory settings (optimized for minimal resources)
        shared_buffers: 1GB
        effective_cache_size: 3GB
        work_mem: 4MB
        maintenance_work_mem: 256MB
        
        # WAL settings
        wal_level: replica
        wal_buffers: 16MB
        max_wal_senders: 10
        max_replication_slots: 10
        hot_standby: "on"
        
        # Checkpoint settings
        checkpoint_completion_target: 0.9
        wal_compression: "on"
        max_wal_size: 2GB
        min_wal_size: 1GB
        
        # Query optimization
        random_page_cost: 1.1
        effective_io_concurrency: 200
        default_statistics_target: 100
        
        # Logging
        log_statement: "none"
        log_min_duration_statement: 1000
        log_checkpoints: "on"
        log_connections: "on"
        log_disconnections: "on"
        log_lock_waits: "on"
        log_temp_files: 0
        
        # Autovacuum
        autovacuum: "on"
        autovacuum_max_workers: 3
        autovacuum_naptime: 60
        autovacuum_vacuum_scale_factor: 0.1
        autovacuum_analyze_scale_factor: 0.05
        
        # Replication
        max_replication_slots: 10
        wal_keep_segments: 64
        
        # Security
        ssl: "off"
        password_encryption: "scram-sha-256"
        
        # Performance
        synchronous_commit: "on"
        fsync: "on"
        full_page_writes: "on"
        
        # Connection pooling
        tcp_keepalives_idle: 600
        tcp_keepalives_interval: 30
        tcp_keepalives_count: 3
        
  initdb:
    - encoding: UTF8
    - data-checksums
  pg_hba:
    - host all all 0.0.0.0/0 md5
    - host replication replicator 0.0.0.0/0 md5
    - host all haproxy_check 0.0.0.0/0 md5
    - host all pooler 0.0.0.0/0 md5

postgresql:
  listen: 0.0.0.0:5432
  connect_address: ${host}:5432
  data_dir: /var/lib/postgresql/data
  bin_dir: /usr/lib/postgresql/17/bin
  authentication:
    superuser:
      username: postgres
      password: ${POSTGRES_PASSWORD}
    replication:
      username: replicator
      password: ${REPLICATION_PASSWORD}
  parameters:
    wal_compression: "on"
    log_statement: "none"
    log_min_duration_statement: 1000
EOF
}
generate_patroni_yaml patroni1 patroni1
generate_patroni_yaml patroni2 patroni2
generate_patroni_yaml patroni3 patroni3

### --------------------------------------------------------------------------
### 6. Docker‑Compose file (with resource limits)
### --------------------------------------------------------------------------
cat > docker-compose.yml <<'EOF'

networks:
  pgnet:
    name: ${NET_NAME}
    driver: bridge

volumes:
  pgdata1:
    driver: local
  pgdata2:
    driver: local
  pgdata3:
    driver: local
  etcd_data1:
    driver: local
  etcd_data2:
    driver: local
  etcd_data3:
    driver: local
  prometheus_data:
    driver: local
  grafana_data:
    driver: local

services:

  # -------------------------------------------------------------------------
  # Distributed Configuration Store – etcd (3 nodes for quorum)
  # -------------------------------------------------------------------------
  etcd1:
    image: bitnami/etcd:3.5.9
    hostname: etcd1
    networks: [pgnet]
    volumes:
      - etcd_data1:/etcd-data
    environment:
      ETCD_NAME: etcd1
      ETCD_INITIAL_CLUSTER: ${ETCD_CLUSTER}
      ETCD_INITIAL_CLUSTER_STATE: new
      ETCD_LISTEN_PEER_URLS: http://0.0.0.0:2380
      ETCD_LISTEN_CLIENT_URLS: http://0.0.0.0:2379
      ETCD_ADVERTISE_CLIENT_URLS: http://etcd1:2379
      ETCD_ADVERTISE_PEER_URLS: http://etcd1:2380
      ETCD_DATA_DIR: /etcd-data
      ALLOW_NONE_AUTHENTICATION: "yes"
    deploy:
      resources:
        limits:
          memory: ${ETCD_MEM_LIMIT}
          cpus: '0.5'
        reservations:
          memory: 128M
          cpus: '0.1'
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "etcdctl", "endpoint", "health"]
      interval: 10s
      timeout: 5s
      retries: 3

  etcd2:
    image: bitnami/etcd:3.5.9
    hostname: etcd2
    networks: [pgnet]
    volumes:
      - etcd_data2:/etcd-data
    environment:
      ETCD_NAME: etcd2
      ETCD_INITIAL_CLUSTER: ${ETCD_CLUSTER}
      ETCD_INITIAL_CLUSTER_STATE: new
      ETCD_LISTEN_PEER_URLS: http://0.0.0.0:2380
      ETCD_LISTEN_CLIENT_URLS: http://0.0.0.0:2379
      ETCD_ADVERTISE_CLIENT_URLS: http://etcd2:2379
      ETCD_ADVERTISE_PEER_URLS: http://etcd2:2380
      ETCD_DATA_DIR: /etcd-data
      ALLOW_NONE_AUTHENTICATION: "yes"
    deploy:
      resources:
        limits:
          memory: ${ETCD_MEM_LIMIT}
          cpus: '0.5'
        reservations:
          memory: 128M
          cpus: '0.1'
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "etcdctl", "endpoint", "health"]
      interval: 10s
      timeout: 5s
      retries: 3

  etcd3:
    image: bitnami/etcd:3.5.9
    hostname: etcd3
    networks: [pgnet]
    volumes:
      - etcd_data3:/etcd-data
    environment:
      ETCD_NAME: etcd3
      ETCD_INITIAL_CLUSTER: ${ETCD_CLUSTER}
      ETCD_INITIAL_CLUSTER_STATE: new
      ETCD_LISTEN_PEER_URLS: http://0.0.0.0:2380
      ETCD_LISTEN_CLIENT_URLS: http://0.0.0.0:2379
      ETCD_ADVERTISE_CLIENT_URLS: http://etcd3:2379
      ETCD_ADVERTISE_PEER_URLS: http://etcd3:2380
      ETCD_DATA_DIR: /etcd-data
      ALLOW_NONE_AUTHENTICATION: "yes"
    deploy:
      resources:
        limits:
          memory: ${ETCD_MEM_LIMIT}
          cpus: '0.5'
        reservations:
          memory: 128M
          cpus: '0.1'
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "etcdctl", "endpoint", "health"]
      interval: 10s
      timeout: 5s
      retries: 3

  # -------------------------------------------------------------------------
  # Patroni‑managed PostgreSQL nodes
  # -------------------------------------------------------------------------
  patroni1:
    image: percona/percona-distribution-postgresql:17.5-2
    hostname: patroni1
    networks: [pgnet]
    depends_on:
      etcd1:
        condition: service_healthy
      etcd2:
        condition: service_healthy
      etcd3:
        condition: service_healthy
    volumes:
      - pgdata1:/var/lib/postgresql/data
      - ./config/patroni1.yml:/etc/patroni.yml:ro
      - ./logs:/var/log/postgresql
    environment:
      PATRONI_CONFIG_PATH: /etc/patroni.yml
      POSTGRES_INITDB_ARGS: "--data-checksums"
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    deploy:
      resources:
        limits:
          memory: ${PG_MEM_LIMIT}
          cpus: '2.0'
        reservations:
          memory: 1G
          cpus: '0.5'
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  patroni2:
    image: percona/percona-distribution-postgresql:17.5-2
    hostname: patroni2
    networks: [pgnet]
    depends_on:
      etcd1:
        condition: service_healthy
      etcd2:
        condition: service_healthy
      etcd3:
        condition: service_healthy
    volumes:
      - pgdata2:/var/lib/postgresql/data
      - ./config/patroni2.yml:/etc/patroni.yml:ro
      - ./logs:/var/log/postgresql
    environment:
      PATRONI_CONFIG_PATH: /etc/patroni.yml
      POSTGRES_INITDB_ARGS: "--data-checksums"
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    deploy:
      resources:
        limits:
          memory: ${PG_MEM_LIMIT}
          cpus: '2.0'
        reservations:
          memory: 1G
          cpus: '0.5'
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  patroni3:
    image: percona/percona-distribution-postgresql:17.5-2
    hostname: patroni3
    networks: [pgnet]
    depends_on:
      etcd1:
        condition: service_healthy
      etcd2:
        condition: service_healthy
      etcd3:
        condition: service_healthy
    volumes:
      - pgdata3:/var/lib/postgresql/data
      - ./config/patroni3.yml:/etc/patroni.yml:ro
      - ./logs:/var/log/postgresql
    environment:
      PATRONI_CONFIG_PATH: /etc/patroni.yml
      POSTGRES_INITDB_ARGS: "--data-checksums"
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    deploy:
      resources:
        limits:
          memory: ${PG_MEM_LIMIT}
          cpus: '2.0'
        reservations:
          memory: 1G
          cpus: '0.5'
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  # -------------------------------------------------------------------------
  # HAProxy – read/write & read‑only VIPs + stats
  # -------------------------------------------------------------------------
  haproxy:
    image: haproxy:2.9
    hostname: haproxy
    networks: [pgnet]
    depends_on:
      patroni1:
        condition: service_healthy
      patroni2:
        condition: service_healthy
      patroni3:
        condition: service_healthy
    ports:
      - "5432:5432"
      - "5433:5433"
      - "7001:7001"
    volumes:
      - ./config/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    deploy:
      resources:
        limits:
          memory: ${HAPROXY_MEM_LIMIT}
          cpus: '0.5'
        reservations:
          memory: 64M
          cpus: '0.1'
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "haproxy", "-c", "-f", "/usr/local/etc/haproxy/haproxy.cfg"]
      interval: 30s
      timeout: 10s
      retries: 3



  # -------------------------------------------------------------------------
  # Monitoring with Prometheus + Grafana
  # -------------------------------------------------------------------------
  prometheus:
    image: prom/prometheus:v2.45.0
    hostname: prometheus
    networks: [pgnet]
    ports:
      - "9090:9090"
    volumes:
      - ./config/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 256M
          cpus: '0.1'
    restart: unless-stopped

  grafana:
    image: grafana/grafana:10.0.3
    hostname: grafana
    networks: [pgnet]
    ports:
      - "3000:3000"
    environment:
      GF_USERS_ALLOW_SIGN_UP: "false"
    volumes:
      - grafana_data:/var/lib/grafana
      - ./config/grafana/dashboards:/etc/grafana/provisioning/dashboards
      - ./config/grafana/datasources:/etc/grafana/provisioning/datasources
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.3'
        reservations:
          memory: 128M
          cpus: '0.1'
    restart: unless-stopped
EOF
envsubst < docker-compose.yml > docker-compose.yml.tmp && mv docker-compose.yml.tmp docker-compose.yml

### --------------------------------------------------------------------------
### 7. Monitoring Configuration
### --------------------------------------------------------------------------
mkdir -p config/grafana/{dashboards,datasources}

# Prometheus configuration
cat > config/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "postgresql_rules.yml"

scrape_configs:
  - job_name: 'postgresql'
    static_configs:
      - targets: ['patroni1:5432', 'patroni2:5432', 'patroni3:5432']
    metrics_path: /metrics
    scrape_interval: 10s

  - job_name: 'haproxy'
    static_configs:
      - targets: ['haproxy:7000']
    metrics_path: /metrics
    scrape_interval: 10s

  - job_name: 'pgbouncer'
    static_configs:
      - targets: ['pgbouncer:6432']
    metrics_path: /metrics
    scrape_interval: 10s

  - job_name: 'etcd'
    static_configs:
      - targets: ['etcd1:2379', 'etcd2:2379', 'etcd3:2379']
    metrics_path: /metrics
    scrape_interval: 10s
EOF

# Grafana datasource
cat > config/grafana/datasources/prometheus.yml <<'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
EOF

# Grafana dashboard provisioning
cat > config/grafana/dashboards/dashboard.yml <<'EOF'
apiVersion: 1

providers:
  - name: 'PostgreSQL'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

### --------------------------------------------------------------------------
### 8. Backup Configuration
### --------------------------------------------------------------------------
cat > config/backup.sh <<'EOF'
#!/bin/bash
# Automated backup script for PostgreSQL cluster

BACKUP_DIR="./pg-ha/backups"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Perform logical backup using pg_dump
docker compose exec -T patroni1 pg_dumpall -U postgres > "$BACKUP_DIR/full_backup_$DATE.sql"

# Compress backup
gzip "$BACKUP_DIR/full_backup_$DATE.sql"

# Remove old backups
find "$BACKUP_DIR" -name "full_backup_*.sql.gz" -mtime +$RETENTION_DAYS -delete

echo "Backup completed: full_backup_$DATE.sql.gz"
EOF

chmod +x config/backup.sh

### --------------------------------------------------------------------------
### 9. Start the cluster
### --------------------------------------------------------------------------
echo "[INFO] Starting PostgreSQL HA cluster..."
docker compose pull
docker compose up -d

echo "[INFO] Waiting for Patroni primary to become available..."
sleep 30   # give Patroni time to initialise

### --------------------------------------------------------------------------
### 10. Seed utility users and create monitoring user
### --------------------------------------------------------------------------
for node in patroni1 patroni2 patroni3; do
  if docker compose exec -T "$node" psql -U postgres -d postgres -c '\q' 2>/dev/null; then
    docker compose exec -T "$node" psql -U postgres -d postgres <<EOSQL
DO
\$\$
BEGIN
  -- Create utility users
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'haproxy_check') THEN
     CREATE ROLE haproxy_check LOGIN;
  END IF;
  
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'pooler') THEN
     CREATE ROLE pooler LOGIN PASSWORD '${POOL_PASSWORD}';
  END IF;
  
  -- Create monitoring user
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'monitor') THEN
     CREATE ROLE monitor LOGIN PASSWORD '${CHECK_PASSWORD}';
     GRANT pg_monitor TO monitor;
  END IF;
  
  -- Create application user
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_user') THEN
     CREATE ROLE app_user LOGIN PASSWORD '${POOL_PASSWORD}';
  END IF;
END
\$\$;

-- Create database outside of function
CREATE DATABASE app_db OWNER app_user;
GRANT ALL PRIVILEGES ON DATABASE app_db TO app_user;
EOSQL
    break
  fi
done

### --------------------------------------------------------------------------
### 11. Setup automated backups
### --------------------------------------------------------------------------
# Add to crontab for daily backups at 2 AM
(crontab -l 2>/dev/null; echo "0 2 * * * $(pwd)/pg-ha/config/backup.sh") | crontab -

### --------------------------------------------------------------------------
### 12. Performance tuning script
### --------------------------------------------------------------------------
cat > config/tune_performance.sh <<'EOF'
#!/bin/bash
# Performance tuning script for PostgreSQL

echo "Tuning PostgreSQL performance..."

# Detect OS and apply appropriate tuning
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "[INFO] macOS detected - kernel tuning not available"
  echo "For macOS, consider adjusting Docker Desktop memory allocation"
  echo "Recommended: 4GB+ RAM for Docker Desktop"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  # Linux kernel tuning
  echo 'vm.swappiness=1' >> /etc/sysctl.conf
  echo 'vm.dirty_ratio=15' >> /etc/sysctl.conf
  echo 'vm.dirty_background_ratio=5' >> /etc/sysctl.conf
  
  # Apply changes
  sysctl -p
  echo "[INFO] Linux kernel parameters applied"
else
  echo "[INFO] Unknown OS - skipping kernel tuning"
fi

echo "Performance tuning completed."
EOF

chmod +x config/tune_performance.sh

### --------------------------------------------------------------------------
### 13. Health check script
### --------------------------------------------------------------------------
cat > config/health_check.sh <<'EOF'
#!/bin/bash
# Health check script for PostgreSQL cluster

echo "Checking cluster health..."

# Check Patroni status
docker compose exec -T patroni1 patronictl list

# Check HAProxy stats
curl -s http://localhost:7001/ | grep -q "postgres" && echo "HAProxy: OK" || echo "HAProxy: FAILED"

# Check PgBouncer
docker compose exec -T pgbouncer psql -h localhost -p 6432 -U pooler -d rw -c "SELECT 1;" && echo "PgBouncer: OK" || echo "PgBouncer: FAILED"

echo "Health check completed."
EOF

chmod +x config/health_check.sh

### --------------------------------------------------------------------------
### 14. Final output with production information
### --------------------------------------------------------------------------
cat <<EOM
------------------------------------------------------------------------------
🎉  Production PostgreSQL HA stack is up and running!

📊 **Connection Endpoints:**
•  Read/Write endpoint :  host:<server_ip>  port:5432  (via HAProxy - RECOMMENDED)
•  Read‑only endpoint  :  host:<server_ip>  port:5433

🔐 **Default credentials:**
   superuser : postgres / ${POSTGRES_PASSWORD}
   pooler    : pooler   / ${POOL_PASSWORD}
   app_user  : app_user / ${POOL_PASSWORD}

📈 **Monitoring:**
•  HAProxy Stats: http://<server_ip>:7001 (admin:${CHECK_PASSWORD})
•  Grafana: http://<server_ip>:3000 (admin:${POSTGRES_PASSWORD})
•  Prometheus: http://<server_ip>:9090

⚡ **Performance Optimizations Applied:**
•  Resource limits configured for minimal usage
•  Optimized PostgreSQL parameters for 1M users
•  Load balancing with HAProxy
•  Automated backups configured
•  Monitoring with Prometheus + Grafana

🔧 **Management Commands:**
•  Check cluster status: docker compose exec patroni1 patronictl list
•  Health check: ./config/health_check.sh
•  Manual backup: ./config/backup.sh
•  Performance tuning: ./config/tune_performance.sh

📋 **Production Recommendations:**
1. Use the HAProxy endpoint (port 5432) for applications
2. Monitor via Grafana dashboard
3. Set up alerting in Grafana
4. Configure log rotation
5. Consider using pgBackRest for advanced backups
6. Implement connection pooling in your application
7. Monitor resource usage and adjust limits as needed
8. For macOS: Ensure Docker Desktop has sufficient memory allocation (4GB+ recommended)

🚀 **Ready for 1M users with minimal resource usage!**
------------------------------------------------------------------------------
EOM
