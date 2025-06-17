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
  read -p "请输入 RPC_URL（例如 https://sepolia.infura.io/v3/<YOUR_PROJECT_ID> 或 Alchemy RPC）: " rpc_url
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

  # 检查是否安装 Git
  if ! command -v git &> /dev/null; then
    log "安装 Git..."
    sudo apt update
    sudo apt install -y git >> "$LOG_FILE" 2>&1 || {
      log "Git 安装失败，请检查日志 $LOG_FILE"
      exit 1
    }
    log "Git 安装完成"
  fi

  # 克隆 Boundless 仓库
  if [ ! -d "$HOME/boundless" ]; then
    log "克隆 Boundless 仓库..."
    git clone https://github.com/boundless-xyz/boundless "$HOME/boundless" >> "$LOG_FILE" 2>&1 || {
      log "克隆 Boundless 仓库失败，请检查日志 $LOG_FILE"
      exit 1
    }
    cd "$HOME/boundless"
    git checkout release-0.10 >> "$LOG_FILE" 2>&1 || {
      log "切换到 release-0.10 分支失败，请检查日志 $LOG_FILE"
      exit 1
    }
    log "Boundless 仓库克隆完成"
  else
    log "Boundless 仓库已存在"
    cd "$HOME/boundless"
  fi

  # 安装 Rust
  if ! command -v cargo &> /dev/null; then
    log "安装 Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >> "$LOG_FILE" 2>&1 || {
      log "Rust 安装失败，请检查日志 $LOG_FILE"
      exit 1
    }
    source "$HOME/.cargo/env"
    log "Rust 安装完成"
  else
    log "Rust 已安装"
  fi

  # 安装 Risc0
  if ! command -v rzup &> /dev/null; then
    log "安装 Risc0..."
    curl -L https://risczero.com/install | bash >> "$LOG_FILE" 2>&1 || {
      log "Risc0 安装失败，请检查日志 $LOG_FILE"
      exit 1
    }
    # 显式设置 PATH
    export PATH="$HOME/.risc0/bin:$PATH"
    if ! grep -q 'export PATH="$HOME/.risc0/bin:$PATH"' "$HOME/.bashrc"; then
      echo 'export PATH="$HOME/.risc0/bin:$PATH"' >> "$HOME/.bashrc"
      log "Risc0 PATH 已写入 ~/.bashrc"
    fi
    source "$HOME/.bashrc"
    if ! command -v rzup &> /dev/null; then
      log "错误：rzup 命令不可用，请检查安装日志 $LOG_FILE"
      exit 1
    }
    log "安装 Risc0 工具链..."
    rzup install >> "$LOG_FILE" 2>&1 || {
      log "Risc0 工具链安装失败，请检查日志 $LOG_FILE"
      exit 1
    }
    log "Risc0 安装完成"
  else
    log "Risc0 已安装"
  fi

  # 安装 Bento 客户端
  if ! command -v bento_cli &> /dev/null; then
    log "安装 Bento 客户端..."
    cargo install --git https://github.com/risc0/risc0 bento-client --bin bento_cli >> "$LOG_FILE" 2>&1 || {
      log "Bento 客户端安装失败，请检查日志 $LOG_FILE"
      exit 1
    }
    log "Bento 客户端安装完成"
  else
    log "Bento 客户端已安装"
  fi

  # 设置 Cargo PATH
  export PATH="$HOME/.cargo/bin:$PATH"
  if ! grep -q 'export PATH="$HOME/.cargo/bin:$PATH"' "$HOME/.bashrc"; then
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$HOME/.bashrc"
    source "$HOME/.bashrc"
    log "Cargo PATH 已更新并写入 ~/.bashrc"
  fi

  # 安装 Boundless CLI
  if ! command -v boundless &> /dev/null; then
    log "安装 Boundless CLI..."
    cargo install --locked boundless-cli >> "$LOG_FILE" 2>&1 || {
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

  # 设置 Boundless 环境变量（VERIFIER_ADDRESS 等）
  log "设置 Boundless 环境变量..."
  cd "$HOME/boundless"
  boundless config set-env --network sepolia >> "$LOG_FILE" 2>&1 || {
    log "设置 Boundless 环境变量失败，请检查日志 $LOG_FILE"
    exit 1
  }
  log "Boundless 环境变量设置完成"

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

  # 在 screen 会话中运行 Boundless Broker
  log "启动 Boundless Broker 在 screen 会话中..."
  screen -dmS boundless boundless broker start >> "$LOG_FILE" 2>&1
  if [ $? -eq 0 ]; then
    log "Boundless Broker 已启动，screen 会话名称为 'boundless'"
    log "使用 'screen -r boundless' 查看会话"
  else
    log "Boundless Broker 启动失败，请检查日志 $LOG_FILE"
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
  if [ -z "$RPC_URL" ]; then
    log "错误：RPC_URL 未定义"
    return 1
  fi
  boundless account deposit-stake 10 >> "$LOG_FILE" 2>&1 || {
    log "质押失败，请检查日志 $LOG_FILE"
    log "提示：请确保账户有足够的 USDC 和 ETH（可通过 https://faucet.circle.com 领取 Sepolia 测试 USDC）"
    log "尝试使用显式 RPC_URL 重试..."
    boundless --rpc-url "$RPC_URL" account deposit-stake 10 >> "$LOG_FILE" 2>&1 || {
      log "使用显式 RPC_URL 质押仍失败，请检查日志 $LOG_FILE"
      return 1
    }
    log "质押操作已完成（使用显式 RPC_URL）"
    return 0
  }
  log "质押操作已完成"
}

# 查看钱包余额
check_balance() {
  log "查看钱包 ETH 和 USDC 余额..."
  source "$ENV_FILE"
  if [ -z "$RPC_URL" ]; then
    log "错误：RPC_URL 未定义"
    return 1
  fi
  boundless account balance >> "$LOG_FILE" 2>&1 || {
    log "查询余额失败，请检查日志 $LOG_FILE"
    log "提示：请确保账户有足够的 USDC 和 ETH（可通过 https://faucet.circle.com 领取 Sepolia 测试 USDC）"
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

  # 卸载 Boundless CLI 和 Bento 客户端
  log "卸载 Boundless CLI 和 Bento 客户端..."
  cargo uninstall boundless-cli >> "$LOG_FILE" 2>&1 || {
    log "警告：Boundless CLI 卸载失败，请检查日志 $LOG_FILE"
  }
  cargo uninstall bento-client >> "$LOG_FILE" 2>&1 || {
    log "警告：Bento 客户端卸载失败，请检查日志 $LOG_FILE"
  }
  log "Boundless CLI 和 Bento 客户端卸载完成"

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
    echo "1. 安装节点，配置 RPC_URL 和 PRIVATE_KEY，并在 screen 中运行 Boundless Broker"
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
