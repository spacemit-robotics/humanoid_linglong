# LingLong L1 V1.4 resources

## 文件来源与修改

- 原始交付基线：厂商 `LingLong_L1_V1.4_20260615` 资源包。原始 URDF SHA256 为 `1095bbbd302ec9256c1364e7b681dcfd61399d9b5c96197268448481a5677d30`。
- `urdf/LingLong_L1_V1.4.urdf`：转换副本，清理行尾空白，并启用 floating base、修正 mesh 相对路径及 `base_link.stl` 文件名大小写；结构化对比确认其余 link、joint、inertial、geometry 和 limit 与原始 URDF 一致。
- `meshes/`：与原始交付包逐文件一致的 29 个 STL 文件。
- `xml/LingLong_L1_V1.4.xml`：使用 MuJoCo 3.4.0 从当前 URDF 转换，再补充 28 个 actuator。
- `xml/scene.xml`：SDK 加载入口和通用 smoke-test 地面。

## 已验证

- 28 个 actuator 与 URDF/MJCF 关节顺序完全一致。
- MuJoCo 3.4.0 编译结果：`nq=35`、`nv=34`、`nu=28`、`nbody=30`、`njnt=29`、总质量约 `62 kg`。
- 原始 URDF 的 `base_link` collision box 为 `0.15 x 0.25 x 0.5 m`，会穿过位于 `z=0.4168 m` 的头部。MJCF 保留该碰撞代理用于物理，但统一放入默认不可见的 geom group 3，并排除零位时确认存在的 3 组内部穿透接触。
- 默认 viewer 只显示 group 1 的真实 mesh；零位 `mj_forward` 初始接触数为 0。
- 无控制 `testspeed` smoke test 可运行，未出现 XML 编译错误或 NaN。

## 尚未获得

- 与 `policy_0611_4.onnx` 完全匹配的训练 MJCF/XML。
- 训练时的 joint damping、armature、frictionloss 和地面接触参数。
- 版本匹配的 MuJoCo IMU、足底接触传感器定义。
- 实机双电机踝机构在 MuJoCo 中的等价约束模型。

因此当前 XML 只表示“几何、惯量、关节和 actuator 可被 SDK/MuJoCo 加载”，不表示已经复现训练动力学。硬件 alias、CAN、IMU 和实例标定不属于模型资源，统一放在 `config/linglong_hardware.yaml`。

## 双臂桌面抓放场景（资源预览）

### 文件与组织方式

沿用 RGBD / lidar 变体的“独立 YAML + 机器人 MJCF + 场景 MJCF”结构：

- `config/linglong_mujoco_picker.yaml`：以 RGBD 配置为模板，仅更改 `scene_xml`，不修改原有策略、默认策略和三进程启动脚本。
- `xml/LingLong_L1_V1.4_picker.xml`：保留原始机器人元素，新增头部双目、双腕 RGB 相机和明确标注的平行夹爪代理。
- `xml/scene_picker.xml`：矩形桌、左右对称的两个自由物体、各物体后方的物理托盘及观察相机。
- `meshes/omni_picker_base.obj`：夹爪底座的可视网格，不用作真实连杆或接触几何。
- `grasp/omnipicker_spec.json`：来源参数与代理假设；`grasp/meshes/provenance.json`：网格转换、哈希和再分发状态。

不包含视觉识别、相机标定、OMPL 规划、抓放状态机、策略权重和运行时接管功能。

### 布局与相机

单位为米，机器人初始前方为 `+x`，左侧为 `+y`。桌面顶面为 `z=0.900`，桌子中心为 `x=0.700`。

| 元素 | 世界坐标 | 说明 |
| --- | --- | --- |
| 红色方块 | `(0.430, 0.360, 0.927)` | 左侧物体，边长 0.050，质量 0.080 kg |
| 蓝色方块 | `(0.430, -0.360, 0.927)` | 右侧物体，相同尺寸和质量 |
| 左侧托盘 | `(0.520, 0.360, 0.900)` | 与红色物体同一横向通道，底板和四壁均参与碰撞 |
| 右侧托盘 | `(0.520, -0.360, 0.900)` | 与蓝色物体同一横向通道，底板和四壁均参与碰撞 |

物体初始底面离桌面约 2 mm，会在物理仿真中自然落桌；没有 weld、隐藏附着或物体位姿强制跟随。
托盘前壁与对应方块的初始水平间隙为 10 mm。这是场景几何间隙，不代表夹爪进近轨迹一定无碰撞。

`head_stereo_left` / `head_stereo_right` 固连在 `head_pitch_link`，基线为 0.060 m；
`left_wrist_rgb` / `right_wrist_rgb` 随对应末端运动；`scene_overview` 仅用于观察。
相机位姿和视场角是当前仿真设置，不代表已完成实机内外参标定，也没有在本 PR 中实现图像发布。

### 夹爪代理边界

夹爪底座中心与腕部末端中心重合，沿用当前模型安装朝向。
每只夹爪使用两个滑动关节、一个平均位移 tendon 驱动和一个同步 equality，开口范围约 0--120 mm。
底座惯量和代理手指的总质量按每手 0.430 kg 设置；接触几何使用盒体代理。
这不是 OmniPicker 真实自适应连杆、被动差动或自锁机制的复现。手指摩擦、力预算、开合时间解释和 TCP 偏置仍为代理假设。
约束仅同步夹爪手指，不附着任务物体。

### 预览与 SDK 兼容性

可使用 MuJoCo 3.4.0 原生 viewer 直接检查场景。从仓库根目录运行：

```bash
python -m mujoco.viewer --mjcf resources/xml/scene_picker.xml
```

需要在独立 Python 环境中安装 `mujoco==3.4.0`。原生 viewer 只是资源预览，不运行 RL 或自动抓放。

**该配置不是当前上游 SDK 的即插即用 RL 抓放入口。** 与无新增活动关节的 RGBD / lidar 变体不同，
此模型增加了四个夹爪滑动关节和两个 actuator；任务物体还各自具有一个 free joint。
左夹爪关节出现在右臂关节前，因此后端若按 `qpos[7+i]` / `qvel[6+i]` 连续读取 28 轴状态，会读取错误的右臂状态。
接入 SDK 前必须完成按关节名称解析状态地址及夹爪执行器映射的配套适配；不能仅修改 `num_dof` 或把夹爪混入 RL 的 28 轴顺序。
本 PR 不修改这些后端接口，不能将 XML 编译或被动短步测试视为站立、抓放或整机验收。
现有三进程脚本、默认 `linglong.yaml` 和策略选择逻辑保持不变。

### 夹爪资源许可与来源

2026-11-04 从官方手册的 `OP1_URDF` 入口重新下载 `robot_description.zip`，
核对包内 `robot_description/package.xml` 明确声明 `<license>Apache-2.0</license>`。
原始声明文件未经修改存档于 [robot_description.package.xml](grasp/meshes/license_evidence/robot_description.package.xml)。
压缩包、原始 `base_link.STL` 和 URDF 的 SHA256 均与已有来源记录一致；
证据文件 SHA256、下载地址、核验日期和转换记录见 [provenance.json](grasp/meshes/provenance.json)
及 [omnipicker_spec.json](grasp/omnipicker_spec.json)。

官方包未包含独立的 LICENSE 或 NOTICE 文件；这里记录的是官方包的许可声明核验，
不是从下载地址、SDK 许可、OmniHand O10 的许可或本仓库许可推定模型授权。
Apache-2.0 全文见仓库根目录 [LICENSE](../LICENSE)。保留来源、原有版权及适用声明；
STL 转为 OBJ 的转换已明确记录，没有简化或改变原始顶点。
