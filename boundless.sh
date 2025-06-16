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

  # 验证 RPC_URL 是否为空
  if [ -z "$rpc_url" ]; then
    log "错误：RPC_URL 不能为空"
    return 1
  fi

  # 验证 RPC_URL 是否有效（通过简单的 curl 测试）
  log "验证 RPC_URL: $rpc_url ..."
  if ! curl -s -H "Content-Type: application/json" -X POST --data '{"jsonrpc":"2.0","method":"web3_clientVersion","id":1}' "$rpc_url" >/dev/null 2>&1; then
    log "错误：RPC_URL 无效或无法连接"
    return 1
  fi
  log "RPC_URL 验证通过"

  # 验证 PRIVATE_KEY 是否为空或格式错误
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

  # 验证输入
  validate_env "$rpc_url" "$private_key" || { log "输入验证失败"; exit 1; }

  # 创建目录（如果不存在）
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

# 安装节点并运行 Boundless CLI 的函数
install_and_run() {
  log "开始安装 Boundless 环境和 CLI..."

  # 1. 克隆 Boundless 仓库
  log "克隆 Boundless 仓库..."
  if [ -d "$HOME/boundless" ]; then
    log "boundless 目录已存在，跳过克隆"
    cd "$HOME/boundless"
  else
    git clone https://github.com/boundless-xyz/boundless "$HOME/boundless" || { log "克隆失败"; exit 1; }
    cd "$HOME/boundless"
  fi
  git checkout release-0.10 || { log "切换到 release-0.10 分支失败"; exit 1; }

  # 2. 安装 Rust
  log "安装 Rust..."
  if command -v rustc >/dev/null 2>&1; then
    log "Rust 已安装，版本: $(rustc --version)"
  else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || { log "Rust 安装失败"; exit 1; }
    source "$HOME/.cargo/env"
    log "Rust 安装完成，版本: $(rustc --version)"
  fi

  # 3. 安装 Risc0
  log "安装 Risc0..."
  if command -v rzup >/dev/null 2>&1; then
    log "Risc0 已安装，版本: $(rzup --version 2>/dev/null || echo '未知')"
  else
    log "开始安装 Risc0..."
    max_attempts=3
    attempt=1
    until [ $attempt -gt $max_attempts ]; do
      log "尝试安装 Risc0 (第 $attempt 次)..."
      if curl -L https://risczero.com/install | bash; then
        log "Risc0 安装脚本执行成功"
        break
      else
        log "Risc0 安装脚本执行失败，重试..."
        ((attempt++))
        sleep 5
      fi
    done
    if [ $attempt -gt $max_attempts ]; then
      log "Risc0 安装失败，超过最大重试次数"
      exit 1
    fi

    # 配置 Risc0 的 PATH
    log "配置 Risc0 PATH..."
    export PATH="$HOME/.risc0/bin:$PATH"
    if ! grep -q "$HOME/.risc0/bin" ~/.bashrc; then
      echo 'export PATH="$HOME/.risc0/bin:$PATH"' >> ~/.bashrc
      log "已将 $HOME/.risc0/bin 添加到 ~/.bashrc"
    fi
    source ~/.bashrc

    # 验证 rzup
    if command -v rzup >/dev/null 2>&1; then
      log "rzup 命令可用，版本: $(rzup --version 2>/dev/null || echo '未知')"
    else
      log "rzup 命令不可用，请检查 $HOME/.risc0/bin 是否存在"
      ls -l "$HOME/.risc0/bin" >> "$LOG_FILE" 2>&1
      exit 1
    fi

    # 运行 rzup install
    log "运行 rzup install..."
    rzup install || { log "rzup install 失败"; exit 1; }
  fi

  # 4. 安装 bento 客户端
  log "安装 bento 客户端..."
  if command -v bento_cli >/dev/null 2>&1; then
    log "bento_cli 已安装，跳过"
  else
    cargo install --git https://github.com/risc0/risc0 bento-client --bin bento_cli || { log "bento_cli 安装失败"; exit 1; }
  fi

  # 5. 配置 PATH（Cargo）
  log "配置 Cargo PATH..."
  if grep -q "$HOME/.cargo/bin" ~/.bashrc; then
    log "Cargo PATH 已配置，跳过"
  else
    export PATH="$HOME/.cargo/bin:$PATH"
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc
    log "Cargo PATH 配置完成"
  fi

  # 6. 安装 Boundless CLI
  log "安装 Boundless CLI..."
  if command -v boundless >/dev/null 2>&1; then
    log "boundless 已安装，跳过"
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

  # 9. 执行 deposit-stake 命令（如果需要）
  read -p "是否运行 'boundless account deposit-stake 10'？(y/n): " run_deposit
  if [ "$run_deposit" = "y" ]; then
    log "运行 boundless account deposit-stake 10..."
    boundless account deposit-stake 10 --rpc-url "$RPC_URL" || { log "boundless account deposit-stake 失败"; exit 1; }
    log "boundless account deposit-stake 10 执行成功"
  else
    log "跳过 deposit-stake 命令"
  fi

  # 10. 在 screen 中运行 Boundless CLI
  log "在 screen 会话中启动 Boundless CLI..."
  screen -dmS boundless bash -c "source \"$ENV_FILE\" && boundless --rpc-url \"$RPC_URL\"; exec bash" || { log "screen 会话创建失败"; exit 1; }
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
  if [ -d "$HOME/boundless" ]; then
    log "删除 boundless 仓库..."
    rm -rf "$HOME/boundless" || { log "删除 boundless 仓库失败"; exit 1; }
  else
    log "boundless 仓库不存在，跳过"
  fi

  # 3. 删除 .env.eth-sepolia 文件
  if [ -f "$ENV_FILE" ]; then
    log "删除 $ENV_FILE 文件..."
    rm -f "$ENV_FILE" || { log "删除 $ENV_FILE 文件失败"; exit 1; }
  else
    log "$ENV_FILE 文件不存在，跳过"
  fi

  # 4. 卸载 boundless-cli
  if command -v boundless >/dev/null 2>&1; then
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
  log "如需卸载 Risc0，请手动删除 $HOME/.risc0 目录并从 ~/.bashrc 移除相关 PATH"

  # 7. 清理 PATH 配置（可选）
  if grep -q "$HOME/.cargo/bin\|$HOME/.risc0/bin" ~/.bashrc; then
    log "检测到 PATH 中包含 $HOME/.cargo/bin 或 $HOME/.risc0/bin"
    read -p "是否从 ~/.bashrc 中移除 PATH 配置？(y/n): " remove_path
    if [ "$remove_path" = "y" ]; then
      log "从 ~/.bashrc 中移除 PATH 配置..."
      sed -i.bak -E "/($HOME\/.cargo\/bin|$HOME\/.risc0\/bin)/d" ~/.bashrc || { log "移除 PATH 配置失败"; exit 1; }
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
