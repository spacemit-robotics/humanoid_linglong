# humanoid_linglong — 灵龙

## 项目简介

灵龙 L1 V1.4 人形机器人应用包，28 自由度（左腿 6 + 右腿 6 + 头部 2 + 左臂 7 + 右臂 7）。包含该机型专属的 YAML 配置、MuJoCo 仿真资源、RL 策略模型及启动脚本，通用控制逻辑见 `humanoid_common` 仓库。

## 功能特性

支持：
- FSM 完整流程（driver + control + hmi 三进程）
- MuJoCo 仿真与 `whole_body` 实机后端切换
- PC 单机仿真（SHM 或 UDP 本机通信）
- sim2sim 跨机推理（PC 仿真 + K3 板卡 RL 推理）
- K3 板卡实机控制（28 轴电机、并联脚踝和 Forsense IMU）
- 多套步行与动作跟踪策略；可选策略以 `config/linglong.yaml` 中的 `policy_names` 为准
- 仿真使用终端 TUI；实机另支持 Android App 和手机扫码网页，统一经过 HMI 服务接入

不支持：
- 在线训练或策略更新
- 通过当前 28 自由度控制链路驱动手部末端执行器

## 快速开始

### 环境准备

**PC 端（x86_64）**：

```bash
# 系统依赖
sudo apt install -y libeigen3-dev libyaml-cpp-dev libboost-dev nlohmann-json3-dev libglfw3-dev cmake g++ python3-yaml

# MuJoCo 3.4.0
mkdir -p ~/.mujoco
wget https://github.com/google-deepmind/mujoco/releases/download/3.4.0/mujoco-3.4.0-linux-x86_64.tar.gz
tar -xzf mujoco-3.4.0-linux-x86_64.tar.gz -C ~/.mujoco/

# ONNX Runtime 1.21.0（仅需 x86_64 本机 RL 推理时安装）
wget https://github.com/microsoft/onnxruntime/releases/download/v1.21.0/onnxruntime-linux-x64-1.21.0.tgz
tar -xzf onnxruntime-linux-x64-1.21.0.tgz
sudo cp -r onnxruntime-linux-x64-1.21.0/include/* /usr/local/include/
sudo cp -r onnxruntime-linux-x64-1.21.0/lib/* /usr/local/lib/
sudo ldconfig
```

**K3 板卡端**：

```bash
# 系统依赖
sudo apt install -y libeigen3-dev libyaml-cpp-dev libboost-dev nlohmann-json3-dev spacemit-tcm pkg-config python3-yaml

# SpacemiT 定制版 ONNX Runtime（含 A100 核 EP 加速）
sudo apt remove libonnxruntime-dev libonnxruntime1.23 python3-onnxruntime
sudo apt install -y libonnx-dev libonnx-testdata libonnx1t64 \
  libonnxruntime-providers onnxruntime-tools python3-onnx \
  python3-spacemit-ort spacemit-onnxruntime
```

### 构建编译

本仓库只包含机型配置、资源和启动脚本，需在 spacemit_robot SDK 内构建：

```bash
source build/envsetup.sh
lunch k3-com260-kit-humanoid-linglong
m
```

### 模型下载

```bash
download_models_linglong.sh
```

### 运行示例

同一份 `config/linglong.yaml` 支持仿真与实机。一键脚本通过 `--sim` / `--real` 同时选择
driver 后端与 HMI 接入模式，不改 YAML、不自动上电。

```bash
run_linglong.sh --sim    # 三个核心进程和原终端 TUI；不提供网页、App 或二维码
```

脚本在当前终端看护进程；Ctrl+C 一起退出。已有核心进程时拒绝重复启动，不终止其他
进程。三个进程的标准输出和错误输出保存在 YAML 的 `logging.directory` 下的
`linglong_launch_*/driver.log`、`control.log`、`hmi.log`；默认根目录为 SDK 的
`log/humanoid/`，与原 `events.log`、CSV 日志统一存放。原运行日志的会话目录不变。
仅启动核心进程可加 `--no-tui`，再单独执行 `run_hmi_tui_linglong.sh`。

**FSM 完整仿真（三个核心进程，另开终端客户端）**：

```bash
run_driver_linglong.sh --sim # 终端1（PC，x86_64）
run_control_linglong.sh   # 终端2（PC 或 K3 板卡）
run_hmi_linglong.sh --sim # 终端3，仅接受本机 TUI
run_hmi_tui_linglong.sh   # 可选终端客户端，不是第四个常驻进程
```

**sim2sim（双终端）**：

```bash
run_driver_linglong.sh --sim # 终端1（PC）
run_sim2sim_linglong.sh   # 终端2（K3 板卡）
```

**K3 实机控制**：

在 K3 板卡上启动：

```bash
run_linglong.sh --real
```

实机默认只启动三个核心进程；需要同一终端显示 TUI 时加 `--tui`，也可另开终端执行
`run_hmi_tui_linglong.sh`。原来的 driver/control/HMI 三条独立脚本仍可使用；HMI 用
`--real`，或不传模式时遵循 YAML 的 `driver.backend`。默认 YAML 是实机。
启动时在当前终端完成 sudo 认证，仅 driver 提权；control、HMI 和 TUI 保持普通用户运行。

每个新终端先执行 `source build/envsetup.sh`。首次实机调试前必须可靠吊装机器人并清空运动范围。
终端客户端按 `L` 申请控制权，再用右箭头按 `POWER_OFF → DAMP → HOME → ZERO → RL` 的顺序切换；
ZERO 显示已到位后才能进入 RL。反馈异常或控制超时时，应立即退回 DAMP 或 POWER_OFF。

**实机手机/App/扫码网页**：使用机器人自带路由器的固定内网地址，手机先连接机器人
Wi-Fi。不使用开发 PC/虚拟机地址，也不依赖展会网络给机器人分配的临时地址。
服务默认仅本机监听；完成机器人内网配置后启动，例如：

```bash
run_linglong.sh --real --listen 0.0.0.0 --public-url http://192.168.1.247:8765
```

Android App 或手机浏览器扫码后手动申请控制权；先释放原终端的控制权再切换客户端。
展示部署时，将 `operator_service.bind_address` 和 `public_url` 配置一次；后续仍运行
`run_hmi_linglong.sh`，不需要可见终端。`public_url` 应使用固定 IP 或可解析的固定主机名。
固定二维码包含连接凭据，扫码自动配对，不用手填凭据；地址和凭据不变时跨重启仍有效。
服务会自动导出 `~/.local/state/humanoid-operator/linglong/access.svg`，可打印交给受信任
操作者，也可从网页右上角下载。二维码等同操作钥匙，不应公开发布。离线导出命令：

```bash
run_hmi_linglong.sh --real --export-pairing --public-url http://192.168.1.247:8765
```

手机扫码连接后手动申请控制权，不会自动上电。仿真不提供网页或扫码接口；
本版本没有公网远控或 TLS。
App 工程与接口说明位于 common 的 `clients/android/` 和 `src/operator_service/`。
部署 APK 后，扫码打开的控制页同时提供“下载 Android App”；下载与控制共用 HMI 的
8765 端口，不需要额外的下载进程。安装后在 App 扫描同一张二维码即可配对。
旧 ROS 2 语音 HMI 尚未迁移，不能同时作为内部 HMI 写端启动。

日常启动无需额外 export。仅测试自定义配置时可使用 `LINGLONG_CONFIG` / `OPERATOR_CONNECTION`。
连接文件与凭据默认位于当前用户的 `~/.local/state/humanoid-operator/linglong/`，
服务与客户端使用同一普通用户，不使用 root 启动 HMI。

### K3 开机自启

SDK、策略和机器人内网配置完成后，以日常操作用户安装服务，例如 `bianbu`：

```bash
cd ~/spacemit_robot
sudo --user root ./output/staging/bin/install_linglong_service.py --user bianbu
sudo --user root systemctl start linglong.service
```

安装命令只启用下次开机自启，不启动硬件；第二条命令启动当前会话。开机依次配置
can0–can5（1 Mbps、restart 10 ms、发送队列 100），再调用 `run_linglong.sh --real`。
只有 driver 和 CAN 配置使用 root；control/HMI 使用指定普通用户，沿用其原二维码、
凭据和 SDK 日志目录。不会自动上电、申请控制权或进入 RL。

```bash
systemctl status linglong.service --no-pager
journalctl -u linglong.service -b -n 80 --no-pager
run_hmi_tui_linglong.sh
sudo --user root systemctl stop linglong.service
sudo --user root systemctl disable linglong.service
```

服务运行时，不再运行 `run_linglong.sh --real` 或临时 CAN 配置脚本；可独立打开
TUI、网页或 App。需要手动调试三进程时先停止服务。任一核心进程退出会清理同组进程，
不会自动重启硬件；排查后再手动启动服务。部署文件见 `services/`，安装只修改
`linglong.service`，不会配置 sudo 免密规则。

## 详细使用

`config/linglong.yaml` 保存通信、FSM 和策略参数，`config/linglong_hardware.yaml` 保存 CAN、IMU、关节映射及硬件标定参数。硬件配置仅适用于匹配的机器人版本和标定结果。

SONIC 使用同一个全身策略跟踪 `sonic_actions` 中选择的参考动作，策略和动作参数见
`config/linglong.yaml`。模型与参考动作单独分发，不包含在源码包中；部署时将资源
放入 `policy/sonic/`，并确认文件路径与配置一致。

人形 SDK 通用流程参考 SpacemiT 人形机器人 SDK 官方文档；仿真模型资源说明见 `resources/README.md`。

## 常见问题

| 现象 | 处理 |
| --- | --- |
| `[PolicyConfigLoader] ONNX 模型文件不存在` | 检查策略 YAML 中的 `model_path` 与 `policy/` 下的实际文件；已发布到模型库的资源可用 `download_models_linglong.sh` 下载 |
| 进程启动后通信无数据 | 检查 `config/linglong.yaml` 中的 transport 配置，确认通信方式与运行环境一致 |
| `whole_body` 初始化失败 | 检查 CAN、IMU 设备和访问权限，并确认没有其他进程占用硬件 |
| RL 控制不稳定或姿态异常 | 立即退出 RL 并保持吊装，检查策略、关节映射、零位和 IMU 方向是否匹配 |

## 版本与发布

| 版本 | 说明 |
| --- | --- |
| 0.1.0 | 初始版本，支持灵龙 28-DOF MuJoCo 仿真与 K3 实机控制 |

## 贡献方式

欢迎通过 GitHub Issue 或 Pull Request 提交问题与改进。

## License

本仓库源码文件头声明为 Apache-2.0，最终以本目录 `LICENSE` 文件为准。机器人模型资源的来源与修改说明见 `resources/README.md`。
