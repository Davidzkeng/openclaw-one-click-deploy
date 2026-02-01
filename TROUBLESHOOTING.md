# OpenClaw 部署故障排查指南

本文档列出了在部署 OpenClaw 时可能遇到的常见问题及解决方案。

## 目录

- [内存问题](#内存问题)
- [网络问题](#网络问题)
- [Docker 问题](#docker-问题)
- [API 配置问题](#api-配置问题)
- [服务启动问题](#服务启动问题)

---

## 内存问题

### ❌ JavaScript heap out of memory

**错误信息**：
```
FATAL ERROR: Reached heap limit Allocation failed - JavaScript heap out of memory
```

**原因**：Docker 构建时 Node.js 内存不足

**解决方案 1**：使用更新的部署脚本（已包含修复）
```bash
# 重新下载最新脚本
curl -fsSL https://raw.githubusercontent.com/Davidzkeng/openclaw-one-click-deploy/main/openclaw-deploy.sh -o openclaw-deploy.sh
chmod +x openclaw-deploy.sh
./openclaw-deploy.sh
```

**解决方案 2**：手动增加 Node.js 堆内存
```bash
cd ~/openclaw

# 在 Dockerfile 中添加内存限制
sed -i '/^FROM node/a ENV NODE_OPTIONS="--max-old-space-size=4096"' Dockerfile

# 使用内存限制构建
export NODE_OPTIONS="--max-old-space-size=4096"
docker-compose build --memory 4g
docker-compose up -d
```

**解决方案 3**：使用预构建镜像（跳过本地构建）
```bash
cd ~/openclaw

# 直接拉取官方镜像
docker-compose pull
docker-compose up -d
```

**预防措施**：
- 确保系统至少有 4GB RAM
- 关闭其他占用内存的应用
- 增加 swap 空间

```bash
# 增加 swap（临时方案）
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

---

## 网络问题

### ❌ Docker 镜像拉取失败

**错误信息**：
```
ERROR: failed to solve: node:22-bookworm: failed to resolve source metadata
dial tcp: lookup docker.mirrors.ustc.edu.cn: no such host
```

**原因**：配置的 Docker 镜像源无法访问

**解决方案 1**：移除镜像源配置（直接访问 Docker Hub）
```bash
# 备份现有配置
sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup

# 移除镜像源配置
sudo rm /etc/docker/daemon.json

# 重启 Docker
sudo systemctl daemon-reload
sudo systemctl restart docker

# 重新尝试部署
cd ~/openclaw
docker-compose build
```

**解决方案 2**：使用可用的镜像源
```bash
# 测试可用的镜像源
curl -I https://dockerproxy.com/v2/
curl -I https://docker.m.daocloud.io/v2/

# 配置可用的镜像源
sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "registry-mirrors": [
    "https://dockerproxy.com",
    "https://docker.m.daocloud.io",
    "https://docker.nju.edu.cn"
  ]
}
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker
```

**解决方案 3**：使用代理
```bash
sudo mkdir -p /etc/systemd/system/docker.service.d

sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf > /dev/null <<'EOF'
[Service]
Environment="HTTP_PROXY=http://your-proxy:port"
Environment="HTTPS_PROXY=http://your-proxy:port"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker
```

### ❌ SSL 连接错误

**错误信息**：
```
curl: (35) OpenSSL SSL_connect: Connection reset by peer
```

**解决方案**：
```bash
# 更新 CA 证书
sudo apt-get update
sudo apt-get install -y ca-certificates

# 或使用 --insecure 跳过 SSL 验证（不推荐）
curl --insecure -fsSL https://...
```

---

## Docker 问题

### ❌ Docker 服务未启动

**错误信息**：
```
Cannot connect to the Docker daemon
```

**解决方案**：
```bash
# 启动 Docker 服务
sudo systemctl start docker

# 设置开机自启
sudo systemctl enable docker

# 检查状态
sudo systemctl status docker
```

### ❌ Docker 权限问题

**错误信息**：
```
permission denied while trying to connect to the Docker daemon socket
```

**解决方案**：
```bash
# 将当前用户添加到 docker 组
sudo usermod -aG docker $USER

# 应用组权限（或重新登录）
newgrp docker

# 验证
docker ps
```

### ❌ 端口被占用

**错误信息**：
```
Bind for 0.0.0.0:8080 failed: port is already allocated
```

**解决方案**：
```bash
# 查找占用端口的进程
sudo lsof -i :8080
sudo netstat -tulpn | grep :8080

# 停止占用进程或修改端口
# 方式 1: 停止占用进程
sudo kill -9 <PID>

# 方式 2: 修改 OpenClaw 端口
cd ~/openclaw
nano .env
# 修改: GATEWAY_PORT=8081

# 重启服务
docker-compose down
docker-compose up -d
```

---

## API 配置问题

### ❌ API Key 无效

**错误信息**：
```
Authentication failed: Invalid API key
```

**解决方案**：
```bash
# 验证 API Key 格式
# Anthropic: sk-ant-xxxxxxxxxxxxx
# OpenAI: sk-xxxxxxxxxxxxx
# Google: xxxxxxxxxxxxx

# 测试 API Key
curl -H "x-api-key: $ANTHROPIC_API_KEY" \
  https://api.anthropic.com/v1/messages

# 更新配置
cd ~/openclaw
nano .env
# 修改对应的 API_KEY

# 重启服务
docker-compose restart
```

### ❌ API 限额超限

**错误信息**：
```
Rate limit exceeded
```

**解决方案**：
```bash
# 检查 API 使用情况
# Anthropic: https://console.anthropic.com/settings/limits
# OpenAI: https://platform.openai.com/usage

# 配置多个 API Key 轮换（如果支持）
# 或等待限额重置
```

---

## 服务启动问题

### ❌ 容器启动失败

**排查步骤**：
```bash
cd ~/openclaw

# 1. 查看容器状态
docker-compose ps

# 2. 查看详细日志
docker-compose logs --tail=100

# 3. 查看特定服务日志
docker-compose logs gateway
docker-compose logs postgres

# 4. 检查容器健康状态
docker inspect openclaw_gateway_1 | grep -A 20 Health
```

**常见原因**：
- 环境变量配置错误
- 数据库连接失败
- 端口冲突
- 内存不足

**解决方案**：
```bash
# 完全重建
docker-compose down -v
docker-compose up -d --build

# 清理所有资源重新开始
docker-compose down -v
docker system prune -a
rm -rf ~/openclaw
# 重新运行部署脚本
```

### ❌ 数据库连接失败

**错误信息**：
```
Connection refused: postgres:5432
```

**解决方案**：
```bash
# 检查 postgres 容器状态
docker-compose ps postgres

# 查看 postgres 日志
docker-compose logs postgres

# 重启 postgres
docker-compose restart postgres

# 等待数据库就绪后重启应用
sleep 10
docker-compose restart gateway
```

---

## 系统资源问题

### 检查系统资源

```bash
# 检查内存使用
free -h
docker stats

# 检查磁盘空间
df -h
docker system df

# 清理 Docker 缓存
docker system prune -a --volumes

# 清理日志
sudo journalctl --vacuum-time=7d
```

### 优化资源使用

```bash
# 限制容器内存使用（修改 docker-compose.yml）
services:
  gateway:
    mem_limit: 1g
    mem_reservation: 512m
  postgres:
    mem_limit: 512m
    mem_reservation: 256m
```

---

## 日志收集

如果问题仍未解决，收集以下信息：

```bash
# 创建日志目录
mkdir -p ~/openclaw-debug

# 收集系统信息
uname -a > ~/openclaw-debug/system-info.txt
free -h >> ~/openclaw-debug/system-info.txt
df -h >> ~/openclaw-debug/system-info.txt

# 收集 Docker 信息
docker version > ~/openclaw-debug/docker-info.txt
docker-compose version >> ~/openclaw-debug/docker-info.txt
docker info >> ~/openclaw-debug/docker-info.txt

# 收集容器日志
cd ~/openclaw
docker-compose logs > ~/openclaw-debug/openclaw-logs.txt

# 收集配置文件（移除敏感信息）
cp .env ~/openclaw-debug/env-config.txt
# 手动编辑移除 API Keys

# 打包日志
cd ~
tar -czf openclaw-debug.tar.gz openclaw-debug/
```

---

## 获取帮助

如果以上方案都无法解决问题：

1. **GitHub Issues**：https://github.com/openclaw/openclaw/issues
2. **OpenClaw Discord**：https://discord.gg/openclaw
3. **本项目 Issues**：https://github.com/Davidzkeng/openclaw-one-click-deploy/issues

提交 Issue 时请附上：
- 错误信息截图
- 系统信息（OS、内存、Docker 版本）
- 相关日志（记得移除敏感信息）

---

**最后更新**：2026-02-01
**版本**：1.1.0
