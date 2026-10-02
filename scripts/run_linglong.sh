#!/bin/bash
# Copyright (C) 2026 SpacemiT (Hangzhou) Technology Co. Ltd.
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

usage() {
    echo "Usage: run_linglong.sh --sim [--no-tui]"
    echo "       run_linglong.sh --real [--profile full|static] [--tui] [--listen ADDRESS] [--public-url URL]"
    echo "       run_linglong.sh --real --service-user USER (root, system service)"
}

MODE="${1:-}"
case "$MODE" in
    --sim) TUI=yes ;;
    --real) TUI=no ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
esac
shift
HMI_ARGS=("$MODE")
SERVICE_USER=""
PROFILE=""
while (($#)); do
    case "$1" in
        --tui) TUI=yes; shift ;;
        --no-tui) TUI=no; shift ;;
        --profile)
            [[ "$MODE" == --real && $# -ge 2 ]] || { usage >&2; exit 1; }
            [[ "$2" == full || "$2" == static ]] || { usage >&2; exit 1; }
            PROFILE="$2"; shift 2 ;;
        --service-user)
            [[ $# -ge 2 ]] || { usage >&2; exit 1; }
            SERVICE_USER="$2"; shift 2 ;;
        --listen|--public-url)
            if [[ "$MODE" != --real || $# -lt 2 ]]; then
                echo "网络入口只用于 --real 实机模式。" >&2
                exit 1
            fi
            HMI_ARGS+=("$1" "$2"); shift 2 ;;
        *) usage >&2; exit 1 ;;
    esac
done

if [[ -z "${SDK_ROOT:-}" ]]; then
    SDK_ROOT=$(dirname "$(readlink -f "$0")")
    while [[ "$SDK_ROOT" != / && ! -f "$SDK_ROOT/build/envsetup.sh" ]]; do
        SDK_ROOT=$(dirname "$SDK_ROOT")
    done
fi
export SDK_ROOT
BIN="$SDK_ROOT/output/staging/bin"
CONFIG="${LINGLONG_CONFIG:-$SDK_ROOT/application/native/humanoid_linglong/config/linglong.yaml}"
if [[ -n "$PROFILE" ]]; then
    CONFIG="$SDK_ROOT/application/native/humanoid_linglong/config/linglong.yaml"
    [[ "$PROFILE" != static ]] || CONFIG="${CONFIG%.yaml}_static.yaml"
fi
export LINGLONG_CONFIG="$CONFIG"
export PATH="$BIN:$PATH"
AS_OPERATOR=()
if [[ -n "$SERVICE_USER" ]]; then
    if [[ "$MODE" != --real || $EUID -ne 0 || "$TUI" == yes ]] ||
        ! id "$SERVICE_USER" >/dev/null 2>&1 || [[ "$(id -u "$SERVICE_USER")" == 0 ]]; then
        echo "--service-user 仅供 root 实机服务使用，须指定普通用户且不能带 --tui。" >&2
        exit 1
    fi
    HOME=$(getent passwd "$SERVICE_USER" | cut -d: -f6)
    export HOME XDG_STATE_HOME="$HOME/.local/state"
    AS_OPERATOR=(runuser --user "$SERVICE_USER" --)
fi
for NAME in driver control hmi; do
    if [[ ! -x "$BIN/run_${NAME}_linglong.sh" || ! -x "$BIN/${NAME}_runtime" ]]; then
        echo "缺少 $NAME 程序，请先编译 humanoid_common 和 humanoid_linglong。" >&2
        exit 1
    fi
done
if [[ ! -x "$BIN/hmi_tui" ]]; then
    echo "缺少 hmi_tui，请先编译 humanoid_common。" >&2
    exit 1
fi
if [[ "$TUI" == yes && ( ! -t 0 || ! -t 1 ) ]]; then
    echo "TUI 需要交互终端；只启动三个核心进程请加 --no-tui。" >&2
    exit 1
fi

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/humanoid-operator/linglong"
CONNECTION="${OPERATOR_CONNECTION:-$STATE/connection.json}"
umask 077
"${AS_OPERATOR[@]}" mkdir -p -m 0700 "$STATE"
"${AS_OPERATOR[@]}" touch "$STATE/launch.lock"
exec 9<"$STATE/launch.lock"
if ! flock -n 9; then
    echo "灵龙启动脚本已在运行，请先退出上一套进程。" >&2
    exit 1
fi
for PID in $(pgrep -x 'driver_main|control_main|hmi_runtime' || true); do
    [[ -r "/proc/$PID/cmdline" ]] || continue
    mapfile -d '' -t PROCESS <"/proc/$PID/cmdline"
    PROCESS_CONFIG="${PROCESS[1]:-}"
    if [[ "$PROCESS_CONFIG" == "$CONFIG" || "$PROCESS_CONFIG" == *humanoid_linglong/* ||
        "${PROCESS_CONFIG##*/}" == linglong*.yaml ]]; then
        echo "已有灵龙核心进程 $PID 运行，请先正常退出；本脚本不会终止已有进程。" >&2
        exit 1
    fi
done
LOG_ROOT=$(python3 -c '
import pathlib
import sys
import yaml

try:
    config = pathlib.Path(sys.argv[1]).absolute()
    with config.open(encoding="utf-8") as source:
        settings = yaml.safe_load(source)
    directory = settings.get("logging", {}).get("directory", "log/humanoid")
    if not isinstance(directory, str) or not directory.strip():
        raise ValueError("logging.directory must be a non-empty path")
    print((config.parent / directory).resolve())
except (OSError, ValueError, AttributeError, yaml.YAMLError) as error:
    sys.exit(f"Cannot resolve logging.directory: {error}")
' "$CONFIG")
if ! "${AS_OPERATOR[@]}" mkdir -p "$LOG_ROOT" ||
    ! "${AS_OPERATOR[@]}" test -w "$LOG_ROOT" || ! "${AS_OPERATOR[@]}" test -x "$LOG_ROOT"; then
    echo "日志目录不可写：$LOG_ROOT；请检查 logging.directory 及其用户组权限。" >&2
    exit 1
fi
if [[ "$MODE" == --real && $EUID -ne 0 ]]; then
    echo "实机 driver 需要硬件权限；如有密码提示，请在当前终端输入。"
    sudo --user root --group "$(id -gn)" --validate
fi

LOG_DIR=$("${AS_OPERATOR[@]}" mktemp -d "$LOG_ROOT/linglong_launch_$(date +%Y%m%d_%H%M%S)_XXXXXXXX")
"${AS_OPERATOR[@]}" touch "$LOG_DIR/driver.log" "$LOG_DIR/control.log" "$LOG_DIR/hmi.log"
PIDS=()
NAMES=()
TUI_PID=""
SUDO_PID=""
signal_children() {
    local PID
    for PID in $(jobs -pr); do
        if [[ "$PID" == "$SUDO_PID" ]]; then
            # Let sudo stop its privileged child; killing the monitor can orphan it.
            local SIGNAL="$1"
            [[ "$SIGNAL" != KILL ]] || SIGNAL=ALRM
            kill -s "$SIGNAL" "$PID" 2>/dev/null || true
        elif [[ "$PID" == "$TUI_PID" ]]; then
            kill -s "$1" "$PID" 2>/dev/null || true
        else
            kill -s "$1" -- "-$PID" 2>/dev/null || true
        fi
    done
}
cleanup() {
    trap '' INT TERM HUP
    local SIGNAL ATTEMPT
    for SIGNAL in INT TERM; do
        signal_children "$SIGNAL"
        for ((ATTEMPT=0; ATTEMPT<30; ATTEMPT++)); do
            [[ -n "$(jobs -pr)" ]] || break
            sleep 0.1
        done
    done
    if [[ -n "$(jobs -pr)" ]]; then
        echo "本次进程停止超时，强制清理；日志：$LOG_DIR" >&2
        signal_children KILL
    fi
    wait 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
start() {
    local NAME="$1"
    shift
    if [[ "$NAME" == driver && "$MODE" == --real && $EUID -ne 0 ]]; then
        # Keep the authentication session but put sudo outside the foreground
        # process group so its terminal monitor cannot consume TUI input.
        set -m
        # The invoking user owns the capture files, not root.
        # shellcheck disable=SC2024
        sudo --non-interactive --user root --group "$(id -gn)" env \
            SDK_ROOT="$SDK_ROOT" LINGLONG_CONFIG="$CONFIG" "$@" \
            9>&- </dev/null >"$LOG_DIR/$NAME.log" 2>&1 &
        SUDO_PID=$!
        set +m
    elif [[ "$NAME" == driver ]]; then
        setsid "$@" 9>&- </dev/null >"$LOG_DIR/$NAME.log" 2>&1 &
    else
        setsid "${AS_OPERATOR[@]}" "$@" 9>&- </dev/null >"$LOG_DIR/$NAME.log" 2>&1 &
    fi
    PIDS+=("$!")
    NAMES+=("$NAME")
}
check_children() {
    local INDEX
    for INDEX in "${!PIDS[@]}"; do
        if ! kill -0 "${PIDS[$INDEX]}" 2>/dev/null; then
            echo "${NAMES[$INDEX]} 已退出，日志：$LOG_DIR/${NAMES[$INDEX]}.log" >&2
            tail -n 15 "$LOG_DIR/${NAMES[$INDEX]}.log" >&2
            exit 1
        fi
    done
}

echo "启动灵龙 ${MODE#--}；日志：$LOG_DIR"
[[ "$PROFILE" != static ]] || echo "固定底座展示：仅双臂 14 关节，无腿部/头部控制，无 IMU 或 RL。"
start driver "$BIN/run_driver_linglong.sh" "$MODE"
start control "$BIN/run_control_linglong.sh"
start hmi "$BIN/run_hmi_linglong.sh" "${HMI_ARGS[@]}"
DEADLINE=$((SECONDS + 60))
while :; do
    check_children
    STATUS=$("${AS_OPERATOR[@]}" "$BIN/hmi_tui" --connection "$CONNECTION" --status 2>/dev/null || true)
    if [[ "$STATUS" == *"online=1"* ]]; then break; fi
    if ((SECONDS >= DEADLINE)); then
        echo "启动超时，HMI 与 control 尚未连通。日志：$LOG_DIR" >&2
        exit 1
    fi
    sleep 0.2
done
echo "三个核心进程已启动，HMI 与 control 已连通；不会自动上电。"
if [[ "$MODE" == --real ]]; then
    sed -n '/^\[hmi\]/p' "$LOG_DIR/hmi.log"
fi
echo "Ctrl+C 退出本次启动的全部进程。"
if [[ "$TUI" == yes ]]; then
    "$BIN/hmi_tui" --connection "$CONNECTION" 9>&- <&0 &
    TUI_PID=$!
    while kill -0 "$TUI_PID" 2>/dev/null; do
        check_children
        sleep 0.2
    done
    wait "$TUI_PID"
else
    while :; do check_children; sleep 0.5; done
fi
