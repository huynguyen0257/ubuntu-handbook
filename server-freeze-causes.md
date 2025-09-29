# Handover: Xử lý & Phòng ngừa Treo Server Ubuntu 22.04 (Docker Compose)

## 1. Triệu chứng

-   Server Ubuntu 22.04 dùng để chạy Docker Compose.
-   Thỉnh thoảng bị treo cứng: không SSH, không ping, không phản hồi.
-   Phải nhấn nút nguồn để restart.

## 2. Phân tích log

-   **kern.log**: dừng hẳn trước 07:10 → hệ thống bị **hard freeze**.
-   **docker.log**: nhiều container không thoát được, DNS timeout hàng
    loạt (`127.0.0.53` systemd-resolved).
-   **prev-boot.log**: không thấy lỗi phần cứng, chỉ log boot bình
    thường.

## 3. Nguyên nhân khả dĩ

1.  **Docker + systemd-resolved DNS bug** → DNS query stuck, container
    treo.
2.  **File descriptor limit quá thấp (1024)** → Docker dễ cạn FD khi
    nhiều container chạy.
3.  **Bug kernel 6.8.x hoặc Docker networking** → gây treo toàn bộ host.
4.  Không có dấu hiệu RAM/disk hỏng, nên phần cứng ít khả năng.

## 4. Checklist Triển khai Phòng Ngừa

### 4.1 Bật Magic SysRq

``` bash
# Bật tạm thời
echo 1 | sudo tee /proc/sys/kernel/sysrq

# Bật vĩnh viễn
echo "kernel.sysrq=1" | sudo tee /etc/sysctl.d/99-sysrq.conf
sudo sysctl --system
```

👉 Khi treo: `Alt + SysRq + R E I S U B`

------------------------------------------------------------------------

### 4.2 Bật kdump

``` bash
sudo apt update
sudo apt install linux-crashdump -y
sudo systemctl enable kdump-tools
sudo systemctl start kdump-tools
systemctl status kdump-tools
```

-   Kiểm tra GRUB có `crashkernel=512M-:192M`.
-   Crash dump lưu tại `/var/crash/`.

------------------------------------------------------------------------

### 4.3 Tăng File Descriptor Limit

``` bash
# Toàn hệ thống
sudo nano /etc/systemd/system.conf
sudo nano /etc/systemd/user.conf
```

Thêm:

    DefaultLimitNOFILE=65535

``` bash
# Docker service
sudo systemctl edit docker
```

Thêm:

    [Service]
    LimitNOFILE=65535

``` bash
sudo systemctl daemon-reexec
sudo systemctl restart docker
```

------------------------------------------------------------------------

### 4.4 Fix Docker DNS

``` bash
sudo nano /etc/docker/daemon.json
```

Thêm:

``` json
{
  "dns": ["8.8.8.8", "1.1.1.1"]
}
```

``` bash
sudo systemctl restart docker
```

------------------------------------------------------------------------

## 5. Quy trình Khi Máy Bị Treo

### 5.1 Khi treo

1.  Thử **Magic SysRq**: `Alt + SysRq + R E I S U B`.
2.  Nếu không được → bắt buộc ấn nút nguồn.

### 5.2 Sau khi reboot

Chạy ngay để lấy log:

``` bash
journalctl -b -1 | grep -i -E "error|fail|oom|panic" | tail -50
journalctl -u docker -b -1 | tail -50
dmesg -T | tail -50
ls -lh /var/crash/
```

------------------------------------------------------------------------

## 6. Next Step Khuyến nghị

-   Giám sát tài nguyên (Prometheus/Node Exporter hoặc htop/iotop).
-   Test stress bằng `stress-ng` để tái hiện lỗi.
-   Cập nhật kernel & Docker lên bản mới nhất.
-   Nếu lỗi tái diễn → dùng kdump crash dump để phân tích sâu.

------------------------------------------------------------------------

**Người soạn**: Huy (handover note)\
**Ngày**: 2025-09-29

