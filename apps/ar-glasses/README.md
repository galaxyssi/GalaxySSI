# GalaxySSI AR 眼镜版

独立 Android 应用，放在 `apps/watch` 同级。首个适配设备为 QIDI VENUS / VEN-A0（序列号 `MTT20M170108`），Android 11、API 30、横屏实际布局约 640×360 dp、`armeabi-v7a`。这台设备有麦克风和音频输出，但没有向普通应用提供系统语音识别或 TTS 服务。Watch 版要求 API 33，因此不能直接安装到这台设备。

## 已实现

- 参考提供的浅蓝界面，采用居中的 GalaxySSI、声波和 Hello Hello 主视图；识别、等待回复和回复内容使用同一视线区域。
- 内置 Vosk 轻量中文和英文离线模型。应用在前台时自动持续监听唤醒词 `Hello Hello`，不显示麦克风开关（连续说或 3 秒内分两次说）；唤醒前不会把其它语音记为问题。唤醒后识别中英文问题，最终结果或稳定的实时文字出现后等待 1.5 秒，期间继续说话会重置计时；然后自动发送。未配置 Agent 时保持监听并提示手机配置。
- 语音命令以 `Hello Hello` 唤醒：拍照、开始录像、停止录像、返回、相册、桌面、Wi-Fi/蓝牙设置、音量、电量、时间，以及应用内的发送、取消、朗读、新对话和会话导航。拍照/录像使用应用内相机；录像不采集音轨，让离线识别持续工作。照片和视频保存到 `DCIM/GalaxySSI`。普通应用只能执行 Android 向其开放的操作，不能运行任意 ADB shell 命令。
- 眼镜 GalaxySSI 在前台且已联网时自动开启手机配对发现，无需进入眼镜设置页。手机「我的 Agent → 设备 → 配置 AR 眼镜」扫描眼镜，两端核对 6 位数字；眼镜可说 `Hello Hello 确认配对`。手机可选已有云端配置或填写新配置，测试后加密传送。该流程复用手表的证书绑定 TLS 配对协议，眼镜使用单独的局域网服务 `_galaxyssi-glasses._tcp.`。
- 首次 Wi-Fi 入网可在手机配置页扫描附近的 WPA2 兼容网络并选择 SSID，或手动填写隐藏网络的名称；密码仍在手机输入并生成二维码。手机扫描需要精确位置权限和系统定位开关，拒绝权限时可手动输入。眼镜说 `Hello Hello 扫描配网` 或点相机页的“扫描配网码”，看向手机，核对 SSID 后说 `Hello Hello 确认联网` 或点按钮确认。眼镜通过 Android Wi-Fi suggestion 请求连接；系统首次授权提示仍需在眼镜上批准。网络由系统选择，不能保证立即连接。
- 直接连接用户配置的 OpenAI 兼容、Anthropic Messages、Gemini generateContent HTTPS API；限制上下文和回复大小，支持取消请求。
- API 密钥及会话记录由 Android Keystore AES-GCM 加密存储。系统 TTS 可用时优先使用；否则复用 GalaxySSI Android/Watch 使用的 Microsoft Edge 在线语音合成。使用后者时，播报文字会发送给其服务。

## 构建与安装

需要 JDK 17/21 和 Android SDK 36。将 SDK 路径写入未跟踪的 `local.properties`。首构建下载并校验 Vosk 中英文轻量模型，存入 Gradle 缓存，不加入 Git。

```powershell
cd apps/ar-glasses
.\gradlew.bat :app:assembleDebug
adb -s MTT20M170108 install -r app/build/outputs/apk/debug/app-debug.apk
adb -s MTT20M170108 shell am start -n com.galaxyssi.glasses/.MainActivity
```

首次打开应用时，应用将中英文模型从 APK 解压到私有存储并加载，之后不需再次解压。应用仅在前台监听唤醒词，不提供后台唤醒。语音识别可离线工作；手机配置传送需要同一 Wi-Fi，模型答复及 Edge 语音合成需要联网。

## 当前范围

此版提供眼镜端语音对话、常用设备操作、手机端 Wi-Fi 二维码和云模型配置。Watch 版的 Desktop QR 配对、Signal 链路、联系人、Web 工具、后台唤醒尚未迁入，因此手机端“扫描添加远端 Agent”尚不能用于眼镜。Android 首次 Wi-Fi 授权和相机/麦克风权限不能由普通应用绕过；不能把系统 `VOICE_COMMAND` 入口等同于全天候唤醒词。未配置 API 凭据时，语音识别和本地设备操作可用，模型回复不可用。VENUS 不稳定断开 ADB 时，相机、二维码配网和端到端语音流程需在设备重新连接后实测。
