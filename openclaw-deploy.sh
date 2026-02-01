#!/bin/bash

################################################################################
# OpenClaw 一键部署脚本
#
# 功能：自动部署 OpenClaw AI 助手到本地环境
# 系统要求：Ubuntu/Debian/macOS/WSL2，Docker，Git
# 版本：1.0.0
# 日期：2026-01-31
################################################################################

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置变量
OPENCLAW_REPO="https://github.com/openclaw/openclaw.git"
INSTALL_DIR="${HOME}/openclaw"
BACKUP_DIR="${HOME}/openclaw_backup_$(date +%Y%m%d_%H%M%S)"

################################################################################
# 工具函数
################################################################################

print_header() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          OpenClaw 一键部署工具 v1.0.0                       ║"
    echo "║          OpenClaw One-Click Deployment Tool                  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "\n${CYAN}==>${NC} ${YELLOW}$1${NC}\n"
}

confirm() {
    read -p "$(echo -e ${YELLOW}$1 [y/N]: ${NC})" -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

################################################################################
# 系统检测
################################################################################

detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS=$NAME
            VER=$VERSION_ID
        fi
        log_info "检测到操作系统: $OS $VER"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macOS"
        log_info "检测到操作系统: macOS"
    else
        log_error "不支持的操作系统: $OSTYPE"
        exit 1
    fi
}

check_dependencies() {
    print_step "检查系统依赖"

    local missing_deps=()

    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        log_warning "Docker 未安装"
        missing_deps+=("docker")
    else
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
        log_success "Docker 已安装: $DOCKER_VERSION"
    fi

    # 检查 Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_warning "Docker Compose 未安装"
        missing_deps+=("docker-compose")
    else
        if command -v docker-compose &> /dev/null; then
            COMPOSE_VERSION=$(docker-compose --version | awk '{print $4}' | sed 's/,//')
        else
            COMPOSE_VERSION=$(docker compose version --short)
        fi
        log_success "Docker Compose 已安装: $COMPOSE_VERSION"
    fi

    # 检查 Git
    if ! command -v git &> /dev/null; then
        log_warning "Git 未安装"
        missing_deps+=("git")
    else
        GIT_VERSION=$(git --version | awk '{print $3}')
        log_success "Git 已安装: $GIT_VERSION"
    fi

    # 检查 curl
    if ! command -v curl &> /dev/null; then
        log_warning "curl 未安装"
        missing_deps+=("curl")
    else
        log_success "curl 已安装"
    fi

    # 如果有缺失依赖，询问是否安装
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_warning "缺失依赖: ${missing_deps[*]}"
        if confirm "是否自动安装缺失的依赖？"; then
            install_dependencies "${missing_deps[@]}"
        else
            log_error "缺少必要依赖，无法继续部署"
            exit 1
        fi
    fi
}

install_docker_with_mirror() {
    log_info "检测网络环境并选择最佳安装方式..."

    # 测试是否能访问 Docker 官方源
    if curl -s --connect-timeout 5 https://download.docker.com >/dev/null 2>&1; then
        log_success "可以访问 Docker 官方源"
        USE_MIRROR=false
    else
        log_warning "无法访问 Docker 官方源，将使用阿里云镜像"
        USE_MIRROR=true
    fi

    if [ "$USE_MIRROR" = true ]; then
        # 使用阿里云镜像安装 Docker
        log_info "使用阿里云镜像安装 Docker..."

        # 安装必要的依赖
        sudo apt-get update
        sudo apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

        # 添加阿里云 Docker GPG 密钥
        curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

        # 设置阿里云 Docker 仓库
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu \
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        # 安装 Docker Engine
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        # 配置 Docker 镜像加速
        sudo mkdir -p /etc/docker
        sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.ccs.tencentyun.com"
  ]
}
EOF
        sudo systemctl daemon-reload
        sudo systemctl restart docker

    else
        # 使用官方脚本安装
        log_info "使用 Docker 官方脚本安装..."
        curl -fsSL https://get.docker.com -o get-docker.sh

        # 添加重试机制
        local max_retries=3
        local retry_count=0

        while [ $retry_count -lt $max_retries ]; do
            if sudo sh get-docker.sh; then
                log_success "Docker 安装成功"
                break
            else
                retry_count=$((retry_count + 1))
                if [ $retry_count -lt $max_retries ]; then
                    log_warning "安装失败，${retry_count}/${max_retries} 次重试..."
                    sleep 2
                else
                    log_error "官方脚本安装失败，切换到阿里云镜像"
                    USE_MIRROR=true
                    install_docker_with_mirror
                    return
                fi
            fi
        done

        rm -f get-docker.sh
    fi

    # 将当前用户添加到 docker 组
    sudo usermod -aG docker $USER
    log_success "Docker 安装完成"
}

install_dependencies() {
    print_step "安装系统依赖"

    local deps=("$@")

    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        log_info "使用 apt 包管理器安装依赖..."

        # 先更新软件源
        log_info "更新软件包列表..."
        if ! sudo apt-get update -qq; then
            log_warning "apt 更新失败，尝试使用阿里云镜像源..."

            # 备份原有源
            sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup

            # 检测系统版本
            UBUNTU_CODENAME=$(lsb_release -cs)

            # 使用阿里云镜像源
            sudo tee /etc/apt/sources.list > /dev/null <<EOF
deb https://mirrors.aliyun.com/ubuntu/ ${UBUNTU_CODENAME} main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ ${UBUNTU_CODENAME}-security main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ ${UBUNTU_CODENAME}-updates main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ ${UBUNTU_CODENAME}-backports main restricted universe multiverse
EOF

            sudo apt-get update
            log_success "已切换到阿里云镜像源"
        fi

        for dep in "${deps[@]}"; do
            case $dep in
                docker)
                    install_docker_with_mirror
                    ;;
                docker-compose)
                    log_info "安装 Docker Compose..."
                    sudo apt-get install -y docker-compose-plugin
                    log_success "Docker Compose 安装完成"
                    ;;
                git)
                    log_info "安装 Git..."
                    sudo apt-get install -y git
                    log_success "Git 安装完成"
                    ;;
                curl)
                    log_info "安装 curl..."
                    sudo apt-get install -y curl
                    log_success "curl 安装完成"
                    ;;
            esac
        done

    elif [[ "$OS" == "macOS" ]]; then
        log_info "使用 Homebrew 安装依赖..."

        # 检查 Homebrew
        if ! command -v brew &> /dev/null; then
            log_info "安装 Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi

        for dep in "${deps[@]}"; do
            case $dep in
                docker)
                    log_info "请手动安装 Docker Desktop for Mac"
                    log_info "下载地址: https://www.docker.com/products/docker-desktop"
                    ;;
                docker-compose)
                    log_info "Docker Desktop 已包含 Docker Compose"
                    ;;
                git)
                    brew install git
                    ;;
                curl)
                    brew install curl
                    ;;
            esac
        done
    fi

    log_warning "如果安装了 Docker，请重新登录或运行: newgrp docker"
}

################################################################################
# OpenClaw 部署
################################################################################

clone_repository() {
    print_step "克隆 OpenClaw 仓库"

    # 如果目录已存在，询问是否备份
    if [ -d "$INSTALL_DIR" ]; then
        log_warning "目录 $INSTALL_DIR 已存在"
        if confirm "是否备份现有目录并重新安装？"; then
            log_info "备份到: $BACKUP_DIR"
            mv "$INSTALL_DIR" "$BACKUP_DIR"
        else
            log_info "使用现有目录"
            return
        fi
    fi

    log_info "克隆仓库到: $INSTALL_DIR"
    git clone "$OPENCLAW_REPO" "$INSTALL_DIR"
    log_success "仓库克隆完成"
}

configure_environment() {
    print_step "配置环境变量"

    cd "$INSTALL_DIR"

    # 创建 .env 文件
    if [ ! -f .env ]; then
        log_info "创建 .env 配置文件"
        cat > .env << 'EOF'
# OpenClaw 环境配置
# 生成时间: $(date)

# 网关令牌（请修改为安全的随机字符串）
OPENCLAW_GATEWAY_TOKEN=

# AI 提供商 API Keys
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
GOOGLE_API_KEY=

# 默认 AI 模型
DEFAULT_MODEL=claude-sonnet-4.5

# 服务端口
GATEWAY_PORT=8080
API_PORT=3000

# 数据库配置
DATABASE_URL=postgresql://openclaw:openclaw_password@postgres:5432/openclaw

# Redis 配置
REDIS_URL=redis://redis:6379

# 日志级别
LOG_LEVEL=info

# 消息渠道配置（可选）
TELEGRAM_BOT_TOKEN=
DISCORD_BOT_TOKEN=
SLACK_BOT_TOKEN=
WHATSAPP_TOKEN=

# 搜索功能（可选）
BRAVE_SEARCH_API_KEY=
GOOGLE_SEARCH_API_KEY=
EOF
        log_success ".env 文件创建完成"
    fi

    # 生成随机网关令牌
    if [ -z "$(grep OPENCLAW_GATEWAY_TOKEN= .env | cut -d'=' -f2)" ]; then
        RANDOM_TOKEN=$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1)
        sed -i.bak "s/OPENCLAW_GATEWAY_TOKEN=/OPENCLAW_GATEWAY_TOKEN=$RANDOM_TOKEN/" .env
        log_success "生成网关令牌: $RANDOM_TOKEN"
    fi

    # 交互式配置
    echo ""
    log_info "请配置 AI 提供商 API Key（至少配置一个）"
    echo ""

    echo -ne "${CYAN}Anthropic API Key [推荐]: ${NC}"
    read ANTHROPIC_KEY
    if [ -n "$ANTHROPIC_KEY" ]; then
        sed -i.bak "s|ANTHROPIC_API_KEY=|ANTHROPIC_API_KEY=$ANTHROPIC_KEY|" .env
        log_success "Anthropic API Key 已配置"
    fi

    echo -ne "${CYAN}OpenAI API Key [可选]: ${NC}"
    read OPENAI_KEY
    if [ -n "$OPENAI_KEY" ]; then
        sed -i.bak "s|OPENAI_API_KEY=|OPENAI_API_KEY=$OPENAI_KEY|" .env
        log_success "OpenAI API Key 已配置"
    fi

    echo -ne "${CYAN}Google API Key [可选]: ${NC}"
    read GOOGLE_KEY
    if [ -n "$GOOGLE_KEY" ]; then
        sed -i.bak "s|GOOGLE_API_KEY=|GOOGLE_API_KEY=$GOOGLE_KEY|" .env
        log_success "Google API Key 已配置"
    fi

    # 清理备份文件
    rm -f .env.bak
}

configure_npm_mirrors() {
    print_step "配置 npm/pnpm 镜像源"

    cd "$INSTALL_DIR"

    # 测试是否能访问 registry.npmjs.org
    if ! curl -s --connect-timeout 5 https://registry.npmjs.org >/dev/null 2>&1; then
        log_warning "无法访问 npm 官方源，配置淘宝镜像"

        # 创建 .npmrc 配置文件
        cat > .npmrc << 'EOF'
registry=https://registry.npmmirror.com
electron_mirror=https://npmmirror.com/mirrors/electron/
sass_binary_site=https://npmmirror.com/mirrors/node-sass/
phantomjs_cdnurl=https://npmmirror.com/mirrors/phantomjs/
chromedriver_cdnurl=https://npmmirror.com/mirrors/chromedriver/
EOF
        log_success "已配置 npm 淘宝镜像"

        # 创建 .pnpmrc 配置文件
        cat > .pnpmrc << 'EOF'
registry=https://registry.npmmirror.com
shamefully-hoist=true
strict-peer-dependencies=false
EOF
        log_success "已配置 pnpm 淘宝镜像"

        # 修改 Dockerfile 以使用镜像源
        if [ -f Dockerfile ]; then
            # 在 COPY package.json 之后添加镜像配置
            if ! grep -q "registry.npmmirror.com" Dockerfile; then
                # 在 pnpm install 之前添加镜像配置
                sed -i '/COPY package.json/a COPY .npmrc .pnpmrc ./' Dockerfile
                sed -i '/pnpm install/i RUN pnpm config set registry https://registry.npmmirror.com' Dockerfile
                log_success "已更新 Dockerfile 使用 npm 镜像"
            fi
        fi

        # 设置环境变量
        export COREPACK_NPM_REGISTRY=https://registry.npmmirror.com
        export npm_config_registry=https://registry.npmmirror.com

    else
        log_success "npm 官方源可访问，使用默认配置"
    fi
}

run_docker_setup() {
    print_step "运行 Docker 配置"

    cd "$INSTALL_DIR"

    # 检查系统内存
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    log_info "检测到系统内存: ${TOTAL_MEM}MB"

    if [ "$TOTAL_MEM" -lt 4096 ]; then
        log_warning "系统内存较低，将优化 Docker 构建参数"

        # 创建或修改 docker-compose.yml 以限制构建内存
        if [ -f docker-compose.yml ]; then
            log_info "配置 Docker 构建参数以减少内存使用"

            # 设置 Node.js 堆内存限制
            export NODE_OPTIONS="--max-old-space-size=2048"

            # 在 Dockerfile 中添加内存限制环境变量
            if [ -f Dockerfile ]; then
                if ! grep -q "NODE_OPTIONS" Dockerfile; then
                    sed -i '/^FROM node/a ENV NODE_OPTIONS="--max-old-space-size=2048"' Dockerfile
                    log_success "已添加 Node.js 内存限制到 Dockerfile"
                fi
            fi
        fi
    fi

    # 配置 npm 镜像源
    configure_npm_mirrors

    # 检查是否存在 docker-setup.sh
    if [ -f docker-setup.sh ]; then
        log_info "执行 docker-setup.sh..."
        chmod +x docker-setup.sh

        # 设置构建时的环境变量
        export DOCKER_BUILDKIT=1
        export COMPOSE_DOCKER_CLI_BUILD=1
        export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=2048}"
        export COREPACK_NPM_REGISTRY=https://registry.npmmirror.com
        export npm_config_registry=https://registry.npmmirror.com

        ./docker-setup.sh
    else
        log_warning "未找到 docker-setup.sh，跳过官方配置脚本"
    fi
}

start_services() {
    print_step "启动 OpenClaw 服务"

    cd "$INSTALL_DIR"

    # 检查 Docker 守护进程是否运行
    if ! docker info &> /dev/null; then
        log_error "Docker 守护进程未运行，请启动 Docker"
        log_info "运行: sudo systemctl start docker"
        exit 1
    fi

    # 检查系统内存并设置构建参数
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')

    # 设置 Docker 构建环境变量
    export DOCKER_BUILDKIT=1
    export COMPOSE_DOCKER_CLI_BUILD=1
    export NODE_OPTIONS="--max-old-space-size=2048"
    export COREPACK_NPM_REGISTRY=https://registry.npmmirror.com
    export npm_config_registry=https://registry.npmmirror.com

    log_info "构建并启动容器（内存优化 + npm 镜像模式）..."
    log_info "Node.js 堆内存限制: 2048MB"
    log_info "npm 镜像源: registry.npmmirror.com"

    # 创建 .dockerignore 以减少构建上下文
    if [ ! -f .dockerignore ]; then
        cat > .dockerignore << 'EOF'
node_modules
.git
.github
*.log
.env
.env.*
dist
build
coverage
.vscode
.idea
EOF
        log_success "已创建 .dockerignore 优化构建"
    fi

    # 使用 docker compose 或 docker-compose
    if docker compose version &> /dev/null; then
        # 使用低内存模式构建
        COMPOSE_HTTP_TIMEOUT=300 docker compose build --memory 2g || {
            log_warning "构建失败，尝试使用预构建镜像..."
            docker compose pull || log_error "无法拉取预构建镜像"
        }
        docker compose up -d
    else
        # 使用低内存模式构建
        COMPOSE_HTTP_TIMEOUT=300 docker-compose build --memory 2g || {
            log_warning "构建失败，尝试使用预构建镜像..."
            docker-compose pull || log_error "无法拉取预构建镜像"
        }
        docker-compose up -d
    fi

    log_success "服务启动完成"

    # 等待服务就绪
    log_info "等待服务启动..."
    sleep 10

    # 显示服务状态
    echo ""
    if docker compose version &> /dev/null; then
        docker compose ps
    else
        docker-compose ps
    fi
}

display_summary() {
    print_step "部署完成"

    cd "$INSTALL_DIR"

    # 读取网关令牌
    GATEWAY_TOKEN=$(grep OPENCLAW_GATEWAY_TOKEN= .env | cut -d'=' -f2)
    GATEWAY_PORT=$(grep GATEWAY_PORT= .env | cut -d'=' -f2)

    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                   部署成功！                                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "${CYAN}访问信息:${NC}"
    echo -e "  控制面板: ${GREEN}http://localhost:${GATEWAY_PORT}${NC}"
    echo -e "  网关令牌: ${YELLOW}${GATEWAY_TOKEN}${NC}"
    echo ""

    echo -e "${CYAN}常用命令:${NC}"
    echo -e "  查看日志: ${YELLOW}cd $INSTALL_DIR && docker-compose logs -f${NC}"
    echo -e "  停止服务: ${YELLOW}cd $INSTALL_DIR && docker-compose down${NC}"
    echo -e "  重启服务: ${YELLOW}cd $INSTALL_DIR && docker-compose restart${NC}"
    echo -e "  查看状态: ${YELLOW}cd $INSTALL_DIR && docker-compose ps${NC}"
    echo ""

    echo -e "${CYAN}安装 OpenClaw Skills:${NC}"
    echo -e "  核心技能: ${YELLOW}npx skills add openclaw/openclaw@clawhub${NC}"
    echo -e "  Gmail:    ${YELLOW}npx skills add openclaw/skills@gmail-manager${NC}"
    echo -e "  Telegram: ${YELLOW}npx skills add openclaw/skills@telegram-bot${NC}"
    echo ""

    echo -e "${CYAN}配置文件:${NC}"
    echo -e "  环境变量: ${YELLOW}$INSTALL_DIR/.env${NC}"
    echo -e "  Docker:   ${YELLOW}$INSTALL_DIR/docker-compose.yml${NC}"
    echo ""

    log_info "感谢使用 OpenClaw 一键部署工具！"
}

cleanup_on_error() {
    log_error "部署过程中出现错误"

    if confirm "是否清理已安装的内容？"; then
        cd "$INSTALL_DIR" 2>/dev/null && docker-compose down -v 2>/dev/null
        rm -rf "$INSTALL_DIR"
        log_info "清理完成"
    fi

    exit 1
}

################################################################################
# 主程序
################################################################################

main() {
    # 设置错误处理
    trap cleanup_on_error ERR

    # 显示欢迎信息
    print_header

    # 检测操作系统
    detect_os

    # 检查依赖
    check_dependencies

    # 确认继续
    echo ""
    log_info "安装目录: $INSTALL_DIR"
    if ! confirm "是否继续部署 OpenClaw？"; then
        log_info "部署已取消"
        exit 0
    fi

    # 执行部署步骤
    clone_repository
    configure_environment
    run_docker_setup
    start_services
    display_summary

    # 提示重新登录（如果安装了 Docker）
    if groups | grep -q docker; then
        :
    else
        log_warning "如果刚安装了 Docker，请运行以下命令或重新登录："
        echo -e "  ${YELLOW}newgrp docker${NC}"
    fi
}

# 执行主程序
main "$@"
