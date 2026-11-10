#!/usr/bin/zsh
# ==============================================================================
# ROS 2 Jazzy Jalisco High-Performance Development Environment
# OS: Ubuntu 24.04 LTS (Noble Numbat)
# Middleware: Eclipse CycloneDDS (rmw_cyclonedds_cpp) & FastDDS Fallback
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Base ROS 2 Sourcing & Fast Shell Autocompletion
# ------------------------------------------------------------------------------
if [[ -f "/opt/ros/jazzy/setup.zsh" ]]; then
    source "/opt/ros/jazzy/setup.zsh"
fi

alias jazzy="source /opt/ros/jazzy/setup.zsh && echo '🐆 /opt/ros/jazzy/setup.zsh Sourced!'"

# Python 3.12+ Argcomplete Integration for Zsh
if (( $+commands[register-python-argcomplete3] )); then
    eval "$(register-python-argcomplete3 --shell zsh ros2 2>/dev/null)"
    eval "$(register-python-argcomplete3 --shell zsh colcon 2>/dev/null)"
elif (( $+commands[register-python-argcomplete] )); then
    eval "$(register-python-argcomplete --shell zsh ros2 2>/dev/null)"
    eval "$(register-python-argcomplete --shell zsh colcon 2>/dev/null)"
fi

# ------------------------------------------------------------------------------
# 2. Logging & Console Formatting Configuration
# ------------------------------------------------------------------------------
export RCUTILS_COLORIZED_OUTPUT=1
export RCUTILS_LOGGING_USE_STDOUT=1
export RCUTILS_LOGGING_BUFFERED_STREAM=0
export RCUTILS_CONSOLE_OUTPUT_FORMAT="[{severity}] [{time}] [{name}]: {message}"

# ------------------------------------------------------------------------------
# 3. Dynamic DDS Infrastructure & Variables
# ------------------------------------------------------------------------------

# export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp


export CYCLONE_BASE_FILE="${HOME}/ROS2CONFIG/DDS_Config/cyclonedds_jazzy_v4.xml"
export FASTDDS_BASE_FILE="${HOME}/ROS2CONFIG/DDS_Config/fastdds_jazzy_v4.xml"
export DEFAULT_ROBOT_IP="${ROBOT_IP:-192.168.100.20}"

_apply_ros_net_settings() {
    local target_mode="$1"
    local target_ip="$2"

    case "${target_mode}" in
        "LOCAL")
            export ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST
            export ROS_STATIC_PEERS=""
            unset CYCLONEDDS_URI
            unset FASTRTPS_DEFAULT_PROFILES_FILE
            ;;
        "SUBNET")
            export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET
            export ROS_STATIC_PEERS=""
            if [[ "${RMW_IMPLEMENTATION}" == "rmw_cyclonedds_cpp" ]]; then
                export CYCLONEDDS_URI="file://${CYCLONE_BASE_FILE}"
                unset FASTRTPS_DEFAULT_PROFILES_FILE
            else
                export FASTRTPS_DEFAULT_PROFILES_FILE="${FASTDDS_BASE_FILE}"
                unset CYCLONEDDS_URI
            fi
            ;;
        "UNICAST")
            export ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST
            local peer_candidate="${target_ip:-${DEFAULT_ROBOT_IP}}"
            export ROS_STATIC_PEERS="${peer_candidate}"

            if [[ "${RMW_IMPLEMENTATION}" == "rmw_cyclonedds_cpp" ]]; then
                export CYCLONEDDS_URI="file://${CYCLONE_BASE_FILE}"
                unset FASTRTPS_DEFAULT_PROFILES_FILE
            else
                export FASTRTPS_DEFAULT_PROFILES_FILE="${FASTDDS_BASE_FILE}"
                unset CYCLONEDDS_URI
            fi
            ;;
    esac
}

export ROS_CUSTOM_MODE="${ROS_CUSTOM_MODE:-LOCAL}"
_apply_ros_net_settings "${ROS_CUSTOM_MODE}"

# ANSI Formatting Helpers
FMT_YELLOW="\033[33m"
FMT_GREEN="\033[32m"
FMT_BLUE="\033[34m"
FMT_RED="\033[31m"
FMT_CYAN="\033[36m"
FMT_MAGENTA="\033[35m"
FMT_BOLD="\033[1m"
FMT_DIM="\033[2m"
FMT_RESET="\033[0m"

# ------------------------------------------------------------------------------
# 4. Workspace Overlay Lifecycle Engine
# ------------------------------------------------------------------------------
ws_reset() {
    local target_distro="${1:-jazzy}"
    unset AMENT_PREFIX_PATH COLCON_PREFIX_PATH ROS_PREFIX_PATH
    if [[ -f "/opt/ros/${target_distro}/setup.zsh" ]]; then
        source "/opt/ros/${target_distro}/setup.zsh"
        echo -e "${FMT_BLUE}Environment reset to Base ROS 2 (${target_distro}) isolated.${FMT_RESET}"
    else
        echo -e "${FMT_RED}Error: Base ROS 2 not found at /opt/ros/${target_distro}${FMT_RESET}"
        return 1
    fi
}

ws() {
    local ws_name="$1"
    local distro="${ROS_DISTRO:-jazzy}"
    local target_dir=""

    if [[ -z "${ws_name}" || "${ws_name}" == "." ]]; then
        ws_name="$(basename "${PWD}")"
    fi

    if [[ -z "${AMENT_PREFIX_PATH}" || "${AMENT_PREFIX_PATH}" == "/opt/ros/${distro}" ]]; then
        [[ -f "/opt/ros/${distro}/setup.zsh" ]] && source "/opt/ros/${distro}/setup.zsh"
    fi

    # 1. PWD 확인
    if [[ "$(basename "${PWD}")" == "${ws_name}" ]]; then
        target_dir="${PWD}"
    # 2. 하위 디렉토리 확인
    elif [[ -d "./${ws_name}" ]]; then
        target_dir="${PWD}/${ws_name}"
    fi

    # 3. 우선순위 디렉토리 탐색
    if [[ -z "${target_dir}" ]]; then
        local search_roots=("${HOME}/PNS" "${HOME}/ros2_ws" "${HOME}/workspace" "${HOME}")
        for root in "${search_roots[@]}"; do
            if [[ -d "${root}/${ws_name}" ]]; then
                target_dir="${root}/${ws_name}"
                break
            fi
        done

        if [[ -z "${target_dir}" ]]; then
            target_dir=$(find "${HOME}" -maxdepth 2 -type d -name "${ws_name}" -print -quit 2>/dev/null)
        fi
    fi

    if [[ -z "${target_dir}" || ! -d "${target_dir}" ]]; then
        echo -e "${FMT_RED}Error: Workspace '${ws_name}' cannot be resolved.${FMT_RESET}"
        return 1
    fi

    local target_setup="${target_dir}/install/local_setup.zsh"
    if [[ -f "${target_setup}" ]]; then
        source "${target_setup}"
        local overlay_count
        overlay_count=$(echo "${AMENT_PREFIX_PATH}" | tr ':' '\n' | grep -v "/opt/ros/" | grep -c -v '^$')
        echo -e "${FMT_GREEN}✔ Workspace '${ws_name}' successfully overlaid!${FMT_RESET} (${target_dir})"
        if (( overlay_count > 1 )); then
            echo -e "${FMT_CYAN}Active Overlaid Chaining Stack (${overlay_count}):${FMT_RESET}"
            echo "${AMENT_PREFIX_PATH}" | tr ':' '\n' | grep -v "/opt/ros/" | sed 's|^|  -> |'
        fi
    else
        echo -e "${FMT_RED}Error: Build artifact '${target_setup}' missing.${FMT_RESET}"
        echo -e "${FMT_YELLOW}Execute 'cb' in ${target_dir} before sourcing.${FMT_RESET}"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# 5. Network & DDS Diagnostics Engine
# ------------------------------------------------------------------------------
ros2_status() {
    local default_dev
    default_dev=$(ip route show default 2>/dev/null | awk '{print $5; exit}')

    local wired_dev
    wired_dev=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(eth|en)' | head -n 1)
    local wireless_dev
    wireless_dev=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(wl)' | head -n 1)

    local wired_ip="" wireless_ip="" lo_ip="" default_ip=""
    [[ -n "${wired_dev}" ]] && wired_ip=$(ip -4 addr show "${wired_dev}" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)
    [[ -n "${wireless_dev}" ]] && wireless_ip=$(ip -4 addr show "${wireless_dev}" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)
    [[ -n "${default_dev}" ]] && default_ip=$(ip -4 addr show "${default_dev}" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)
    lo_ip=$(ip -4 addr show lo 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)

    local dds_state=""
    if [[ "${RMW_IMPLEMENTATION}" == "rmw_cyclonedds_cpp" && -n "${CYCLONEDDS_URI}" ]]; then
        if [[ -f "${CYCLONE_BASE_FILE}" ]]; then
            dds_state="\033[32mCycloneDDS [Active: $(basename "${CYCLONE_BASE_FILE}")]\033[0m"
        else
            dds_state="\033[31mCycloneDDS [Error: File Missing]\033[0m"
        fi
    elif [[ "${RMW_IMPLEMENTATION}" == "rmw_fastrtps_cpp" && -n "${FASTRTPS_DEFAULT_PROFILES_FILE}" ]]; then
        dds_state="\033[32mFastDDS [Active: $(basename "${FASTRTPS_DEFAULT_PROFILES_FILE}")]\033[0m"
    else
        dds_state="\033[33mIsolated Mode [Host Socket Loopback]\033[0m"
    fi

    local traffic_path=""
    case "${ROS_CUSTOM_MODE}" in
        "LOCAL")
            traffic_path="\033[1;32mLoopback (lo) Sockets [Localhost IPC Isolation]\033[0m"
            ;;
        "SUBNET")
            if [[ -n "${default_dev}" ]]; then
                traffic_path="\033[1;34mSubnet Auto-Discovery via ${default_dev} (${default_ip:-No IP})\033[0m"
            else
                traffic_path="\033[1;31mRouting Failed: No Default Gateway Found\033[0m"
            fi
            ;;
        "UNICAST")
            traffic_path="\033[1;36mTargeted Unicast Peer(s): [${ROS_STATIC_PEERS:-Unset}]\033[0m"
            ;;
    esac

    echo "======================================================================"
    echo -e "RMW IMPLEMENTATION   : \033[1;35m${RMW_IMPLEMENTATION}\033[0m"
    echo -e "ACTIVE DDS PROFILE   : ${dds_state}"
    echo -e "ROS TRAFFIC ROUTE    : ${traffic_path}"
    echo "----------------------------------------------------------------------"
    echo -e "Ethernet (${wired_dev:-N/A})  : $([[ -n "${wired_ip}" ]] && echo -e "\033[32mUP (${wired_ip})\033[0m" || echo -e "\033[31mDOWN\033[0m")"
    echo -e "Wireless (${wireless_dev:-N/A})  : $([[ -n "${wireless_ip}" ]] && echo -e "\033[32mUP (${wireless_ip})\033[0m" || echo -e "\033[31mDOWN\033[0m")"
    echo -e "Loopback (lo)        : $([[ -n "${lo_ip}" ]] && echo -e "\033[32mUP (${lo_ip})\033[0m" || echo -e "\033[31mDOWN\033[0m")"
    echo "----------------------------------------------------------------------"
    echo -e "ROS_DOMAIN_ID        : \033[1;33m${ROS_DOMAIN_ID:-0}\033[0m"
    echo -e "DISCOVERY RANGE      : \033[1;32m${ROS_AUTOMATIC_DISCOVERY_RANGE}\033[0m"
    echo "======================================================================"
}

ros2_mode() {
    local target=$(echo "$1" | tr '[:lower:]' '[:upper:]')
    local target_ip="$2"

    if [[ "${target}" == "RESET" || "${target}" == "INIT" ]]; then
        target="LOCAL"
        echo -e "${FMT_BLUE}Resetting network topology to LOCAL...${FMT_RESET}"
    fi

    case "${target}" in
        "LOCAL"|"SUBNET"|"UNICAST")
            export ROS_CUSTOM_MODE="${target}"
            _apply_ros_net_settings "${target}" "${target_ip}"
            echo -e "${FMT_GREEN}✔ ROS 2 Network Strategy Applied: [${FMT_YELLOW}${target}${FMT_RESET}${FMT_GREEN}]${FMT_RESET}"
            ;;
        *)
            echo -e "${FMT_RED}Usage: ros2_mode [LOCAL | SUBNET | UNICAST <IP> | RESET]${FMT_RESET}"
            return 1
            ;;
    esac
    echo ""
    ros2_status
}

ros2_domain() {
    if [[ -z "$1" || ! "$1" =~ ^[0-9]+$ ]]; then
        echo -e "${FMT_RED}Usage: ros2_domain [DOMAIN_ID_NUMBER (0~101)]${FMT_RESET}"
        return 1
    fi
    export ROS_DOMAIN_ID="$1"
    echo -e "${FMT_GREEN}✔ ROS_DOMAIN_ID set to: [${FMT_YELLOW}${1}${FMT_RESET}${FMT_GREEN}]${FMT_RESET}"
    echo ""
    ros2_status
}

# ------------------------------------------------------------------------------
# 6. Interactive Developer Guide Engine (ros2_help)
# ------------------------------------------------------------------------------
ros2_help() {
    if (( $# > 0 )); then
        builtin help "$@"
        return
    fi

    echo -e "${FMT_BLUE}================================================================================${FMT_RESET}"
    echo -e "  🐆  ${FMT_BOLD}${FMT_GREEN}ROS 2 Jazzy & CycloneDDS Production System CLI Guide${FMT_RESET}"
    echo -e "${FMT_BLUE}================================================================================${FMT_RESET}"

    echo -e "${FMT_YELLOW}[1] 워크스페이스 제어 (Workspace Overlay Engine)${FMT_RESET}"
    echo -e "  • ${FMT_CYAN}ws [워크스페이스명 / .]${FMT_RESET} : 해당 워크스페이스를 자동 검색하여 오버레이 소싱"
    echo -e "  • ${FMT_CYAN}ws_reset [디스트로명]${FMT_RESET} : 오버레이 의존성을 완전히 언셋하고 Base ROS 2로 초기화"
    echo -e "  • ${FMT_CYAN}jazzy${FMT_RESET}                  : ROS 2 Jazzy 기본 환경(/opt/ros/jazzy) 강제 재소싱"
    echo ""

    echo -e "${FMT_YELLOW}[2] DDS 네트워크 및 토폴로지 제어 (Network & DDS Engine)${FMT_RESET}"
    echo -e "  • ${FMT_CYAN}ros_mode / ros2_mode [모드] [IP]${FMT_RESET} : DDS 통신 범위 및 엔드포인트 동적 전환"
    echo -e "      - ${FMT_GREEN}LOCAL${FMT_RESET}                 : 호스트 루프백(lo) 및 내부 프로세스 통신으로 완전 격리"
    echo -e "      - ${FMT_GREEN}SUBNET${FMT_RESET}                : 서브넷 전체 멀티캐스트 자동 탐색 (239.255.0.1)"
    echo -e "      - ${FMT_GREEN}UNICAST [IP]${FMT_RESET}          : 타깃 로봇/PC IP 지정 1:1 유니캐스트 (Wi-Fi 드롭 방어)"
    echo -e "      - ${FMT_GREEN}RESET${FMT_RESET}                 : 통신 설정을 LOCAL 기본값으로 초기화"
    echo -e "  • ${FMT_CYAN}ros_domain / ros2_domain [ID]${FMT_RESET}  : ROS_DOMAIN_ID 동적 변경 (0~101) 및 포트 분리"
    echo -e "  • ${FMT_CYAN}ros_status / ros2_status${FMT_RESET}       : 물리 인터페이스(IP), 게이트웨이, DDS 프로필 진단"
    echo ""

    echo -e "${FMT_YELLOW}[3] Colcon 빌드 & 테스트 가속 엔진 (Build & Test)${FMT_RESET}"
    echo -e "  • ${FMT_CYAN}cb / cbs${FMT_RESET}                 : colcon build --symlink-install (심볼릭 링크 빌드)"
    echo -e "  • ${FMT_CYAN}cbp [패키지명]${FMT_RESET}          : 특정 패키지만 선택 지정하여 빌드"
    echo -e "  • ${FMT_CYAN}cbu [패키지명]${FMT_RESET}          : 지정 패키지 및 상위 의존성 패키지까지 연쇄 빌드"
    echo -e "  • ${FMT_CYAN}ct${FMT_RESET}                       : colcon test (테스트 스위트 전체 실행)"
    echo -e "  • ${FMT_CYAN}ctp [패키지명]${FMT_RESET}          : 특정 패키지만 선택하여 단위 테스트 실행"
    echo -e "  • ${FMT_CYAN}ctr${FMT_RESET}                      : 테스트 결과 요약 분석 리포트 출력"
    echo ""

    echo -e "${FMT_YELLOW}[4] ROS 2 CLI & 런타임 제어 단축어 (Runtime CLI)${FMT_RESET}"
    echo -e "  • ${FMT_CYAN}r2${FMT_RESET}                       : 'ros2' 명령 축약"
    echo -e "  • ${FMT_CYAN}rtl / tl${FMT_RESET}                 : 활성 토픽 목록 조회 (ros2 topic list)"
    echo -e "  • ${FMT_CYAN}te [토픽명]${FMT_RESET}              : 토픽 데이터 실시간 출력 (ros2 topic echo)"
    echo -e "  • ${FMT_CYAN}rnl / nl${FMT_RESET}                 : 활성 노드 목록 조회 (ros2 node list)"
    echo -e "  • ${FMT_CYAN}rsl / ral / rpl${FMT_RESET}          : Service / Action / Parameter 목록 조회"
    echo -e "  • ${FMT_CYAN}rnode [pkg] [exec]${FMT_RESET}       : ros2 run 노드 실행"
    echo -e "  • ${FMT_CYAN}testpub / testsub${FMT_RESET}        : demo_nodes_cpp talker / listener 통신 검증 노드"
    echo -e "  • ${FMT_CYAN}di${FMT_RESET}                       : rosdep 종속성 자동 설치 (Ubuntu Noble 24.04)"
    echo -e "  • ${FMT_CYAN}killgz / killgazebo${FMT_RESET}      : 좀비 Gazebo Harmonic 프로세스 강제 종료"
    echo -e "  • ${FMT_CYAN}roslog / roserr${FMT_RESET}          : 로그 컬러라이징(ccze) / ERROR 및 WARN 필터링"
    echo -e "${FMT_BLUE}================================================================================${FMT_RESET}"
}

# ------------------------------------------------------------------------------
# 7. Function Aliases & Operations
# ------------------------------------------------------------------------------
alias ros_status="ros2_status"
alias ros_mode="ros2_mode"
alias ros_domain="ros2_domain"
alias ros_help="ros2_help"

# Colcon Compilation Accelerators
export CMAKE_BUILD_PARALLEL_LEVEL=$(nproc)
alias cb='colcon build --symlink-install --cmake-args -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo'
alias cbs='colcon build --symlink-install --cmake-args -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo'
alias cbp='colcon build --symlink-install --cmake-args -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo --packages-select'
alias cbu='colcon build --symlink-install --cmake-args -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo --packages-up-to'
alias ct='colcon test'
alias ctp='colcon test --packages-select'
alias ctr='colcon test-result --all'

# Operational Shorthands
alias r2='ros2'
alias rtl='ros2 topic list'
alias tl='ros2 topic list'
alias te='ros2 topic echo'
alias rnl='ros2 node list'
alias nl='ros2 node list'
alias rsl='ros2 service list'
alias ral='ros2 action list'
alias rpl='ros2 param list'
alias rnode='ros2 run'
alias af='ament_flake8'
alias ac='ament_cpplint'
alias roslog="ccze -A"
alias roserr="grep -E 'WARN|ERROR'"

alias testpub='ros2 run demo_nodes_cpp talker'
alias testsub='ros2 run demo_nodes_cpp listener'
alias testpubimg='ros2 run image_tools cam2image'
alias testsubimg='ros2 run image_tools showimage'
alias di='rosdep install --from-paths src -y --ignore-src --os=ubuntu:noble'
alias killgz='killall -9 ruby gz-sim-server gz-sim-gui 2>/dev/null; echo "Gazebo Harmonic instances terminated."'
alias killgazebo='killall -9 ruby gz-sim-server gz-sim-gui 2>/dev/null; echo "Gazebo Harmonic instances terminated."'

# Simulation & Robot Profile
export TURTLEBOT3_MODEL=burger
export GZ_SIM_RENDER_ENGINE_BACKEND=ogre2
export QT_QUICK_BACKEND=opengl
export QT_QPA_PLATFORM=xcb
export QT_LOGGING_RULES="qt.qml.binding.removal.info=false;qt.qml.binding.loop=false;*.debug=false"
export GZ_IP=127.0.0.1
export GZ_PARTITION=default
export GZ_TRANSPORT_USE_SHARED_MEMORY=1
export GZ_FUEL_DISABLE=1
