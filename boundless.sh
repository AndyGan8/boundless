#!/bin/bash

# Boundless CLI 安装与操作脚本

# 环境变量
REPO_URL="https://github.com/boundless-xyz/boundless"
RELEASE_TAG="release-0.10"
ENV_FILE=".env.base-mainnet"
CONTRACT_ADDRESS="0x26759dbB201aFbA361Bec78E097Aa3942B0b4AB8"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}$1 未安装，请先安装 $1${NC}"
        exit 1
    fi
}

# 选项菜单
show_menu() {
    echo -e "${YELLOW}=== Boundless CLI 操作菜单 ===${NC}"
    echo "1. 安装节点"
    echo "2. 配置环境文件"
    echo "3. 质押 USDC"
    echo "4. 删除节点文件"
    echo "5. 退出"
    echo -n "请选择操作 [1-5]: "
}

# 1. 安装节点
install_node() {
    echo -e "${GREEN}开始安装节点...${NC}"

    # 检查前置依赖
    check_command git
    check_command curl

    # 克隆仓库
    echo "克隆 Boundless 仓库..."
    git clone $REPO_URL
    cd boundless
    git checkout $RELEASE_TAG

    # 安装 Rust
    echo "安装 Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    source $HOME/.cargo/env

    # 安装 Risc0
    echo "安装 Risc0..."
    curl -L https://risczero.com/install | bash
    source ~/.bashrc
    rzup install

    # 安装 bento 客户端
    echo "安装 bento 客户端..."
    cargo install --git https://github.com/risc0/risc0 bento-client --bin bento_cli
    export PATH="$HOME/.cargo/bin:$PATH"
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc

    # 安装 Boundless CLI
    echo "安装 Boundless CLI..."
    cargo install --locked boundless-cli

    echo -e "${GREEN}节点安装完成！${NC}"
}

# 2. 配置环境文件
configure_env() {
    echo -e "${GREEN}开始配置环境文件...${NC}"
    
    if [ ! -f $ENV_FILE ]; then
        echo -e "${YELLOW}创建 $ENV_FILE 文件${NC}"
        touch $ENV_FILE
    else
        echo -e "${YELLOW}$ENV_FILE 已存在，将进行编辑${NC}"
    fi

    # 提示用户输入 RPC 和私钥
    read -p "请输入 Base 主网 RPC URL (例如 https://mainnet.base.org): " rpc_url
    read -p "请输入钱包私钥: " private_key

    # 写入配置文件
    echo "RPC_URL=$rpc_url" > $ENV_FILE
    echo "PRIVATE_KEY=$private_key" >> $ENV_FILE
    echo "CONTRACT_ADDRESS=$CONTRACT_ADDRESS" >> $ENV_FILE

    # 使配置文件生效
    source $ENV_FILE
    echo -e "${GREEN}环境文件配置完成！${NC}"
}

# 3. 质押 USDC
stake_usdc() {
    echo -e "${GREEN}开始质押 USDC...${NC}"

    # 检查 boundless CLI 是否安装
    if ! command -v boundless &> /dev/null; then
        echo -e "${RED}boundless CLI 未安装，请先运行选项 1 安装节点${NC}"
        exit 1
    fi

    # 检查环境文件是否存在
    if [ ! -f $ENV_FILE ]; then
        echo -e "${RED}环境文件 $ENV_FILE 不存在，请先运行选项 2 配置环境${NC}"
        exit 1
    fi

    # 加载环境变量
    source $ENV_FILE

    # 检查 RPC_URL 和 PRIVATE_KEY 是否存在
    if [ -z "$RPC_URL" ] || [ -z "$PRIVATE_KEY" ]; then
        echo -e "${RED}环境变量 RPC_URL 或 PRIVATE_KEY 未设置，请检查 $ENV_FILE 文件${NC}"
        exit 1
    fi

    # 执行质押 0.01 USDC
    echo "执行质押 0.01 USDC 到合约 $CONTRACT_ADDRESS..."
    boundless --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" account deposit-stake 0.01

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}质押成功！请检查 CLI 返回的质押信息${NC}"
    else
        echo -e "${RED}质押失败，请检查 RPC URL、私钥、USDC 余额或网络连接${NC}"
        echo -e "${YELLOW}提示：确保钱包在 Base 主网上有至少 0.01 USDC 和足够的 ETH 用于 Gas 费用${NC}"
        echo -e "${YELLOW}USDC 合约地址：0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913${NC}"
    fi
}

# 4. 删除节点文件
remove_node() {
    echo -e "${GREEN}开始删除节点文件...${NC}"

    # 删除 boundless 仓库
    if [ -d "boundless" ]; then
        echo "删除 boundless 仓库..."
        rm -rf boundless
    else
        echo -e "${YELLOW}boundless 仓库不存在${NC}"
    fi

    # 删除环境文件
    if [ -f $ENV_FILE ]; then
        echo "删除 $ENV_FILE 文件..."
        rm $ENV_FILE
    else
        echo -e "${YELLOW}$ENV_FILE 文件不存在${NC}"
    fi

    # 提示卸载 Rust 和 Risc0（可选）
    echo -e "${YELLOW}是否需要卸载 Rust 和 Risc0？（手动操作）${NC}"
    echo "卸载 Rust: rustup self uninstall"
    echo "卸载 Risc0: 请参考 Risc0 官方文档"

    echo -e "${GREEN}节点文件删除完成！${NC}"
}

# 主循环
while true; do
    show_menu
    read choice

    case $choice in
        1)
            install_node
            ;;
        2)
            configure_env
            ;;
        3)
            stake_usdc
            ;;
        4)
            remove_node
            ;;
        5)
            echo -e "${GREEN}退出脚本${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请输入 1-5${NC}"
            ;;
    esac
    echo
done
