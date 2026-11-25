module("luci.controller.campusnet", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/campusnet") then
		return
	end

	entry({"admin", "services", "campusnet"}, cbi("campusnet"), _("校园网认证"), 30).dependent = true
	entry({"admin", "services", "campusnet_help"}, template("campusnet/help"), _("校园网-使用说明"), 31)
	entry({"admin", "services", "campusnet_status"}, call("campusnet_status"))
	entry({"admin", "services", "campusnet_run"}, call("campusnet_run"))
end

-- 返回核心脚本的 JSON 状态
function campusnet_status()
	local json = luci.sys.exec("/usr/libexec/campusnet/campusnet.sh status 2>/dev/null")
	luci.http.prepare_content("application/json")
	if json and #json > 0 then
		luci.http.write(json)
	else
		luci.http.write('{"found":0,"online":0}')
	end
end

-- 立即执行一次强制认证
function campusnet_run()
	luci.sys.call("/usr/libexec/campusnet/campusnet.sh force >/dev/null 2>&1")
	luci.http.prepare_content("application/json")
	luci.http.write('{"done":1}')
end
