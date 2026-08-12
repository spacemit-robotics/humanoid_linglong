#!/bin/bash
# driver_runtime 按 linglong.yaml 的 driver.backend 选择 MuJoCo 或 whole_body。
# 当前配置默认 whole_body，启动后初始保持失能；离线仿真需显式切换为 mujoco。
SCRIPT_PATH=$(readlink -f "$0")
: "${SDK_ROOT:=$(cd "$(dirname "$SCRIPT_PATH")/../../.." && pwd)}"
CONFIG="$SDK_ROOT/application/native/humanoid_linglong/config/linglong.yaml"
DRIVER="$SDK_ROOT/output/staging/bin/driver_runtime"

if [[ ! -x "$DRIVER" ]]; then
    echo "[run_driver_linglong] driver_runtime 未找到，请先编译 humanoid_common。" >&2
    exit 1
fi

BACKEND=$(awk '
    /^driver:[[:space:]]*($|#)/ { in_driver = 1; next }
    in_driver && /^[^[:space:]#]/ { exit }
    in_driver && $1 == "backend:" { gsub(/[" ]/, "", $2); print $2; exit }
' "$CONFIG")

if [[ "$BACKEND" == "whole_body" ]]; then
    if [[ $EUID -ne 0 ]]; then
        if ! command -v sudo >/dev/null; then
            echo "[run_driver_linglong] whole_body 需要 root 访问 CAN 和 IMU，未找到 sudo。" >&2
            exit 1
        fi
        # root 访问硬件，同时保留调用用户组供 SHM 与 control/HMI 通信。
        exec sudo --user root --group "$(id -gn)" "$SCRIPT_PATH" "$@"
    fi
    if ! command -v flock >/dev/null; then
        echo "[run_driver_linglong] 缺少 flock，无法建立硬件独占锁。" >&2
        exit 1
    fi
    exec flock --exclusive --nonblock /tmp/linglong_hardware.lock "$DRIVER" "$CONFIG"
fi

exec "$DRIVER" "$CONFIG"
