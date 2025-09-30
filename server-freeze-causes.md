# Handover: Xử lý & Phòng ngừa Treo Server Ubuntu 22.04 (Docker + kdump)

> **Phiên bản:** 2025-09-30 • **Phạm vi:** PC chạy Ubuntu 22.04, Docker/Compose, kdump đã cấu hình `crashkernel=1G`

---

## 0) Mục tiêu
- **Khi treo**: ép kernel **panic** để **thu crash dump** (không power cycle) → phục hồi an toàn & có dữ liệu phân tích.
- **Sau khi reboot**: gom log/dump đúng chỗ.
- **Phòng ngừa**: hạn chế lặp lại do DNS/Docker FD/kernel networking.

---

## 1) Triệu chứng điển hình
- SSH không vào, ping time-out; màn hình/console **freeze**.
- Trước đây: bắt buộc nhấn nút nguồn → **không có dump**.
- Nay: đã cấu hình kdump **OK** ⇒ có thể **ép panic** để thu dump.

---

## 2) Quy trình Khi Máy Bị Treo (Runbook)
### 2.1. Tại console (ưu tiên)
1. **Thử SysRq crash qua phím**: `Alt` + `SysRq` + `c`  
   (Nếu bàn phím không phản hồi, chuyển sang bước 2)
2. **Nếu còn shell/tty**: chạy lệnh
   ```bash
   echo c | sudo tee /proc/sysrq-trigger
   ```
3. **Kỳ vọng**: Máy sẽ tự reboot theo chuỗi: **panic → boot capture kernel → dump → reboot về kernel thường**.

> **Không** power cycle (giữ nút nguồn) trừ khi tất cả cách trên thất bại, vì như vậy sẽ **không có dump**.

### 2.2. Sau khi máy bật lại
Chạy ngay các lệnh sau để thu thập bằng chứng:
```bash
# Thư mục dump mới theo timestamp
ls -lh /var/crash/
ls -lh /var/crash/<TIMESTAMP>/

# Log kernel trước khi crash
less /var/crash/<TIMESTAMP>/dmesg.*

# Kích thước dump (vmcore)
ls -lh /var/crash/<TIMESTAMP>/dump.*
```

---

## 3) Xác minh kdump (định kỳ hoặc sau thay đổi kernel)
```bash
# Kernel cmdline phải có đúng 1 tham số crashkernel (khuyến nghị 1G)
cat /proc/cmdline

# Kernel đã reserve vùng crash
sudo dmesg | grep -i crash
cat /sys/kernel/kexec_crash_size     # > 0
grep -i crash /proc/iomem            # thấy entry "Crash kernel"

# Trạng thái kdump-tools
systemctl status kdump-tools
kdump-config show
# 'current state: ready to kdump'
# 'crashkernel addr:' có giá trị (vd 0x8000000)

# Test load capture kernel (không crash máy)
sudo kdump-config test

# Reload khi đổi cấu hình
sudo kdump-config reload
```

---

## 4) Phân tích Crash Dump (sau sự cố)
### 4.1. Công cụ
```bash
sudo apt update
sudo apt install -y crash kdump-tools linux-image-$(uname -r)-dbgsym
```

### 4.2. Đọc nhanh dmesg
```bash
less /var/crash/<TIMESTAMP>/dmesg.*
```

### 4.3. Phân tích vmcore chi tiết
```bash
sudo crash /usr/lib/debug/boot/vmlinux-$(uname -r) /var/crash/<TIMESTAMP>/dump.*
```

### 4.4. Thu gọn dump (nếu cần gửi/backup)
```bash
sudo makedumpfile -c --message-level 1 -d 31   /var/crash/<TIMESTAMP>/dump.*   /var/crash/<TIMESTAMP>/vmcore.filtered
```

---

## 5) Phòng ngừa & Hardening

### 5.1. Docker DNS (tránh stuck systemd-resolved)
`/etc/docker/daemon.json`:
```json
{
  "dns": ["8.8.8.8", "1.1.1.1"]
}
```
```bash
sudo systemctl restart docker
```

### 5.2. File Descriptor limit (tránh “too many open files”)
```bash
# System-wide
sudo sed -i 's/^#\?DefaultLimitNOFILE.*/DefaultLimitNOFILE=65535/' /etc/systemd/system.conf
sudo sed -i 's/^#\?DefaultLimitNOFILE.*/DefaultLimitNOFILE=65535/' /etc/systemd/user.conf

# Docker service
sudo systemctl edit docker <<'EOF'
[Service]
LimitNOFILE=65535
EOF
sudo systemctl daemon-reexec
sudo systemctl restart docker

# Kiểm tra
systemctl show docker | grep -i LimitNOFILE
ulimit -n
cat /proc/sys/fs/file-max
```

### 5.3. Magic SysRq
```bash
# Bật vĩnh viễn
echo "kernel.sysrq=1" | sudo tee /etc/sysctl.d/99-sysrq.conf
sudo sysctl --system
cat /proc/sys/kernel/sysrq  # phải = 1
```

### 5.4. kdump ổn định (tránh trùng tham số)
- **Giữ 1** tham số: `crashkernel=1G` trong `/etc/default/grub`  
- **Loại bỏ** cấu hình chèn thêm từ `kdump-tools.cfg` (ví dụ `crashkernel=...-:192M`).
```bash
sudo grep -R --line-number --color crashkernel /etc/default/grub /etc/default/grub.d /etc/grub.d
sudo nano /etc/default/grub.d/kdump-tools.cfg   # comment dòng crashkernel nếu có
sudo update-grub && sudo reboot
```

### 5.5. Tùy chọn tăng độ chắc chắn
```bash
# Tự động panic khi gặp oops/hung task/softlockup (để tự sinh dump)
sudo tee /etc/sysctl.d/98-panic.conf <<'EOF'
kernel.panic_on_oops=1
kernel.panic=10
kernel.softlockup_panic=1
kernel.hung_task_panic=1
kernel.nmi_watchdog=1
EOF
sudo sysctl --system
```

---

## 6) Cây quyết định nhanh
- **Treo** → Thử `Alt+SysRq+c` → **OK**?  
  - **Có** → Chờ máy tự reboot → Thu log/dump tại `/var/crash/`.
  - **Không** → Còn shell? `echo c | sudo tee /proc/sysrq-trigger` → **OK**?
    - **Có** → Xử lý như trên.
    - **Không** → **Bất khả kháng** mới power cycle (chấp nhận không có dump).

---

## 7) Checklist định kỳ (tuần/lần hoặc sau update kernel)
```bash
# Xác minh cmdline & vùng reserve
cat /proc/cmdline | grep -o 'crashkernel=[^ ]*'
sudo dmesg | grep -i crash | head
cat /sys/kernel/kexec_crash_size
grep -i crash /proc/iomem

# Trạng thái kdump
systemctl status kdump-tools --no-pager
kdump-config show | sed -n '1,20p'

# Docker DNS & FD limit
cat /etc/docker/daemon.json
systemctl show docker | grep -i LimitNOFILE
```

---

**Người soạn:** Conative Ops • **Cập nhật:** 2025-09-30  
**Liên hệ:** Minh (DE Lead) • Handover này **override** phiên bản cũ.