#!/bin/bash
# driver_runtime 按 linglong.yaml 的 driver.backend 选择 MuJoCo 或 whole_body。
SCRIPT_PATH=$(readlink -f "$0")
: "${SDK_ROOT:=$(cd "$(dirname "$SCRIPT_PATH")/../../.." && pwd)}"
CONFIG="${LINGLONG_CONFIG:-$SDK_ROOT/application/native/humanoid_linglong/config/linglong.yaml}"
DRIVER="$SDK_ROOT/output/staging/bin/driver_runtime"
DRIVER_ARGS=()
BACKEND_OVERRIDE=""
for ARG in "$@"; do
    if [[ -n "$BACKEND_OVERRIDE" ]]; then
        echo "Specify only one of --sim or --real" >&2
        exit 1
    fi
    case "$ARG" in
        --sim) BACKEND_OVERRIDE=mujoco ;;
        --real) BACKEND_OVERRIDE=whole_body ;;
        --help|-h)
            echo "Usage: run_driver_linglong.sh [--sim|--real]"
            exit 0 ;;
        *) echo "Unknown option: $ARG" >&2; exit 1 ;;
    esac
done
if [[ -n "$BACKEND_OVERRIDE" ]]; then
    DRIVER_ARGS=(--backend "$BACKEND_OVERRIDE")
fi

if [[ ! -x "$DRIVER" ]]; then
    echo "[run_driver_linglong] driver_runtime 未找到，请先编译 humanoid_common。" >&2
    exit 1
fi

BACKEND=$(awk '
    /^driver:[[:space:]]*($|#)/ { in_driver = 1; next }
    in_driver && /^[^[:space:]#]/ { exit }
    in_driver && $1 == "backend:" { gsub(/[" ]/, "", $2); print $2; exit }
' "$CONFIG")
BACKEND="${BACKEND_OVERRIDE:-$BACKEND}"

if [[ "$BACKEND" == "whole_body" ]]; then
    if [[ $EUID -ne 0 ]]; then
        if ! command -v sudo >/dev/null; then
            echo "[run_driver_linglong] whole_body 需要 root 访问 CAN 和 IMU，未找到 sudo。" >&2
            exit 1
        fi
        # root 访问硬件，同时保留调用用户组供 SHM 与 control/HMI 通信。
        exec sudo --user root --group "$(id -gn)" env \
            SDK_ROOT="$SDK_ROOT" LINGLONG_CONFIG="$CONFIG" "$SCRIPT_PATH" "$@"
    fi
    if ! command -v flock >/dev/null; then
        echo "[run_driver_linglong] 缺少 flock，无法建立硬件独占锁。" >&2
        exit 1
    fi
    exec flock --exclusive --nonblock --no-fork /tmp/linglong_hardware.lock \
        "$DRIVER" "$CONFIG" "${DRIVER_ARGS[@]}"
fi

exec "$DRIVER" "$CONFIG" "${DRIVER_ARGS[@]}"
