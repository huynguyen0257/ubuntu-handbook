# 🧾 Handover Document – Portainer “Hybrid Systemd + Docker Compose” Deployment

### **Project Name:**  
Portainer Monitoring & Management Stack for `onda-server`

### **Owner:**  
Internal DevOps – Minh Nguyen

### **Environment:**  
- **Server:** Ubuntu 22.04 LTS (`onda-server`)  
- **Client access:** via Tailscale mesh network  
- **Network exposure:** private (Tailscale only)  
- **Container runtime:** Docker Engine + Docker Compose v2  
- **Service manager:** `systemd` (hybrid management)

---

## 1️⃣ Objective

Triển khai hệ thống quản trị Docker trên `onda-server` với:
- Web UI trực quan để quản lý containers, stacks, volumes, networks.
- Tự khởi động cùng hệ thống (systemd integration).
- Giao tiếp an toàn, không mở port public (chạy trong mạng Tailscale).
- Dễ bảo trì, rollback, mở rộng sang các stack khác (monitoring, metrics…).

---

## 2️⃣ Architecture Overview

### Components
| Component | Description | Run Type | Ports |
|------------|-------------|-----------|-------|
| **Portainer CE** | Web-based Docker management UI | Docker container | 9000 (HTTP), 9443 (HTTPS) |
| **Docker Engine** | Container runtime | System service | — |
| **Docker Compose** | Declarative stack manager | CLI tool | — |
| **Systemd Service** | Supervises Compose stack lifecycle | OS-level | — |

### Network Topology
```
[Client via Tailscale]  <---- WireGuard (encrypted) ---->  [onda-server:9443]
```

---

## 3️⃣ Deployment Path

| Path | Purpose |
|------|----------|
| `/srv/portainer/docker-compose.yml` | Main Docker Compose file |
| `/etc/systemd/system/portainer-compose.service` | systemd unit quản lý stack |
| `/var/lib/docker/volumes/portainer_data/_data/` | Persistent data của Portainer |

---

## 4️⃣ Configuration Details

### Docker Compose File
```yaml
version: "3.8"

services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: always
    ports:
      - "9000:9000"
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    environment:
      - TZ=Asia/Ho_Chi_Minh

volumes:
  portainer_data:
```

### Systemd Unit
```ini
[Unit]
Description=Portainer via Docker Compose
Requires=docker.service network-online.target
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=/srv/portainer
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down

[Install]
WantedBy=multi-user.target
```

---

## 5️⃣ Startup Behavior

1. Khi Ubuntu khởi động:
   - `docker.service` → start Docker daemon.
   - `portainer-compose.service` → gọi `docker compose up -d`.
   - Containers trong stack có `restart: always` → tự khởi động lại nếu crash.

2. Khi tắt máy:
   - `ExecStop` gọi `docker compose down` để dừng stack sạch sẽ.

---

## 6️⃣ Access Instructions

| Action | Command / URL |
|--------|----------------|
| Web UI | `https://onda-server:9443` |
| Initial login | Tạo tài khoản admin lần đầu |
| Environment setup | Chọn **Local Docker environment** |
| CLI check | `docker ps` |
| Logs (systemd) | `sudo journalctl -u portainer-compose -f` |
| Logs (docker) | `docker logs portainer -f` |

---

## 7️⃣ Operations Guide

| Task | Command |
|------|----------|
| Start service | `sudo systemctl start portainer-compose` |
| Stop service | `sudo systemctl stop portainer-compose` |
| Restart service | `sudo systemctl restart portainer-compose` |
| Enable on boot | `sudo systemctl enable portainer-compose` |
| Disable on boot | `sudo systemctl disable portainer-compose` |
| Check status | `sudo systemctl status portainer-compose` |
| View logs | `sudo journalctl -u portainer-compose -n 50` |

---

## 8️⃣ Update / Upgrade Procedure

```bash
cd /srv/portainer
sudo docker compose pull
sudo docker compose up -d
```

Rollback:
```bash
sudo docker compose down
sudo docker run portainer/portainer-ce:<old_tag>
```

---

## 9️⃣ Backup / Restore

### Backup
```bash
sudo docker stop portainer
sudo tar -czf /srv/backup/portainer_data_$(date +%F).tar.gz   /var/lib/docker/volumes/portainer_data/_data/
sudo docker start portainer
```

### Restore
```bash
sudo docker stop portainer
sudo tar -xzf /srv/backup/portainer_data_<date>.tar.gz -C /
sudo docker start portainer
```

---

## 🔒 Security Considerations

- Portainer chạy trong mạng Tailscale (private).
- `/var/run/docker.sock` chỉ mount cho Portainer.
- HTTPS (port 9443) dùng cert tự sinh.
- Không cần mở port public.

---

## 🔁 Rollback Plan

| Trigger | Action |
|----------|--------|
| Portainer container lỗi | `docker compose down && up -d` |
| Service không khởi động | `systemctl restart portainer-compose` |
| Cập nhật lỗi | Dùng image tag cũ |
| Mất dữ liệu | Restore từ backup |

---

## 📈 Future Extension

- Glances container để xem metrics CPU/RAM/disk.
- Prometheus + Grafana monitoring stack.
- Alert webhook cho container fail.

---

## ✅ Verification Checklist

| Item | Status |
|------|--------|
| Portainer UI truy cập được qua Tailscale | ✅ |
| Service tự khởi động khi reboot | ✅ |
| Logs hiển thị qua `journalctl` | ✅ |
| Dữ liệu được giữ sau restart | ✅ |
| Không expose port public | ✅ |

---

📍 **End of Handover Document**  
**Prepared by:** ChatGPT (GPT-5) – Infrastructure Assistant  
**Date:** 2025-11-10

