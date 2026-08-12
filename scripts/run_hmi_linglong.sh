#!/bin/bash
: "${SDK_ROOT:=$(cd "$(dirname "$(readlink -f "$0")")/../../.." && pwd)}"
exec hmi_runtime "$SDK_ROOT/application/native/humanoid_linglong/config/linglong.yaml"
