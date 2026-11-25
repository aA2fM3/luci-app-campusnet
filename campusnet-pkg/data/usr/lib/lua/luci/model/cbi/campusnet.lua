local m, s, o

m = Map("campusnet", translate("CampusNet 校园网认证"),
	translate("连接指定 WiFi 后自动检测网络并完成网页认证，必要时可设置 MTU。"))

-- 实时状态区
s = m:section(SimpleSection, translate("运行状态"))
s.template = "campusnet/status"

-- ============ 基本设置 ============
s = m:section(TypedSection, "campusnet", translate("基本设置"))
s.addremove = false
s.anonymous = true

o = s:option(Flag, "enabled", translate("启用"), translate("总开关。关闭后不进行检测与认证。"))
o.rmempty = false
o.default = "1"

o = s:option(Value, "ssid", translate("WiFi 名 (SSID)"),
	translate("WiFi 的名称。路由器连接这个名称的 WiFi 时进行认证。"))
o.datatype = "minlength(1)"
o.placeholder = translate("请输入 WiFi 名称")

o = s:option(Value, "bssid", translate("接入点标识 (BSSID)"),
	translate("无线接入点（AP）的 MAC 地址，格式 AA:BB:CC:DD:EE:FF。通常无需填写，留空时按 WiFi 名称识别。"))
o.placeholder = translate("通常留空")

o = s:option(Value, "user_id", translate("上网账号 / 学号"),
	translate("填写学号或账号本身，无需添加前缀和后缀，系统会按所选运营商自动组成完整账号。"))
o.datatype = "minlength(1)"
o.placeholder = translate("请输入学号")

o = s:option(ListValue, "isp", translate("运营商"),
	translate("选择账号对应的运营商。"))
o:value("none", translate("校园网 / 不带运营商（无后缀）"))
o:value("unicom", translate("中国联通（后缀 @unicom）"))
o:value("cmcc", translate("中国移动（后缀 @cmcc）"))
o:value("telecom", translate("中国电信（后缀 @telecom）"))
o:value("custom", translate("自定义后缀"))
o.default = "none"

o = s:option(Value, "isp_suffix", translate("自定义运营商后缀"),
	translate("选择自定义运营商时填写，需包含 @ 符号，例如 @abc。"))
o.placeholder = "@xxx"
o:depends("isp", "custom")

o = s:option(Value, "password", translate("登录密码 / 密文"),
	translate("填写登录密码；如认证使用密文则填写密文。"))
o.password = true

o = s:option(Flag, "mtu_enable", translate("自定义 MTU"),
	translate("关闭时保持系统默认 1500。开启后对当前 WiFi 的接口应用下面的 MTU 值。"))
o.rmempty = false
o.default = "0"

o = s:option(Value, "mtu", translate("MTU 值"),
	translate("MTU 值，默认 1280，范围 576–1500。"))
o.datatype = "range(576,1500)"
o.default = "1280"
o:depends("mtu_enable", "1")

o = s:option(Value, "probe_ip", translate("探活目标 IP"),
	translate("用于判断网络是否连通的 IP 地址。默认 223.5.5.5，直接 ping 该地址，不依赖域名解析。"))
o.datatype = "ipaddr"
o.default = "223.5.5.5"

o = s:option(Value, "probe_count", translate("探活 ping 包数"),
	translate("每次检测发送的 ping 包数。"))
o.datatype = "range(1,10)"
o.default = "3"

o = s:option(Value, "check_interval", translate("定时检测间隔（分钟）"),
	translate("定时检测的时间间隔，默认 10。连接或重连时会立即检测。"))
o.datatype = "range(1,60)"
o.default = "10"

-- ============ 高级设置 ============
s = m:section(TypedSection, "campusnet", translate("高级设置"),
	translate("账号前缀、认证地址与超时。一般保持默认即可。"))
s.addremove = false
s.anonymous = true

o = s:option(Value, "account_raw", translate("完整账号（可选）"),
	translate("留空时由学号和运营商自动组成。如已知道完整账号，可在此直接填写。"))
o.placeholder = translate("通常留空")

o = s:option(Flag, "prefix_enable", translate("添加账号前缀"),
	translate("开启后在账号前添加下面的前缀。"))
o.rmempty = false
o.default = "1"

o = s:option(Value, "prefix", translate("账号前缀"),
	translate("账号前缀，默认 ,0,。"))
o.default = ",0,"
o:depends("prefix_enable", "1")

o = s:option(Value, "new_base", translate("HTTPS 认证地址"))
o.placeholder = translate("请输入认证服务器地址")

o = s:option(Value, "old_base", translate("HTTP 认证地址"))
o.placeholder = translate("请输入认证服务器地址")

o = s:option(Value, "connect_timeout", translate("连接超时（秒）"))
o.datatype = "range(2,30)"
o.default = "5"

o = s:option(Value, "max_timeout", translate("请求超时（秒）"))
o.datatype = "range(3,60)"
o.default = "10"

return m
