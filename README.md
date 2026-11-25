# 伊犁师范大学luci校园网自动认证插件

面向使用 **Dr.COM / eportal 网页认证**校园网的 OpenWrt / LuCI 路由器插件。
路由器连接校园网 WiFi 后自动完成网页登录，网络断开时重新认证，全程图形界面配置，无需手动打开认证网页。

## 功能特性

- 按 WiFi 名（SSID）识别使用的无线网络；可选填 BSSID 指定接入点，默认留空。
- 连接 / 重连 WiFi 时立即检测，无法连通时重新认证。
- 按设定间隔定时检测，默认 10 分钟。
- 路由器开机后自动运行。
- 账号只需填写学号并选择运营商，自动组成含前缀（默认 `,0,`）和后缀（`@unicom` / `@cmcc` / `@telecom`）的完整账号。
- MTU 开关默认关闭、保持 1500；开启后仅对当前 WiFi 的接口应用设定值（默认 1280）。
- 优先使用 HTTPS 认证地址，不可用时使用 HTTP 地址。
- 探活默认 ping `223.5.5.5`，直接 ping IP，不依赖域名解析。
- 可在软件包中完整安装 / 卸载，卸载会移除开机启动和定时任务。

## 安装

将 `luci-app-campusnet_1.0.0-1_all.ipk` 上传到路由器后：

```sh
opkg update
opkg install luci-app-campusnet_1.0.0-1_all.ipk
```

依赖 `curl`、`jsonfilter`、`iwinfo`，opkg 会自动补装。
安装后菜单入口：**服务 → 校园网认证**，另有 **校园网-使用说明** 页面。

## 使用步骤

1. 在“无线”中让路由器连接学校的 WiFi。
2. 打开“服务 → 校园网认证”：
   - 填写 WiFi 名（SSID）。
   - 在上网账号 / 学号中填写学号，无需添加前缀和后缀。
   - 选择运营商，填写登录密码。
   - 填写认证地址（HTTPS / HTTP）。
3. 点“保存并应用”，再点“立即测试/登录”，看到“外网状态：在线”即完成。

## 配置项说明（UCI：/etc/config/campusnet）

| 选项 | 含义 | 默认 |
|---|---|---|
| enabled | 总开关 | 1 |
| ssid | WiFi 名称（需填写） | 空 |
| bssid | 接入点 MAC，留空按 WiFi 名称识别 | 空 |
| user_id | 学号 / 账号本身（需填写） | 空 |
| isp | 运营商：none/unicom/cmcc/telecom/custom | none |
| isp_suffix | 自定义后缀（含 @） | 空 |
| prefix_enable | 是否添加账号前缀 | 1 |
| prefix | 账号前缀 | ,0, |
| account_raw | 完整账号，留空自动组成 | 空 |
| password | 登录密码 / 密文（需填写） | 空 |
| mtu_enable | MTU 开关 | 0 |
| mtu | MTU 值 | 1280 |
| probe_ip | 探活目标 IP | 223.5.5.5 |
| probe_count | 探活 ping 包数 | 3 |
| check_interval | 定时检测间隔（分钟） | 10 |
| new_base | HTTPS 认证地址（需填写） | 空 |
| old_base | HTTP 认证地址（需填写） | 空 |
| connect_timeout | 连接超时（秒） | 5 |
| max_timeout | 请求超时（秒） | 10 |

## 工作原理

- `hotplug.d/iface`：监听网络连接 / 断开事件，连接后执行检测。
- `init.d/campusnet`：开机服务，维护定时任务并在后台等待目标 WiFi。
- `usr/libexec/campusnet/campusnet.sh`：核心逻辑（识别、探活、认证、MTU、状态）。
- 状态以 JSON 输出，供 LuCI 每 5 秒刷新。

命令行手动操作：

```sh
/usr/libexec/campusnet/campusnet.sh run     # 检测并按需认证
/usr/libexec/campusnet/campusnet.sh force   # 强制登录
/usr/libexec/campusnet/campusnet.sh status  # 查看 JSON 状态
/usr/libexec/campusnet/campusnet.sh mtu     # 仅设置 MTU
```

## 卸载

```sh
opkg remove luci-app-campusnet
```

## 适配说明

- 架构无关（Architecture: all），适用于带 LuCI 的 OpenWrt 系固件。
- 认证地址、端口、路径、账号规则因学校而异，部署时按本校实际情况填写。
- 密码在 UCI 中以明文 / 密文形式存储，请注意路由器本身的访问安全。
