# ===============================================================
# 1. ROS2 기본 로드 및 자동완성 (필수)
# ===============================================================
eval "$(register-python-argcomplete ros2)"
eval "$(register-python-argcomplete colcon)"

# ===============================================================
# 2. 로그 및 네트워크 설정 (전역 변수 영역)
# ===============================================================
export RCUTILS_COLORIZED_OUTPUT=1
export RCUTILS_LOGGING_USE_STDOUT=1
export RCUTILS_LOGGING_BUFFERED_STREAM=0
export RCUTILS_CONSOLE_OUTPUT_FORMAT="[{severity}] [{time}] [{name}]: {message}"

# [Fast DDS 전역 변수 선언]
export FASTRTPS_BASE_FILE="/home/won/DDS2ROS/fastdds_jazzy.xml"
export FASTRTPS_FILE_NAME="${FASTRTPS_BASE_FILE##*/}"
export FASTRTPS_FILE_PATH="${FASTRTPS_BASE_FILE}"

# ✨ [Jazzy 전용 피어 관리] 무선/간섭방지/1대다 통신 시 연동할 상대방 고정 IP 목록 명시 (세미콜론 구분)
export MY_STATIC_PEERS="192.168.100.20"

# 공통 네트워크 설정 적용 내부 함수
_apply_ros_net_settings() {
    case "$1" in
        "LOCAL")
            # 💡 [LOCALHOST 설정] 외부 멀티캐스트 방출을 차단하고 오직 루프백(lo) 통신만 수행
            export ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST
            export ROS_STATIC_PEERS=""
	    unset FASTRTPS_DEFAULT_PROFILES_FILE
            ;;
        "SUBNET")
            # 동일 서브넷 내 멀티캐스트 자동 검색 활성화 (Fast DDS 프로파일 사용)
            export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET
            export ROS_STATIC_PEERS=""
            export FASTRTPS_DEFAULT_PROFILES_FILE="$FASTRTPS_BASE_FILE"
            ;;
        "UNICAST")
            # 불필요한 검색 패킷 발생 차단, 수동 고정 IP 1:1 유니캐스트 집중 통신
            export ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST
            if [ -n "$2" ]; then
                export ROS_STATIC_PEERS="$2"
            else
                export ROS_STATIC_PEERS="$MY_STATIC_PEERS"
            fi
            export FASTRTPS_DEFAULT_PROFILES_FILE="$FASTRTPS_BASE_FILE"
            ;;
    esac
}

# 🚀 [수정 완완] 기본 네트워크 부팅 모드를 SUBNET에서 LOCAL (LOCALHOST) 모드로 변경
export ROS_CUSTOM_MODE="${ROS_CUSTOM_MODE:-LOCAL}"
_apply_ros_net_settings "$ROS_CUSTOM_MODE"

# RMW 구현체를 Fast DDS로 변경 적용
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
# Fast DDS 자체 내부 로그 레벨 정의 (기본 경고 수준, 불필요한 콘솔 오염 방지)
export FAST_DDS_LOG_CONTROL=WARN

# ===============================================================
# 색상 정의
# ===============================================================
YELLOW="\033[33m"
GREEN="\033[32m"
BLUE="\033[34m"
RED="\033[31m"
CYAN="\033[36m"   
RESET="\033[0m"

# ROS2 Jazzy 기본 소싱 및 에일리어스 정의
source /opt/ros/jazzy/setup.zsh
alias jazzy="source /opt/ros/jazzy/setup.zsh; echo '🐆 /opt/ros/jazzy/setup.zsh'"

# ===============================================================
# 워크스페이스 관리 함수
# ===============================================================
ws() {
    local ws_name="$1"
    : ${ROS_DISTRO:=jazzy}
    : ${ROS_DOMAIN_ID:=77}

    if [ -z "$ws_name" ]; then
        echo -e "${RED}Error: Please specify a workspace name. (e.g., ws ros2_ws)${RESET}"
        return 1
    fi

    if [[ -z "$AMENT_PREFIX_PATH" || "$AMENT_PREFIX_PATH" == "/opt/ros/$ROS_DISTRO" ]]; then
        if [ -f "/opt/ros/$ROS_DISTRO/setup.zsh" ]; then
            source "/opt/ros/$ROS_DISTRO/setup.zsh"
            echo -e "${YELLOW}Base ROS2 ($ROS_DISTRO) initialized.${RESET}"
        fi
    fi

    local TARGET_DIR=$(find "$HOME" -maxdepth 4 -type d -name "$ws_name" -print -quit 2>/dev/null)

    if [ -z "$TARGET_DIR" ]; then
        echo -e "${RED}Error: Workspace '$ws_name' folder not found under $HOME${RESET}"
        return 1
    fi

    local TARGET_PATH="$TARGET_DIR/install/local_setup.zsh"

    if [ -f "$TARGET_PATH" ]; then
        source "$TARGET_PATH"
        echo -e "${GREEN}Workspace '$ws_name' found at: $TARGET_DIR${RESET}"
        echo -e "${GREEN}Successfully added to current environment.${RESET}"
    else
        echo -e "${RED}Error: $TARGET_PATH not found.${RESET}"
        echo -e "${YELLOW}Did you build it? Run 'colcon build' in $TARGET_DIR${RESET}"
    fi
}

ws_reset() {
    local ROS_DISTRO=${1:-jazzy}
    unset AMENT_PREFIX_PATH
    unset COLCON_PREFIX_PATH
    unset ROS_PREFIX_PATH
    if [ -f "/opt/ros/$ROS_DISTRO/setup.zsh" ]; then
        source "/opt/ros/$ROS_DISTRO/setup.zsh"
        echo -e "${BLUE}Environment reset to Base ROS2 ($ROS_DISTRO) only.${RESET}"
    else
        echo -e "${RED}Error: Base ROS2 not found at /opt/ros/$ROS_DISTRO${RESET}"
    fi
}

# ===============================================================
# ros_status 함수 (Fast DDS 환경 출력 커스텀 튜닝)
# ===============================================================
ros_status() {
    # Real-time network interface parsing
    local WIRED_INT=$(ip -4 -o addr show | awk '{print $2}' | grep -E '^e' | head -n 1)
    local WIRELESS_INT=$(ip -4 -o addr show | awk '{print $2}' | grep -E '^w' | head -n 1)

    local WIRED_IP=""
    local WIRELESS_IP=""
    [ -n "$WIRED_INT" ] && WIRED_IP=$(ip -4 addr show "$WIRED_INT" 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1)
    [ -n "$WIRELESS_INT" ] && WIRELESS_IP=$(ip -4 addr show "$WIRELESS_INT" 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1)
    local LO_IP=$(ip -4 addr show lo 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1)

    # Fast DDS profiles config determination
    local CURRENT_MODE=""
    if [ -n "$FASTRTPS_DEFAULT_PROFILES_FILE" ]; then
        if [[ -f "$FASTRTPS_FILE_PATH" ]]; then
            CURRENT_MODE="\033[32m${FASTRTPS_FILE_NAME}\033[0m"
        else
            CURRENT_MODE="\033[31mUNKNOWN CONFIG (No File Found)\033[0m"
        fi
    else
        CURRENT_MODE="\033[33mOFFLINE MODE (Local Virtual Mode)\033[0m"
    fi

    # ✨ [Requested Patch] Interface fallback names in English
    local W_NAME=${WIRED_INT:-"No Ethernet Card"}
    local WL_NAME=${WIRELESS_INT:-"No Wi-Fi Card"}

    # Connection status localization
    local WIRED_STATUS WIRELESS_STATUS LO_STATUS
    if [ -n "$WIRED_IP" ]; then WIRED_STATUS="\033[32mConnected ($WIRED_IP)\033[0m"; else WIRED_STATUS="\033[31mDisconnected\033[0m"; fi
    if [ -n "$WIRELESS_IP" ]; then WIRELESS_STATUS="\033[32mConnected ($WIRELESS_IP)\033[0m"; else WIRELESS_STATUS="\033[31mDisconnected\033[0m"; fi
    if [ -n "$LO_IP" ]; then LO_STATUS="\033[32mActive ($LO_IP)\033[0m"; else LO_STATUS="\033[31mInactive\033[0m"; fi

    # Default system gateway determination
    local DEFAULT_ROUTE_INT=$(ip route | grep default | awk '{print $5}' | head -n 1)
    local OS_INTERNET="\033[37mLocal Offline (No Internet)\033[0m"
    if [ "$DEFAULT_ROUTE_INT" = "$WIRED_INT" ] && [ -n "$WIRED_INT" ]; then
        OS_INTERNET="\033[34mEthernet Active (${WIRED_INT})\033[0m"
    elif [ "$DEFAULT_ROUTE_INT" = "$WIRELESS_INT" ] && [ -n "$WIRELESS_INT" ]; then
        OS_INTERNET="\033[33mWi-Fi Active (${WIRELESS_INT})\033[0m"
    elif [ -n "$WIRED_IP" ]; then
        OS_INTERNET="\033[34mEthernet Connected (No Internet Access)\033[0m"
    elif [ -n "$WIRELESS_IP" ]; then
        OS_INTERNET="\033[33mWi-Fi Connected (No Internet Access)\033[0m"
    fi

    # Real-time ROS2 Data Traffic Path evaluation
    local ROS_TRAFFIC_PATH=""
    case "$ROS_CUSTOM_MODE" in
        "LOCAL")
            ROS_TRAFFIC_PATH="\033[1;32mLoopback (lo) & Shared Memory (SHM) [Local IPC Only]\033[0m"
            ;;
        "SUBNET")
            if [ -n "$DEFAULT_ROUTE_INT" ]; then
                local ACTIVE_IP=""
                [ "$DEFAULT_ROUTE_INT" = "$WIRED_INT" ] && ACTIVE_IP="$WIRED_IP"
                [ "$DEFAULT_ROUTE_INT" = "$WIRELESS_INT" ] && ACTIVE_IP="$WIRELESS_IP"
                ROS_TRAFFIC_PATH="\033[1;34mPhysical Net (${DEFAULT_ROUTE_INT} -> ${ACTIVE_IP:-"No IP"}) [Subnet Auto-Discovery]\033[0m"
            else
                ROS_TRAFFIC_PATH="\033[1;31mRouting Failed (No Physical Network Connected)\033[0m"
            fi
            ;;
        "UNICAST")
            if [ -n "$DEFAULT_ROUTE_INT" ]; then
                ROS_TRAFFIC_PATH="\033[1;36mPhysical Net (${DEFAULT_ROUTE_INT}) -> Unicast Static Peer [${ROS_STATIC_PEERS:-"No Peers"}]\033[0m"
            else
                ROS_TRAFFIC_PATH="\033[1;31mRouting Failed (No Physical Network Connected)\033[0m"
            fi
            ;;
    esac
    
    # Terminal UI output layout
    echo "----------------------------------------"
    echo -e "CURRENT DDS CONFIG   : ${CURRENT_MODE}"
    echo -e "ACTUAL ROS2 PATH     : ${ROS_TRAFFIC_PATH}"
    echo -e "SYSTEM DEFAULT GATE  : ${OS_INTERNET}"
    echo "----------------------------------------"
    echo -e "Ethernet  (${W_NAME})   : ${WIRED_STATUS}"
    echo -e "Wi-Fi     (${WL_NAME})   : ${WIRELESS_STATUS}"
    echo -e "Loopback  (lo)        : ${LO_STATUS}"
    echo "----------------------------------------"
    echo "ROS_DOMAIN_ID        : \033[1;33m${ROS_DOMAIN_ID:-0}\033[0m"
    echo -e "ROS NETWORK MODE     : \033[1;36m${ROS_CUSTOM_MODE}\033[0m (Discovery: \033[1;32m${ROS_AUTOMATIC_DISCOVERY_RANGE}\033[0m)"
    
    # Conditionally display static peers only in UNICAST mode
    if [ "$ROS_CUSTOM_MODE" = "UNICAST" ]; then
        echo -e "ROS_STATIC_PEERS     : \033[1;33m${ROS_STATIC_PEERS:-(None)}\033[0m"
    fi
    
    echo "RMW_IMPLEMENTATION   : ${RMW_IMPLEMENTATION:-0}"
    echo "----------------------------------------"
}

# ========================================================
# 4. Aliases & Functions
# ========================================================
# 🌐 사용자 선택형 통신 제어 및 초기화 명령어 (ros_mode)
ros_mode() {
    local target=$(echo "$1" | tr '[:lower:]' '[:upper:]')
    local target_ip="$2"

    # 🔄 [추가] RESET 또는 INIT 입력 시 기본 상태인 LOCAL 모드로 자동 매핑 및 안내 출력
    if [ "$target" = "RESET" ] || [ "$target" = "INIT" ]; then
        target="LOCAL"
        echo -e "${BLUE}🔄 ROS2 네트워크 환경 변수를 초기 기본값(LOCAL)으로 리셋합니다...${RESET}"
    fi

    case "$target" in
        "LOCAL"|"SUBNET"|"UNICAST")
            export ROS_CUSTOM_MODE="$target"
            _apply_ros_net_settings "$target" "$target_ip"
            echo -e "${GREEN}✔ ROS2 통신 모드가 변경되었습니다: [${RESET}${YELLOW}${target}${RESET}${GREEN}]${RESET}"
            ;;
        *)
            echo -e "${RED}Usage: ros_mode [local | subnet | unicast [IP_ADDRESS] | reset | init]${RESET}"
            return 1
            ;;
    esac
    
    echo ""
    ros_status
}

# 🆔 ROS_DOMAIN_ID 변경 명령어 (ros_domain) 추가
ros_domain() {
    if [ -z "$1" ]; then
        echo -e "${RED}Usage: ros_domain [DOMAIN_ID_NUMBER]${RESET}"
        echo -e "${BLUE}Current ROS_DOMAIN_ID: ${ROS_DOMAIN_ID:-0}${RESET}"
        return 1
    fi

    if [[ "$1" =~ ^[0-9]+$ ]]; then
        export ROS_DOMAIN_ID="$1"
        echo -e "${GREEN}✔ ROS_DOMAIN_ID가 변경되었습니다: [${RESET}${YELLOW}${1}${RESET}${GREEN}]${RESET}"
        echo ""
        ros_status
    else
        echo -e "${RED}Error: DOMAIN_ID는 숫자만 입력 가능합니다.${RESET}"
        return 1
    fi
}

# ===============================================================
# ℹ️ ROS2 개발 환경 맞춤형 통합 도움말 함수 (ros_help)
# ===============================================================
ros_help() {
    # 쉘 빌트인 help 기능과 충돌을 방지하며 인자가 있을 때는 기본 help 기능 처리
    if [ $# -ne 0 ]; then
        builtin help "$@"
        return
    fi

    echo -e "${BLUE}======================================================================${RESET}"
    echo -e "  🐆  ${GREEN}ROS2 Jazzy & Fast DDS 개발 인프라 단축 명령어 가이드${RESET}"
    echo -e "${BLUE}======================================================================${RESET}"
    
    echo -e "${YELLOW}[1] 워크스페이스 제어 (Workspace)${RESET}"
    echo -e "  • ${CYAN}ws [워크스패이스]${RESET}        : ~/ 하위의 해당 워크스페이스를 자동 검색하여 소싱"
    echo -e "  • ${CYAN}ws_reset [워크스패이스]${RESET}  : 워크스페이스 의존 환경을 초기화하고 기본 ROS2만 유지"
    echo -e "  • ${CYAN}jazzy${RESET}                  : ROS2 Jazzy 기본 설정 파일 수동 재소싱"
    echo ""
    
   echo -e "${YELLOW}[2] DDS 네트워크 환경 제어 (Network & DDS)${RESET}"
    echo -e "  • ${CYAN}ros_mode [모드]${RESET}       : 통신 모드 제어 (${GREEN}LOCAL${RESET} | ${GREEN}SUBNET${RESET} | ${GREEN}UNICAST [IP]${RESET} | ${GREEN}RESET${RESET})"
    echo -e "    ${GREEN}ex)${RESET} ros_mode local     (단일 PC 내부 루프백 통신 전용)"
    echo -e "    ${GREEN}ex)${RESET} ros_mode subnet    (동일 네트워크 서브넷 대역 전체 자동 탐색)"
    echo -e "    ${GREEN}ex)${RESET} ros_mode unicast \"192.168.100.101\" (단일 IP 대상 지정 유니캐스트)"
    echo -e "    ${GREEN}ex)${RESET} ros_mode unicast \"192.168.100.101;192.168.100.102\" (다중 IP 지정 시 큰따옴표 필수!)"
    echo -e "    ${GREEN}ex)${RESET} ros_mode reset     (DDS 설정을 시스템 부팅 초기 상태인 LOCAL로 안전 복구)"
    echo -e "  • ${CYAN}ros_domain [ID]${RESET}      : ROS_DOMAIN_ID 값을 손쉽게 변경 후 모드 확인"
    echo -e "    ${GREEN}ex)${RESET} ros_domain 30      (통신 도메인 ID를 30으로 즉시 분리)"
    echo -e "  • ${CYAN}ros_status${RESET}           : IP 대역, 네트워크 연결 유무, DDS 변수 및 모드 종합 진단"
    echo ""
        
    echo -e "${YELLOW}[3] Colcon 빌드 및 테스트 (Build & Test)${RESET}"
    echo -e "  • ${CYAN}cbs${RESET}                 : colcon build --symlink-install (심볼릭 빌드)"
    echo -e "  • ${CYAN}cbp [패키지명]${RESET}        : 특정 패키지만 선택 지정하여 빌드"
    echo -e "  • ${CYAN}cbu [패키지명]${RESET}        : 지정 패키지 및 이에 의존하는 상위 패키지 일괄 빌드"
    echo -e "  • ${CYAN}ct${RESET}                   : 패키지 테스트 실행 (colcon test)"
    echo -e "  • ${CYAN}ctp [패키지명]${RESET}        : 특정 패키지만 테스트 실행"
    echo -e "  • ${CYAN}ctr${RESET}                 : 테스트 실패 유무 및 상세 결과 요약 조회"
    echo ""
       
    echo -e "💡  ${GREEN}Tip:'ros_help'를 입력하면 언제든지 이 설명서를 호출할 수 있습니다.${RESET}"
}

alias roslog="ccze -A"
alias roserr="grep -E 'WARN|ERROR'"
alias cbs='colcon build --symlink-install'
alias cbp='colcon build --symlink-install --packages-select'
alias cbu='colcon build --symlink-install --packages-up-to'
alias ct='colcon test'
alias ctp='colcon test --packages-select'
alias ctr='colcon test-result'
alias tl='ros2 topic list'
alias te='ros2 topic echo'
alias nl='ros2 node list'
alias af='ament_flake8'
alias ac='ament_cpplint'
alias testpub='ros2 run demo_nodes_cpp talker'
alias testsub='ros2 run demo_nodes_cpp listener'
alias testpubimg='ros2 run image_tools cam2image'
alias testsubimg='ros2 run image_tools showimage'
alias di='rosdep install --from-paths src -y --ignore-src --os=ubuntu:noble'
alias killgazebo='killall -9 ruby gz-sim-server gz-sim-gui 2>/dev/null; echo "Gazebo Harmonic terminated."'

# ========================================================
# ✨ Gazebo Harmonic (Jazzy 기본 표준) 최적화 설정
# ========================================================
export GZ_FUEL_DISABLE=1

MY_GZ_RESOURCE_DIRS=("/home/won/.gz/my_models" "/home/won/.gz/my_worlds" "/home/won/.gazebo/my_models" "/home/won/.gazebo/my_worlds")
for dir in "${MY_GZ_RESOURCE_DIRS[@]}"; do
    if [ -d "$dir" ] && [[ ":$GZ_SIM_RESOURCE_PATH:" != *":$dir:"* ]]; then
        export GZ_SIM_RESOURCE_PATH="$dir${GZ_SIM_RESOURCE_PATH:+:$GZ_SIM_RESOURCE_PATH}"
    fi
done

#export TURTLEBOT3_MODEL=burger
#export LDS_MODEL=LDS-02
