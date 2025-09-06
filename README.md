# tphotos

使用 Flutter 的**非官方** TerraPhotos 客户端，实现照片管理。

> 平台支持：Android、Windows、iOS（无签名构建）、macOS（未签名）。
> 仅测试了 Android 与 Windows，其他平台如有问题请提 issue。

此 README 侧重于开发/调试信息；运行说明、架构要点与常见陷阱请参见仓库内 `lib/` 与 `.github/copilot-instructions.md`。

## 快速开始

1. 安装依赖：
```bash
flutter pub get
```

2. 运行（在已连接设备或模拟器上）：
```bash
flutter run
```

如需桌面/移动平台指定：
- Windows：`flutter run -d windows`
- Android：`flutter run -d android`
- iOS（需 macOS 且已配置 Xcode/iOS 模拟器）：`flutter run -d ios`
- macOS：`flutter run -d macos`

3. 本地后端地址配置：
- 推荐在应用启动时通过登录页输入服务器地址（`lib/pages/login_page.dart` 的默认值为 `http://192.168.2.2:8181`）。
- 如需硬编码测试服务器，可在 `lib/main.dart` 中创建 `TosAPI('http://your-server:8181')` 后直接跳转。

## 核心架构（简要）

- `lib/api/`
   - `tos_client.dart`：统一的 HTTP 客户端，负责 Cookie 管理、CSRF 头注入、统一错误（抛出 `APIError`）。
   - `auth_api.dart`：登录/登出/会话接口，包含 RSA 登录流程的实现。
   - `photos_api.dart`：缩略图、原图请求与分页加载（`photoListAll`）。

- `lib/models/`：API 返回与客户端模型的映射（`timeline_models.dart`, `photo_list_models.dart`）。注意：模型字段可能与服务端拼写不完全一致，修改时须同步。

- `lib/pages/`：界面层（`login_page.dart`, `photos_page.dart`），普遍使用 `FutureBuilder`，并在页面内实现简单缓存（如 `_datePhotoCache`, `_thumbCache`）。

## 项目特有约定与注意事项（必须阅读）

- Cookie / CSRF 管理：所有需要登录态的请求必须使用 `TosClient`（不要直接使用 `http.Client`），以保证 Cookie 与 `X-CSRF-Token` 被正确维护与注入，避免 403/401 问题。

- RSA 登录流程（务必按顺序实现）：
   1. GET `/tos/` —— 获取初始 Cookie/CSRF
   2. GET `/v2/lang/tos` （调用时使用 `includeHeaders: true`）—— 从 response headers 读取 `x-rsa-token`（Base64 的 PEM 文本）
   3. 解析 `x-rsa-token` 并使用 `encrypt`（或 `pointycastle`）将密码加密（返回 base64），再 POST 到 `/v2/login`。

- 二进制资源（图片）：必须使用 `TosClient.getBytes()`（或 `PhotosAPI.thumbnailBytes()` / `PhotosAPI.originalPhotoBytes()`），因为服务端验证依赖 Cookie，直接 `get()` 返回字符串会导致 403。

- API/模型拼写陷阱：
   - `PhotoItem.fromJson` 显式使用 `json['timetamp']`（不是 `timestamp`）。如果要更改此字段名，务必全库搜索并同步修改所有使用点（`models` 与 `pages`）。
   - `TimelineResponse` 與 `PhotoListResponse` 的 `code` 字段是布尔类型（true 表示成功）。

## 常见问题与排查

- 登录失败／403：确认先调用 `/tos/` 以建立 cookie，再调用 `/v2/lang/tos` 并从 headers 读取 `x-rsa-token`。
- 图片 403：确认代码使用了 `getBytes()` 并且 `TosClient` 的 `_cookies` 正确包含服务端返回的认证 cookie。

## 开发建议（对 AI 代理/贡献者）

- 新增 API：优先在 `lib/api/` 添加方法并复用 `TosClient`；返回的 JSON 解析放入 `lib/models/`。
- 修改模型字段后：全仓库搜索该字段并同步更新 `fromJson`/`toJson` 与所有调用点。

## 主要参考文件

- `lib/api/tos_client.dart` — Cookie/CSRF 与错误处理实现
- `lib/api/auth_api.dart` — RSA 登录实现示例（`x-rsa-token` 解析）
- `lib/api/photos_api.dart` — 缩略图 / 原图获取与分页示例
- `lib/models/*.dart` — 数据模型（注意 `timetamp` 拼写）
- `lib/pages/login_page.dart`, `lib/pages/photos_page.dart` — 页面使用模式与缓存示例

---

<a href="https://www.flaticon.com/free-icons/gallery" title="gallery icons">Gallery icons created by Hilmy Abiyyu A. - Flaticon</a>