#!/bin/sh
# ============================================================
# campusnet 核心脚本（校园网 Dr.COM 自动认证 + MTU 联动）
# 用法:
#   campusnet.sh run     正常单次：识别SSID→设MTU→IP探活→按需登录（默认）
#   campusnet.sh force   跳过探活，强制登录一次
#   campusnet.sh mtu     仅识别SSID并设置MTU
#   campusnet.sh status  输出JSON状态（供LuCI调用）
# 说明：默认按 SSID 识别对应的无线接口；
#       可选填 BSSID 做额外校验。账号填写学号并选择运营商，前缀后缀自动组成。
# 兼容：busybox ash / POSIX sh
# ============================================================

LOG=/tmp/campusnet.log
STATE=/tmp/campusnet.state
ACTION=${1:-run}

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

# ---------- 读取 UCI 配置（缺失时给默认值）----------
cfg() {
    v=$(uci -q get "campusnet.main.$1" 2>/dev/null)
    if [ -z "$v" ]; then
        case "$1" in
            enabled) v=1 ;;
            ssid) v='' ;;
            user_id) v='' ;;
            isp) v='none' ;;
            isp_suffix) v='' ;;
            prefix_enable) v=1 ;;
            prefix) v=',0,' ;;
            account_raw) v='' ;;
            account) v='' ;;
            bssid) v='' ;;
            mtu_enable) v=0 ;;
            mtu) v=1280 ;;
            probe_ip) v=223.5.5.5 ;;
            probe_count) v=3 ;;
            check_interval) v=10 ;;
            new_base) v='' ;;
            old_base) v='' ;;
            connect_timeout) v=5 ;;
            max_timeout) v=10 ;;
            *) v='' ;;
        esac
    fi
    echo "$v"
}

ENABLED=$(cfg enabled)
WANT_SSID=$(cfg ssid)
WANT_BSSID=$(cfg bssid)
MTU_ENABLE=$(cfg mtu_enable)
WANT_MTU=$(cfg mtu)
PROBE_IP=$(cfg probe_ip)
PROBE_COUNT=$(cfg probe_count)
NEW_BASE=$(cfg new_base)
OLD_BASE=$(cfg old_base)
CT=$(cfg connect_timeout)
MT=$(cfg max_timeout)
PASSWD=$(cfg password)
EP_PATH=/eportal/portal
CHAN=auto
ACCOUNT=""

# ---------- 组装登录账号 ----------
# 优先级：高级“完整账号” > 学号+运营商自动拼接 > 旧版 account 字段
# 完整格式：前缀(默认 ,0,) + 学号 + 运营商后缀(@unicom/@cmcc/@telecom/自定义)
build_account() {
    raw=$(cfg account_raw)
    if [ -n "$raw" ]; then
        ACCOUNT="$raw"
        return 0
    fi
    uid=$(cfg user_id)
    if [ -n "$uid" ]; then
        pre=""
        if [ "$(cfg prefix_enable)" = "1" ]; then
            pre=$(cfg prefix)
            [ -n "$pre" ] || pre=",0,"
        fi
        sfx=""
        case "$(cfg isp)" in
            unicom)  sfx="@unicom" ;;
            cmcc)    sfx="@cmcc" ;;
            telecom) sfx="@telecom" ;;
            custom)  sfx=$(cfg isp_suffix) ;;
            none|*)  sfx="" ;;
        esac
        ACCOUNT="${pre}${uid}${sfx}"
        return 0
    fi
    # 向后兼容：旧版本直接写完整账号
    ACCOUNT=$(cfg account)
}

# ---------- 动态识别：找到连到目标SSID的无线接口 ----------
# 结果写入全局 DEVICE；未找到则 DEVICE 为空
find_device() {
    DEVICE=""
    got=""
    nb="" nw=""
    devs=$(ubus call iwinfo devices 2>/dev/null | jsonfilter -e '@.devices[*]' 2>/dev/null)
    printf '%s' "$WANT_SSID" > /tmp/campusnet_wantssid
    # 目标 BSSID 规范化（去冒号、转小写），留空则不做 BSSID 校验
    if [ -n "$WANT_BSSID" ]; then
        nw=$(printf '%s' "$WANT_BSSID" | tr -d ':' | tr 'A-Z' 'a-z')
    fi
    for d in $devs; do
        # 经命令替换剥离末尾换行，再与目标（printf无换行）比较
        got=$(ubus call iwinfo info "{\"device\":\"$d\"}" 2>/dev/null \
            | jsonfilter -e '@.ssid' 2>/dev/null)
        printf '%s' "$got" > /tmp/campusnet_gotssid
        if cmp -s /tmp/campusnet_gotssid /tmp/campusnet_wantssid; then
            # 可选 BSSID 校验：SSID 相同后再比较 AP 的 MAC
            if [ -n "$nw" ]; then
                cb=$(ubus call iwinfo info "{\"device\":\"$d\"}" 2>/dev/null \
                    | jsonfilter -e '@.bssid' 2>/dev/null)
                nb=$(printf '%s' "$cb" | tr -d ':' | tr 'A-Z' 'a-z')
                [ "$nb" = "$nw" ] || continue
            fi
            DEVICE="$d"
            return 0
        fi
    done
    return 1
}

# ---------- 取该物理接口的 IPv4 地址 ----------
get_ip() {
    ip -4 addr show "$DEVICE" 2>/dev/null \
        | grep -o 'inet [0-9.]*' | head -1 | awk '{print $2}'
}

# ---------- 取当前MTU ----------
get_mtu() {
    ip link show "$DEVICE" 2>/dev/null | grep -o 'mtu [0-9]*' | awk '{print $2}'
}

# ---------- 仅对该接口设置MTU ----------
apply_mtu() {
    [ "$MTU_ENABLE" = "1" ] || return 0
    [ -n "$WANT_MTU" ] && [ "$WANT_MTU" != "0" ] || return 0
    cur=$(get_mtu)
    if [ "$cur" != "$WANT_MTU" ]; then
        ip link set "$DEVICE" mtu "$WANT_MTU" 2>/dev/null && \
            log "接口 $DEVICE MTU: $cur -> $WANT_MTU"
    fi
}

# ---------- IP层探活（不依赖DNS/域名）----------
probe() {
    ping -c "$PROBE_COUNT" -W 2 "$PROBE_IP" >/dev/null 2>&1
}

# ---------- 底层 JSONP 请求 ----------
raw_request() {
    _base="$1"; _action="$2"; _cb="$3"; shift 3
    case "$_base" in
        https://*)
            curl -k -s --connect-timeout "$CT" --max-time "$MT" \
                -G "$_base$EP_PATH/$_action" \
                --data-urlencode "callback=$_cb" "$@" ;;
        *)
            curl -s --connect-timeout "$CT" --max-time "$MT" \
                -G "$_base$EP_PATH/$_action" \
                --data-urlencode "callback=$_cb" "$@" ;;
    esac
}

# ---------- 新通道优先，传输层失败降级旧通道 ----------
smart_request() {
    _action="$1"; _cb="$2"; shift 2
    if [ "$CHAN" != "old" ]; then
        RESP=$(raw_request "$NEW_BASE" "$_action" "$_cb" "$@")
        if [ -n "$RESP" ] && echo "$RESP" | grep -q "$_cb("; then
            CHAN=new; return 0
        fi
        log "HTTPS通道不可用，降级HTTP通道"
        CHAN=old
    fi
    RESP=$(raw_request "$OLD_BASE" "$_action" "$_cb" "$@")
    if [ -n "$RESP" ] && echo "$RESP" | grep -q "$_cb("; then
        return 0
    fi
    log "HTTP通道也不可用"
    return 1
}

do_login() {
    smart_request login dr1003 \
        --data-urlencode "login_method=1" \
        --data-urlencode "user_account=$ACCOUNT" \
        --data-urlencode "user_password=$PASSWD" \
        --data-urlencode "wlan_user_ip=$USER_IP" \
        --data-urlencode "wlan_user_ipv6=" \
        --data-urlencode "wlan_user_mac=000000000000" \
        --data-urlencode "wlan_ac_ip=" \
        --data-urlencode "wlan_ac_name=" \
        --data-urlencode "jsVersion=4.1.3" \
        --data-urlencode "terminal_type=1" \
        --data-urlencode "lang=zh-cn" \
        --data-urlencode "v=3955"
}

do_logout() {
    smart_request logout dr1004 \
        --data-urlencode "login_method=1" \
        --data-urlencode "user_account=drcom" \
        --data-urlencode "user_password=123" \
        --data-urlencode "ac_logout=0" \
        --data-urlencode "register_mode=1" \
        --data-urlencode "wlan_user_ip=$USER_IP" \
        --data-urlencode "wlan_user_ipv6=" \
        --data-urlencode "wlan_vlan_id=0" \
        --data-urlencode "wlan_user_mac=000000000000" \
        --data-urlencode "wlan_ac_ip=" \
        --data-urlencode "wlan_ac_name=" \
        --data-urlencode "jsVersion=4.1.3" \
        --data-urlencode "v=6943"
}

# ---------- 状态输出 ----------
emit_status() {
    build_account
    if find_device; then
        _ip=$(get_ip); _mtu=$(get_mtu)
        if ping -c 1 -W 2 "$PROBE_IP" >/dev/null 2>&1; then _on=1; else _on=0; fi
        printf '{"found":1,"device":"%s","ip":"%s","mtu":%s,"online":%s,"probe":"%s","account":"%s"}\n' \
            "$DEVICE" "$_ip" "$_mtu" "$_on" "$PROBE_IP" "$ACCOUNT"
    else
        printf '{"found":0,"online":0,"account":"%s"}\n' "$ACCOUNT"
    fi
}

if [ "$ACTION" = "status" ]; then
    emit_status
    exit 0
fi

# ---------- 总开关（status除外）----------
if [ "$ENABLED" != "1" ]; then
    log "功能未启用，退出"
    exit 0
fi

# ---------- 组装账号 ----------
build_account
if [ -z "$ACCOUNT" ]; then
    log "未配置账号（学号），本次不处理"
    exit 1
fi

# ---------- 识别SSID对应接口 ----------
if ! find_device; then
    log "未连接到目标SSID（$WANT_SSID），本次不处理"
    exit 0
fi
USER_IP=$(get_ip)
if [ -z "$USER_IP" ]; then
    log "接口 $DEVICE 尚未获取IP，等待下次触发"
    exit 1
fi

# ---------- 设MTU ----------
apply_mtu

if [ "$ACTION" = "mtu" ]; then
    log "仅设置MTU完成，接口=$DEVICE MTU=$(get_mtu)"
    exit 0
fi

# ---------- 探活（force模式跳过）----------
if [ "$ACTION" != "force" ] && probe; then
    log "网络正常（$PROBE_IP可达），无需登录，接口=$DEVICE"
    exit 0
fi

# ---------- 登录 ----------
if ! do_login; then
    log "登录失败：两通道均不可用，接口=$DEVICE IP=$USER_IP"
    exit 1
fi

# 已在线但无法上网时，先注销再重新登录
if echo "$RESP" | grep -q "已经在线"; then
    log "检测到已在线会话，注销后重新登录"
    do_logout >/dev/null 2>&1
    sleep 2
    if ! do_login; then
        log "重新登录失败"
        exit 1
    fi
fi

echo "$RESP" >> "$LOG"
if echo "$RESP" | grep -qE '"result":1|"result": 1'; then
    log "登录成功，通道=$CHAN 账号=$ACCOUNT 接口=$DEVICE IP=$USER_IP"
    exit 0
else
    log "登录可能失败，响应见上一行"
    exit 1
fi
