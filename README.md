# 打卡提醒 · CheckInReminder

一个 iOS 原生 App（SwiftUI），用地理围栏做「离开 A 区域就提醒打卡」。

## 一句话规则

> 当天**进入过** A 区域 → 在 **17:30–19:00** 之间**离开 A 区域 30 米以上** → 铃声 + 震动提醒打卡。
> 当天没去过 A 区域 → 整天都不提醒；已打卡 → 不再提醒。

三个条件必须同时满足，缺一不可（代码见 `Services/ReminderEngine.swift`）。

## 目录结构

```
CheckInReminder/
├── CheckInReminder.xcodeproj        # 双击即可用 Xcode 打开
├── project.yml                      # 工程描述（用 XcodeGen 重新生成工程用）
└── CheckInReminder/
    ├── App/CheckInReminderApp.swift      入口 + 通知按钮回调
    ├── Models/AppSettings.swift          配置与当日状态（UserDefaults 持久化）
    ├── Services/LocationManager.swift    后台定位 + 地理围栏 + 距离二次判定
    ├── Services/NotificationService.swift 本地通知（铃声/震动/快捷操作）
    ├── Services/SoundStore.swift          铃声选择、导入转码、试听、删除
    ├── Services/ReminderEngine.swift     提醒决策核心
    ├── Views/HomeView.swift              主界面
    ├── Views/LocationSearch.swift        地址搜索（MKLocalSearch 补全 + 解析坐标）
    ├── Views/ZoneMapView.swift           地图长按选点 + 半径圈
    ├── Views/SettingsView.swift          时间窗/提醒方式设置
    ├── Resources/reminder.wav            内置铃声：清脆三连音（默认）
    ├── Resources/chime.wav               内置铃声：柔和钟琴
    ├── Resources/radar.wav               内置铃声：雷达滴答
    ├── Resources/bell.wav                内置铃声：门铃叮咚
    ├── Assets.xcassets                   图标目录（可自行替换图标）
    └── Info.plist                        定位权限说明 + 后台定位声明
```

## 装到手机（4 步）

1. 双击 `CheckInReminder.xcodeproj` 用 Xcode 打开（需要 Xcode 15+，macOS）。
2. 左侧点蓝色项目图标 → `Signing & Capabilities` → **Team** 选你自己的 Apple ID（个人免费账号即可，无需付费开发者）。
3. iPhone 用数据线连上电脑，解锁并点「信任此电脑」；Xcode 顶部设备列表选你的 iPhone。
4. 按 `⌘R` 运行。手机上首次打开会弹两个权限，**定位一定要选「始终允许」**，通知选「允许」。

> 免费 Apple ID 签名的 App 有效期 7 天，过期后重新 `⌘R` 装一次即可。

## 使用

设定 A 区域有三种方式，任选其一：

1. **搜索地址**（最常用）：在搜索框输入「腾讯大厦」「科技园地铁站」等，边打字边出候选，点一下即可定位；也可以打完直接按键盘上的「搜索」。有定位权限时会自动优先搜你附近的同名地点。
2. **地图长按**：长按地图任意位置落点。
3. **用当前位置**：人站在 A 区域中心点，点一下按钮直接记录当前 GPS 坐标。

选好之后底部会显示地点名和精确经纬度，方便核对。
2. 拖动滑块调半径，默认 30 米。
3. 点「测试提醒（铃声 + 震动）」确认声音和震动正常。
4. 设置页可改时间窗（默认 17:30–19:00）、重复提醒间隔、铃声/震动开关。
5. 通知上直接点「我已打卡」即可结束当天提醒。

> 搜索用的是苹果自带地图服务（MKLocalSearch），国内可直接搜到中文地址，无需额外申请 Key。

## 关于 30 米这个精度

iOS 系统围栏（CLCircularRegion）官方建议半径 ≥ 100 米，30 米属于偏小的临界值，GPS 误差通常就有 5–20 米。为了尽量准时，App 做了三层保险：

- 系统地理围栏（进出回调，锁屏/杀进程后系统仍会唤醒 App）；
- 显著位置变化监听（`startMonitoringSignificantLocationChanges`，省电兜底）；
- 实时坐标距离二次判定（离 A 越近定位精度越高，最近 3 米一跳）。

实测出圈后通常几十秒内会响。如果实际体验觉得太灵敏/太迟钝，把半径调到 50–100 米会更稳。

## 耗电与隐私

- 位置数据只在本地计算，不上传任何服务器，也没有网络请求。
- 离 A 区域远时自动降低定位精度（100 米/次），近了才提高精度，正常使用一天耗电通常在 3% 以内。

## 铃声怎么换

设置页里有「内置铃声」和「我的铃声」两块，点一下即可选中并自动试听。

**内置 4 款**：清脆三连音（默认）、柔和钟琴、雷达滴答、门铃叮咚。

**用自己的音频**：点「从「文件」导入音频」→ 在「文件」App 里挑一首 mp3 / m4a / wav → 自动转成单声道 16bit wav、裁剪前 30 秒、存进 App 沙盒的 `Library/Sounds`，并立刻设为当前铃声。原文件不会被改动。

> **为什么不能直接选 Apple Music 里的歌？**
> iOS 的通知铃声只能是 App 包内或 App 容器 `Library/Sounds` 下的 wav / caf / aiff（≤30 秒）。Apple Music 的歌曲受 DRM 保护，系统不允许第三方 App 读取并用作铃声。
> 想用某首歌，可以先把音频文件存到「文件」App（比如从电脑传过去、或用支持导出的音乐工具），再在这里导入。

**删掉不想要的**：自定义铃声右侧有垃圾桶图标，点一下删除并自动回退到默认铃声。

> 注意：手机处于静音模式（侧边拨杆）时本地通知不会响铃，但依然会震动。想要静音也响铃需要申请 Critical Alerts 权限（需付费开发者账号 + 向苹果申请），本版本未启用。

## 自动编译（GitHub Actions）

仓库内置了 `.github/workflows/build.yml`，**每次推送到 main 都会自动在 GitHub 的 macOS 云主机上编译**，无需本机安装 Xcode。

- 推送代码 → Actions 页自动跑 → 构建完成后在详情页底部 Artifacts 下载 `CheckInReminder.ipa`
- 打 tag（`git tag v1.0 && git push --tags`）→ 自动把 ipa 发布到仓库的 Releases 页面

**默认产出的是未签名 ipa**（stdlib 未签名 / ad-hoc），它不能直接装进 iPhone，需要你用 AltStore、SideStore 之类工具用自己的 Apple ID 重签后安装。

**想让 CI 直接产出签好名的 ipa**，在仓库 `Settings → Secrets and variables → Actions` 里加三个变量：

| Secret 名称 | 内容 | 获取方式 |
|---|---|---|
| `CERT_P12_BASE64` | 开发者证书（p12）的 base64 | 钥匙串里导出「Apple Development」证书为 .p12，然后 `base64 -i cert.p12` |
| `CERT_P12_PASSWORD` | 导出 p12 时设的密码 | — |
| `MOBILEPROVISION_BASE64` | 描述文件的 base64 | 从 [developer.apple.com](https://developer.apple.com/account/resources/profiles/list) 下载 `.mobileprovision`，然后 `base64 -i app.mobileprovision` |

配好后 Actions 会自动用证书重签名。Ad Hoc 描述文件里包含的设备 UDID 才装得起来。

## 能不能「点链接直接安装」

不能——这是苹果的规则限制，与实现方式无关：

| 方式 | 要求 | 结果 |
|---|---|---|
| Xcode 数据线安装 | 免费 Apple ID + 一台 Mac | 可用，**7 天过期**，重连一次即续 |
| TestFlight | 付费开发者账号 ¥688/年 | 手机上点邀请链接即安装，最多 1 万人 |
| App Store | 付费账号 + 审核 | 公开发布 |
| 企业内部分发 | 企业账号 ¥1988/年 | 内网 `itms-services://` 链接直装 |
| AltStore / SideStore | 免费 Apple ID + 一次电脑配置 | 手机上自助重签，需每 7 天续签一次 |
