#!/bin/bash

################################################################################
# OpenClaw 终极修复脚本 v2.0
#
# 彻底解决 clipboard 模块问题：
# 1. 使用预构建的官方镜像（推荐）
# 2. 或创建假的 clipboard 模块绕过错误
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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

print_header() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          OpenClaw 终极修复工具 v2.0                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_header

# 检查是否在 openclaw 目录
if [ ! -f "docker-compose.yml" ]; then
    log_error "请在 OpenClaw 项目根目录运行此脚本"
    exit 1
fi

echo ""
log_warning "检测到 clipboard 模块运行时错误"
echo ""
echo -e "${CYAN}选择修复方案:${NC}"
echo ""
echo -e "  ${GREEN}1.${NC} 使用预构建镜像 (推荐，最快速)"
echo -e "     从 Docker Hub 拉取官方已构建好的镜像"
echo -e "     优点: 快速、可靠、官方支持"
echo ""
echo -e "  ${YELLOW}2.${NC} 创建假模块绕过错误 (实验性)"
echo -e "     在 Dockerfile 中创建空的 clipboard 模块"
echo -e "     优点: 本地构建，但可能导致功能缺失"
echo ""
echo -e "  ${BLUE}3.${NC} 联系 OpenClaw 官方支持"
echo -e "     在 GitHub 提交 Issue 获取帮助"
echo ""

read -p "$(echo -e ${CYAN}请选择方案 [1/2/3]: ${NC})" choice

case $choice in
    1)
        log_info "方案 1: 使用预构建镜像"
        echo ""

        # 停止现有容器
        log_info "停止现有容器..."
        docker-compose down 2>/dev/null || true

        # 清理本地构建的镜像
        log_info "清理本地构建的镜像..."
        docker images | grep openclaw | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true

        # 拉取预构建镜像
        log_info "从 Docker Hub 拉取预构建镜像..."
        if docker-compose pull; then
            log_success "预构建镜像拉取成功"

            # 启动服务
            log_info "启动服务..."
            docker-compose up -d

            echo ""
            log_success "OpenClaw 已使用预构建镜像启动！"
            echo ""
            echo -e "${CYAN}查看服务状态:${NC}"
            docker-compose ps
            echo ""
            echo -e "${CYAN}查看日志:${NC}"
            echo "  docker-compose logs -f"

        else
            log_error "拉取预构建镜像失败"
            log_info "可能原因:"
            echo "  1. 网络连接问题"
            echo "  2. Docker Hub 访问受限"
            echo "  3. 镜像不存在或需要认证"
            echo ""
            log_info "尝试配置 Docker Hub 镜像:"
            echo "  sudo mkdir -p /etc/docker"
            echo "  sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'"
            echo '{'
            echo '  "registry-mirrors": ["https://dockerproxy.com"]'
            echo '}'
            echo 'EOF'
            echo "  sudo systemctl restart docker"
            exit 1
        fi
        ;;

    2)
        log_info "方案 2: 创建假模块绕过"
        echo ""

        # 备份 Dockerfile
        if [ ! -f "Dockerfile.original" ]; then
            cp Dockerfile Dockerfile.original
            log_info "已备份原始 Dockerfile"
        fi

        # 创建补丁文件
        log_info "创建 clipboard 补丁..."
        cat > clipboard-fix.js << 'EOF'
// Fake clipboard module to bypass ARM architecture error
module.exports = {
    readText: () => Promise.resolve(''),
    writeText: (text) => Promise.resolve(),
    readHTML: () => Promise.resolve(''),
    writeHTML: (html) => Promise.resolve(''),
    readRTF: () => Promise.resolve(''),
    writeRTF: (rtf) => Promise.resolve(''),
    readImage: () => Promise.resolve(null),
    writeImage: (image) => Promise.resolve(),
    clear: () => Promise.resolve()
};
EOF

        # 修改 Dockerfile
        log_info "修改 Dockerfile..."

        # 在 pnpm install 之后添加假模块
        if ! grep -q "clipboard-fix.js" Dockerfile; then
            # 找到 RUN pnpm install 的行号
            line_num=$(grep -n "RUN pnpm install" Dockerfile | head -1 | cut -d: -f1)

            if [ -n "$line_num" ]; then
                # 在该行之后插入
                sed -i "${line_num}a\\
\\
# Fix clipboard module for ARM architecture\\
COPY clipboard-fix.js /tmp/clipboard-fix.js\\
RUN mkdir -p /app/node_modules/.pnpm/@mariozechner+clipboard@0.3.0/node_modules/@mariozechner/clipboard/ \\\\\\
    && cp /tmp/clipboard-fix.js /app/node_modules/.pnpm/@mariozechner+clipboard@0.3.0/node_modules/@mariozechner/clipboard/index.js \\\\\\
    || true" Dockerfile

                log_success "Dockerfile 修改完成"
            else
                log_error "无法找到 pnpm install 命令"
                exit 1
            fi
        else
            log_warning "Dockerfile 已包含补丁，跳过"
        fi

        # 重新构建
        log_info "清理旧容器和镜像..."
        docker-compose down 2>/dev/null || true
        docker system prune -f

        log_info "重新构建镜像（这可能需要几分钟）..."
        if docker-compose build --no-cache; then
            log_success "构建成功"

            log_info "启动服务..."
            docker-compose up -d

            echo ""
            log_success "OpenClaw 已启动！"
            echo ""
            log_warning "注意: clipboard 功能已被禁用"
            echo ""
            docker-compose ps

        else
            log_error "构建失败"
            echo ""
            log_info "恢复原始 Dockerfile:"
            echo "  mv Dockerfile.original Dockerfile"
            echo ""
            log_info "建议尝试方案 1 (使用预构建镜像)"
            exit 1
        fi
        ;;

    3)
        log_info "方案 3: 联系官方支持"
        echo ""
        echo -e "${CYAN}请访问以下链接提交 Issue:${NC}"
        echo ""
        echo "  OpenClaw GitHub Issues:"
        echo "  https://github.com/openclaw/openclaw/issues"
        echo ""
        echo -e "${CYAN}Issue 标题建议:${NC}"
        echo '  "Cannot find module @mariozechner/clipboard-linux-arm-gnueabihf"'
        echo ""
        echo -e "${CYAN}请附上以下信息:${NC}"
        echo "  - 操作系统: $(uname -a)"
        echo "  - Docker 版本: $(docker --version)"
        echo "  - 架构: $(uname -m)"
        echo "  - 错误日志: (复制完整错误信息)"
        echo ""
        ;;

    *)
        log_error "无效选择"
        exit 1
        ;;
esac

echo ""
log_info "修复脚本执行完成"
echo ""
