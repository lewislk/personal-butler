# PersonalButler · SPEC 索引

本目录是 PersonalButler（iOS 私人管家 App）的项目级与模块级 SPEC 汇总。仓库根 [README.md](../../README.md) 提供面向新读者的入口说明；本索引面向查资料 / 找模块边界的场景。

## 1. 项目级

- [project-spec.md](./project-spec.md) — 服务定位、业务边界、模块导航、跨模块请求流向、服务级约定

## 2. 模块级

按依赖层级从上至下：

| 层 | 模块 | SPEC | 关键入口 |
|----|------|------|---------|
| 骨架 | App 骨架（入口/路由/主题/Tab） | [module-app-shell-spec.md](./module-app-shell-spec.md) | `App/PersonalButlerApp.swift` · `Presentation/Views/RootView.swift` |
| 骨架 | Main Tab（主页 / 全部应用 / 我的） | [module-main-tab-spec.md](./module-main-tab-spec.md) | `Presentation/Views/MainTab/*.swift` |
| 业务 | 日程管理 | [module-schedule-spec.md](./module-schedule-spec.md) | `SubPages/ScheduleView.swift` |
| 业务 | 纪念日 | [module-anniversary-spec.md](./module-anniversary-spec.md) | `SubPages/AnniversaryView.swift` |
| 业务 | 笔记 | [module-note-spec.md](./module-note-spec.md) | `SubPages/NoteView.swift` |
| 业务 | 密码 & 2FA | [module-password-otp-spec.md](./module-password-otp-spec.md) | `SubPages/PasswordView.swift` |
| 业务 | 美食记录 | [module-food-spec.md](./module-food-spec.md) | `SubPages/FoodRecordView.swift` |
| 业务 | 烹饪 / 菜谱 | [module-cook-spec.md](./module-cook-spec.md) | `SubPages/CookRecipeView.swift` |
| 跨模块 | 备份 & 局域网同步 | [module-backup-sync-spec.md](./module-backup-sync-spec.md) | `Domain/UseCases/BackupSyncUseCase.swift` · `SubPages/LanSyncView.swift` · `Sheets/LocalBackupSheet.swift` |
| 底座 | Core 通用能力 | [module-infra-spec.md](./module-infra-spec.md) | `Core/Auth/*.swift` · `Core/Utils/*.swift` · `Core/Extensions/*.swift` |

## 3. 模块依赖关系

```text
App 骨架
  └─ Main Tab
      ├─ 主页 (HomeView)：聚合 schedule / anniversary / cook / manual todo
      ├─ 全部应用：编辑 AppModule.order
      └─ 我的：入口 → 备份 & 局域网同步

业务模块（可独立进入子页面）：
  schedule / anniversary / note / password-otp / food / cook

备份 & 局域网同步：读全部业务 @Model + Keychain → 组装 SyncPayload

Core 通用能力（横切底座）：
  KeychainManager / LocalAuthService / OTPGenerator / DateCalculator / NotificationManager / UIConstant / *+Ext
```

## 4. 快速定位规则

- 找"某功能页面从哪里进"：先看 [module-main-tab-spec.md](./module-main-tab-spec.md) 与 [module-app-shell-spec.md](./module-app-shell-spec.md) 中的 `AppModuleRouter` 部分
- 找"敏感数据怎么存 / 怎么加密"：[module-infra-spec.md](./module-infra-spec.md) + [module-password-otp-spec.md](./module-password-otp-spec.md)
- 找"同步接口 / JSON 结构"：[module-backup-sync-spec.md](./module-backup-sync-spec.md) + `personal-butler/Data/Mapper/SyncPayload.swift`
- 找"主页待办为什么会自动出现某条日程 / 纪念日"：[module-main-tab-spec.md § 主页 · 今日/近期待办聚合](./module-main-tab-spec.md#主页--今日待办聚合)
- 找"如何新增一个功能模块"：见 [project-spec.md § 服务级约定 · 路由 id 稳定](./project-spec.md#6-服务级约定)
