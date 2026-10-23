# 灵龙网页语音部署

手机扫码进入 HTTPS 页面，按住说话；K3 本地运行 ASR 和 TTS，对话模型按本机
`llm.json` 调用云端 API。动作通过 common 的 MCP 客户端进入 HMI，和 TUI、网页、App
共用控制权与动作接口，不直接操作电机或共享内存。

| 所属仓库 | 内容 |
| --- | --- |
| humanoid_linglong | 人设、动作白名单、声卡、启动脚本和用户服务 |
| humanoid_common | Web 语音面板、HTTPS 适配、MCP 操作客户端 |
| omni_agent | `ptt_chat` 语音引擎、时间和天气工具 |
| llm | 通用模型请求及流式响应 |

## 准备

按 omni_agent 的说明构建语音依赖并准备模型，再分别编译 omni_agent、humanoid_common、
humanoid_linglong。三个仓库必须安装到同一 `PREFIX`；不再单独构建 humanoid_operator_mcp 仓库。
构建灵龙或 common 本身不会自动安装语音依赖。

运行用户需准备以下文件，密钥和证书不入库：

- `~/.config/omni_agent/llm.json`：`api_base`、`api_key`、`model_name`，可选 `extra_body`。
- `~/.config/linglong_voice/tls/fullchain.pem` 和 `key.pem`：匹配
  `<主机名>.spacemit-interaction.cc` 且受手机信任的证书。
- 机器人内网 DNS 将该域名解析到 K3；手机先连接机器人 Wi-Fi。
- 系统需提供 `espeak-ng`、`amixer`，生成二维码还需 `qrencode`。

HMI 和语音以同一普通用户运行，读取
`~/.local/state/humanoid-operator/linglong/connection.json`。
先确认运控服务状态与展示环境安全；语音服务不会替代 full/static 服务的准备流程。
静态模式自动准备可能使双臂运动，启动前必须固定底座并清空运动范围。

## 启停

在 SDK 根目录执行：

```bash
source build/envsetup.sh
run_linglong_voice.sh start
run_linglong_voice.sh status
run_linglong_voice.sh qr
```

默认扬声器为 `SPV Composite`，就绪后将 PCM 音量设为 alsamixer 刻度 80。
`start --silent` 不播放声音，但仍会连接对话模型和动作工具，不是无硬件测试模式。
默认 HTTPS 端口 8443、HTTP 跳转端口 8442；YAML 的 `operator_service.voice_chat_port`
须与跳转端口一致。`start --port N` 使用 N 和 N-1，仅适合手动调试。

```bash
run_linglong_voice.sh logs
run_linglong_voice.sh stop
run_linglong_voice.sh autostart-on
systemctl --user status linglong-voice.service --no-pager
run_linglong_voice.sh autostart-off
```

`autostart-on` 安装并立即启动用户服务，启用 linger 后无需登录即可开机启动。
它与 `linglong@full.service` / `linglong@static.service` 分开管理；语音启动失败后每 15 秒重试。
更换脚本安装路径后需重新执行一次 `autostart-on`，旧服务不会自动改用新脚本。
普通 `stop` 不关闭下次开机自启，`autostart-off` 才关闭。

## 配置与记录

修改 `config/linglong_voice.json.in` 可调整人设、动作清单和默认天气城市；修改后重新 `mm`，
再重启语音服务。允许动作仍须存在于 HMI 当前策略/固定底座动作目录，MCP 不负责切换 FSM 或策略。
有其他客户端持有控制权时不抢占；取消动作走公共取消接口，不直接失能。

安装后的模板位于 `share/humanoid_linglong/`；启动时生成
`output/linglong_voice/run/mcp.json`，二维码在同目录 `console_qr.png`。
二维码只含公开语音配对凭据，手动控制仍需网页管理员验证。

语音日志在 `output/linglong_voice/logs/voice.log` 和 `chat.log`，重启后追加；
启动时分别超过 5 MiB / 20 MiB 才轮换一份 `.1`，不是运行中的硬容量上限。
控制、driver 和 CSV 日志仍由机型 YAML 的 `logging.directory` 管理。
使用独立 `STAGING_PREFIX` / `PREFIX` 时，语音运行目录随该 prefix 放在其上一级目录，
避免与主 SDK 输出混用。
