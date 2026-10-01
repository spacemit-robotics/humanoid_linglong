#!/bin/bash
: "${SDK_ROOT:=$(cd "$(dirname "$(readlink -f "$0")")/../../.." && pwd)}"
CONFIG="${LINGLONG_CONFIG:-$SDK_ROOT/application/native/humanoid_linglong/config/linglong.yaml}"
exec "$SDK_ROOT/output/staging/bin/hmi_runtime" "$CONFIG" "$@"
