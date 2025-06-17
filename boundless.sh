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

# 安装并运行 Boundless CLI
install_and_run() {
  log "开始安装和运行 Boundless 节点..."

  # 检查是否已安装 Boundless CLI
  if ! command -v boundless &> /dev/null; then
    log "未检测到 Boundless CLI，正在安装..."

    # 安装 Node.js 和 npm
    if ! command -v npm &> /dev/null; then
      log "安装 Node.js 和 npm..."
      sudo apt update
      sudo apt install -y nodejs npm >> "$LOG_FILE" 2>&1 || {
        log "Node.js 和 npm 安装失败，请检查日志 $LOG_FILE"
        exit 1
      }
      log "Node.js 和 npm 安装完成"
    fi

    # 安装 Boundless CLI
    log "安装 Boundless CLI..."
    npm install -g @boundlessprotocol/cli >> "$LOG_FILE" 2>&1 || {
      log "Boundless CLI 安装失败，请检查日志 $LOG_FILE"
      exit 1
    }
    log "Boundless CLI 安装完成"
  else
    log "Boundless CLI 已安装"
  fi

  # 配置环境变量
  configure_env || {
    log "环境变量配置失败"
    exit 1
  }

  # 检查 screen 是否安装
  if ! command -v screen &> /dev/null; then
    log "安装 screen..."
    sudo apt update
    sudo apt install -y screen >> "$LOG_FILE" 2>&1 || {
      log "screen 安装失败，请检查日志 $LOG_FILE"
      exit 1
    }
    log "screen 安装完成"
  fi

  # 在 screen 会话中运行 Boundless CLI
  log "启动 Boundless CLI 在 screen 会话中..."
  screen -dmS boundless boundless start --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" >> "$LOG_FILE" 2>&1
  if [ $? -eq 0 ]; then
    log "Boundless CLI 已启动，screen 会话名称为 'boundless'"
    log "使用 'screen -r boundless' 查看会话"
  else
    log "Boundless CLI 启动失败，请检查日志 $LOG_FILE"
    exit 1
  fi
}

# 查看日志
view_logs() {
  log "查看日志 $LOG_FILE ..."
  if [ -f "$LOG_FILE" ]; then
    less "$LOG_FILE"
  else
    log "日志文件 $LOG_FILE 不存在"
  fi
}

# 发起质押
deposit_stake() {
  log "发起质押 (boundless account deposit-stake 10)..."
  source "$ENV_FILE"
  boundless --rpc-url "$RPC_URL" account deposit-stake 10 >> "$LOG_FILE" 2>&1 || {
    log "质押失败，请检查日志 $LOG_FILE"
    return 1
  }
  log "质押操作已完成"
}

# 查看钱包余额
check_balance() {
  log "查看钱包 ETH 和 USDC 余额..."
  source "$ENV_FILE"
  boundless account balance >> "$LOG_FILE" 2>&1 || {
    log "查询余额失败，请检查日志 $LOG_FILE"
    return 1
  }
  log "余额查询完成，查看日志 $LOG_FILE 获取详情"
}

# 删除节点和会话
delete_node_and_session() {
  log "删除节点和会话..."

  # 终止 screen 会话
  if screen -list | grep -q "boundless"; then
    screen -S boundless -X quit >> "$LOG_FILE" 2>&1
    log "已终止 screen 会话 'boundless'"
  else
    log "未找到 screen 会话 'boundless'"
  fi

  # 卸载 Boundless CLI
  log "卸载 Boundless CLI..."
  npm uninstall -g @boundlessprotocol/cli >> "$LOG_FILE" 2>&1 || {
    log "警告：Boundless CLI 卸载失败，请检查日志 $LOG_FILE"
  }
  log "Boundless CLI 卸载完成"

  # 删除 Boundless 目录及其内容
  if [ -d "$HOME/boundless" ]; then
    log "删除 Boundless 目录 $HOME/boundless..."
    rm -rf "$HOME/boundless" >> "$LOG_FILE" 2>&1 || {
      log "错误：无法删除 $HOME/boundless，请检查权限或日志 $LOG_FILE"
    }
    log "Boundless 目录已删除"
  else
    log "Boundless 目录 $HOME/boundless 不存在"
  fi

  # 删除日志文件（在最后删除，避免丢失日志）
  if [ -f "$LOG_FILE" ]; then
    log "删除日志文件 $LOG_FILE..."
    rm "$LOG_FILE" >> /dev/null 2>&1 || {
      log "错误：无法删除日志文件 $LOG_FILE"
    }
    log "日志文件已删除"
  else
    log "日志文件 $LOG_FILE 不存在"
  fi

  log "节点和会话清理完成"
  log "请检查以下文件是否已删除："
  log "- $ENV_FILE"
  log "- $LOG_FILE"
  log "- $HOME/boundless"
}

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
main_menu
