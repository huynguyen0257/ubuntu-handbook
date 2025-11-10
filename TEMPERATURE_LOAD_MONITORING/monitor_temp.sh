#!/bin/bash
LOGFILE="temperature_log.txt"
INTERVAL=120  # Ghi log sau mỗi 120 giây (2 phút)
DURATION=21600000 # 6 tiếng * 3600 giây/tiếng = 21600 giây

echo "--- Bắt đầu Giám sát Nhiệt độ CPU/VRM: $(date) ---" >> $LOGFILE
START_TIME=$(date +%s)

while [ $(($(date +%s) - START_TIME)) -lt $DURATION ]; do
    echo -e "\nThời gian: $(date)" >> $LOGFILE

    # Lấy thông tin nhiệt độ từ sensors và ghi vào log
    sensors 2>/dev/null | grep -E 'Package id|Tdie|temp' >> $LOGFILE # Lọc các dòng nhiệt độ chính

    # (Tùy chọn) Giám sát tải CPU bằng htop/top để tham khảo:
    # top -b -n 1 | grep "Cpu(s)" >> $LOGFILE 

    # (Tùy chọn) Giám sát tải Docker:
    # docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" >> $LOGFILE

    sleep $INTERVAL
done

echo -e "\n--- Kết thúc Giám sát Nhiệt độ: $(date) ---" >> $LOGFILE
