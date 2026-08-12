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
