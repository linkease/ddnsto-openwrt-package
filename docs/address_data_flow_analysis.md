# DDNSTO 远程访问域名数据流分析报告

## 一、问题概述

**问题描述**：用户在 ddnsto 控制台手动编辑或删除地址后，LuCI 界面的远程访问地址不会同步更新，导致展示的数据过期无效。

**根本原因**：`address` 字段的写入和更新机制存在设计缺陷，只能从快速向导单向写入，无法从 ddnsto 服务器同步最新状态。

---

## 二、代码架构分析

### 2.1 项目结构

```
ddnsto-openwrt-package/
├── ddnsto/                          # 后端二进制和启动脚本
│   ├── files/
│   │   ├── ddnsto.config           # UCI 默认配置
│   │   ├── ddnsto.init             # 启动脚本
│   │   └── ddnsto.uci-default      # 初始化脚本
│   └── Makefile
├── luci-app-ddnsto/                 # LuCI 前端应用
│   ├── luasrc/
│   │   ├── controller/ddnsto.lua   # 后端 API 接口
│   │   ├── model/cbi/ddnsto.lua    # 传统配置页面
│   │   └── view/ddnsto/main.htm    # 主页面模板
│   └── root/www/luci-static/ddnsto/index.js  # React 前端应用
└── docs/
    └── address_data_flow_analysis.md  # 本报告
```

### 2.2 前端源码位置

React 源码位于独立项目：
```
src/ddnsto-openwrt-web/
├── src/
│   ├── App.tsx                     # 主应用组件
│   ├── components/
│   │   ├── OnboardingWizardCard.tsx  # 快速向导组件
│   │   ├── StatusCard.tsx          # 状态显示卡片
│   │   └── ...
│   └── main.tsx
└── package.json
```

编译后输出到：`luci-app-ddnsto/root/www/luci-static/ddnsto/index.js`

---

## 三、address 字段数据流详细分析

### 3.1 数据写入路径（唯一）

```
┌─────────────────────────────────────────────────────────────────────────┐
│  写入路径                                                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  用户操作                                                                │
│     ↓                                                                   │
│  OnboardingWizardCard.tsx (快速向导)                                     │
│     ↓ 调用 saveAddress()                                                │
│  POST /api/onboarding/address                                           │
│     ↓                                                                   │
│  ddnsto.lua: api_onboarding_address()                                   │
│     ↓ uci:set("ddnsto", sid, "address", url)                           │
│  /etc/config/ddnsto (UCI 配置)                                          │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**代码位置**：[luci-app-ddnsto/luasrc/controller/ddnsto.lua:L520-L544](file:///Users/ycl/Desktop/work_sync/ddnsto/release/ddnsto-openwrt-package/luci-app-ddnsto/luasrc/controller/ddnsto.lua#L520-L544)

```lua
function api_onboarding_address()
  ...
  local url = param(body, "url") or param(body, "address")
  ...
  uci:set("ddnsto", sid, "address", url)  -- 唯一写入点
  uci:commit("ddnsto")
  ...
end
```

### 3.2 数据读取路径

```
┌─────────────────────────────────────────────────────────────────────────┐
│  读取路径                                                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  /etc/config/ddnsto (UCI 配置)                                          │
│     ↓                                                                   │
│  ddnsto.lua: read_config()                                              │
│     ↓                                                                   │
│  GET /api/config 或 GET /api/status                                     │
│     ↓                                                                   │
│  App.tsx: fetchConfig() / fetchStatus()                                 │
│     ↓                                                                   │
│  StatusCard.tsx (状态卡片展示)                                           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**代码位置**：
- 后端读取：[luci-app-ddnsto/luasrc/controller/ddnsto.lua:L206-L266](file:///Users/ycl/Desktop/work_sync/ddnsto/release/ddnsto-openwrt-package/luci-app-ddnsto/luasrc/controller/ddnsto.lua#L206-L266)
- 前端读取：[src/ddnsto-openwrt-web/src/App.tsx:L70-L98](file:///Users/ycl/Desktop/work_sync/ddnsto/src/ddnsto-openwrt-web/src/App.tsx#L70-L98)

### 3.3 快速向导数据流

```
┌─────────────────────────────────────────────────────────────────────────┐
│  快速向导完整数据流                                                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────┐                                                    │
│  │  LuCI 页面       │                                                   │
│  │  (OpenWrt)       │                                                   │
│  │  ┌───────────┐  │                                                    │
│  │  │ index.js  │  │  React 应用主入口                                   │
│  │  │ ┌───────┐ │  │                                                    │
│  │  │ │ 快速向导 │ │  │  OnboardingWizardCard 组件                       │
│  │  │ │ ┌───┐ │ │  │                                                    │
│  │  │ │ │iframe│ │ │  │  src="https://www.kooldns.cn/bind"              │
│  │  │ │ └───┘ │ │  │                                                    │
│  │  │ └───────┘ │  │                                                    │
│  │  └───────────┘  │                                                    │
│  └────────┬────────┘                                                    │
│           │ postMessage                                                  │
│           ↓                                                              │
│  ┌─────────────────┐     ┌──────────────────────────┐     ┌───────────┐ │
│  │ 本地 OpenWrt     │ ←→  │  https://www.kooldns.cn  │ ←→  │ ddnsto后端 │ │
│  │ (index.js)       │     │ /bind (iframe)            │     │ (域名分配) │ │
│  └─────────────────┘     └──────────────────────────┘     └───────────┘ │
│           ↑                                              ↓              │
│           └──────────── 返回 url (远程访问域名) ←──────────┘              │
│                                                                         │
│  保存到本地                                                              │
│     ↓                                                                   │
│  POST /api/onboarding/address                                           │
│     ↓                                                                   │
│  UCI 配置 (/etc/config/ddnsto)                                          │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 四、问题详细分析

### 4.1 问题 1：单向数据流

| 方向 | 支持 | 说明 |
|------|------|------|
| 快速向导 → UCI | ✅ | 通过 `api_onboarding_address` 写入 |
| ddnsto 服务器 → UCI | ❌ | 无同步机制 |
| UCI → ddnsto 服务器 | ❌ | 无同步机制 |

**后果**：
- 用户在 ddnsto 控制台修改/删除域名后，本地 UCI 中的 `address` 字段不会更新
- LuCI 界面始终显示旧的、可能已失效的域名

### 4.2 问题 2：无刷新/同步机制

**检查所有相关代码**：

1. **ddnsto.init 启动脚本**：[ddnsto/files/ddnsto.init](file:///Users/ycl/Desktop/work_sync/ddnsto/release/ddnsto-openwrt-package/ddnsto/files/ddnsto.init)
   - 只读取 `enabled`, `logger`, `token`, `index`, `feat_enabled`
   - **不读取/写入 `address`**

2. **监控脚本**
   - 文档中提及 `ddnsto-monitor.sh`，但实际不存在于代码库中
   - OpenWrt 版本使用 `procd` 进程管理器（`respawn` 参数）实现自动重启，无需单独监控脚本

3. **前端定时刷新**
   - [App.tsx:L204-L209](file:///Users/ycl/Desktop/work_sync/ddnsto/src/ddnsto-openwrt-web/src/App.tsx#L204-L209)
   - 每 5 秒调用 `fetchStatus()`，但只获取本地状态，**不从服务器同步**

### 4.3 问题 3：快速向导始终显示

**预期行为**（根据注释）：已配置时快速向导应折叠

**实际行为**：快速向导始终显示完整内容

**代码分析**：[OnboardingWizardCard.tsx:L242-L249](file:///Users/ycl/Desktop/work_sync/ddnsto/src/ddnsto-openwrt-web/src/App.tsx#L242-L249)

```tsx
// App.tsx 中无条件渲染
<OnboardingWizardCard 
  apiBase={apiBase}
  csrfToken={csrfToken}
  deviceId={deviceId}
  onboardingBase={onboardingBase}
  onRefreshStatus={refreshStatusAndConfig}
  onComplete={() => setIsConfigured(true)}
/>
```

组件内部没有根据 `isConfigured` 状态进行折叠的逻辑。

---

## 五、影响范围

### 5.1 用户体验问题

| 场景 | 问题描述 |
|------|----------|
| 用户在控制台删除域名 | LuCI 仍显示旧域名，点击无法访问 |
| 用户在控制台修改域名 | LuCI 显示旧域名，新域名不可见 |
| 用户重新绑定设备 | 新域名无法自动同步到 LuCI |

### 5.2 技术债务

1. **数据不一致**：本地 UCI 与远程服务器状态不一致
2. **无法自动恢复**：域名变更后需要用户手动重新走快速向导
3. **误导性展示**：显示"远程访问域名"但可能已失效

---

## 六、修复建议

### 方案 1：从 ddnstod 二进制获取真实地址（推荐）

检查 ddnstod 是否支持输出当前绑定的域名：

```bash
# 假设 ddnstod 支持以下命令
/usr/sbin/ddnstod -x 0 --get-address
```

然后在 `api_status()` 中调用并返回：

```lua
function api_status()
  ...
  -- 从 ddnstod 获取真实地址
  local real_address = get_command("/usr/sbin/ddnstod -x " .. index .. " --get-address")
  
  write_json({
    ...
    data = {
      ...
      address = real_address ~= "" and real_address or address,
      ...
    }
  })
end
```

### 方案 2：定期从服务器同步

在 `api_status()` 中添加从 ddnsto API 查询域名的逻辑：

```lua
function api_status()
  ...
  -- 查询 ddnsto 服务器获取最新域名
  local server_address = fetch_address_from_server(token)
  
  -- 如果与本地不一致，更新本地配置
  if server_address ~= "" and server_address ~= address then
    local sid = ensure_ddnsto_section()
    uci:set("ddnsto", sid, "address", server_address)
    uci:commit("ddnsto")
    address = server_address
  end
  ...
end
```

### 方案 3：前端直接查询（iframe 通信）

修改快速向导组件，在每次加载时从 iframe 获取最新域名：

```typescript
useEffect(() => {
  // 向 iframe 发送消息请求当前域名
  iframeRef.current?.contentWindow?.postMessage(
    { action: 'getDomain' },
    'https://www.kooldns.cn'
  );
}, []);
```

### 方案 4：移除 address 展示

如果无法可靠获取，考虑从状态卡片中移除"远程访问域名"展示，或添加提示：

```tsx
{address ? (
  <div>
    <span>远程访问域名：</span>
    <a href={address} target="_blank">{address}</a>
    <span className="text-warning">（如已失效请重新运行快速向导）</span>
  </div>
) : (
  <span>未配置（请运行快速向导获取域名）</span>
)}
```

---

## 七、结论

### 7.1 核心问题

1. **`address` 字段只能从快速向导单向写入**，没有同步/刷新机制
2. **ddnsto 服务器与本地 UCI 数据可能不一致**
3. **用户在其他平台修改域名后，LuCI 界面不会更新**

### 7.2 设计缺陷总结

| 缺陷 | 说明 |
|------|------|
| 单向数据流 | 只能从快速向导写入，无法从服务器同步 |
| 无监控机制 | 启动脚本不检查/更新 address |
| 前端展示依赖过期数据 | 只读取 UCI，不验证有效性 |
| 快速向导无法折叠 | 已配置用户仍需看到完整向导 |

### 7.3 建议优先级

1. **高优先级**：实现从 ddnstod 获取真实地址（方案 1）
2. **中优先级**：添加数据过期提示（方案 4）
3. **低优先级**：修复快速向导折叠功能

---

## 八、附录：相关代码引用

### 8.1 后端 API 代码

```lua
-- luci-app-ddnsto/luasrc/controller/ddnsto.lua

-- 唯一写入 address 的接口
function api_onboarding_address()
  local http = require "luci.http"
  local uci = require "luci.model.uci".cursor()
  ...
  local url = param(body, "url") or param(body, "address")
  ...
  local sid = ensure_ddnsto_section()
  uci:set("ddnsto", sid, "address", url)  -- 唯一写入点
  uci:commit("ddnsto")
  ...
end

-- 读取 address 的接口
function api_status()
  ...
  uci:foreach("ddnsto", "ddnsto", function(s)
    address = s.address or ""  -- 只从 UCI 读取
  end)
  ...
  write_json({
    ...
    data = {
      address = address,  -- 可能已过期
      ...
    }
  })
end
```

### 8.2 前端代码

```typescript
// src/ddnsto-openwrt-web/src/App.tsx

const fetchStatus = useCallback(async () => {
  const res = await fetch(`${apiBase}/admin/services/ddnsto/api/status`, {
    credentials: 'same-origin',
  });
  const json = await res.json();
  const data = json?.data || {};
  
  setIsRunning(!!data.running);
  if (data.token_set) setIsConfigured(true);
  if (data.address) setAddress(data.address);  // 使用可能过期的数据
  ...
}, [apiBase]);
```

---

**报告完成时间**：2026-05-12  
**分析人员**：AI Assistant  
**相关版本**：ddnsto-openwrt-package  
