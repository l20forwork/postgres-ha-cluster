# PostgreSQL High Availability Cluster Setup

## 🎯 **Project Overview**

This project provides a **production-ready PostgreSQL High Availability (HA) cluster** optimized for **1 million users** with minimal resource usage. The setup includes automatic failover, load balancing, monitoring, and backup capabilities.

## 📋 **Architecture Components**

### Core Services
- **PostgreSQL Cluster**: 3-node Patroni-managed PostgreSQL instances
- **etcd**: Distributed configuration store for cluster coordination
- **HAProxy**: Load balancer for read/write traffic distribution
- **Prometheus**: Metrics collection and monitoring
- **Grafana**: Data visualization and dashboards

### Production Features
- ✅ **Automatic failover** with Patroni
- ✅ **Load balancing** with HAProxy
- ✅ **Monitoring** with Prometheus + Grafana
- ✅ **Automated backups** with retention
- ✅ **Health checks** and performance tuning
- ✅ **Resource limits** for minimal usage
- ✅ **Cross-platform** (macOS/Linux) compatibility

## 🚀 **Quick Start**

### Prerequisites
- Docker and Docker Compose installed
- At least 4GB RAM available for Docker
- Ports 5432, 5433, 3000, 7001, 9090 available

### Installation
```bash
# Clone or download the setup script
chmod +x setup_with_monitoring.sh

# Run the setup
./setup_with_monitoring.sh
```

### Final Results
After successful setup, you'll have:

#### 🔐 **Connection Endpoints**
- **Read/Write**: `localhost:5432` (via HAProxy - RECOMMENDED)
- **Read-Only**: `localhost:5433`

#### 📊 **Monitoring Dashboards**
- **Grafana**: `http://localhost:3000`
  - Username: `admin`
  - Password: `admin`
- **HAProxy Stats**: `http://localhost:7001`
  - Username: `admin`
  - Password: `7fLruirODctkHT73NeUWpURbdME+ll4LZqswXzMpJrE=`
- **Prometheus**: `http://localhost:9090`

#### 🔑 **Database Credentials**
```
Superuser: postgres / rI9ZA/XkdpliNLmvuIYF26s/opmTLCDD1xmdWHiboZg=
Pooler:   pooler   / fnFjBowcVtH/Hr1WkUW2E5PnoQB2aPaEZD1rcAQDk84=
App User: app_user / fnFjBowcVtH/Hr1WkUW2E5PnoQB2aPaEZD1rcAQDk84=
```

## 📈 **Performance Optimizations**

### Resource Allocation
- **PostgreSQL**: 1GB RAM, 2 CPU cores per node
- **etcd**: 256MB RAM, 0.5 CPU cores per node
- **HAProxy**: 128MB RAM, 0.25 CPU cores
- **Prometheus**: 512MB RAM, 1 CPU core
- **Grafana**: 256MB RAM, 0.5 CPU cores

### PostgreSQL Tuning
```yaml
# Key optimizations for 1M users
max_connections: 2000
shared_buffers: 1GB
effective_cache_size: 3GB
work_mem: 4MB
maintenance_work_mem: 256MB
wal_buffers: 16MB
checkpoint_completion_target: 0.9
max_wal_size: 2GB
autovacuum_max_workers: 3
```

## 🔧 **Management Commands**

### Cluster Status
```bash
# Check cluster health
docker compose ps

# View Patroni cluster status
docker compose exec patroni1 patronictl list

# Check HAProxy stats
curl -u admin:7fLruirODctkHT73NeUWpURbdME+ll4LZqswXzMpJrE= http://localhost:7001/stats

# Health check script
./config/health_check.sh
```

### Backup & Maintenance
```bash
# Manual backup
./config/backup.sh

# Performance tuning (Linux only)
./config/tune_performance.sh

# View logs
docker compose logs -f [service_name]
```

### Database Operations
```bash
# Connect to primary database
docker compose exec patroni1 psql -U postgres -d postgres

# Connect via HAProxy (recommended)
psql -h localhost -p 5432 -U postgres -d postgres

# Check replication lag
docker compose exec patroni1 psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

## 🛠️ **Troubleshooting**

### Common Issues & Solutions

#### 1. Grafana Login Issues
**Problem**: "Invalid username or password"
**Solution**: 
- Use default credentials: `admin` / `admin`
- If blocked, restart Grafana: `docker compose restart grafana`

#### 2. Port Conflicts
**Problem**: "Port already in use"
**Solution**:
- Check for conflicting services: `lsof -i :[port]`
- Modify ports in `docker-compose.yml` if needed

#### 3. Resource Issues
**Problem**: Containers failing to start
**Solution**:
- Ensure Docker Desktop has sufficient memory (4GB+ recommended)
- Check system resources: `docker system df`

#### 4. macOS Compatibility
**Problem**: `free: command not found`
**Solution**: Script automatically detects macOS and uses appropriate commands

### Health Checks
```bash
# Check all services
docker compose ps

# Check specific service logs
docker compose logs [service_name]

# Test database connectivity
docker compose exec patroni1 pg_isready -U postgres
```

## 📊 **Monitoring & Alerts**

### Grafana Dashboards
- **PostgreSQL Overview**: Key metrics and performance indicators
- **HAProxy Stats**: Load balancer performance and traffic distribution
- **System Resources**: CPU, memory, and disk usage

### Key Metrics to Monitor
- **Database Connections**: Active connections and connection pool usage
- **Replication Lag**: Time difference between primary and replicas
- **Query Performance**: Slow queries and execution times
- **System Resources**: CPU, memory, and disk I/O

### Alerting Setup
1. Configure alerting rules in Grafana
2. Set up notification channels (email, Slack, etc.)
3. Monitor critical thresholds:
   - Replication lag > 10 seconds
   - Connection count > 80% of max
   - Disk usage > 85%

## 🔒 **Security Considerations**

### Production Hardening
1. **Change default passwords** after setup
2. **Enable SSL/TLS** for database connections
3. **Configure firewall rules** to restrict access
4. **Use connection pooling** in applications
5. **Implement proper backup encryption**

### Network Security
```bash
# Restrict access to monitoring endpoints
# Add to your firewall rules
iptables -A INPUT -p tcp --dport 5432 -s [trusted_ips] -j ACCEPT
iptables -A INPUT -p tcp --dport 3000 -s [trusted_ips] -j ACCEPT
```

## 📈 **Scaling Considerations**

### Vertical Scaling
- Increase resource limits in `docker-compose.yml`
- Adjust PostgreSQL parameters based on workload
- Monitor and tune based on actual usage patterns

### Horizontal Scaling
- Add more PostgreSQL nodes (requires Patroni configuration updates)
- Implement read replicas for read-heavy workloads
- Consider sharding for very large datasets

## 🗂️ **File Structure**

```
postgres_cluster/
├── setup_with_monitoring.sh    # Main setup script
├── README.md                   # This documentation
└── pg-ha/                     # Generated cluster directory
    ├── docker-compose.yml      # Docker Compose configuration
    ├── config/                 # Configuration files
    │   ├── haproxy.cfg        # HAProxy configuration
    │   ├── grafana/           # Grafana dashboards & datasources
    │   ├── backup.sh          # Backup script
    │   ├── health_check.sh    # Health monitoring script
    │   └── tune_performance.sh # Performance tuning script
    ├── logs/                  # Application logs
    ├── data/                  # Database data volumes
    └── backups/               # Automated backups
```

## 🎯 **Production Checklist**

### Before Going Live
- [ ] Change all default passwords
- [ ] Configure SSL/TLS certificates
- [ ] Set up proper backup retention
- [ ] Configure monitoring alerts
- [ ] Test failover scenarios
- [ ] Document recovery procedures
- [ ] Set up log rotation
- [ ] Configure firewall rules

### Regular Maintenance
- [ ] Monitor backup success/failure
- [ ] Review slow query logs
- [ ] Check disk space usage
- [ ] Update security patches
- [ ] Review performance metrics
- [ ] Test disaster recovery procedures

## 📞 **Support & Resources**

### Useful Commands
```bash
# View cluster topology
docker compose exec patroni1 patronictl topology

# Check PostgreSQL configuration
docker compose exec patroni1 psql -U postgres -c "SHOW ALL;"

# Monitor replication status
docker compose exec patroni1 psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Check HAProxy backend status
curl -s http://localhost:7001/stats | grep -E "(BACKEND|FRONTEND)"
```

### Documentation Links
- [Patroni Documentation](https://patroni.readthedocs.io/)
- [HAProxy Documentation](https://www.haproxy.org/download/2.4/doc/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Grafana Documentation](https://grafana.com/docs/)

## 🏆 **Success Metrics**

After successful deployment, you should see:
- ✅ All containers running and healthy
- ✅ Grafana accessible with working dashboards
- ✅ HAProxy distributing traffic correctly
- ✅ PostgreSQL replication working
- ✅ Automated backups running
- ✅ Monitoring metrics being collected

---

**Version**: 2.0 - 2025-01-27  
**Compatibility**: macOS, Linux  
**Optimized for**: 1M users with minimal resource usage  
**Status**: ✅ Production Ready 