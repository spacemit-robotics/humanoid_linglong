#!/usr/bin/env bash
set -euo pipefail

ROBOT_NAME="humanoid_linglong"
BASE_URL="https://archive.spacemit.com/spacemit-ai/model_zoo/rl/${ROBOT_NAME}/"
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
if [[ -z "${SDK_ROOT:-}" ]]; then
  if [[ -f "$SCRIPT_DIR/../../../build/envsetup.sh" ]]; then
    SDK_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
  else
    SDK_ROOT=$(cd "$SCRIPT_DIR/../../../.." && pwd)
  fi
fi
POLICY_DIR="$SDK_ROOT/application/native/${ROBOT_NAME}/policy"
ARCHIVE_FILES=()

discover_files() {
  local relative_dir=$1
  local page href

  if ! page=$(wget -qO- --no-check-certificate "${BASE_URL}${relative_dir}"); then
    echo "[download_models] 无法读取目录：${BASE_URL}${relative_dir}" >&2
    return 1
  fi

  while IFS= read -r href; do
    case "$href" in
      ""|"./"|"../"|/*|\?*|\#*|*://*) continue ;;
    esac
    if [[ "$href" == */ ]]; then
      discover_files "${relative_dir}${href}" || return 1
    else
      ARCHIVE_FILES+=("${relative_dir}${href}")
    fi
  done < <(printf '%s\n' "$page" | grep -oE 'href="[^"]+"' | cut -d'"' -f2)
}

echo "[download_models] 从 SpacemiT 模型库拉取 ${ROBOT_NAME} 模型..."
if ! discover_files ""; then
  exit 1
fi
if ((${#ARCHIVE_FILES[@]} == 0)); then
  echo "[download_models] archive 中没有可下载文件：$BASE_URL" >&2
  exit 1
fi

echo "[download_models] 发现 ${#ARCHIVE_FILES[@]} 个文件"
mkdir -p "$POLICY_DIR"
downloaded=0
skipped=0
for file in "${ARCHIVE_FILES[@]}"; do
  target="$POLICY_DIR/$file"
  if [[ -s "$target" ]]; then
    ((skipped += 1))
    continue
  fi

  mkdir -p "$(dirname "$target")"
  echo "[download_models] 下载：$file"
  if ! wget -q --show-progress --progress=bar:force:noscroll \
      --no-check-certificate -O "$target.part" "${BASE_URL}${file}"; then
    rm -f "$target.part"
    echo "[download_models] 下载失败：${BASE_URL}${file}" >&2
    exit 1
  fi
  if [[ ! -s "$target.part" ]]; then
    rm -f "$target.part"
    echo "[download_models] 下载文件为空：${BASE_URL}${file}" >&2
    exit 1
  fi
  mv "$target.part" "$target"
  ((downloaded += 1))
done

echo "[download_models] 完成：共 ${#ARCHIVE_FILES[@]} 个文件（下载 $downloaded，已存在 $skipped），保存至 $POLICY_DIR"
