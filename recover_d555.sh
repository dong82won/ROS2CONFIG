#!/usr/bin/env bash
set -euo pipefail

TARGET_IP="192.168.11.55"
TARGET_IF="enx00e04c6841ec"

echo -e "\033[34m[1/4] D555 물리 링크 점검 중...\033[0m"
if ! ping -c 1 -W 1 "${TARGET_IP}" >/dev/null 2>&1; then
    echo -e "\033[31m[ERROR] D555(${TARGET_IP}) 응답 없음. 케이블 및 전원을 점검하십시오.\033[0m"
    exit 1
fi
echo -e "\033[32m✔ D555 ICMP 응답 정상 (RTT < 1ms)\033[0m"

echo -e "\033[34m[2/4] 호스트 NIC MTU 9000 적용 중...\033[0m"
sudo ip link set dev "${TARGET_IF}" mtu 9000
echo -e "\033[32m✔ ${TARGET_IF} MTU 9000 설정 완료\033[0m"

echo -e "\033[34m[3/4] 고착된 ROS 2 데몬 및 DDS 캐시 초기화 중...\033[0m"
ros2 daemon stop >/dev/null 2>&1 || true
killall -9 ros2-daemon 2>/dev/null || true
echo -e "\033[32m✔ 데몬 프로세스 정리 완료\033[0m"

echo -e "\033[34m[4/4] D555 Native DDS 토픽 수신 여부 확인 중...\033[0m"
TOPICS=$(ros2 topic list --no-daemon 2>/dev/null | grep "realsense" || true)

if [[ -n "${TOPICS}" ]]; then
    echo -e "\033[32m✔ D555 토픽 정상 감지 성공:\033[0m"
    echo "${TOPICS}" | sed 's/^/  -> /'
else
    echo -e "\033[31m[WARN] 토픽이 아직 검색되지 않았습니다. SUBNET 모드로 전환 후 재시도합니다...\033[0m"
    export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET
    ros2 topic list --no-daemon | grep "realsense" | sed 's/^/  -> /' || true
fi
