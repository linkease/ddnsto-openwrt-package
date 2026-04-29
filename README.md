# DDNSTO OpenWrt Package

DDNSTO 远程访问 OpenWrt 软件包，支持新版本 OpenWrt (SNAPSHOT) 的 apk 包管理器，同时兼容旧版本的 opkg。

## 特性

- ✅ 支持 OpenWrt SNAPSHOT (apk 包格式)
- ✅ 支持 OpenWrt 24.10 / 22.03 (ipk 包格式)
- ✅ 多设备索引支持
- ✅ WebDAV 文件共享
- ✅ 网络连通性检测
- ✅ 现代化 React 管理界面

## 支持的架构

- aarch64_generic
- arm_cortex-a9
- x86_64
- mipsel_24kc

## 安装

### OpenWrt SNAPSHOT (apk)

```bash
# 添加软件源（如果需要）
echo "https://your-repo-url/packages.tar.gz" >> /etc/apk/repositories

# 安装
apk add ddnsto luci-app-ddnsto
```

### OpenWrt 24.10 / 22.03 (opkg/ipk)

```bash
# 添加软件源（如果需要）
echo "src/gz ddnsto https://your-repo-url/packages" >> /etc/opkg/customfeeds.conf
opkg update

# 安装
opkg install ddnsto luci-app-ddnsto
```

## 配置

安装完成后，访问 LuCI 界面：

```
服务 -> DDNSTO 远程控制
```

### 基本配置

1. **Token**: 从 [DDNSTO 官网](https://www.ddnsto.com) 获取
2. **设备索引**: 多设备时设置不同索引（0-99）
3. **启用日志**: 调试时开启

### WebDAV 文件共享

1. 启用 WebDAV
2. 设置端口（默认 3033）
3. 设置用户名和密码
4. 选择共享路径

## 编译

### 本地编译

```bash
# 克隆 OpenWrt SDK
git clone https://github.com/openwrt/openwrt.git
cd openwrt

# 复制软件包到 feeds
cp -r /path/to/ddnsto-openwrt-package package/

# 更新 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 配置
make menuconfig
# 选择: Network -> Web Servers/Proxies -> ddnsto
# 选择: LuCI -> Applications -> luci-app-ddnsto

# 编译
make package/ddnsto/compile V=s
make package/luci-app-ddnsto/compile V=s
```

### GitHub Actions 自动构建

本项目已配置 GitHub Actions，支持自动构建：

1. 推送 tag (`v*`) 触发构建
2. 或手动触发 workflow_dispatch

构建矩阵：
| SDK | 包格式 | 说明 |
|-----|--------|------|
| openwrt-24.10 | ipk | 稳定版，兼容 22.03/24.10 |
| SNAPSHOT | apk | 开发版，使用 apk 包管理器 |

```bash
# 创建并推送 tag
git tag v3.2.1
git push origin v3.2.1
```

## 目录结构

```
ddnsto-openwrt-package/
├── ddnsto/                          # 核心软件包
│   ├── Makefile                     # 构建脚本
│   └── files/
│       ├── ddnsto.init              # procd init 脚本
│       ├── ddnsto.config            # 默认配置
│       └── ddnsto.uci-default       # 首次安装配置
├── luci-app-ddnsto/                 # LuCI 界面
│   ├── Makefile                     # 构建脚本
│   ├── luasrc/
│   │   ├── controller/ddnsto.lua    # 控制器 + API
│   │   ├── model/cbi/ddnsto.lua     # CBI 表单（备选）
│   │   └── view/ddnsto/main.htm     # 主模板
│   ├── po/zh-cn/ddnsto.po           # 中文翻译
│   └── root/
│       ├── etc/uci-defaults/        # 初始化脚本
│       └── www/luci-static/ddnsto/  # React 前端资源
└── .github/workflows/
    └── release-build.yml            # CI/CD 配置
```

## API 接口

LuCI 控制器提供以下 RESTful API：

| 接口 | 方法 | 说明 |
|------|------|------|
| `/api/config` | GET/POST | 读取/更新配置 |
| `/api/status` | GET | 获取运行状态 |
| `/api/service` | POST | 服务控制（start/stop/restart） |
| `/api/logs` | GET | 获取日志 |
| `/api/connectivity` | GET | 网络连通性检测 |

## 迁移说明

本项目从原版 ddnsto 迁移，主要改进：

1. **支持 apk 包格式**: 适配 OpenWrt SNAPSHOT 新包管理器
2. **统一构建**: 使用 GitHub Actions 自动构建多版本
3. **优化 init 脚本**: 使用 procd 进程管理，支持 limits 设置
4. **保留功能**: 完整保留 WebDAV、文件共享等高级功能

## 许可证

- ddnsto: 专有软件（二进制分发）
- luci-app-ddnsto: Apache License 2.0

## 致谢

- 原作者：jjm2473 <jjm2473@gmail.com>
- 改进维护：基于 ddnstox 构建框架适配

## 问题反馈

如有问题，请提交 Issue 或联系维护者。
