#!/bin/bash

set -e  # 遇到错误时退出

# 日志文件路径
LOG_FILE="$HOME/boundless_install.log"
# 统一指定 .env.eth-sepolia 文件路径
ENV_FILE="$HOME/boundless/.env.eth-sepolia"

# 记录日志的函数
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
  echo "$1"
}

# 验证 RPC_URL 和 PRIVATE_KEY 的函数
validate_env() {
  local rpc_url=$1
  local private_key=$2

  if [ -z "$rpc_url" ]; then
    log "错误：RPC_URL 不能为空"
    return 1
  fi

  log "验证 RPC_URL: $rpc_url ..."
  if ! curl -s -H "Content-Type: application/json" -X POST --data '{"jsonrpc":"2.0","method":"net_version","id":1}' "$rpc_url" | grep -q '"result":"11155111"'; then
    log "错误：RPC_URL 无效或不是 Sepolia 网络（链 ID 11155111）"
    return 1
  fi
  log "RPC_URL 验证通过"

  if [ -z "$private_key" ]; then
    log "错误：PRIVATE_KEY 不能为空"
    return 1
  fi
  if [[ ! "$private_key" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    log "错误：PRIVATE_KEY 格式无效，必须是 64 位十六进制字符串（以 0x 开头）"
    return 1
  fi
  log "PRIVATE_KEY 验证通过"
}

# 配置 RPC_URL 和 PRIVATE_KEY 的函数
configure_env() {
  if [ -n "$RPC_URL" ] && [ -n "$PRIVATE_KEY" ]; then
    log "检测到环境变量 RPC_URL 和 PRIVATE_KEY，使用现有配置"
    validate_env "$RPC_URL" "$PRIVATE_KEY" || { log "环境变量验证失败"; exit 1; }
    if [ ! -f "$ENV_FILE" ]; then
      log "创建 $ENV_FILE 文件..."
      mkdir -p "$(dirname "$ENV_FILE")"
      cat <<EOL > "$ENV_FILE"
RPC_URL="$RPC_URL"
PRIVATE_KEY="$PRIVATE_KEY"
EOL
      log "$ENV_FILE 已创建"
    fi
    source "$ENV_FILE"
    return 0
  fi

  if [ -f "$ENV_FILE" ]; then
    log "$ENV_FILE 已存在"
    read -p "是否重新配置 RPC_URL 和 PRIVATE_KEY？(y/n): " reconfigure
    if [ "$reconfigure" != "y" ]; then
      log "使用现有 $ENV_FILE 文件"
      source "$ENV_FILE"
      validate_env "$RPC_URL" "$PRIVATE_KEY" || { log "环境变量验证失败"; exit 1; }
      return 0
    fi
  fi

  log "配置 $ENV_FILE 文件..."
  read -p "请输入 RPC_URL（例如 https://sepolia.infura.io/v3/<YOUR_PROJECT_ID>）: " rpc_url
  read -p "请输入 PRIVATE_KEY（以 0x 开头的 64 位十六进制字符串）: " private_key

  validate_env "$rpc_url" "$private_key" || { log "输入验证失败"; exit 1; }

  mkdir -p "$(dirname "$ENV_FILE")"
  cat <<EOL > "$ENV_FILE"
RPC_URL="$rpc_url"
PRIVATE_KEY="$private_key"
EOL
  log "$ENV_FILE 已更新，请确认内容"

  log "使配置文件生效..."
  source "$ENV_FILE"
  log "配置文件已生效"
}

# 其他函数（check_balance, deposit_stake, install_and_run, delete_node_and_session, view_logs）保持不变，但需替换 --rpc-info 为 --rpc-url（若适用）

# 主菜单
main_menu() {
  while true; do
    echo "=== Boundless 安装与管理菜单 ==="
    echo "1. 安装节点，配置 RPC_URL 和 PRIVATE_KEY，并在 screen 中运行 Boundless CLI"
    echo "2. 查看日志"
    echo "3. 配置或更新 RPC_URL 和 PRIVATE_KEY"
    echo "4. 发起质押 (boundless account deposit-stake 10)"
    echo "5. 查看钱包 ETH 和 USDC 余额"
    echo "6. 删除节点和会话"
    echo "7. 退出"
    read -p "请选择操作 (1-7): " choice

    case $choice in
      1)
        install_and_run
        ;;
      2)
        view_logs
        ;;
      3)
        configure_env
        ;;
      4)
        deposit_stake
        ;;
      5)
        check_balance
        ;;
      6)
        delete_node_and_session
        ;;
      7)
        log "退出脚本"
        exit 0
        ;;
      *)
        log "无效选项，请输入 1-7"
        ;;
    esac
  done
}

# 脚本入口
if [ "$1" = "--auto-install" ]; then
  log "执行一键安装..."
  install_and_run
  exit 0
fi

# 初始化日志文件
touch "$LOG_FILE"
log "脚本启动"

# 启动主菜单
main
