#!/usr/bin/zsh
# ===============================================================
# 1. ROS 2 Jazzy 기본 소싱 및 자동완성
# ===============================================================
if [ -f "/opt/ros/jazzy/setup.zsh" ]; then
    source /opt/ros/jazzy/setup.zsh
fi
alias jazzy="source /opt/ros/jazzy/setup.zsh; echo '🐆 /opt/ros/jazzy/setup.zsh Sourced!'"

if command -v register-python-argcomplete3 &>/dev/null; then
    eval "$(register-python-argcomplete3 --shell zsh ros2)"
    eval "$(register-python-argcomplete3 --shell zsh colcon)"
elif command -v register-python-argcomplete &>/dev/null; then
    eval "$(register-python-argcomplete --shell zsh ros2)"
    eval "$(register-python-argcomplete --shell zsh colcon)"
fi

# ===============================================================
# 2. 전역 네트워크 & DDS 환경 변수
# ===============================================================
export RCUTILS_COLORIZED_OUTPUT=1
export RCUTILS_LOGGING_USE_STDOUT=1
export RCUTILS_LOGGING_BUFFERED_STREAM=0
export RCUTILS_CONSOLE_OUTPUT_FORMAT="[{severity}] [{time}] [{name}]: {message}"

# [Layer 1] 글로벌 기본 설정 (초기값)
export ROS_DOMAIN_ID=0
export RMW_IMPLEMENTATION="rmw_cyclonedds_cpp"

# 물리적 라우팅이 열려있는 기본 인터페이스 탐지 (가상망 우회)
export ROS_TARGET_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
# 오프라인 상태라 default 라우팅이 없을 경우 유선/무선 중 활성화된 것을 찾음
if [ -z "$ROS_TARGET_INTERFACE" ]; then
    export ROS_TARGET_INTERFACE=$(ip -4 -o addr show | awk '{print $2}' | grep -E '^en|^wl' | head -n 1)
fi

export CYCLONE_BASE_FILE="$HOME/ROS2CONFIG/DDS_Config/cyclonedds_jazzy_v5.xml"
export FASTDDS_BASE_FILE="$HOME/ROS2CONFIG/DDS_Config/fastdds_jazzy_v5.xml"
export CYCLONE_FILE_NAME="${CYCLONE_BASE_FILE##*/}"
export FASTDDS_FILE_NAME="${FASTDDS_BASE_FILE##*/}"

# ===============================================================
# 3. 글로벌 터미널 동기화 (Zsh Hook)
# ===============================================================
autoload -Uz add-zsh-hook

_save_ros_state() {
    echo "export ROS_CUSTOM_MODE=\"$ROS_CUSTOM_MODE\"" > "$HOME/.ros2_env_state"
    echo "export ROS_STATIC_PEERS=\"$ROS_STATIC_PEERS\"" >> "$HOME/.ros2_env_state"
    echo "export RMW_IMPLEMENTATION=\"$RMW_IMPLEMENTATION\"" >> "$HOME/.ros2_env_state"
    echo "export ROS_DOMAIN_ID=\"$ROS_DOMAIN_ID\"" >> "$HOME/.ros2_env_state"
}

_sync_ros_state() {
    if [ -f "$HOME/.ros2_env_state" ]; then
        local OLD_MODE="$ROS_CUSTOM_MODE"
        local OLD_RMW="$RMW_IMPLEMENTATION"
        local OLD_DOMAIN="$ROS_DOMAIN_ID"

        # 외부 터미널에서 변경된 글로벌 상태 로드
        source "$HOME/.ros2_env_state"

        # 상태가 외부 터미널에 의해 변경되었다면 백그라운드 적용
        if [ "$OLD_MODE" != "$ROS_CUSTOM_MODE" ] || [ "$OLD_RMW" != "$RMW_IMPLEMENTATION" ] || [ "$OLD_DOMAIN" != "$ROS_DOMAIN_ID" ]; then
            _apply_ros_net_settings "$ROS_CUSTOM_MODE" "$ROS_STATIC_PEERS" > /dev/null 2>&1
        fi
    fi
}

# 엔터(프롬프트 갱신) 시마다 동기화 함수 자동 실행
add-zsh-hook precmd _sync_ros_state

# ===============================================================
# 4. 네트워크 및 RMW 제어 코어 함수
# ===============================================================
_apply_ros_net_settings() {
    local mode="${1:u}"
    local peer_ip="$2"

    export ROS_CUSTOM_MODE="$mode"

    # 공통: 어떤 모드에서든 성능 튜닝이 반영된 XML 설정은 항상 로드합니다.
    # (LOCAL 모드여도 ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST 옵션 덕분에 외부로 트래픽이 나가지 않습니다.)
    if [ "$RMW_IMPLEMENTATION" = "rmw_cyclonedds_cpp" ]; then
        export CYCLONEDDS_URI="file://${CYCLONE_BASE_FILE}"
    elif [ "$RMW_IMPLEMENTATION" = "rmw_fastrtps_cpp" ]; then
        export FASTRTPS_DEFAULT_PROFILES_FILE="${FASTDDS_BASE_FILE}"
    fi

    case "$mode" in
        LOCAL)
            export ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST
            unset ROS_STATIC_PEERS
            ;;
        SUBNET)
            export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET
            # 외부 PC(Wi-Fi) IP가 인자로 주어지면 하이브리드 피어로 주입
            if [ -n "$peer_ip" ]; then
                export ROS_STATIC_PEERS="$peer_ip"
            else
                unset ROS_STATIC_PEERS
            fi
            ;;
        UNICAST)
            export ROS_AUTOMATIC_DISCOVERY_RANGE=OFF
            if [ -n "$peer_ip" ]; then
                export ROS_STATIC_PEERS="$peer_ip"
            elif [ -z "$ROS_STATIC_PEERS" ]; then
                export ROS_STATIC_PEERS="127.0.0.1" # Safe fallback
            fi
            ;;
        *)
            echo "Invalid ROS Network Mode."
            return 1
            ;;
    esac
}

# 셸 진입 시 초기 모드 로드 (기존 상태 파일이 있으면 로드, 없으면 LOCAL)
if [ -f "$HOME/.ros2_env_state" ]; then
    source "$HOME/.ros2_env_state"
    _apply_ros_net_settings "${ROS_CUSTOM_MODE}" "${ROS_STATIC_PEERS}" > /dev/null 2>&1
else
    _apply_ros_net_settings "LOCAL"
    _save_ros_state
fi

# ===============================================================
# ANSI 색상
# ===============================================================
YELLOW="\033[33m"
GREEN="\033[32m"
BLUE="\033[34m"
RED="\033[31m"
CYAN="\033[36m"
RESET="\033[0m"

# ===============================================================
# 5. 워크스페이스 관리
# ===============================================================
ws_reset() {
    local ROS_DISTRO=${1:-jazzy}
    unset AMENT_PREFIX_PATH
    unset COLCON_PREFIX_PATH
    unset ROS_PREFIX_PATH
    if [ -f "/opt/ros/$ROS_DISTRO/setup.zsh" ]; then
        source "/opt/ros/$ROS_DISTRO/setup.zsh"
        echo -e "${BLUE}Environment reset to Base ROS 2 ($ROS_DISTRO) only.${RESET}"
    fi
}

ws() {
    export PATH="/usr/bin:/bin:/usr/local/bin:${PATH}"
    local ws_name="$1"
    : ${ROS_DISTRO:=jazzy}

    if [ -z "$ws_name" ] || [ "$ws_name" = "." ]; then
        ws_name=$(basename "$PWD")
    fi

    if [[ -z "$AMENT_PREFIX_PATH" || "$AMENT_PREFIX_PATH" == "/opt/ros/$ROS_DISTRO" ]]; then
        if [ -f "/opt/ros/$ROS_DISTRO/setup.zsh" ]; then
            source "/opt/ros/$ROS_DISTRO/setup.zsh"
        fi
    fi

    local TARGET_DIR=""
    if [ "$(basename "$PWD")" = "$ws_name" ]; then
        TARGET_DIR="$PWD"
    elif [ -d "./$ws_name" ]; then
        TARGET_DIR="$(pwd)/$ws_name"
    fi

    if [ -z "$TARGET_DIR" ]; then
        if [ -d "$HOME" ]; then
            TARGET_DIR=$(find "$HOME" -maxdepth 5 -type d -name "$ws_name" -print -quit 2>/dev/null)
        fi
    fi

    if [ -z "$TARGET_DIR" ]; then
        echo -e "${RED}Error: Workspace '$ws_name' not found.${RESET}"
        return 1
    fi

    local TARGET_PATH="$TARGET_DIR/install/local_setup.zsh"
    if [ -f "$TARGET_PATH" ]; then
        source "$TARGET_PATH"
        echo -e "${GREEN}✔ Workspace '$ws_name' overlaid!${RESET} ($TARGET_DIR)"
    else
        echo -e "${RED}Error: $TARGET_PATH not found. Did you colcon build?${RESET}"
    fi
}

# ===============================================================
# 6. 커맨드라인 CLI 툴 (상태 진단 및 제어)
# ===============================================================
ros2_rmw() {
    local target=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$target" in
        cyclone) export RMW_IMPLEMENTATION="rmw_cyclonedds_cpp" ;;
        fastdds) export RMW_IMPLEMENTATION="rmw_fastrtps_cpp" ;;
        *)
            echo -e "${RED}Usage: ros2_rmw [cyclone|fastdds]${RESET}"
            return 1
            ;;
    esac
    _apply_ros_net_settings "$ROS_CUSTOM_MODE" "$ROS_STATIC_PEERS"
    _save_ros_state

    # 데몬 그래프 꼬임 방지를 위한 백그라운드 재시작
    ros2 daemon stop > /dev/null 2>&1
    ros2 daemon start > /dev/null 2>&1

    echo -e "${GREEN}✔ RMW 변경 및 Daemon 재시작 완료: ${RMW_IMPLEMENTATION}${RESET}\n"
    ros2_status
}

ros2_mode() {
    local target=$(echo "$1" | tr '[:lower:]' '[:upper:]')
    local target_ip="$2"

    case "$target" in
        LOCAL|SUBNET|UNICAST)
            if [ "$target" = "UNICAST" ] && [ -z "$target_ip" ] && [ -z "$ROS_STATIC_PEERS" ]; then
                echo -e "${RED}Error: UNICAST mode requires a target IP address.${RESET}"
                echo "Usage: ros2_mode unicast <IP_ADDRESS>"
                return 1
            fi

            _apply_ros_net_settings "$target" "$target_ip"
            _save_ros_state

            # 네트워크 모드 변경 시 백그라운드 데몬 재시작
            ros2 daemon stop > /dev/null 2>&1
            ros2 daemon start > /dev/null 2>&1

            echo -e "${GREEN}✔ ROS 2 통신 모드 변경 완료: [${YELLOW}${target}${GREEN}]${RESET}\n"
            ros2_status
            ;;
        *)
            echo -e "${RED}Usage: ros2_mode [local | subnet | unicast <IP>]${RESET}"
            return 1
            ;;
    esac
}

ros2_domain() {
    if [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 0 && $1 <= 232 )); then
        export ROS_DOMAIN_ID="$1"
        _save_ros_state

        ros2 daemon stop > /dev/null 2>&1
        ros2 daemon start > /dev/null 2>&1

        echo -e "${GREEN}✔ ROS_DOMAIN_ID 변경 완료: [${YELLOW}${1}${GREEN}]${RESET}\n"
        ros2_status
    else
        echo -e "${RED}Error: ROS_DOMAIN_ID must be a number between 0 and 232.${RESET}"
        return 1
    fi
}

ros2_status() {
    local DEFAULT_NIC=$(ip route | grep default | awk '{print $5}' | head -n 1)
    local TARGET_NIC="${ROS_TARGET_INTERFACE:-$DEFAULT_NIC}"
    local TARGET_IP=$(ip -4 addr show "$TARGET_NIC" 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1)

    local CURRENT_MODE=""
    if [ "$RMW_IMPLEMENTATION" = "rmw_cyclonedds_cpp" ] && [ -n "$CYCLONEDDS_URI" ]; then
        [[ -f "$CYCLONE_BASE_FILE" ]] && CURRENT_MODE="\033[32m${CYCLONE_FILE_NAME} (CycloneDDS)\033[0m" || CURRENT_MODE="\033[31mNO CONFIG FILE\033[0m"
    elif [ "$RMW_IMPLEMENTATION" = "rmw_fastrtps_cpp" ] && [ -n "$FASTRTPS_DEFAULT_PROFILES_FILE" ]; then
        [[ -f "$FASTDDS_BASE_FILE" ]] && CURRENT_MODE="\033[32m${FASTDDS_FILE_NAME} (FastDDS)\033[0m" || CURRENT_MODE="\033[31mNO CONFIG FILE\033[0m"
    else
        CURRENT_MODE="\033[33mOFFLINE (Local default config)\033[0m"
    fi

    local ROS_TRAFFIC_PATH=""
    case "$ROS_CUSTOM_MODE" in
        "LOCAL")
            ROS_TRAFFIC_PATH="\033[1;32mLocalhost Discovery [ROS 2 Local IPC]\033[0m"
            ;;
        "SUBNET")
            if [ -n "$TARGET_IP" ]; then
                if [ -n "$ROS_STATIC_PEERS" ]; then
                    ROS_TRAFFIC_PATH="\033[1;34mHybrid Subnet (${TARGET_NIC})\033[0m + \033[1;36mPeer [${ROS_STATIC_PEERS}]\033[0m"
                else
                    ROS_TRAFFIC_PATH="\033[1;34mMulticast Subnet (${TARGET_NIC} -> ${TARGET_IP})\033[0m"
                fi
            else
                ROS_TRAFFIC_PATH="\033[1;31mRouting Failed (NIC Down or Missing)\033[0m"
            fi
            ;;
        "UNICAST")
            if [ -n "$ROS_STATIC_PEERS" ]; then
                local PEER_ROUTE=$(ip route get "$ROS_STATIC_PEERS" 2>/dev/null)
                local PEER_INT=$(echo "$PEER_ROUTE" | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
                local PEER_SRC=$(echo "$PEER_ROUTE" | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
                if [ -n "$PEER_INT" ]; then
                    ROS_TRAFFIC_PATH="\033[1;36mUnicast Route (${PEER_INT} : ${PEER_SRC}) -> Peer [${ROS_STATIC_PEERS}]\033[0m"
                else
                    ROS_TRAFFIC_PATH="\033[1;31mUnicast Routing Failed (Check IP)\033[0m"
                fi
            else
                ROS_TRAFFIC_PATH="\033[1;31mNo Static Peer Defined\033[0m"
            fi
            ;;
    esac

    echo "--------------------------------------------------------"
    echo -e "CURRENT DDS CONFIG   : ${CURRENT_MODE}"
    echo -e "ACTUAL ROS 2 PATH    : ${ROS_TRAFFIC_PATH}"
    echo "--------------------------------------------------------"
    echo -e "Target NIC (${TARGET_NIC:-"None"}) : \033[32m${TARGET_IP:-"Disconnected"}\033[0m"
    echo "--------------------------------------------------------"
    echo -e "ROS_DOMAIN_ID        : \033[1;33m${ROS_DOMAIN_ID}\033[0m"
    echo -e "ROS NETWORK MODE     : \033[1;36m${ROS_CUSTOM_MODE}\033[0m (Discovery: \033[1;32m${ROS_AUTOMATIC_DISCOVERY_RANGE}\033[0m)"
    [ -n "$ROS_STATIC_PEERS" ] && echo -e "ROS_STATIC_PEERS     : \033[1;33m${ROS_STATIC_PEERS}\033[0m"
    echo -e "RMW_IMPLEMENTATION   : \033[1;32m${RMW_IMPLEMENTATION}\033[0m"
    echo "--------------------------------------------------------"
}

# ===============================================================
# 7. Aliases
# ===============================================================
alias ros_status="ros2_status"
alias ros_mode="ros2_mode"
alias ros_domain="ros2_domain"
alias ros_rmw="ros2_rmw"

alias roslog="ccze -A"
alias roserr="grep -E 'WARN|ERROR'"

alias cb='colcon build --symlink-install'
alias ct='colcon test'
alias cbs='colcon build --symlink-install'
alias cbp='colcon build --symlink-install --packages-select'
alias cbu='colcon build --symlink-install --packages-up-to'

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

export TURTLEBOT3_MODEL=burger
export GZ_SIM_RENDER_ENGINE_BACKEND=ogre2
export QT_QUICK_BACKEND=opengl

# Gazebo IPC 격리 (ROS 2 DDS 아님)
export GZ_IP=127.0.0.1
export GZ_PARTITION=default
export GZ_TRANSPORT_USE_SHARED_MEMORY=1
export GZ_FUEL_DISABLE=1
