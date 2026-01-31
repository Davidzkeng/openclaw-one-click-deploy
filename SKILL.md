---
name: "openclaw-deployer"
description: "One-click local deployment tool for OpenClaw AI assistant. Automates Docker setup, environment configuration, and service initialization. Invoke when user wants to deploy or setup OpenClaw locally."
---

# OpenClaw 一键部署工具

## 功能说明

该技能用于在本地环境一键部署 OpenClaw AI 助手，自动处理 Docker 环境配置、依赖安装、服务启动等全流程。

## 系统要求

- **操作系统**: Ubuntu 20.04+ / Debian 11+ / macOS / WSL2
- **内存**: 最低 2GB RAM（推荐 4GB+）
- **磁盘空间**: 最低 5GB 可用空间
- **必需软件**:
  - Docker 20.10+
  - Docker Compose 2.0+
  - Git
  - curl

## 部署方式

### 方式一：使用自动化脚本（推荐）

运行以下命令进行一键部署：

```bash
bash openclaw-deploy.sh
```

该脚本会自动完成：
1. 检查系统依赖（Docker、Docker Compose、Git）
2. 克隆 OpenClaw 仓库
3. 运行 Docker 配置脚本
4. 启动交互式配置向导
5. 生成网关令牌
6. 启动 OpenClaw 服务

### 方式二：手动部署步骤

#### 1. 检查并安装 Docker

```bash
# 检查 Docker 是否已安装
docker --version

# 如未安装，执行以下命令（Ubuntu/Debian）
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# 安装 Docker Compose
sudo apt-get update
sudo apt-get install docker-compose-plugin
```

#### 2. 克隆 OpenClaw 仓库

```bash
git clone https://github.com/openclaw/openclaw.git
cd openclaw
```

#### 3. 运行 Docker 部署脚本

```bash
chmod +x docker-setup.sh
./docker-setup.sh
```

#### 4. 配置向导

脚本会启动交互式配置界面，按提示完成以下配置：

**a. AI 模型提供商配置**

选择以下任一提供商并输入 API Key：
- Anthropic (Claude) - 推荐
- OpenAI (GPT-4)
- Google (Gemini)
- 其他兼容 OpenAI 的提供商

```bash
# 示例：Anthropic API Key
ANTHROPIC_API_KEY=sk-ant-xxxxxxxxxxxxxxxxxxxxx
```

**b. 消息渠道配置**

至少选择一个消息平台进行集成：
- Telegram Bot
- Discord
- Slack
- WhatsApp
- 网页界面

**c. 可选技能配置**
- Web 搜索功能
- 图片生成
- 文件处理
- 代码执行

#### 5. 启动服务

```bash
docker-compose up -d
```

#### 6. 访问控制面板

部署完成后，访问：
```
http://localhost:8080
```

使用生成的网关令牌登录（令牌会在配置完成后显示）。

## 环境变量配置

创建 `.env` 文件配置以下参数：

```bash
# 网关令牌（自动生成或自定义）
OPENCLAW_GATEWAY_TOKEN=your-secure-token-here

# AI 提供商配置
ANTHROPIC_API_KEY=sk-ant-xxxxxxxxxxxxxxxxxxxxx
OPENAI_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxx
GOOGLE_API_KEY=xxxxxxxxxxxxxxxxxxxxx

# 默认 AI 模型
DEFAULT_MODEL=claude-sonnet-4.5

# 服务端口
GATEWAY_PORT=8080
API_PORT=3000

# 数据库配置
DATABASE_URL=postgresql://openclaw:password@postgres:5432/openclaw

# Redis 配置
REDIS_URL=redis://redis:6379

# 日志级别
LOG_LEVEL=info
```

## 快速启动命令

```bash
# 启动所有服务
docker-compose up -d

# 查看服务状态
docker-compose ps

# 查看日志
docker-compose logs -f

# 停止服务
docker-compose down

# 重启服务
docker-compose restart

# 完全清理（包括数据）
docker-compose down -v
```

## 技能集成

部署完成后，可以通过 Skills CLI 安装 OpenClaw 技能：

```bash
# 安装核心技能
npx skills add openclaw/openclaw@clawhub

# 安装 Gmail 管理
npx skills add openclaw/skills@gmail-manager

# 安装 Telegram Bot
npx skills add openclaw/skills@telegram-bot

# 安装 YouTube 分析
npx skills add openclaw/skills@youtube-analytics

# 安装 DeFi 工具
npx skills add openclaw/skills@defi

# 安装 Google Gemini 媒体处理
npx skills add openclaw/skills@google-gemini-media
```

## 故障排查

### 问题 1: Docker 服务未启动

```bash
# 启动 Docker 服务
sudo systemctl start docker
sudo systemctl enable docker
```

### 问题 2: 端口被占用

```bash
# 检查端口占用
sudo lsof -i :8080
sudo lsof -i :3000

# 修改 .env 文件中的端口配置
GATEWAY_PORT=8081
API_PORT=3001
```

### 问题 3: API Key 无效

```bash
# 验证 API Key
curl -H "x-api-key: $ANTHROPIC_API_KEY" https://api.anthropic.com/v1/messages

# 重新配置
docker-compose down
./docker-setup.sh
```

### 问题 4: 容器启动失败

```bash
# 查看详细日志
docker-compose logs --tail=100

# 重新构建镜像
docker-compose build --no-cache
docker-compose up -d
```

### 问题 5: 内存不足

```bash
# 清理未使用的 Docker 资源
docker system prune -a

# 限制容器内存使用（修改 docker-compose.yml）
services:
  gateway:
    mem_limit: 1g
```

## 安全最佳实践

1. **更改默认令牌**: 部署后立即修改默认的网关令牌
2. **使用环境变量**: 不要在代码中硬编码 API Key
3. **设置防火墙**: 限制只允许必要的端口访问
4. **定期更新**: 保持 OpenClaw 和依赖项为最新版本
5. **备份数据**: 定期备份 PostgreSQL 数据库

```bash
# 备份数据库
docker-compose exec postgres pg_dump -U openclaw openclaw > backup.sql

# 恢复数据库
docker-compose exec -T postgres psql -U openclaw openclaw < backup.sql
```

## 更新 OpenClaw

```bash
# 拉取最新代码
cd openclaw
git pull origin main

# 重新构建并启动
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

## 卸载

```bash
# 停止并删除所有容器和卷
cd openclaw
docker-compose down -v

# 删除镜像
docker rmi $(docker images 'openclaw*' -q)

# 删除仓库
cd ..
rm -rf openclaw
```

## 性能优化

### 1. 使用 Redis 缓存

在 `docker-compose.yml` 中确保 Redis 配置正确：

```yaml
services:
  redis:
    image: redis:7-alpine
    restart: always
    volumes:
      - redis_data:/data
```

### 2. 配置数据库连接池

在 `.env` 中添加：

```bash
DATABASE_POOL_MIN=2
DATABASE_POOL_MAX=10
```

### 3. 启用 HTTP/2

在网关配置中启用 HTTP/2 以提升性能。

## 监控与日志

### 查看实时日志

```bash
# 所有服务
docker-compose logs -f

# 特定服务
docker-compose logs -f gateway
docker-compose logs -f postgres
```

### 资源监控

```bash
# 查看容器资源使用
docker stats

# 查看磁盘使用
docker system df
```

## 高级配置

### 自定义 AI 模型

在配置文件中指定自定义模型：

```yaml
models:
  - name: custom-claude
    provider: anthropic
    model: claude-sonnet-4.5
    max_tokens: 4096
```

### 配置多个消息渠道

同时支持多个平台：

```bash
TELEGRAM_BOT_TOKEN=xxxx
DISCORD_BOT_TOKEN=yyyy
SLACK_BOT_TOKEN=zzzz
```

### 启用 Web Search

```bash
# 添加搜索 API Key
BRAVE_SEARCH_API_KEY=xxxxx
# 或
GOOGLE_SEARCH_API_KEY=yyyyy
```

## 参考资料

- [OpenClaw 官方网站](https://openclaw.ai)
- [Vultr 部署指南](https://www.vultr.com/docs/deploy-openclaw-on-vultr/)
- [DigitalOcean 部署指南](https://www.digitalocean.com/community/tutorials/openclaw-deployment)
- [Hostinger VPS 部署](https://www.hostinger.com/tutorials/openclaw-installation)
- [OpenClaw GitHub 仓库](https://github.com/openclaw/openclaw)

## 常见问题（FAQ）

**Q: OpenClaw 支持哪些 AI 模型？**
A: 支持 Anthropic Claude、OpenAI GPT、Google Gemini 以及所有兼容 OpenAI API 的模型。

**Q: 可以在 Windows 上部署吗？**
A: 可以，建议使用 WSL2 + Docker Desktop。

**Q: 数据存储在哪里？**
A: 默认使用 PostgreSQL 数据库，数据存储在 Docker volume 中。

**Q: 如何添加自定义技能？**
A: 使用 `npx skills add` 命令安装，或自行开发技能并放置在 skills 目录。

**Q: 支持离线运行吗？**
A: 不支持，需要网络连接以调用 AI API。

## 贡献与支持

- 问题反馈: [GitHub Issues](https://github.com/openclaw/openclaw/issues)
- 社区讨论: [Discord](https://discord.gg/openclaw)
- 文档贡献: Pull Request 欢迎

---

**最后更新**: 2026-01-31
**版本**: 1.0.0
**作者**: OpenClaw Deployer Skill
