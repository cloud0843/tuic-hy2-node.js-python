#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# Hysteria2 极简部署脚本（支持命令行端口参数 + 默认跳过证书验证 + 自动下载最新版）
# 适用于超低内存环境（32-64MB）

set -e

# ---------- 默认配置 ----------
HYSTERIA_VERSION=""  # 改为空，自动获取最新版本
DEFAULT_PORT=22222         # 自适应端口
AUTH_PASSWORD="ieshare2025"   # 建议修改为复杂密码
CERT_FILE="cert.pem"
KEY_FILE="key.pem"
SNI="www.bing.com"
ALPN="h3"
# ------------------------------

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "Hysteria2 极简部署脚本（Shell 版）- 自动下载最新版本"
echo "支持命令行端口参数，如：bash hysteria2.sh 443"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

# ---------- 自动获取最新版本号 ----------
get_latest_version() {
    echo "🔍 正在获取 Hysteria2 最新版本号..."
    # 调用GitHub API获取最新版本，兼容网络超时情况
    local latest_version
    latest_version=$(curl -s --max-time 10 https://api.github.com/repos/apernet/hysteria/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    # 若获取失败，降级使用备用方式（直接解析发布页）
    if [ -z "$latest_version" ]; then
        echo "⚠️  API获取版本失败，尝试备用方式..."
        latest_version=$(curl -s --max-time 10 https://github.com/apernet/hysteria/releases/latest | grep -o 'tag/v[0-9.]*' | sed 's/tag\///')
    fi
    
    # 若仍失败，使用保底版本（避免脚本中断）
    if [ -z "$latest_version" ]; then
        echo "⚠️  备用方式也失败，使用保底版本 v2.6.5"
        latest_version="v2.6.5"
    fi
    
    echo "✅ 检测到最新版本: $latest_version"
    echo "$latest_version"
}

# 初始化最新版本号
if [ -z "$HYSTERIA_VERSION" ]; then
    HYSTERIA_VERSION=$(get_latest_version)
fi

# ---------- 获取端口 ----------
if [[ $# -ge 1 && -n "${1:-}" ]]; then
    SERVER_PORT="$1"
    echo "✅ 使用命令行指定端口: $SERVER_PORT"
else
    SERVER_PORT="${SERVER_PORT:-$DEFAULT_PORT}"
    echo "⚙️  未提供端口参数，使用默认端口: $SERVER_PORT"
fi

# ---------- 检测架构 ----------
arch_name() {
    local machine
    machine=$(uname -m | tr '[:upper:]' '[:lower:]')
    if [[ "$machine" == *"arm64"* ]] || [[ "$machine" == *"aarch64"* ]]; then
        echo "arm64"
    elif [[ "$machine" == *"x86_64"* ]] || [[ "$machine" == *"amd64"* ]]; then
        echo "amd64"
    else
        echo ""
    fi
}

ARCH=$(arch_name)
if [ -z "$ARCH" ]; then
  echo "❌ 无法识别 CPU 架构: $(uname -m)"
  exit 1
fi

BIN_NAME="hysteria-linux-${ARCH}"
BIN_PATH="./${BIN_NAME}"

# ---------- 下载二进制（适配最新版本） ----------
download_binary() {
    if [ -f "$BIN_PATH" ]; then
        # 检查现有二进制版本，若不是最新则重新下载
        local current_version
        current_version=$("./$BIN_NAME" version 2>/dev/null | grep -o 'v[0-9.]*' | head -1)
        if [ "$current_version" == "$HYSTERIA_VERSION" ]; then
            echo "✅ 已存在最新版本 ${HYSTERIA_VERSION}，跳过下载。"
            return
        else
            echo "⚠️  现有版本 ${current_version} 不是最新版 ${HYSTERIA_VERSION}，重新下载..."
            rm -f "$BIN_PATH"
        fi
    fi
    
    # 拼接最新版本的下载链接（修复原脚本的链接错误：app/ 是多余的）
    URL="https://github.com/apernet/hysteria/releases/download/${HYSTERIA_VERSION}/${BIN_NAME}"
    echo "⏳ 下载最新版本: $URL"
    # 增加超时重试，适配弱网环境
    curl -L --retry 5 --connect-timeout 30 -o "$BIN_PATH" "$URL"
    chmod +x "$BIN_PATH"
    echo "✅ 最新版本 ${HYSTERIA_VERSION} 下载完成并设置可执行: $BIN_PATH"
}

# ---------- 生成证书 ----------
ensure_cert() {
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
        echo "✅ 发现证书，使用现有 cert/key。"
        return
    fi
    echo "🔑 未发现证书，使用 openssl 生成自签证书（prime256v1）..."
    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -days 3650 -keyout "$KEY_FILE" -out "$CERT_FILE" -subj "/CN=${SNI}"
    echo "✅ 证书生成成功。"
}

# ---------- 写配置文件 ----------
write_config() {
cat > server.yaml <<EOF
listen: ":${SERVER_PORT}"
tls:
  cert: "$(pwd)/${CERT_FILE}"
  key: "$(pwd)/${KEY_FILE}"
  alpn:
    - "${ALPN}"
auth:
  type: "password"
  password: "${AUTH_PASSWORD}"
bandwidth:
  up: "200mbps"
  down: "200mbps"
quic:
  max_idle_timeout: "10s"
  max_concurrent_streams: 4
  initial_stream_receive_window: 65536
  max_stream_receive_window: 131072
  initial_conn_receive_window: 131072
  max_conn_receive_window: 262144
EOF
    echo "✅ 写入配置 server.yaml（端口=${SERVER_PORT}, SNI=${SNI}, ALPN=${ALPN}）。"
}

# ---------- 获取服务器 IP ----------
get_server_ip() {
    IP=$(curl -s --max-time 10 https://api.ipify.org || echo "YOUR_SERVER_IP")
    echo "$IP"
}

# ---------- 打印连接信息 ----------
print_connection_info() {
    local IP="$1"
    echo "🎉 Hysteria2 部署成功！（极简优化版 - 最新版本 ${HYSTERIA_VERSION}）"
    echo "=========================================================================="
    echo "📋 服务器信息:"
    echo "   🌐 IP地址: $IP"
    echo "   🔌 端口: $SERVER_PORT"
    echo "   🔑 密码: $AUTH_PASSWORD"
    echo "   📌 版本: ${HYSTERIA_VERSION}"
    echo ""
    echo "📱 节点链接（SNI=${SNI}, ALPN=${ALPN}, 跳过证书验证）:"
    echo "hysteria2://${AUTH_PASSWORD}@${IP}:${SERVER_PORT}?sni=${SNI}&alpn=${ALPN}&insecure=1#Hy2-Bing-${HYSTERIA_VERSION}"
    echo ""
    echo "📄 客户端配置文件:"
    echo "server: ${IP}:${SERVER_PORT}"
    echo "auth: ${AUTH_PASSWORD}"
    echo "tls:"
    echo "  sni: ${SNI}"
    echo "  alpn: [\"${ALPN}\"]"
    echo "  insecure: true"
    echo "socks5:"
    echo "  listen: 127.0.0.1:1080"
    echo "http:"
    echo "  listen: 127.0.0.1:8080"
    echo "=========================================================================="
}

# ---------- 主逻辑 ----------
main() {
    download_binary
    ensure_cert
    write_config
    SERVER_IP=$(get_server_ip)
    print_connection_info "$SERVER_IP"
    echo "🚀 启动 Hysteria2 服务器（版本 ${HYSTERIA_VERSION}）..."
    exec "$BIN_PATH" server -c server.yaml
}

main "$@"
