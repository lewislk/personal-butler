# 私人管家 iOS App 完整技术栈 & 项目架构结构设计文档
## 基础信息
1. 项目名称：PersonalButler（私人管家），Bundle ID `org.lewislk.personal-butler`
2. 最低系统版本：iOS 18
3. UI框架：纯 SwiftUI（iOS18 新特性全面使用，无 UIKit 兜底）
4. 本地存储底层：SwiftData（内核 SQLite 加密数据库）
5. 同步方案：局域网自建同步服务，手动触发 HTTP JSON 全量同步，无外网访问
6. 核心特色：日程/纪念日/待办/美食/菜谱/密码库+内置2FA身份验证器、内网同步、JSON导入导出备份、本地生物识别锁
7. 数据规则：日常所有操作仅读写本地 SQLite；仅用户手动触发上传/下载才调用局域网接口；密码、2FA密钥允许内网同步传输，无公网泄露风险

# 一、完整技术栈清单
## 1. UI & 视图框架（iOS18 原生）
### 核心 SwiftUI
- 自定义底部三栏 Tab Bar（普通 HStack 组件，而非系统 `TabView`）
  · 之所以不用系统 `TabView`：从主页 push 子页面时，系统 TabView 的 `.toolbar(.hidden, for: .tabBar)` 会导致返回主页时内容区被挤压出现"上浮"过渡；改用自定义 HStack + 外层 `NavigationStack(path:)` 后，push/pop 走原生栈动画，且系统边缘滑动返回手势自动可用。
- 顶部三 Tab：主页 / 全部应用 / 我的
- `NavigationStack(path: $router.path)` 承载 root（MainTabView）与所有子页面
- `ReorderableList` 原生列表拖拽排序（功能模块排序、2FA账号排序）
- `SegmentedPickerStyle` 分段控制器（待办切换、纪念日双模式、密码/2FA切换）
- `LazyVStack / LazyVGrid` 长列表、菜谱双列网格懒加载优化
- `ScrollView(.horizontal)` 横向分类标签筛选
- `Sheet / NavigationStack` 弹窗表单、页面路由
- `PhotosPicker` 原生相册拍照（美食记录配图）
- `ShareLink` 本地备份文件分享导出
- `LocalizedStringKey` 多语言兼容

### 系统原生视觉/图标
- SF Symbols 线性矢量图标（完全匹配原型图图标体系）
- iOS18 原生卡片阴影、圆角、色彩适配、动态类型

## 2. 架构设计范式
**Clean Architecture + MVVM + Combine 响应式数据流**
分层隔离：视图层 → 业务用例层 → 数据仓库层 → 本地/远程数据源
- View：纯UI展示，无业务逻辑
- ViewModel：持有UseCase，处理页面状态、交互、数据监听
- UseCase：封装完整业务流程，解耦视图与存储/网络
- Repository：统一封装本地持久化、局域网网络请求
- DataSource：实现底层SQLite存储、HTTP网络接口

## 3. 本地持久化（SQLite 底层 SwiftData）
1. **SwiftData（主存储）**
   - 底层内核：标准 SQLite 文件，iOS18 支持数据库文件加密
   - 能力：模型ORM、自动UI数据绑定、批量增删改查、原生JSON序列化、自定义SQL执行
   - 存储范围：待办、日程、纪念日、美食、菜谱、功能模块排序、设置基础信息
2. **KeychainServices（敏感数据隔离存储）**
   - 存储：账号明文、登录密码、2FA TOTP密钥
   - 特性：系统硬件加密、应用隔离、卸载自动清除、锁屏保护
3. UserDefaults
   - 轻量配置：同步服务器地址、上次同步时间、筛选标签状态、开关临时配置

## 4. 2FA 身份验证器配套能力
1. OneTimePassword（第三方轻量库）：TOTP/HOTP 6位动态验证码生成
2. VisionKit（系统原生）：解析 otpauth:// 二维码，一键导入2FA密钥
3. Combine Timer：30秒周期自动刷新验证码UI

## 5. 局域网同步网络层
1. URLSession：原生HTTP客户端，内网REST接口请求
2. Codable 全局JSON序列化：App导出数据包、服务端传输、本地导入恢复统一JSON结构
3. 内网鉴权：静态SyncToken + 设备唯一UUID请求头校验
4. 同步模式：手动全量上传/下载，无后台自动同步

## 6. 加密 & 安全框架（系统原生 CryptoKit）
1. LocalAuthentication：面容ID/指纹
   - 应用锁、密码页查看权限、2FA验证码查看校验、同步操作二次验证
2. CryptoKit AES-256（可选增强）：内网传输JSON整体加密、本地备份文件加密
3. SwiftData 数据库文件加密：本地SQLite防文件窃取

## 7. 本地推送提醒
UserNotifications：待办、日程、纪念日定时弹窗提醒

## 8. 日期工具
SwiftDate：公历/农历互转、倒计时天数计算、时间差、日期格式化

## 9. 图片处理
Kingfisher：本地图片缓存、压缩、读取美食探店相册图片

## 10. 文件处理
FileManager：本地备份目录管理、缓存大小计算
ZipArchive：备份JSON压缩打包

## 11. 第三方依赖汇总（轻量化无冗余）
| 库 | 作用 |
|----|------|
| SwiftDate | 农历、倒计时、日期计算 |
| OneTimePassword | 2FA TOTP/HOTP验证码生成 |
| Kingfisher | 本地图片缓存处理 |
| ZipArchive | 备份文件压缩解压 |

## 12. 系统原生依赖汇总
SwiftUI、Combine、SwiftData、LocalAuthentication、Keychain、CryptoKit、VisionKit、UserNotifications、Photos、URLSession、FileManager

# 二、全局规范约束
1. 数据分层存储规范
   - 非敏感展示字段：SwiftData(SQLite)
   - 密码、2FA密钥：仅Keychain，SQLite只存展示元数据
   - 同步传输：内存中拼接完整JSON（SQLite元数据 + Keychain敏感数据），不落地明文本地文件
2. 本地优先原则
   - 日常增删改查全部操作本地SQLite，无网络依赖
   - 同步仅用户手动触发，断网同步按钮置灰，不影响完整本地功能
3. 同步传输安全约束
   - 仅局域网内网服务交互，无外网请求
   - 全量JSON传输，支持密码、2FA密钥同步，无公网泄露风险
4. 版本兼容
   - 同步JSON携带dataVersion字段，后续迭代兼容新旧数据结构

# 三、完整项目目录分包结构（Clean架构分层）
```
PersonalButler/
├── App/                     # App入口、全局环境、SwiftData容器配置、根路由
├── Core/                    # 全局通用工具、网络、加密、扩展、权限
├── Domain/                  # 领域层：数据模型 + 业务用例（核心业务逻辑）
├── Data/                    # 数据层：本地SQLite仓库 + 局域网同步网络源
├── Presentation/            # SwiftUI 所有页面、组件、ViewModel、弹窗
├── Resources/               # 静态资源、多语言
└── Tests/                   # 单元测试（UseCase、JSON序列化、同步逻辑）
```

## 1. App 应用入口层
```
App/
├── PersonalButlerApp.swift         # 程序主入口，初始化加密SwiftData SQLite容器、全局环境、推送
├── AppEnvironment.swift            # 全局环境对象：注入所有仓库、同步服务、通知管理器
├── AppRouter.swift                 # 全局根路由：NavigationStack path 状态（子页面 push/pop）
├── AppTab.swift                    # 底部Tab枚举：home / allApp / mine
├── AppSyncConfig.swift             # 局域网同步全局配置（默认端口8090、同步密钥、服务地址）
└── AppColorTheme.swift             # 全局主题色（原型主色 #4A86E8）
```
核心：SwiftData容器开启数据库加密，底层SQLite持久化，全局单例环境统一注入所有业务类。`AppRouter` 以 `@Published var path: [String]` 驱动子页面栈，模块 id（"schedule" / "anniversary" 等）作为 path 元素，`AppModuleRouter.destination(for:)` 负责按 id 返回对应视图。

## 2. Core 核心通用层（无业务耦合，全局复用）
```
Core/
├── Extensions/                     # Swift原生扩展
│   ├── View+Ext.swift              # SwiftUI通用卡片、阴影、圆角、间距扩展
│   ├── Date+Ext.swift              # 日期快捷计算
│   ├── String+Ext.swift
│   └── Color+Ext.swift             # 全局主题色扩展
├── Auth/                           # 生物识别认证
│   └── LocalAuthService.swift      # 面容/指纹校验工具
├── Crypto/                         # AES加密工具（备份/内网传输增强）
│   ├── AESEncryptor.swift
│   └── BackupCrypto.swift
├── Network/                        # 局域网同步专用HTTP工具
│   ├── SyncHttpClient.swift        # URLSession封装内网请求客户端
│   ├── SyncRequestHeader.swift     # 统一请求头构造（DeviceID、SyncToken）
│   └── SyncResponseModel.swift     # 接口统一返回结构体
├── Utils/                          # 通用工具集合
│   ├── KeychainManager.swift       # 读写密码、2FA密钥
│   ├── DateCalculator.swift        # 纪念日倒计时、农历转换
│   ├── OTPGenerator.swift          # 2FA验证码生成工具
│   ├── QRScannerHelper.swift       # VisionKit二维码解析otpauth链接
│   ├── FileBackupHelper.swift      # 本地备份文件读写、压缩、缓存计算
│   └── NotificationManager.swift   # 本地推送统一管理
└── Constants/                      # 全局常量
    ├── UIConstant.swift            # 卡片尺寸、间距、字体、圆角
    ├── SyncConstant.swift          # 同步接口地址、端口、错误码定义
    └── TextConstant.swift          # 全局静态文案
```

## 3. Domain 领域层（业务模型 + 业务用例，不依赖UI/网络/SQLite）
### 3.1 Models 业务实体（SwiftData Model，全部实现Codable用于JSON同步）
```
Domain/Models/
├── Common/
│   └── SyncMeta.swift              # 同步数据包头部元数据（设备ID、时间戳、版本）
├── TodoItem.swift                  # 待办模型
├── ScheduleEvent.swift             # 日程模型
├── Anniversary.swift               # 纪念日模型（公历/农历、倒计时/累计）
├── PasswordAccount.swift           # 密码账号基础元数据（密码存Keychain）
├── OTPAccount.swift                # 2FA身份验证器模型（密钥存Keychain）
├── FoodRecord.swift                # 美食探店记录
├── CookRecipe.swift                # 自建菜谱
├── AppModule.swift                 # 首页功能模块（排序序号）
└── AppSetting.swift                # App全局设置
```

### 3.2 UseCases 业务用例（所有页面业务逻辑统一封装）
```
Domain/UseCases/
├── TodoUseCase.swift               # 待办增删改查、今日/近期待办筛选、计数统计
├── ScheduleUseCase.swift           # 日程日/月视图查询、推送提醒注册
├── AnniversaryUseCase.swift        # 纪念日倒计时、公历农历转换、双模式数据
├── PasswordUseCase.swift           # 密码分类筛选、查看校验、Keychain读写
├── OTPUseCase.swift                # 2FA账号增删、扫码导入、验证码定时刷新
├── FoodUseCase.swift               # 美食标签筛选、相册图片存储
├── CookUseCase.swift               # 菜谱网格、分类筛选
├── AppOrderUseCase.swift           # 功能模块拖拽排序、首页6项截取
├── SettingUseCase.swift            # 清除缓存、应用锁、版本信息
└── BackupSyncUseCase.swift         # 【核心同步用例】
    // 能力：
    // 1. 读取本地全部数据+Keychain敏感数据，组装标准同步JSON包
    // 2. 调用局域网接口上传全量数据
    // 3. 拉取服务端JSON并解析写入SQLite+Keychain
    // 4. 查询服务端备份信息、清空服务端备份
```

## 4. Data 数据层（存储、网络接口实现，隔离底层细节）
```
Data/
├── Repository/                     # 统一仓库层，UseCase唯一调用入口
│   ├── TodoRepository.swift
│   ├── ScheduleRepository.swift
│   ├── AnniversaryRepository.swift
│   ├── PasswordRepository.swift
│   ├── OTPRepository.swift
│   ├── FoodRepository.swift
│   ├── CookRepository.swift
│   ├── AppModuleRepository.swift
│   ├── SettingRepository.swift
│   └── SyncRepository.swift        # 同步仓库：封装局域网上传/下载/查询接口
├── LocalDataSource/                # SwiftData SQLite本地数据源实现
│   ├── SwiftDataStack.swift        # 加密SQLite容器初始化、数据库配置
│   ├── TodoLocalSource.swift
│   ├── OTPLocalSource.swift
│   ├── BackupJSONLocalSource.swift # JSON与本地模型互转逻辑
│   └── ...其余本地数据源
├── NetworkDataSource/              # 局域网同步远程数据源
│   └── LanSyncRemoteSource.swift   # 实现4个同步HTTP接口底层请求
└── Mapper/                         # JSON与领域模型映射（同步专用）
    ├── ModelToSyncJSONMapper.swift # 本地实体 → 同步JSON结构体
    └── SyncJSONToModelMapper.swift # 同步JSON → 本地实体批量写入
```

## 5. Presentation 视图层（纯SwiftUI页面、组件、ViewModel、弹窗）
### 5.1 ViewModels（每个页面独立VM，持有对应UseCase）
```
Presentation/ViewModels/
├── MainTab/
│   ├── HomeViewModel.swift         # Tab1首页：待办+功能宫格
│   ├── AllAppViewModel.swift       # Tab2全部应用：拖拽排序
│   └── MineViewModel.swift         # Tab3我的：设置、同步入口
├── SubPages/
│   ├── ScheduleViewModel.swift
│   ├── AnniversaryViewModel.swift
│   ├── PasswordViewModel.swift     # 密码列表+切换2FA子页
│   ├── OTPListViewModel.swift      # 2FA身份验证器列表
│   ├── FoodRecordViewModel.swift
│   ├── CookRecipeViewModel.swift
│   └── LanSyncViewModel.swift      # 局域网同步页面状态管理（加载、错误、备份信息）
```

### 5.2 Views 页面视图
```
Presentation/Views/
├── RootView.swift                  # 根视图：常驻 NavigationStack(path:) + MainTabView
├── AppModuleRouter.swift           # 模块 id → 子页面视图的工厂
├── MainTab/                        # 底部三栏主框架
│   ├── MainTabView.swift           # 自定义 tab bar（HStack）+ 内容区切换
│   ├── HomeView.swift
│   ├── AllAppView.swift
│   └── MineView.swift
├── SubPages/                       # 所有功能子页面
│   ├── Schedule/
│   │   └── ScheduleView.swift
│   ├── Anniversary/
│   │   └── AnniversaryView.swift
│   ├── Password/
│   │   ├── PasswordView.swift      # 密码主页面（分段切换密码/2FA）
│   │   └── OTPListView.swift      # 2FA身份验证器列表子页面
│   ├── FoodRecord/
│   │   └── FoodRecordView.swift
│   ├── CookRecipe/
│   │   └── CookRecipeView.swift
│   └── Sync/                       # 局域网同步专属页面
│       └── LanSyncView.swift       # 输入服务器IP、上传/下载、同步记录
├── Components/                     # 全局复用UI组件
│   ├── Common/                     # 通用基础控件
│   │   ├── SegmentedControl.swift
│   │   ├── HorizontalTagBar.swift
│   │   ├── FABAddButton.swift
│   │   ├── NavBackBar.swift
│   │   └── TabItemView.swift
│   ├── Home/
│   │   ├── TodoCard.swift
│   │   ├── TodoItemCell.swift
│   │   └── AppFeatureGrid.swift
│   ├── AllApp/
│   │   └── DragAppRow.swift
│   ├── Schedule/
│   │   └── ScheduleItemCell.swift
│   ├── Anniversary/
│   │   ├── AnniHeroCard.swift
│   │   └── AnniItemCell.swift
│   ├── Password/
│   │   ├── PasswordCard.swift
│   │   └── OTPCodeCell.swift      # 2FA验证码列表卡片
│   ├── Food/
│   │   └── FoodRecordCell.swift
│   ├── Cook/
│   │   └── CookRecipeGridCard.swift
│   ├── Mine/
│   │   ├── SettingGroupCard.swift
│   │   └── SettingRow.swift
│   └── Sync/
│       └── SyncInfoPanel.swift     # 同步信息展示面板
└── Sheets/                         # 新增/编辑弹窗表单
    ├── CreateTodoSheet.swift
    ├── CreateScheduleSheet.swift
    ├── CreateAnniversarySheet.swift
    ├── CreatePasswordSheet.swift
    ├── CreateOTPSheet.swift        # 添加2FA账号弹窗（扫码/手动输入）
    ├── CreateCookSheet.swift
    └── LocalBackupSheet.swift      # 本地导出备份弹窗
```

## 6. Resources 资源目录
```
Resources/
├── Assets.xcassets/    # 图片素材、配色集
├── Localizable.strings # 多语言文案
└── Fonts/              # 自定义字体（可选）
```

# 四、局域网同步REST接口完整定义（内置进设计文档）
## 基础规范
1. 服务地址：`http://局域网IP:8090`
2. 请求头统一携带
```http
Content-Type: application/json
X-Device-ID: 设备唯一UUID（App本地生成永久不变）
X-Sync-Token: 内网同步静态密钥（App与服务端配置一致）
```
3. 统一返回JSON结构
```json
{
  "code": 0,
  "msg": "提示文本",
  "data": {}
}
```
4. 错误码
| code | 说明 |
|------|------|
| 0 | 成功 |
| 1001 | 请求头缺失设备ID/同步密钥 |
| 1002 | 同步密钥校验失败 |
| 1003 | JSON解析失败 |
| 2001 | 服务端存储写入失败 |
| 2002 | 该设备无备份数据 |
| 5000 | 服务端内部异常 |

## 同步数据包顶层JSON结构（上传/下载通用）
```json
{
  "syncMeta": {
    "deviceId": "uuid字符串",
    "syncTimestamp": 1784701046,
    "appVersion": "1.0.0",
    "dataVersion": 1
  },
  "data": {
    "todoList": [],
    "scheduleList": [],
    "anniversaryList": [],
    "passwordList": [],
    "otpList": [],
    "foodRecordList": [],
    "cookRecipeList": [],
    "appModuleList": [],
    "setting": {}
  }
}
```

## 接口1：上传本地全量数据（导出接口）
- Method：POST
- Path：`/sync/upload`
- Request Body：完整同步数据包JSON
- 返回data：`{"saveTime": 时间戳, "totalItemCount": 条目总数}`

## 接口2：拉取设备备份（导入接口）
- Method：GET
- Path：`/sync/download`
- Query：无，依靠请求头X-Device-ID区分设备
- 返回data：完整同步数据包

## 接口3：查询设备同步备份信息
- Method：GET
- Path：`/sync/info`
- 返回data：
```json
{
  "hasBackup": true,
  "lastSyncTime": 1784701046,
  "totalCount": 128
}
```

## 接口4：清空当前设备服务端备份
- Method：DELETE
- Path：`/sync/clear`
- 返回code=0，data=null

# 五、核心业务流程说明
## 1. 本地数据读写流程（常态）
用户操作页面 → View触发ViewModel方法 → ViewModel调用对应UseCase → UseCase调用Repository → Repository操作SwiftData SQLite本地库 → Combine监听数据变更自动刷新UI。
密码/2FA密钥读写额外调用KeychainManager，不存入SQLite。

## 2. 局域网同步上传流程（本地→服务端）
1. 用户进入LanSyncView，点击【上传备份到内网服务器】
2. LocalAuthService生物验证
3. BackupSyncUseCase读取全部SQLite数据 + Keychain读取所有密码、OTP密钥
4. Mapper组装标准同步JSON包
5. SyncRepository调用LanSyncRemoteSource发起POST `/sync/upload`
6. 成功后本地缓存同步时间，UI提示完成；失败展示网络/鉴权错误

## 3. 局域网同步下载流程（服务端→本地）
1. 用户点击【从内网服务器恢复数据】
2. 先调用`/sync/info`获取备份信息弹窗确认
3. 用户确认后GET `/sync/download` 获取完整JSON
4. Mapper解析JSON分离普通数据与敏感凭证
5. 普通数据批量写入SwiftData SQLite；密码/OTP密钥写入Keychain
6. 全局发送数据变更通知，所有页面自动重载

## 4. 2FA身份验证器完整流程
1. 密码页面分段切换至OTP列表，强制生物验证通过才可查看验证码
2. 新增2FA两种方式：扫码解析otpauth链接 / 手动输入密钥
3. OTPUseCase通过Combine Timer每30秒刷新6位动态验证码
4. 同步上传时OTP账号完整携带密钥进入JSON包同步至局域网服务

# 六、安全设计要点
1. 本地存储分层隔离，敏感凭证永不落地SQLite明文
2. SwiftData SQLite文件开启系统加密，防止本地文件窃取
3. 所有查看密码、2FA、同步操作强制生物识别校验
4. 同步仅局域网内网传输，无外网访问，不存在公网泄露风险
5. 同步JSON仅内存临时组装，不会在本地生成明文备份文件
6. 内网简易鉴权：静态SyncToken+设备UUID双重校验，拒绝局域网陌生设备访问
7. 可选增强：内网使用自签HTTPS、JSON传输AES整体加密
