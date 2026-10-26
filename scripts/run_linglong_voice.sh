#!/usr/bin/env bash
#
# Copyright (C) 2026 SpacemiT (Hangzhou) Technology Co. Ltd.
# SPDX-License-Identifier: Apache-2.0
#
# 灵龙控制台的语音模式，在机器人上以运行 linglong 服务的普通用户执行，不需要 sudo。直接从 SDK 目录运行：
# 程序、网页和配置取安装目录 output/staging，运行时文件写 output/linglong_voice。
#   run_linglong_voice.sh start [--silent] [--port N]   起语音服务（--silent 不出声；--port 换 HTTPS 端口，跳转端口用 N-1）
#   run_linglong_voice.sh stop | status | logs | url
#   run_linglong_voice.sh qr                            生成贴在机器人上的二维码（控制台 HTTPS 版 + 配对令牌，就是控制钥匙）
#   run_linglong_voice.sh autostart-on | autostart-off  开机自启（systemd 用户服务 linglong-voice + linger）
# 需要：~/.config/omni_agent/llm.json（api_base、api_key、model_name、extra_body，omni_agent 的大模型配置）、
# ~/.config/linglong_voice/tls/{fullchain.pem,key.pem}（<主机名>.spacemit-interaction.cc 的证书）、apt 装的 espeak-ng。
set -euo pipefail

script="$(readlink -f "${BASH_SOURCE[0]}")"
sdk="${SDK_ROOT:-$(dirname "${script}")}"
while [[ "${sdk}" != / && ! -f "${sdk}/build/envsetup.sh" ]]; do
  sdk="$(dirname "${sdk}")"
done
[[ -f "${sdk}/build/envsetup.sh" ]] || { echo "找不到 SDK，请设置 SDK_ROOT。" >&2; exit 1; }
staging="${STAGING_PREFIX:-${PREFIX:-${sdk}/output/staging}}"
templates="${staging}/share/humanoid_linglong"
voice_web="${staging}/share/humanoid_common/operator_web/voice/ptt_server.py"
state="$(dirname "${staging}")/linglong_voice"
run="${state}/run"
logs="${state}/logs"
config="${XDG_CONFIG_HOME:-${HOME}/.config}"
llm_json="${config}/omni_agent/llm.json"
tls_cert="${config}/linglong_voice/tls/fullchain.pem"
tls_key="${config}/linglong_voice/tls/key.pem"
connection="${XDG_STATE_HOME:-${HOME}/.local/state}/humanoid-operator/linglong/connection.json"
lan_host="$(hostname).spacemit-interaction.cc"
pid_file="${run}/voice.pid"
mode_file="${run}/voice.mode"
url_file="${run}/voice.url"
unit=linglong-voice.service
speaker_volume=80  # 扬声器音量，使用 alsamixer 的 PCM 显示刻度（amixer -M）。
unit_file="${config}/systemd/user/${unit}"

usage() { sed -n '6,14p' "$0"; }

running() { [[ -f "${pid_file}" ]] && kill -0 "$(cat "${pid_file}")" 2>/dev/null; }
unit_active() { systemctl --user is-active --quiet "${unit}" 2>/dev/null; }
autostart_enabled() { [[ -f "${unit_file}" ]] && systemctl --user is-enabled --quiet "${unit}" 2>/dev/null; }

# 按组停止 setsid 启动的进程及其子进程，只处理本次安装目录下的程序。
ours() { [[ -n "$1" ]] && pgrep -g "$1" -f "${staging}/" > /dev/null; }

stop_group() {
  local pid
  pid="$(cat "${pid_file}" 2>/dev/null || true)"
  if ours "${pid}"; then
    kill -TERM -- "-${pid}" 2>/dev/null || true
    for _ in $(seq 1 100); do ours "${pid}" || break; sleep 0.1; done
    if ours "${pid}"; then
      echo "10 s 内没退完，强制结束进程组 ${pid}" >&2
      kill -KILL -- "-${pid}" 2>/dev/null || true
    fi
  fi
  rm -f "${pid_file}" "${mode_file}" "${url_file}"
}

url() { cat "${url_file}" 2>/dev/null || echo "https://${lan_host}:8443/"; }

# 打印出来贴在机器人上：扫码直接进控制台的 HTTPS 版（有语音）。令牌和灵龙原来的二维码是同一个，重新配对后要重印。
qr() {
  local out="${run}/console_qr.png"
  [[ -f "${connection}" ]] || { echo "找不到操作服务连接文件 ${connection}，linglong 服务没在运行？" >&2; exit 1; }
  mkdir -p "${run}"
  (umask 077 && python3 -c 'import json, sys; c = json.load(open(sys.argv[1])); print(sys.argv[2] + "#token=" + c.get("public_token", c["token"]), end="")' \
    "${connection}" "https://${lan_host}:8443/" | qrencode -s 12 -m 2 -o "${out}")
  echo "${out}（语音访问二维码；手动控制仍需管理员登录）"
}

fail() { echo "$*" >&2; exit 1; }

# 日志追加写，重启前的记录留着排查；超过上限时上一份改名为 .1（只留一份）
rotate_logs() {
  local f limit
  mkdir -p "${logs}"
  for f in voice.log:5 chat.log:20; do
    limit=$(( ${f#*:} * 1024 * 1024 ))
    f="${logs}/${f%%:*}"
    if [[ -f "${f}" && $(stat -c %s "${f}") -gt ${limit} ]]; then mv -f "${f}" "${f}.1"; fi
  done
}

# 把扬声器 PCM 音量设成 speaker_volume。ptt_chat 直接打开 ALSA 声卡，只受这个硬件音量影响；开机时 WirePlumber 会按它
# 记住的值（没记过是 40%，alsamixer 显示 34）改一次，所以等 ptt_chat 就绪、占住声卡后再设，WirePlumber 也会记下这个值。
set_volume() {
  local card
  card="$(awk -v d="${device}" 'index($0, d) { print $1; exit }' /proc/asound/cards)"
  if [[ -n "${card}" ]] && amixer -q -c "${card}" -M sset PCM "${speaker_volume}%" 2>/dev/null; then
    echo "$(date +%T) 扬声器音量 ${speaker_volume}（$(amixer -c "${card}" sget PCM | grep -o '\[-\?[0-9.]*dB\]' | head -1)）"
  else
    echo "$(date +%T) 扬声器音量没设上（声卡「${device}」${card:+ card ${card}}），保持原样"
  fi
}

# 本次启动从 voice.log 的哪个位置开始写（就绪判断只看这之后的内容）
log_mark() { stat -c %s "${logs}/voice.log" 2>/dev/null || echo 0; }
log_header() { echo "==== $(date "+%F %T") 启动${*:+ $*} ===="; }

# 解析参数、检查依赖、生成运行时文件，设好 device / address / server（完整命令行）；start 和 run 共用
prepare() {
  device="SPV Composite"
  local port=8443
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --silent) device=none; shift ;;
      --port) port="$2"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done
  local redirect_port=$((port - 1)) f
  [[ -f "${connection}" ]] || fail "找不到操作服务连接文件 ${connection}，linglong 服务没在运行？"
  for f in "${staging}/bin/ptt_chat" "${staging}/bin/humanoid_operator_mcp"; do
    [[ -x "${f}" ]] || fail "缺少 ${f}：先编译 omni_agent、humanoid_common 和 humanoid_linglong"
  done
  for f in "${voice_web}" "${templates}/linglong_voice.json.in" "${staging}/share/omni_agent/info_mcp.py"; do
    [[ -f "${f}" ]] || fail "缺少 ${f}：请重新安装对应仓库的构建产物"
  done
  for f in "${llm_json}" "${tls_cert}" "${tls_key}"; do
    [[ -f "${f}" ]] || fail "缺少 ${f}（见本仓库 README）"
  done
  command -v espeak-ng > /dev/null || fail "缺少 espeak-ng（语音合成念英文要用）：sudo apt install espeak-ng"
  for f in "${port}" "${redirect_port}"; do
    if ss -Hltn "sport = :${f}" | grep -q .; then fail "端口 ${f} 已被占用（语音服务已在运行？）"; fi
  done
  address="https://${lan_host}:${port}/"
  mkdir -p "${run}" "${logs}"

  # 大模型：omni_agent 的 llm.json；密钥经环境变量传给 ptt_chat，不出现在命令行
  local llm
  llm="$(python3 - "${llm_json}" <<'EOF'
import json, sys
c = json.load(open(sys.argv[1]))
missing = [k for k in ("api_base", "api_key", "model_name") if not c.get(k)]
if missing:
    sys.exit(f"{sys.argv[1]} 缺少 {', '.join(missing)}")
print(c["api_base"]); print(c["model_name"]); print(json.dumps(c.get("extra_body") or {}))
EOF
)" || exit 1
  local api_base model extra_body
  { read -r api_base; read -r model; read -r extra_body; } <<< "${llm}"
  OPENAI_API_KEY="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["api_key"])' "${llm_json}")"
  export OPENAI_API_KEY

  python3 - "${templates}/linglong_voice.json.in" "${run}/mcp.json" "${staging}" <<'EOF'
import json, sys
from pathlib import Path

config = json.loads(Path(sys.argv[1]).read_text())
for server in config["servers"]:
    server["command"] = server["command"].replace("@PREFIX@", sys.argv[3])
    server["args"] = [arg.replace("@PREFIX@", sys.argv[3]) for arg in server.get("args", [])]
Path(sys.argv[2]).write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n")
EOF
  # 语音面板上列的动作就是交给 MCP 的那份 --actions，不另外维护
  local actions
  actions="$(python3 - "${run}/mcp.json" <<'EOF'
import json, sys
for server in json.load(open(sys.argv[1]))["servers"]:
    args = server.get("args", [])
    if "--actions" in args[:-1]:
        print(args[args.index("--actions") + 1])
        break
EOF
)"

  # 控制台就是操作服务，地址取连接文件里的（监听 0.0.0.0 时写的是 127.0.0.1）
  local console
  console="$(python3 -c 'import json, sys, urllib.parse as u; e = u.urlsplit(json.load(open(sys.argv[1]))["endpoint"]); print(f"{e.hostname}:{e.port}")' "${connection}")"
  # 空闲 5 分钟清空对话记忆：展会上换了一拨人，不接着上一拨的话题聊
  server=(python3 "${voice_web}"
    --listen "[::]:${port}" --tls-cert "${tls_cert}" --tls-key "${tls_key}"
    --console "${console}" --operator-connection "${connection}"
    --redirect-listen "[::]:${redirect_port}" --redirect-to "${address}" --upload-dir "${run}/uploads"
    --chat-log "${logs}/chat.log" --actions "${actions}" --idle-reset 300 --
    "${staging}/bin/ptt_chat" --llm-url "${api_base}" --model "${model}" --llm-extra-body "${extra_body}"
    --mcp-config "${run}/mcp.json" -o "${device}" --playback-rate 16000 --playback-channels 2)
}

# ptt_chat 要连得上大模型、打得开扬声器才算就绪（连不上时 ptt_server 隔 15 s 重启它，控制台照常可用）。
# 参数：扬声器名、本次启动的日志起点（log_mark），后面是判断还活着的命令。
wait_ready() {
  local device="$1" mark="$2"
  shift 2
  echo "启动中（扬声器: ${device}），模型加载约 20 s ..."
  for _ in $(seq 1 120); do
    if tail -c +$((mark + 1)) "${logs}/voice.log" 2>/dev/null | grep -F "ptt_chat 就绪" > /dev/null; then  # 不用 -q：提前退出时 tail 收到 SIGPIPE，pipefail 下算失败
      echo "就绪：$(url)"
      return
    fi
    if ! "$@"; then
      echo "启动失败，${logs}/voice.log 和 chat.log 最后几行：" >&2
      tail -n 3 "${logs}/voice.log" >&2
      tail -n 4 "${logs}/chat.log" >&2 2>/dev/null || true
      return 1
    fi
    sleep 0.5
  done
  echo "60 s 还没就绪，${logs}/voice.log 最后几行：" >&2
  tail -n 3 "${logs}/voice.log" >&2
  return 1
}

start() {
  if autostart_enabled; then
    [[ $# -eq 0 ]] || fail "开机自启开着，只能按默认方式启动；要用 $* 先 $0 autostart-off"
    if unit_active; then echo "已在运行（systemd 管理）"; return; fi
    local mark
    mark="$(log_mark)"
    systemctl --user start "${unit}"
    wait_ready "SPV Composite" "${mark}" unit_active || fail "还没就绪，会自己重试，$0 logs 看进度，$0 stop 停止"
    return
  fi
  if running; then
    echo "已在运行（扬声器: $(cat "${mode_file}" 2>/dev/null || echo 未知)），要换方式先 $0 stop"
    return
  fi
  rotate_logs
  prepare "$@"
  local mark
  mark="$(log_mark)"
  log_header "$@" >> "${logs}/voice.log"
  nohup setsid "${server[@]}" >> "${logs}/voice.log" 2>&1 < /dev/null &
  echo $! > "${pid_file}"
  echo "${device}" > "${mode_file}"
  echo "${address}" > "${url_file}"
  wait_ready "${device}" "${mark}" running || { stop_group; exit 1; }
  [[ "${device}" == none ]] || set_volume | tee -a "${logs}/voice.log"
}

# systemd 用的前台模式：等扬声器插上再起；启动失败（例如灵龙服务还没起来）由 systemd 15 s 后重启
run_foreground() {
  rotate_logs
  local mark
  mark="$(log_mark)"
  exec >> "${logs}/voice.log" 2>&1 < /dev/null
  log_header "(systemd)" "$@"
  prepare "$@"
  if [[ "${device}" != none ]] && ! grep -qF "${device}" /proc/asound/cards; then
    echo "$(date +%T) 等待扬声器「${device}」插上"
    until grep -qF "${device}" /proc/asound/cards; do sleep 5; done
  fi
  echo $$ > "${pid_file}"
  echo "${device}" > "${mode_file}"
  echo "${address}" > "${url_file}"
  if [[ "${device}" != none ]]; then  # 等 ptt_chat 第一次就绪后设音量（没网时可能要等很久；服务停止时随之结束）
    ( (until tail -c +$((mark + 1)) "${logs}/voice.log" | grep -F "ptt_chat 就绪" > /dev/null; do sleep 2; done
       set_volume) & )  # 两层括号：交给 systemd 回收，不在 ptt_server 下留僵尸进程
  fi
  exec "${server[@]}"
}

stop() {
  # 装了 systemd 服务就先让 systemd 停（也取消失败后等着的重启），否则它会再拉起来
  if [[ -f "${unit_file}" ]]; then
    systemctl --user stop "${unit}" 2>/dev/null || true
    if autostart_enabled; then echo "已停止；开机自启还开着，下次开机会自动启动"; fi
  fi
  stop_group
}

autostart_on() {
  # linger：开机不用登录就启动这个用户的 systemd 服务
  if [[ "$(loginctl show-user "${USER}" -p Linger --value 2>/dev/null)" != yes ]] && ! loginctl enable-linger; then
    fail "开不了 linger，请管理员执行 sudo loginctl enable-linger ${USER}"
  fi
  mkdir -p "$(dirname "${unit_file}")" "${logs}"
  sed -e "s#@SDK@#${sdk}#g" -e "s#@SCRIPT@#${script}#g" -e "s#@PREFIX@#${staging}#g" \
    "${templates}/linglong-voice.service.in" > "${unit_file}"
  systemctl --user daemon-reload
  unit_active || stop_group  # 手动起的先停掉，换成 systemd 管
  systemctl --user enable "${unit}"
  local mark
  mark="$(log_mark)"
  systemctl --user restart "${unit}"
  wait_ready "SPV Composite" "${mark}" unit_active || fail "还没就绪，会自己重试，$0 logs 看进度"
  echo "已开开机自启（${unit_file}）"
}

autostart_off() {
  if [[ -f "${unit_file}" ]]; then
    systemctl --user disable --now "${unit}" 2>/dev/null || true
    rm -f "${unit_file}"
    systemctl --user daemon-reload
  fi
  stop_group
  echo "已关开机自启并停止服务（linger 保留，不需要了可 loginctl disable-linger）"
}

case "${1:-}" in
  --help|-h) usage ;;
  start) shift; start "$@" ;;
  run) shift; run_foreground "$@" ;;
  stop) stop ;;
  status)
    if running; then
      echo "语音服务: 运行中（扬声器: $(cat "${mode_file}" 2>/dev/null || echo 未知)，$(url)）"
    else
      echo "语音服务: 未运行"
    fi
    if autostart_enabled; then
      echo "开机自启: 开（systemd: $(systemctl --user is-active "${unit}" 2>/dev/null || true)）"
    else
      echo "开机自启: 关"
    fi ;;
  logs) tail -f "${logs}/voice.log" ;;
  url) url ;;
  qr) qr ;;
  autostart-on) autostart_on ;;
  autostart-off) autostart_off ;;
  *) usage; exit 2 ;;
esac
