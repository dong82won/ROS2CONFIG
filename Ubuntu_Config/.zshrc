# ==============================================================================
# 1. Powerlevel10k Instant Prompt (반드시 최상단 유지)
# ==============================================================================
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ==============================================================================
# 2. 시스템 기본 PATH & 개발 환경 변수 (Zsh 경로 중복 자동 제거)
# ==============================================================================
# Zsh 전용 옵션: PATH, LD_LIBRARY_PATH, PYTHONPATH 내 중복 경로 자동 제거
typeset -U PATH LD_LIBRARY_PATH PYTHONPATH

# 기본 시스템 명령 경로 선언
export PATH="/usr/bin:/bin:/usr/local/bin:${PATH}"

# 사용자 바이너리 경로
[[ -d "$HOME/bin" ]] && export PATH="$HOME/bin:${PATH}"
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:${PATH}"

# ==============================================================================
# 3. NVIDIA GeForce RTX 5050 & CUDA 13.2 가속 설정
# ==============================================================================
# [수정됨] 현재 prime-select nvidia (NVIDIA 전용 모드)를 사용 중이므로, 
# 하이브리드(Offload) 모드 변수를 켜두면 창 종료 시 Xorg 크래시가 발생합니다.
# 따라서 아래 두 줄은 주석(#) 처리하여 비활성화합니다.
# export __NV_PRIME_RENDER_OFFLOAD=1
# export __GLX_VENDOR_LIBRARY_NAME=nvidia

export CUDA_CACHE_DISABLE=0

# EGL Vendor JSON 자동 감지 (NVIDIA 드라이버 EGL 자원 정상 해제 유도)
if [ -f "/usr/share/glvnd/egl_vendor.d/10_nvidia.json" ]; then
    export __EGL_VENDOR_LIBRARY_FILENAMES="/usr/share/glvnd/egl_vendor.d/10_nvidia.json"
fi

# CUDA 13.2 Toolkit 경로 설정
export CUDA_HOME="/usr/local/cuda"
if [[ -d "$CUDA_HOME" ]]; then
    export PATH="$CUDA_HOME/bin:${PATH}"
    [[ -d "$CUDA_HOME/lib64" ]] && export LD_LIBRARY_PATH="$CUDA_HOME/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi

# (안정화 설정) NVIDIA 드라이버 스레드 충돌 및 DRI3 해제 크래시 방지
export __GL_THREADED_OPTIMIZATIONS=0
export QT_X11_NO_MITSHM=1
export OGRE_RTT_MODE=Copy
export GZ_RENDERING_ENGINE_GUIS=ogre2
export LIBGL_DRI3_DISABLE=1

# ==============================================================================
# 4. Intel RealSense SDK C++ 공유 라이브러리 & Python 바인딩
# ==============================================================================
# CUDA 가속 빌드된 librealsense2.so C++ 공유 라이브러리 경로
[[ -d "/usr/local/lib" ]] && export LD_LIBRARY_PATH="/usr/local/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# pyrealsense2 공용 사이트 패키지 경로 (3rdparty 가상환경 전역 바인딩)
REALSENSE_PYTHON_DIR="/home/won/PNS/100_Development/150_3rdparty/.venv/lib/python3.12/site-packages"
[[ -d "$REALSENSE_PYTHON_DIR" ]] && export PYTHONPATH="$REALSENSE_PYTHON_DIR${PYTHONPATH:+:${PYTHONPATH}}"

# OpenCV & Qt GUI 백엔드 최적화 (Ubuntu 24.04 GUI 경고 및 폰트 로그 차단)
export QT_QPA_PLATFORM=xcb
export QT_QPA_FONTDIR=/usr/share/fonts/truetype/dejavu
export QT_LOGGING_RULES="qt.qpa.fonts=false;qt.qpa.gl=false;*.debug=false"

# ==============================================================================
# 5. Oh My Zsh 핵심 & 속도 최적화 설정
# ==============================================================================
ZSH_DISABLE_COMPFIX="true"
SKIP_FIX_SECURE_COMPLETION="true"
DISABLE_MAGIC_FUNCTIONS="true"
DISABLE_AUTO_TITLE="true"
DISABLE_UNTRACKED_FILES_DIRTY="true"
COMPLETION_WAITING_DOTS="true"

zstyle ':omz:update' mode reminder
zstyle ':omz:update' frequency 30

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git)

# Oh My Zsh 로드
source $ZSH/oh-my-zsh.sh

# Powerlevel10k 설정 파일 로드
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Locale 설정
export LC_ALL=en_US.UTF-8
export LANGUAGE=en_US:en

# ==============================================================================
# 6. 색상, 히스토리(History) & Zsh Completion 설정
# ==============================================================================
zstyle ':completion:*' list-colors "${(@s.:.)LS_COLORS}"
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/.zcompcache"

HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY

# ==============================================================================
# 7. 사용자 단축어 (Aliases)
# ==============================================================================
# VSCode 내장 GPU(iGPU) 하드웨어 가속 실행 (Electron WebGL 샌드박스 충돌 방지)
alias code='__NV_PRIME_RENDER_OFFLOAD=0 code'

# Shell & Configuration Helpers
alias sz="source ~/.zshrc; echo '✅ .zshrc 가 성공적으로 재로드되었습니다!'"
alias sgz='gedit ~/.zshrc &'
alias io='io.elementary.files . >/dev/null 2>&1 &'
alias blender4.5='~/.local/share/blender/blender > /dev/null 2>&1 &|'

# eza 기반 현대적 ls (가독성 높은 청록색 디렉토리)
if command -v eza &> /dev/null; then
    export EZA_COLORS="di=1;36:ln=1;35:ex=1;32:ur=38;5;250:gw=38;5;245:da=38;5;244"
    alias ls='eza --icons=auto --group-directories-first'
    alias ll='eza -l --icons=auto --git'
    alias tree='eza --tree --icons=auto'
fi

# RealSense 실행 단축키 (CUDA 가속 인라인 자동 바인딩)
alias rs-viewer='sudo realsense-viewer'
alias rs-calib='Intel.Realsense.DynamicCalibrator'

# ROS 2 Jazzy + CycloneDDS 환경 로드
ROS_SETUP_SCRIPT="$HOME/ROS2CONFIG/ROS2SH/ros2_jazzy_cyclone.sh"
alias sros="source $ROS_SETUP_SCRIPT && echo '🤖 ROS 2 Jazzy + CycloneDDS 환경이 적용되었습니다!'"

# Python & UV Development Helpers (가상환경 PYTHONPATH 오염 방지)
alias uva="source .venv/bin/activate"
alias uvr="uv run"
alias uvs="uv sync"
alias uvtest="PYTHONPATH= uv run pytest"

# Git Shortcuts
alias gs='git status'
alias gl='git log --oneline --graph --decorate'

# ==============================================================================
# 8. 외부 프로그램 및 스크립트 로드
# ==============================================================================
# ROS 2 & DDS 통합 환경 자동 Sourcing (P10k 프롬프트 경고 차단 Silent Mode)
if [[ -f "$ROS_SETUP_SCRIPT" ]]; then
    source "$ROS_SETUP_SCRIPT" > /dev/null 2>&1
fi

# NVM 지연 로딩 엔진 (.nvm 디렉토리가 있을 때만 활성화)
export NVM_DIR="$HOME/.nvm"
if [[ -d "$NVM_DIR" ]]; then
    _lazy_load_nvm() {
      unset -f nvm node npm npx yarn pnpm corepack 2>/dev/null
      if [ -s "$NVM_DIR/nvm.sh" ]; then
        \. "$NVM_DIR/nvm.sh"
      fi
      "$@"
    }

    for cmd in nvm node npm npx yarn pnpm corepack; do
      $cmd() { _lazy_load_nvm ${0} "$@"; }
    done
fi

# ==============================================================================
# 9. 무거운 플러그인 수동 로드 & 커스텀 하이라이트 스타일
# ==============================================================================
# 바이트코드 바인딩 최적화 함수
_zsh_source_optimized() {
  local file="$1"
  if [[ -f "$file" ]]; then
    if [[ ! "$file.zwc" -nt "$file" ]]; then
      zcompile "$file" 2>/dev/null
    fi
    source "$file"
  fi
}

# (1) zsh-autosuggestions (자동완성 추천 스타일)
SUGGESTIONS_PATH="$ZSH/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh"
[[ ! -f "$SUGGESTIONS_PATH" ]] && SUGGESTIONS_PATH="$ZSH/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
_zsh_source_optimized "$SUGGESTIONS_PATH"
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=244'

# (2) fast-syntax-highlighting (컴파일 로더 & 상세 구문 색상 커스텀)
FSH_PATH="$ZSH/custom/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh"
if [[ -f "$FSH_PATH" ]]; then
  _zsh_source_optimized "$FSH_PATH"

  FAST_HIGHLIGHT[fast_cursor]=1
  FAST_HIGHLIGHT[use_brackets]=1

  FAST_HIGHLIGHT_STYLES[command]='fg=green,bold'
  FAST_HIGHLIGHT_STYLES[alias]='fg=green,bold'
  FAST_HIGHLIGHT_STYLES[path]='fg=yellow,bold'
  FAST_HIGHLIGHT_STYLES[path-prefix]='fg=yellow,bold'
  FAST_HIGHLIGHT_STYLES[path-underline]='none'
  FAST_HIGHLIGHT_STYLES[path-prefix-underline]='none'
  FAST_HIGHLIGHT_STYLES[single-hyphen-option]='fg=yellow'
  FAST_HIGHLIGHT_STYLES[double-hyphen-option]='fg=yellow'
  FAST_HIGHLIGHT_STYLES[single-quoted-argument]='fg=magenta'
  FAST_HIGHLIGHT_STYLES[double-quoted-argument]='fg=magenta'
  FAST_HIGHLIGHT_STYLES[unknown-token]='fg=red,bold,underline'
fi
