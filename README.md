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
- walk / wave_hello 两套预训练 RL 策略

不支持：
- 在线训练或策略更新
- 通过当前 28 自由度控制链路驱动手部末端执行器

## 快速开始

### 环境准备

**PC 端（x86_64）**：

```bash
# 系统依赖
sudo apt install -y libeigen3-dev libyaml-cpp-dev libglfw3-dev cmake g++

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
sudo apt install -y libeigen3-dev libyaml-cpp-dev spacemit-tcm pkg-config

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

默认配置使用 `whole_body` 实机后端。进行 MuJoCo 仿真前，将
`config/linglong.yaml` 切换为：

```yaml
driver:
  backend: mujoco
```

**FSM 完整仿真（三终端）**：

```bash
run_driver_linglong.sh    # 终端1（PC，x86_64）
run_control_linglong.sh   # 终端2（PC 或 K3 板卡）
run_hmi_linglong.sh       # 终端3（PC 或 K3 板卡）
```

**sim2sim（双终端）**：

```bash
run_driver_linglong.sh    # 终端1（PC）
run_sim2sim_linglong.sh   # 终端2（K3 板卡）
```

**K3 实机控制（三终端）**：

在 K3 板卡上依次启动：

```bash
run_driver_linglong.sh
run_control_linglong.sh
run_hmi_linglong.sh
```

首次实机调试前必须可靠吊装机器人并清空运动范围。通过 HMI 按 `POWER_OFF → DAMP → HOME → ZERO → RL` 的顺序切换状态；反馈异常或控制超时时，应立即退回 DAMP 或 POWER_OFF。

## 详细使用

`config/linglong.yaml` 保存通信、FSM 和策略参数，`config/linglong_hardware.yaml` 保存 CAN、IMU、关节映射及硬件标定参数。硬件配置仅适用于匹配的机器人版本和标定结果。

人形 SDK 通用流程参考 SpacemiT 人形机器人 SDK 官方文档；模型资源说明见 `resources/README.md`。

## 常见问题

| 现象 | 处理 |
| --- | --- |
| `[PolicyConfigLoader] ONNX 模型文件不存在` | 运行 `download_models_linglong.sh` 下载模型后重试 |
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
