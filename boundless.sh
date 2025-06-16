#!/bin/bash

set -e  # 遇到错误时退出

# 日志文件路径
LOG_FILE="$HOME/boundless_install.log"

# 记录日志的函数
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
  echo "$1"
}

# 配置 RPC_URL 和 PRIVATE_KEY 的函数
configure_env() {
  if [ -f ".env.eth-sepolia" ]; then
    log ".env.eth-sepolia 已存在"
    read -p "是否重新配置 RPC_URL 和 PRIVATE_KEY？(y/n): " reconfigure
    if [ "$reconfigure" != "y" ]; then
      log "使用现有 .env.eth-sepolia 文件"
      source .env.eth-sepolia
      return 0
    fi
  fi

  log "配置 .env.eth-sepolia 文件..."
  read -p "请输入 RPC_URL: " rpc_url
  read -p "请输入 PRIVATE_KEY: " private_key

  cat <<EOL > .env.eth-sepolia
RPC_URL="$rpc_url"
PRIVATE_KEY="$private_key"
EOL
  log ".env.eth-sepolia 已更新，请确认内容"

  log "使配置文件生效..."
  source .env.eth-sepolia
  log "配置文件已生效"
}

# 安装节点并运行 Boundless CLI 的函数
install_and_run() {
  log "开始安装 Boundless 环境和 CLI..."

  # 1. 克隆 Boundless 仓库
  log "克隆 Boundless 仓库..."
  if [ -d "boundless" ]; then
    log "boundless 目录已存在，跳过克隆"
    cd boundless
  else
    git clone https://github.com/boundless-xyz/boundless || { log "克隆失败"; exit 1; }
    cd boundless
  fi
  git checkout release-0.10 || { log "切换到 release-0.10 分支失败"; exit 1; }

  # 2. 安装 Rust
  log "安装 Rust..."
  if command -v rustc >/dev/null 2>&1; then
    log "Rust 已安装，跳过"
  else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || { log "Rust 安装失败"; exit 1; }
    source $HOME/.cargo/env
  fi

  # 3. 安装 Risc0
  log "安装 Risc0..."
  if command -v rzup >/dev/null 2>&1; then
    log "Risc0 已安装，跳过"
  else
    curl -L https://risczero.com/install | bash || { log "Risc0 安装失败"; exit 1; }
    source ~/.bashrc
    rzup install || { log "Risc0 安装失败"; exit 1; }
  fi

  # 4. 安装 bento 客户端
  log "安装 bento 客户端..."
  if command -v bento_cli >/dev/null 2>&1; then
    log "bento_cli 已安装，跳过"
  else
    cargo install --git https://github.com/risc0/risc0 bento-client --bin bento_cli || { log "bento_cli 安装失败"; exit 1; }
  fi

  # 5. 配置 PATH
  log "配置 PATH..."
  if grep -q "$HOME/.cargo/bin" ~/.bashrc; then
    log "PATH 已配置，跳过"
  else
    export PATH="$HOME/.cargo/bin:$PATH"
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc
  fi

  # 6. 安装 Boundless CLI
  log "安装 Boundless CLI..."
  if command -v boundless-cli >/dev/null 2>&1; then
    log "boundless-cli 已安装，跳过"
  else
    cargo install --locked boundless-cli || { log "Boundless CLI 安装失败"; exit 1; }
  fi

  log "节点安装完成！"

  # 7. 配置 RPC_URL 和 PRIVATE_KEY
  configure_env

  # 8. 检查 screen 是否安装
  log "检查 screen 是否安装..."
  if ! command -v screen >/dev/null 2>&1; then
    log "screen 未安装，正在安装..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
      sudo apt-get update && sudo apt-get install -y screen || { log "screen 安装失败"; exit 1; }
    elif [[ "$OSTYPE" == "darwin"* ]]; then
      brew install screen || { log "screen 安装失败"; exit 1; }
    else
      log "不支持的操作系统，请手动安装 screen"
      exit 1
    fi
  fi

  # 9. 在 screen 中运行 Boundless CLI
  log "在 screen 会话中启动 Boundless CLI..."
  screen -dmS boundless bash -c 'source .env.eth-sepolia && boundless-cli; exec bash' || { log "screen 会话创建失败"; exit 1; }
  log "Boundless CLI 已在 screen 会话 'boundless' 中运行"
  log "使用 'screen -r boundless' 查看或恢复会话"
}

# 删除节点和会话的函数
delete_node_and_session() {
  log "开始删除节点和会话..."

  # 1. 终止 screen 会话
  if screen -ls | grep -q "boundless"; then
    log "终止 boundless screen 会话..."
    screen -X -S boundless quit || { log "终止 boundless 会话失败"; exit 1; }
  else
    log "没有找到 boundless screen 会话，跳过"
  fi

  # 2. 删除 boundless 仓库
  if [ -d "boundless" ]; then
    log "删除 boundless 仓库..."
    cd ..
    rm -rf boundless || { log "删除 boundless 仓库失败"; exit 1; }
  else
    log "boundless 仓库不存在，跳过"
  fi

  # 3. 删除 .env.eth-sepolia 文件
  if [ -f ".env.eth-sepolia" ]; then
    log "删除 .env.eth-sepolia 文件..."
    rm -f .env.eth-sepolia || { log "删除 .env.eth-sepolia 文件失败"; exit 1; }
  else
    log ".env.eth-sepolia 文件不存在，跳过"
  fi

  # 4. 卸载 boundless-cli
  if command -v boundless-cli >/dev/null 2>&1; then
    log "卸载 boundless-cli..."
    cargo uninstall boundless-cli || { log "卸载 boundless-cli 失败"; exit 1; }
  else
    log "boundless-cli 未安装，跳过"
  fi

  # 5. 卸载 bento_cli
  if command -v bento_cli >/dev/null 2>&1; then
    log "卸载 bento_cli..."
    cargo uninstall bento-client || { log "卸载 bento_cli 失败"; exit 1; }
  else
    log "bento_cli 未安装，跳过"
  fi

  # 6. 提示用户手动清理 Rust 和 Risc0（可选）
  log "注意：Rust 和 Risc0 未自动卸载，因其可能被其他项目使用"
  log "如需卸载 Rust，请运行：rustup self uninstall"
  log "如需卸载 Risc0，请手动删除相关文件（参考 Risc0 文档）"

  # 7. 清理 PATH 配置（可选）
  if grep -q "$HOME/.cargo/bin" ~/.bashrc; then
    log "检测到 PATH 中包含 $HOME/.cargo/bin"
    read -p "是否从 ~/.bashrc 中移除 PATH 配置？(y/n): " remove_path
    if [ "$remove_path" = "y" ]; then
      log "从 ~/.bashrc 中移除 PATH 配置..."
      sed -i.bak "/$HOME\/.cargo\/bin/d" ~/.bashrc || { log "移除 PATH 配置失败"; exit 1; }
      log "PATH 配置已移除，请运行 'source ~/.bashrc' 刷新环境"
    else
      log "保留 PATH 配置"
    fi
  fi

  log "节点和会话删除完成！"
}

# 查看日志的函数
view_logs() {
  if [ -f "$LOG_FILE" ]; then
    log "查看安装日志..."
    cat "$LOG_FILE"
  else
    log "日志文件 $LOG_FILE 不存在"
  fi
}

# 主菜单
main_menu() {
  while true; do
    echo "=== Boundless 安装与管理菜单 ==="
    echo "1. 安装节点，配置 RPC_URL 和 PRIVATE_KEY，并在 screen 中运行 Boundless CLI"
    echo "2. 查看日志"
    echo "3. 删除节点和会话"
    echo "4. 退出"
    read -p "请选择操作 (1-4): " choice

    case $choice in
      1)
        install_and_run
        ;;
      2)
        view_logs
        ;;
      3)
        delete_node_and_session
        ;;
      4)
        log "退出脚本"
        exit 0
        ;;
      *)
        log "无效选项，请输入 1-4"
        ;;
    esac
  done
}

# 初始化日志文件
touch "$LOG_FILE"
log "脚本启动"

# 启动主菜单
main_menu
