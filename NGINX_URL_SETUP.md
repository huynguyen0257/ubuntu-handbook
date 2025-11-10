# 🧾 Handover: Setup URL nội bộ cho từng server mới

## 🎯 Mục tiêu
Chuẩn hoá cách tạo URL nội bộ thân thiện cho các web UI (như Glances, Portainer, Kafka UI, Grafana…)  
- Không cần nhớ port.  
- Dễ quản lý và mở rộng khi có nhiều tool.  
- Giữ cách làm đơn giản, không phụ thuộc DNS server phức tạp.  

Ví dụ:
```
http://glances.onda-server
http://portainer.onda-server
http://kafka.onda-server
```

---

## 🏗️ 1. Kiến trúc tổng quan

| Thành phần | Vai trò |
|-------------|----------|
| **Server (`onda-server`)** | Chạy các service (Glances, Portainer, Kafka UI, …) và Nginx làm reverse proxy. |
| **Client (laptop / desktop)** | Dùng trình duyệt để truy cập UI qua Tailscale (hoặc LAN). |
| **Nginx** | Lắng nghe cổng 80 → định tuyến request đến đúng service theo `server_name`. |
| **/etc/hosts (client)** | Map tên miền nội bộ (VD: `glances.onda-server`) đến IP thật (VD: `100.88.118.24`). |

---

## ⚙️ 2. Setup Nginx trên Server

### 2.1 Cài đặt Nginx
```bash
sudo apt update
sudo apt install -y nginx
sudo systemctl enable --now nginx
```

### 2.2 Tạo site cho từng ứng dụng

#### Ví dụ 1 – Glances (port 61208)
```bash
sudo tee /etc/nginx/sites-available/glances > /dev/null <<'EOF'
server {
    listen 80;
    server_name glances.onda-server;

    location / {
        proxy_pass http://127.0.0.1:61208/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
    }
}
EOF
```

#### Ví dụ 2 – Portainer (port 9000)
```bash
sudo tee /etc/nginx/sites-available/portainer > /dev/null <<'EOF'
server {
    listen 80;
    server_name portainer.onda-server;

    location / {
        proxy_pass http://127.0.0.1:9000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
    }
}
EOF
```

#### Ví dụ 3 – Kafka UI (port 8080)
```bash
sudo tee /etc/nginx/sites-available/kafka-ui > /dev/null <<'EOF'
server {
    listen 80;
    server_name kafka.onda-server;

    location / {
        proxy_pass http://127.0.0.1:8080/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
    }
}
EOF
```

Kích hoạt các site:
```bash
sudo ln -s /etc/nginx/sites-available/glances /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/portainer /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/kafka-ui /etc/nginx/sites-enabled/

sudo nginx -t && sudo systemctl reload nginx
```

---

## 🧩 3. Setup Client (máy truy cập)

1. Lấy IP của server (`onda-server`):
   ```bash
   tailscale ip -4
   ```

2. Sửa file `/etc/hosts`:
   ```bash
   sudo nano /etc/hosts
   ```

3. Thêm các dòng:
   ```
   100.88.118.24 glances.onda-server
   100.88.118.24 portainer.onda-server
   100.88.118.24 kafka.onda-server
   ```

4. Mở trình duyệt:
   ```
   http://glances.onda-server
   http://portainer.onda-server
   http://kafka.onda-server
   ```

---

## 🧱 4. Khi thêm service mới
1. Tạo file `/etc/nginx/sites-available/<service>`
2. Cấu hình tương tự, đổi `server_name` và `proxy_pass` port.
3. Link file → reload Nginx
4. Thêm dòng vào `/etc/hosts` trên client.
5. Mở trình duyệt kiểm tra.

---

## 🔒 5. Tuỳ chọn bảo mật
- **Giới hạn truy cập theo IP Tailscale:**
  ```nginx
  allow 100.64.0.0/10;
  deny all;
  ```
- **Thêm xác thực Basic Auth:**
  ```bash
  sudo apt install apache2-utils
  sudo htpasswd -c /etc/nginx/.htpasswd user1
  ```

---

## 🧭 6. Checklist khởi tạo server mới

| Bước | Hành động | Lệnh |
|------|------------|------|
| 1 | Cài Nginx | `sudo apt install nginx` |
| 2 | Tạo site | `/etc/nginx/sites-available/<app>` |
| 3 | Symlink và reload | `ln -s … && nginx -t && systemctl reload nginx` |
| 4 | Lấy IP server | `tailscale ip -4` |
| 5 | Cập nhật /etc/hosts | Thêm `<IP> <subdomain>.<server>` |
| 6 | Mở URL test | `curl -I http://<subdomain>.<server>` |

---

## 💡 7. Hints: Hướng DNS trong tương lai

| Hướng | Mô tả | Ưu điểm |
|--------|-------|----------|
| **Tailscale MagicDNS + Split DNS** | Dùng DNS nội bộ của Tailscale để resolve `*.onda-server`. | Tự động, toàn mạng. |
| **CoreDNS nội bộ** | DNS tự host, trả lời `*.onda-server`. | Kiểm soát toàn bộ. |
| **Pi-hole / AdGuard Home** | Giao diện quản lý DNS + ad-block. | Trực quan, dễ sửa. |
| **Caddy / Traefik (Docker)** | Reverse proxy tự nhận hostname theo label container. | Dễ deploy trong Docker. |
| **Public DNS (Cloudflare / Route53)** | Dùng domain thật (vd: `*.onda.lab`). | Có SSL và global access. |

---

## ✅ Kết luận
Cách `/etc/hosts` + Nginx là phương pháp nhanh gọn và ổn định cho môi trường dev/lab.  
Khi mở rộng, có thể chuyển sang **CoreDNS + Split DNS** để tự động hóa.


