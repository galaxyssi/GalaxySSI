# GalaxySSI AR 眼镜版

独立 Android 应用，放在 `apps/watch` 同级。首个适配设备为 QIDI VENUS / VEN-A0（序列号 `MTT20M170108`），Android 11、API 30、横屏实际布局约 640×360 dp、`armeabi-v7a`。这台设备有麦克风和音频输出，但没有向普通应用提供系统语音识别或 TTS 服务。Watch 版要求 API 33，因此不能直接安装到这台设备。

## 已实现

- 参考提供的浅蓝界面，采用居中的 GalaxySSI、声波和 Hello Hello 主视图；识别、等待回复和回复内容使用同一视线区域。
- 内置 Vosk 轻量中文和英文离线模型。前台持续监听唤醒词 `Hello Hello`（连续说或 3 秒内分两次说）；唤醒前不会把其它语音记为问题。唤醒后识别中英文问题，最终结果或稳定的实时文字出现后等待 1.5 秒，期间继续说话会重置计时；然后自动发送。未配置 Agent 时保持监听并提示手机配置。
- 语音命令：`发送`、`取消`、`朗读`、`停止朗读`、`新对话`、`设置`。模型回复显示在眼镜中并自动播报，可点「重播回复」。
- 连接设置全部由 GalaxySSI 手机应用完成：手机「我的 Agent → 设备 → 配置 AR 眼镜」，眼镜点「手机配置」，两端连接同一 Wi-Fi、核对 6 位数字，再由手机选择已有云端配置或填写新配置并传送。该流程复用手表的证书绑定 TLS 配对协议，眼镜使用单独的局域网服务 `_galaxyssi-glasses._tcp.`。
- 直接连接用户配置的 OpenAI 兼容、Anthropic Messages、Gemini generateContent HTTPS API；限制上下文和回复大小，支持取消请求。
- API 密钥及会话记录由 Android Keystore AES-GCM 加密存储。系统 TTS 可用时优先使用；否则复用 GalaxySSI Android/Watch 使用的 Microsoft Edge 在线语音合成。使用后者时，播报文字会发送给其服务。

## 构建与安装

需要 JDK 17/21 和 Android SDK 35。将 SDK 路径写入未跟踪的 `local.properties`。首构建下载并校验 Vosk 中英文轻量模型，存入 Gradle 缓存，不加入 Git。

```powershell
cd apps/ar-glasses
.\gradlew.bat :app:assembleDebug
adb -s MTT20M170108 install -r app/build/outputs/apk/debug/app-debug.apk
adb -s MTT20M170108 shell am start -n com.galaxyssi.glasses/.MainActivity
```

首次打开应用时，应用将中英文模型从 APK 解压到私有存储并加载，之后不需再次解压。应用仅在前台监听唤醒词，不提供后台唤醒。语音识别可离线工作；手机配置传送需要同一 Wi-Fi，模型答复及 Edge 语音合成需要联网。

## 当前范围

此版提供眼镜端语音对话和手机端云模型配置。Watch 版的 Desktop 配对、Signal 链路、联系人、Web 工具、后台唤醒尚未迁入；不能把 Android 系统的 `VOICE_COMMAND` 入口等同于全天候唤醒词。未配置 API 凭据时，语音识别可用，模型回复不可用。
