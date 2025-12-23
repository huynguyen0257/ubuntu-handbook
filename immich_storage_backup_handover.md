# IMMICH STORAGE & BACKUP HANDOVER (NO CLOUD / NO NAS)

## 1. Mục tiêu setup
- Immich chạy trên Ubuntu Server (Docker)
- Ảnh & video từ 500GB – 1TB
- KHÔNG dùng Cloud
- KHÔNG dùng NAS
- An toàn khi SSD / HDD lỗi
- Backup offline, chi phí thấp

---

## 2. Kiến trúc tổng thể

**SSD 500GB**
- Ubuntu Server
- Docker
- Immich app + PostgreSQL

**HDD #1 (1.5TB – gắn trong)**
- Chứa toàn bộ ảnh & video Immich

**HDD #2 (1.5TB – ổ rời USB)**
- Backup định kỳ (offline)
- Chỉ cắm khi backup
- Không dùng cron tự động

**Nguyên tắc:**
- Immich KHÔNG là nơi duy nhất chứa ảnh
- HDD #1 chết → restore từ HDD #2
- HDD #2 luôn rút ra sau khi backup

---

## 3. Setup HDD #1 (ổ gắn trong – chứa ảnh)

### 3.1 Xác định ổ đĩa
```
lsblk
```
Ví dụ:
- sda = SSD 500GB
- sdb = HDD 1.5TB (ổ chính)

---

### 3.2 Format HDD (chỉ làm 1 lần – xoá sạch dữ liệu)
```
sudo mkfs.ext4 /dev/sdb
```

---

### 3.3 Mount HDD
```
sudo mkdir -p /data/immich
sudo mount /dev/sdb /data/immich
```
Kiểm tra:
```
df -h
```

---

### 3.4 Auto-mount khi reboot
Lấy UUID:
```
blkid /dev/sdb
```

Sửa fstab:
```
sudo nano /etc/fstab
```

Thêm dòng:
```
UUID=<UUID_CUA_SDB>  /data/immich  ext4  defaults  0  2
```

Reboot test:
```
sudo reboot
df -h
```

---

## 4. Cấu hình Immich dùng HDD #1

Trong `docker-compose.yml`:
```
volumes:
  - /data/immich:/usr/src/app/upload
```

Apply:
```
docker compose down
docker compose up -d
```

Từ giờ:
- Ảnh/video → HDD
- SSD chỉ chạy app

---

## 5. Backup với HDD #2 (ổ rời USB)

### 5.1 Khi backup
- Cắm HDD #2
- Kiểm tra:
```
lsblk
```
Ví dụ: sdc

---

### 5.2 Mount ổ backup
```
sudo mkdir -p /mnt/backup
sudo mount /dev/sdc /mnt/backup
```

---

### 5.3 Backup ảnh & video
```
rsync -av --delete \
  /data/immich \
  /mnt/backup/immich-library
```

---

### 5.4 Backup database Immich (BẮT BUỘC)
```
docker exec immich_postgres \
  pg_dump -U postgres immich \
  > /mnt/backup/immich-db.sql
```

---

### 5.5 Unmount & rút ổ
```
sync
sudo umount /mnt/backup
```

Cất HDD #2 ở nơi an toàn.

---

## 6. Về cron job
- KHÔNG dùng cron cho HDD rời
- Backup làm thủ công:
  - 1–2 tuần / lần
  - Hoặc trước khi update Immich
- Offline backup an toàn hơn cron

---

## 7. Script backup (tuỳ chọn)

File: `backup_immich.sh`
```
#!/bin/bash

mount /mnt/backup || exit 1

rsync -av --delete /data/immich /mnt/backup/immich-library
docker exec immich_postgres pg_dump -U postgres immich > /mnt/backup/immich-db.sql

sync
umount /mnt/backup
```

Chạy:
```
sudo bash backup_immich.sh
```

---

## 8. Test restore (BẮT BUỘC LÀM 1 LẦN)

### 8.1 Stop Immich
```
docker compose down
```

---

### 8.2 Mount HDD backup
```
sudo mount /dev/sdc /mnt/backup
```

---

### 8.3 Restore ảnh
```
rsync -av /mnt/backup/immich-library /data/immich
```

---

### 8.4 Restore database
```
docker compose up -d postgres
docker exec -i immich_postgres \
  psql -U postgres immich \
  < /mnt/backup/immich-db.sql
```

---

### 8.5 Start Immich
```
docker compose up -d
```

Mở Immich UI:
- Ảnh hiển thị
- Album đúng
- User còn

→ Restore OK

---

## 9. Checklist nhanh
- [ ] HDD #1 chứa ảnh
- [ ] HDD #2 backup offline
- [ ] Backup ảnh + DB
- [ ] Không dùng cron
- [ ] Restore test thành công

---

## 10. Ghi nhớ quan trọng
- RAID ≠ Backup
- 1 ổ = không an toàn
- Backup mà không test restore = vô nghĩa
- Immich là app, không phải storage system

END.

