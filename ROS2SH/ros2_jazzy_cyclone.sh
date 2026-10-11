#!/usr/bin/zsh
# ===============================================================
# 1. ROS2 Jazzy 기본 소싱 및 자동완성 (최상단 배치)
# ===============================================================
if [ -f "/opt/ros/jazzy/setup.zsh" ]; then
    source /opt/ros/jazzy/setup.zsh
fi
alias jazzy="source /opt/ros/jazzy/setup.zsh; echo '🐆 /opt/ros/jazzy/setup.zsh Sourced!'"

# Ubuntu 24.04 Python 3.12 Zsh 자동완성 안전 등록
if command -v register-python-argcomplete3 &>/dev/null; then
    eval "$(register-python-argcomplete3 --shell zsh ros2)"
    eval "$(register-python-argcomplete3 --shell zsh colcon)"
elif command -v register-python-argcomplete &>/dev/null; then
    eval "$(register-python-argcomplete --shell zsh ros2)"
    eval "$(register-python-argcomplete --shell zsh colcon)"
fi

# ===============================================================
# 2. 로그 및 네트워크 설정 (전역 변수 영역)
# ===============================================================
export RCUTILS_COLORIZED_OUTPUT=1
export RCUTILS_LOGGING_USE_STDOUT=1
export RCUTILS_LOGGING_BUFFERED_STREAM=0
export RCUTILS_CONSOLE_OUTPUT_FORMAT="[{severity}] [{time}] [{name}]: {message}"

# [DDS 전역 변수 선언] - ROS2CONFIG 통합 경로 추종
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONE_BASE_FILE="$HOME/ROS2CONFIG/DDS_Config/cyclonedds_jazzy_v3.xml"
export FASTDDS_BASE_FILE="$HOME/ROS2CONFIG/DDS_Config/fastdds_jazzy_v3.xml"

export CYCLONE_FILE_NAME="${CYCLONE_BASE_FILE##*/}"
export CYCLONE_FILE_PATH="${CYCLONE_BASE_FILE}"

export MY_STATIC_PEERS="192.168.100.20"

_apply_ros_net_settings() {
    case "$1" in
        "LOCAL")
            export ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST
            export ROS_STATIC_PEERS=""
            unset CYCLONEDDS_URI
            unset FASTRTPS_DEFAULT_PROFILES_FILE
            ;;
        "SUBNET")
            export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET
            export ROS_STATIC_PEERS=""
            if [ "$RMW_IMPLEMENTATION" = "rmw_cyclonedds_cpp" ]; then
                export CYCLONEDDS_URI="file://${CYCLONE_BASE_FILE}"
            else
                export FASTRTPS_DEFAULT_PROFILES_FILE="${FASTDDS_BASE_FILE}"
            fi
            ;;
        "UNICAST")
            export ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST
            if [ -n "$2" ]; then
                export ROS_STATIC_PEERS="$2"
            else
                export ROS_STATIC_PEERS="$MY_STATIC_PEERS"
            fi
            if [ "$RMW_IMPLEMENTATION" = "rmw_cyclonedds_cpp" ]; then
                export CYCLONEDDS_URI="file://${CYCLONE_BASE_FILE}"
            else
                export FASTRTPS_DEFAULT_PROFILES_FILE="${FASTDDS_BASE_FILE}"
            fi
            ;;
    esac
}

export ROS_CUSTOM_MODE="${ROS_CUSTOM_MODE:-LOCAL}"
_apply_ros_net_settings "$ROS_CUSTOM_MODE"

# ===============================================================
# ANSI 색상 정의
# ===============================================================
YELLOW="\033[33m"
GREEN="\033[32m"
BLUE="\033[34m"
RED="\033[31m"
CYAN="\033[36m"
RESET="\033[0m"

# ===============================================================
# 3. 워크스페이스 관리 함수
# ===============================================================
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

ws() {
    export PATH="/usr/bin:/bin:/usr/local/bin:${PATH}"

    local ws_name="$1"
    : ${ROS_DISTRO:=jazzy}
    : ${ROS_DOMAIN_ID:=77}

    # 1. 인자가 없거나 '.'인 경우 현재 위치의 폴더명을 워크스페이스 이름으로 자동 지정
    if [ -z "$ws_name" ] || [ "$ws_name" = "." ]; then
        ws_name=$(basename "$PWD")
    fi

    # 2. ROS 2 Base 환경 초기화
    if [[ -z "$AMENT_PREFIX_PATH" || "$AMENT_PREFIX_PATH" == "/opt/ros/$ROS_DISTRO" ]]; then
        if [ -f "/opt/ros/$ROS_DISTRO/setup.zsh" ]; then
            source "/opt/ros/$ROS_DISTRO/setup.zsh"
            echo -e "${YELLOW}Base ROS2 ($ROS_DISTRO) initialized.${RESET}"
        fi
    fi

    local TARGET_DIR=""

    # [우선순위 1] 현재 작업 디렉토리(PWD) 자체가 대상인 경우
    if [ "$(basename "$PWD")" = "$ws_name" ]; then
        TARGET_DIR="$PWD"
    # [우선순위 2] 현재 작업 디렉토리 바로 하위에 존재하는 경우
    elif [ -d "./$ws_name" ]; then
        TARGET_DIR="$(pwd)/$ws_name"
    fi

    # [우선순위 3] $HOME 하위 동적 탐색 (최대 5단계 깊이)
    if [ -z "$TARGET_DIR" ]; then
        echo -e "${YELLOW}Searching for '$ws_name' dynamically in $HOME...${RESET}"
        if [ -d "$HOME" ]; then
            TARGET_DIR=$(find "$HOME" -maxdepth 5 -type d -name "$ws_name" -print -quit 2>/dev/null)
        fi
    fi

    # 대상을 찾지 못한 경우 예외 처리
    if [ -z "$TARGET_DIR" ]; then
        echo -e "${RED}Error: Workspace '$ws_name' folder not found under $HOME.${RESET}"
        return 1
    fi

    # 3. local_setup.zsh 소싱 및 환경 반영
    local TARGET_PATH="$TARGET_DIR/install/local_setup.zsh"

    if [ -f "$TARGET_PATH" ]; then
        source "$TARGET_PATH"
        local OVERLAY_COUNT=$(echo "$AMENT_PREFIX_PATH" | tr ':' '\n' | grep -v "/opt/ros/" | wc -l)

        echo -e "${GREEN}✔ Workspace '$ws_name' successfully overlaid!${RESET} ($TARGET_DIR)"
        if [ "$OVERLAY_COUNT" -gt 1 ]; then
            echo -e "${CYAN}🔗 Current Overlaid Workspaces: $OVERLAY_COUNT${RESET}"
            echo "$AMENT_PREFIX_PATH" | tr ':' '\n' | grep -v "/opt/ros/" | sed 's|^|  - |'
        fi
    else
        echo -e "${RED}Error: $TARGET_PATH not found.${RESET}"
        echo -e "${YELLOW}Did you build it? Run 'colcon build' in $TARGET_DIR${RESET}"
    fi
}

# ===============================================================
# 4. ros2_status 함수 (네트워크 및 DDS 상태 진단)
# ===============================================================
ros2_status() {
    local WIRED_INT=$(ip -4 -o addr show | awk '{print $2}' | grep -E '^e' | head -n 1)
    local WIRELESS_INT=$(ip -4 -o addr show | awk '{print $2}' | grep -E '^w' | head -n 1)

    local WIRED_IP=""
    local WIRELESS_IP=""
    [ -n "$WIRED_INT" ] && WIRED_IP=$(ip -4 addr show "$WIRED_INT" 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1)
    [ -n "$WIRELESS_INT" ] && WIRELESS_IP=$(ip -4 addr show "$WIRELESS_INT" 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1)
    local LO_IP=$(ip -4 addr show lo 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1)

    local CURRENT_MODE=""
    if [ "$RMW_IMPLEMENTATION" = "rmw_cyclonedds_cpp" ] && [ -n "$CYCLONEDDS_URI" ]; then
        if [[ -f "$CYCLONE_FILE_PATH" ]]; then
            CURRENT_MODE="\033[32m${CYCLONE_FILE_NAME} (CycloneDDS)\033[0m"
        else
            CURRENT_MODE="\033[31mUNKNOWN CONFIG (No File Found)\033[0m"
        fi
    elif [ "$RMW_IMPLEMENTATION" = "rmw_fastrtps_cpp" ] && [ -n "$FASTRTPS_DEFAULT_PROFILES_FILE" ]; then
        CURRENT_MODE="\033[32mfastdds_jazzy_v3.xml (FastDDS)\033[0m"
    else
        CURRENT_MODE="\033[33mOFFLINE MODE (Local Virtual Mode)\033[0m"
    fi

    local W_NAME=${WIRED_INT:-"No Ethernet Card"}
    local WL_NAME=${WIRELESS_INT:-"No Wi-Fi Card"}

    local WIRED_STATUS WIRELESS_STATUS LO_STATUS
    if [ -n "$WIRED_IP" ]; then WIRED_STATUS="\033[32mConnected ($WIRED_IP)\033[0m"; else WIRED_STATUS="\033[31mDisconnected\033[0m"; fi
    if [ -n "$WIRELESS_IP" ]; then WIRELESS_STATUS="\033[32mConnected ($WIRELESS_IP)\033[0m"; else WIRELESS_STATUS="\033[31mDisconnected\033[0m"; fi
    if [ -n "$LO_IP" ]; then LO_STATUS="\033[32mActive ($LO_IP)\033[0m"; else LO_STATUS="\033[31mInactive\033[0m"; fi

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

    echo "----------------------------------------"
    echo -e "CURRENT DDS CONFIG   : ${CURRENT_MODE}"
    echo -e "ACTUAL ROS2 PATH     : ${ROS_TRAFFIC_PATH}"
    echo -e "SYSTEM DEFAULT GATE  : ${OS_INTERNET}"
    echo "----------------------------------------"
    echo -e "Ethernet  (${W_NAME})   : ${WIRED_STATUS}"
    echo -e "Wi-Fi     (${WL_NAME})   : ${WIRELESS_STATUS}"
    echo -e "Loopback  (lo)        : ${LO_STATUS}"
    echo "----------------------------------------"
    echo -e "ROS_DOMAIN_ID        : \033[1;33m${ROS_DOMAIN_ID:-0}\033[0m"
    echo -e "ROS NETWORK MODE     : \033[1;36m${ROS_CUSTOM_MODE}\033[0m (Discovery: \033[1;32m${ROS_AUTOMATIC_DISCOVERY_RANGE}\033[0m)"

    if [ "$ROS_CUSTOM_MODE" = "UNICAST" ]; then
        echo -e "ROS_STATIC_PEERS     : \033[1;33m${ROS_STATIC_PEERS:-(None)}\033[0m"
    fi

    echo -e "RMW_IMPLEMENTATION   : \033[1;32m${RMW_IMPLEMENTATION}\033[0m"
    echo "----------------------------------------"
}

# ========================================================
# 5. Aliases & Functions
# ========================================================
ros2_mode() {
    local target=$(echo "$1" | tr '[:lower:]' '[:upper:]')
    local target_ip="$2"

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
    ros2_status
}

ros2_domain() {
    if [ -z "$1" ]; then
        echo -e "${RED}Usage: ros_domain [DOMAIN_ID_NUMBER]${RESET}"
        echo -e "${BLUE}Current ROS_DOMAIN_ID: ${ROS_DOMAIN_ID:-0}${RESET}"
        return 1
    fi

    if [[ "$1" =~ ^[0-9]+$ ]]; then
        export ROS_DOMAIN_ID="$1"
        echo -e "${GREEN}✔ ROS_DOMAIN_ID가 변경되었습니다: [${RESET}${YELLOW}${1}${RESET}${GREEN}]${RESET}"
        echo ""
        ros2_status
    else
        echo -e "${RED}Error: DOMAIN_ID는 숫자만 입력 가능합니다.${RESET}"
        return 1
    fi
}

ros2_help() {
    if [ $# -ne 0 ]; then
        builtin help "$@"
        return
    fi

    echo -e "${BLUE}======================================================================${RESET}"
    echo -e "  🐆  ${GREEN}ROS2 Jazzy & CycloneDDS/FastDDS 개발 인프라 가이드${RESET}"
    echo -e "${BLUE}======================================================================${RESET}"

    echo -e "${YELLOW}[1] 워크스페이스 제어 (Workspace)${RESET}"
    echo -e "  • ${CYAN}ws [워크스페이스]${RESET}        : ~/ 하위의 해당 워크스페이스를 자동 검색하여 소싱"
    echo -e "  • ${CYAN}ws_reset [워크스페이스]${RESET}  : 워크스페이스 의존 환경을 초기화하고 기본 ROS2만 유지"
    echo -e "  • ${CYAN}jazzy${RESET}                  : ROS2 Jazzy 기본 설정 파일 수동 재소싱"
    echo ""

    echo -e "${YELLOW}[2] DDS 네트워크 환경 제어 (Network & DDS)${RESET}"
    echo -e "  • ${CYAN}ros_mode / ros2_mode [모드]${RESET} : 통신 모드 제어 (${GREEN}LOCAL${RESET} | ${GREEN}SUBNET${RESET} | ${GREEN}UNICAST [IP]${RESET} | ${GREEN}RESET${RESET})"
    echo -e "  • ${CYAN}ros_domain / ros2_domain [ID]${RESET}: ROS_DOMAIN_ID 값을 손쉽게 변경 후 모드 확인"
    echo -e "  • ${CYAN}ros_status / ros2_status${RESET}     : IP 대역, 네트워크 연결 유무, DDS 변수 및 모드 종합 진단"
    echo ""

    echo -e "${YELLOW}[3] Colcon 빌드 및 테스트 (Build & Test)${RESET}"
    echo -e "  • ${CYAN}cb / cbs${RESET}               : colcon build --symlink-install (심볼릭 빌드)"
    echo -e "  • ${CYAN}cbp [패키지명]${RESET}        : 특정 패키지만 선택 지정하여 빌드"
    echo -e "  • ${CYAN}ct${RESET}                   : 패키지 테스트 실행 (colcon test)"
    echo -e "  • ${CYAN}ctr${RESET}                 : 테스트 결과 요약 조회"
    echo ""

    echo -e "💡  ${GREEN}Tip: 'ros_help' 또는 'ros2_help'를 입력하면 언제든지 이 설명서를 호출할 수 있습니다.${RESET}"
}

# 함수 이름 양방향 호환 별칭
alias ros_status="ros2_status"
alias ros_mode="ros2_mode"
alias ros_domain="ros2_domain"
alias ros_help="ros2_help"

# 로깅 및 ROS 2 개발 전용 통합 별칭
alias roslog="ccze -A"
alias roserr="grep -E 'WARN|ERROR'"
alias cb='colcon build --symlink-install'
alias cbs='colcon build --symlink-install'
alias cbp='colcon build --symlink-install --packages-select'
alias cbu='colcon build --symlink-install --packages-up-to'
alias ct='colcon test'
alias ctp='colcon test --packages-select'
alias ctr='colcon test-result'
alias r2='ros2'
alias rtl='ros2 topic list'
alias tl='ros2 topic list'
alias te='ros2 topic echo'
alias rnl='ros2 node list'
alias nl='ros2 node list'
alias rnode='ros2 run'
alias af='ament_flake8'
alias ac='ament_cpplint'
alias testpub='ros2 run demo_nodes_cpp talker'
alias testsub='ros2 run demo_nodes_cpp listener'
alias testpubimg='ros2 run image_tools cam2image'
alias testsubimg='ros2 run image_tools showimage'
alias di='rosdep install --from-paths src -y --ignore-src --os=ubuntu:noble'
alias killgazebo='killall -9 ruby gz-sim-server gz-sim-gui 2>/dev/null; echo "Gazebo Harmonic terminated."'

# 로봇 기본 설정
export TURTLEBOT3_MODEL=burger

# Gazebo Harmonic (Jazzy 기본 표준) 최적화 설정
export GZ_SIM_RENDER_ENGINE_BACKEND=ogre2
export QT_QUICK_BACKEND=opengl
export QT_QPA_PLATFORM=xcb

# QML 비치명적 로그 스팸 차단
export QT_LOGGING_RULES="qt.qml.binding.removal.info=false;qt.qml.binding.loop=false;*.debug=false"

# Gazebo Transport 통신 최적화
export GZ_IP=127.0.0.1
export GZ_PARTITION=default
export GZ_TRANSPORT_USE_SHARED_MEMORY=1
export GZ_FUEL_DISABLE=1

