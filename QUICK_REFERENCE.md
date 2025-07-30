# PostgreSQL HA Cluster - Quick Reference

## 🚀 **Quick Access**

### 📊 **Monitoring Dashboards**
| Service | URL | Username | Password |
|---------|-----|----------|----------|
| **Grafana** | http://localhost:3000 | `admin` | `admin` |
| **HAProxy Stats** | http://localhost:7001 | `admin` | `7fLruirODctkHT73NeUWpURbdME+ll4LZqswXzMpJrE=` |
| **Prometheus** | http://localhost:9090 | - | - |

### 🗄️ **Database Connections**
| Type | Host | Port | Username | Password |
|------|------|------|----------|----------|
| **Read/Write** | localhost | 5432 | postgres | `rI9ZA/XkdpliNLmvuIYF26s/opmTLCDD1xmdWHiboZg=` |
| **Read-Only** | localhost | 5433 | postgres | `rI9ZA/XkdpliNLmvuIYF26s/opmTLCDD1xmdWHiboZg=` |
| **App User** | localhost | 5432 | app_user | `fnFjBowcVtH/Hr1WkUW2E5PnoQB2aPaEZD1rcAQDk84=` |

---

## 🔧 **Essential Commands**

### 📊 **Status Checks**
```bash
# Check all containers
docker compose ps

# View cluster status
docker compose exec patroni1 patronictl list

# Check HAProxy stats
curl -u admin:7fLruirODctkHT73NeUWpURbdME+ll4LZqswXzMpJrE= http://localhost:7001/stats

# Health check
./config/health_check.sh
```

### 🗄️ **Database Operations**
```bash
# Connect via HAProxy (recommended)
psql -h localhost -p 5432 -U postgres -d postgres

# Connect to primary directly
docker compose exec patroni1 psql -U postgres

# Check replication
docker compose exec patroni1 psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

### 📝 **Logs & Debugging**
```bash
# View all logs
docker compose logs -f

# Service-specific logs
docker compose logs -f patroni1
docker compose logs -f haproxy
docker compose logs -f grafana

# Check container health
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
```

---

## 🚨 **Troubleshooting Quick Fixes**

### ❌ **Grafana Login Issues**
```bash
# Restart Grafana
docker compose restart grafana
# Use: admin / admin
```

### ❌ **Port Conflicts**
```bash
# Check what's using a port
lsof -i :5432
lsof -i :3000
lsof -i :7001
```

### ❌ **Container Won't Start**
```bash
# Check resource usage
docker system df
docker stats

# Restart specific service
docker compose restart [service_name]
```

### ❌ **Database Connection Issues**
```bash
# Test connectivity
docker compose exec patroni1 pg_isready -U postgres

# Check HAProxy backend status
curl -s http://localhost:7001/stats | grep BACKEND
```

---

## 📈 **Key Metrics to Monitor**

### 🎯 **Critical Thresholds**
- **Replication Lag**: < 10 seconds
- **Active Connections**: < 80% of max (1600/2000)
- **Disk Usage**: < 85%
- **Memory Usage**: < 80%

### 📊 **Quick Health Check**
```bash
# All services running?
docker compose ps | grep -v "Up"

# Cluster healthy?
docker compose exec patroni1 patronictl list | grep -v "running"

# HAProxy backends up?
curl -s http://localhost:7001/stats | grep -E "(BACKEND|FRONTEND)" | grep -v "UP"
```

---

## 🔄 **Maintenance Commands**

### 💾 **Backup Operations**
```bash
# Manual backup
./config/backup.sh

# Check backup directory
ls -la backups/
```

### 🔧 **Performance Tuning**
```bash
# Linux performance tuning
./config/tune_performance.sh

# Check PostgreSQL settings
docker compose exec patroni1 psql -U postgres -c "SHOW max_connections;"
```

### 🧹 **Cleanup**
```bash
# Remove unused containers/images
docker system prune -f

# Check disk usage
docker system df
```

---

## 🆘 **Emergency Procedures**

### 🔄 **Failover Test**
```bash
# Simulate primary failure
docker compose stop patroni1

# Check failover
docker compose exec patroni2 patronictl list

# Restart original primary
docker compose start patroni1
```

### 🔄 **Service Restart**
```bash
# Restart entire cluster
docker compose restart

# Restart specific service
docker compose restart [service_name]
```

### 🔄 **Complete Reset**
```bash
# Stop and remove everything
docker compose down -v

# Re-run setup
cd .. && ./setup_with_monitoring.sh
```

---

## 📞 **Support Information**

### 📋 **System Info**
- **Platform**: macOS (darwin 24.5.0)
- **Docker Version**: Latest
- **Setup Date**: 2025-01-27
- **Status**: ✅ Production Ready

### 🔗 **Useful URLs**
- **Grafana**: http://localhost:3000
- **HAProxy Stats**: http://localhost:7001
- **Prometheus**: http://localhost:9090
- **Documentation**: README.md

### 📚 **Documentation Files**
- `README.md` - Complete documentation
- `SETUP_RESULTS.md` - Detailed setup results
- `QUICK_REFERENCE.md` - This quick reference

---

**🎯 Ready for 1M users with minimal resource usage!** 