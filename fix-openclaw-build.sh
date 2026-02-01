#!/bin/bash

################################################################################
# OpenClaw 构建修复脚本
#
# 解决问题：
# 1. npm/pnpm 镜像源访问失败
# 2. ARM 架构原生模块缺失 (@mariozechner/clipboard)
# 3. Corepack 无法下载 pnpm
################################################################################

set -e

# 颜色定义
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
    echo "║          OpenClaw 构建修复工具                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 检查是否在 openclaw 目录
if [ ! -f "package.json" ]; then
    log_error "请在 OpenClaw 项目根目录运行此脚本"
    log_info "提示: cd ~/openclaw && ./fix-openclaw-build.sh"
    exit 1
fi

print_header

log_info "开始修复 OpenClaw 构建配置..."
echo ""

# 1. 创建 .npmrc
log_info "步骤 1/6: 创建 .npmrc 配置..."
cat > .npmrc << 'EOF'
registry=https://registry.npmmirror.com
electron_mirror=https://npmmirror.com/mirrors/electron/
sass_binary_site=https://npmmirror.com/mirrors/node-sass/
phantomjs_cdnurl=https://npmmirror.com/mirrors/phantomjs/
chromedriver_cdnurl=https://npmmirror.com/mirrors/chromedriver/
strict-ssl=false
EOF
log_success ".npmrc 创建完成"

# 2. 创建 .pnpmrc
log_info "步骤 2/6: 创建 .pnpmrc 配置..."
cat > .pnpmrc << 'EOF'
registry=https://registry.npmmirror.com
shamefully-hoist=true
strict-peer-dependencies=false
auto-install-peers=true
EOF
log_success ".pnpmrc 创建完成"

# 3. 备份原始 Dockerfile
log_info "步骤 3/6: 备份 Dockerfile..."
if [ ! -f "Dockerfile.backup" ]; then
    cp Dockerfile Dockerfile.backup
    log_success "已备份原始 Dockerfile 到 Dockerfile.backup"
else
    log_warning "备份文件已存在，跳过备份"
fi

# 4. 修改 Dockerfile
log_info "步骤 4/6: 修改 Dockerfile..."

# 检查是否已经修改过
if grep -q "OPENCLAW_DISABLE_CLIPBOARD" Dockerfile; then
    log_warning "Dockerfile 已包含修复，恢复原始版本后重新修改"
    cp Dockerfile.backup Dockerfile
fi

# 在 FROM 后添加环境变量
sed -i '/^FROM node:22-bookworm$/a \
\
# Fix for network and architecture issues\
ENV COREPACK_NPM_REGISTRY=https://registry.npmmirror.com \
ENV npm_config_registry=https://registry.npmmirror.com \
ENV PNPM_REGISTRY=https://registry.npmmirror.com \
ENV NODE_OPTIONS="--max-old-space-size=2048" \
ENV OPENCLAW_DISABLE_CLIPBOARD=1' Dockerfile

# 查找 COPY package.json 所在行并在之后添加
sed -i '/COPY package.json pnpm-lock.yaml/a COPY .npmrc .pnpmrc ./' Dockerfile

# 在 pnpm install 之前添加配置命令
sed -i '/RUN pnpm install --frozen-lockfile/i \\\n# Configure pnpm registry\nRUN pnpm config set registry https://registry.npmmirror.com 2>/dev/null || true\n' Dockerfile

# 修改 pnpm install 命令，忽略可选依赖
sed -i 's/RUN pnpm install --frozen-lockfile/RUN pnpm install --frozen-lockfile --no-optional --shamefully-hoist/' Dockerfile

log_success "Dockerfile 修改完成"

# 5. 创建 .dockerignore
log_info "步骤 5/6: 优化 .dockerignore..."
cat > .dockerignore << 'EOF'
node_modules
.git
.github
*.log
logs
.env
.env.*
dist
build
coverage
.vscode
.idea
*.md
Dockerfile.backup
EOF
log_success ".dockerignore 创建完成"

# 6. 创建 docker-compose.override.yml
log_info "步骤 6/6: 创建 docker-compose.override.yml..."
cat > docker-compose.override.yml << 'EOF'
version: '3.8'

services:
  gateway:
    build:
      args:
        - COREPACK_NPM_REGISTRY=https://registry.npmmirror.com
        - npm_config_registry=https://registry.npmmirror.com
        - NODE_OPTIONS=--max-old-space-size=2048
        - OPENCLAW_DISABLE_CLIPBOARD=1
    environment:
      - COREPACK_NPM_REGISTRY=https://registry.npmmirror.com
      - npm_config_registry=https://registry.npmmirror.com
      - OPENCLAW_DISABLE_CLIPBOARD=1
EOF
log_success "docker-compose.override.yml 创建完成"

# 显示修改摘要
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                  修复完成！                                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}应用的修复:${NC}"
echo "  ✓ npm/pnpm 镜像源配置 (淘宝镜像)"
echo "  ✓ 禁用 clipboard 可选依赖"
echo "  ✓ Node.js 内存限制 (2GB)"
echo "  ✓ pnpm 配置优化"
echo "  ✓ Docker 构建优化"
echo ""
echo -e "${CYAN}创建的文件:${NC}"
echo "  • .npmrc - npm 镜像配置"
echo "  • .pnpmrc - pnpm 镜像配置"
echo "  • .dockerignore - Docker 构建优化"
echo "  • docker-compose.override.yml - 构建参数覆盖"
echo "  • Dockerfile.backup - 原始 Dockerfile 备份"
echo ""
echo -e "${CYAN}下一步操作:${NC}"
echo -e "  ${YELLOW}1.${NC} 清理旧容器和镜像:"
echo "     docker-compose down"
echo "     docker system prune -f"
echo ""
echo -e "  ${YELLOW}2.${NC} 重新构建:"
echo "     docker-compose build --no-cache"
echo ""
echo -e "  ${YELLOW}3.${NC} 启动服务:"
echo "     docker-compose up -d"
echo ""
echo -e "${CYAN}如果构建仍然失败，可以尝试:${NC}"
echo "  • 使用预构建镜像: docker-compose pull"
echo "  • 恢复备份: mv Dockerfile.backup Dockerfile"
echo "  • 查看详细日志: docker-compose logs -f"
echo ""
log_success "所有修复已应用完成！"
echo ""
