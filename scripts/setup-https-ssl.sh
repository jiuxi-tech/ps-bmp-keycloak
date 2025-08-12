#!/bin/bash

# Keycloak HTTPS/SSL 配置脚本
# 配置生产环境 SSL 证书和 HTTPS 访问

set -e

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

DOMAIN=${1:-"keycloak.local"}
CERTS_DIR="/mnt/d/Keycloak_project/certs"
SSL_DIR="/mnt/d/Keycloak_project/ssl-config"

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}          Keycloak HTTPS/SSL 配置工具${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "域名: $DOMAIN"
echo "证书目录: $CERTS_DIR"
echo ""

# 创建必要的目录
mkdir -p "$CERTS_DIR"
mkdir -p "$SSL_DIR"

# ============================================
# 1. 生成自签名 SSL 证书
# ============================================
echo -e "${CYAN}1. 生成 SSL 证书${NC}"

if [ ! -f "$CERTS_DIR/keycloak.crt" ]; then
    echo "   生成自签名证书..."
    
    # 创建证书配置文件
    cat > "$CERTS_DIR/openssl.conf" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = CN
ST = Beijing
L = Beijing
O = Keycloak Demo
OU = IT Department
CN = $DOMAIN

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = localhost
DNS.3 = *.${DOMAIN}
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

    # 生成私钥
    openssl genrsa -out "$CERTS_DIR/keycloak.key" 2048
    
    # 生成证书签名请求
    openssl req -new -key "$CERTS_DIR/keycloak.key" -out "$CERTS_DIR/keycloak.csr" -config "$CERTS_DIR/openssl.conf"
    
    # 生成自签名证书
    openssl x509 -req -in "$CERTS_DIR/keycloak.csr" -signkey "$CERTS_DIR/keycloak.key" -out "$CERTS_DIR/keycloak.crt" -days 365 -extensions v3_req -extfile "$CERTS_DIR/openssl.conf"
    
    # 创建 PKCS12 格式证书（Keycloak 使用）
    openssl pkcs12 -export -in "$CERTS_DIR/keycloak.crt" -inkey "$CERTS_DIR/keycloak.key" -out "$CERTS_DIR/keycloak.p12" -name keycloak -passout pass:changeit
    
    echo -e "   ${GREEN}✓ SSL 证书生成完成${NC}"
    echo "     - 私钥: $CERTS_DIR/keycloak.key"
    echo "     - 证书: $CERTS_DIR/keycloak.crt"
    echo "     - PKCS12: $CERTS_DIR/keycloak.p12"
else
    echo -e "   ${GREEN}✓ SSL 证书已存在${NC}"
fi

echo ""

# ============================================
# 2. 创建 HTTPS Docker Compose 配置
# ============================================
echo -e "${CYAN}2. 创建 HTTPS Docker Compose 配置${NC}"

cat > "$SSL_DIR/docker-compose-https.yml" <<EOF
version: '3.8'

services:
  postgres:
    image: postgres:15
    container_name: keycloak-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: keycloak
      POSTGRES_USER: keycloak
      POSTGRES_PASSWORD: keycloak123
      POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --locale=C.UTF-8"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5433:5432"
    networks:
      - keycloak-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U keycloak"]
      interval: 10s
      timeout: 5s
      retries: 5

  keycloak:
    image: quay.io/keycloak/keycloak:latest
    container_name: keycloak-https
    restart: unless-stopped
    environment:
      # Database
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://postgres:5432/keycloak
      KC_DB_USERNAME: keycloak
      KC_DB_PASSWORD: keycloak123
      
      # Admin credentials
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: admin123
      
      # HTTPS Configuration
      KC_HOSTNAME: ${DOMAIN}
      KC_HOSTNAME_STRICT: true
      KC_HOSTNAME_STRICT_HTTPS: true
      KC_HTTP_ENABLED: false
      KC_HTTPS_PORT: 8443
      KC_HTTPS_CERTIFICATE_FILE: /opt/keycloak/conf/keycloak.crt
      KC_HTTPS_CERTIFICATE_KEY_FILE: /opt/keycloak/conf/keycloak.key
      
      # Security Headers
      KC_HTTP_RELATIVE_PATH: /
      KC_PROXY: edge
      
      # Features and logging
      KC_HEALTH_ENABLED: true
      KC_METRICS_ENABLED: true
      KC_LOG_LEVEL: INFO
      KC_LOG_CONSOLE_OUTPUT: default
      
      # Performance tuning
      JAVA_OPTS_APPEND: >-
        -Xms2048m -Xmx4096m
        -XX:+UseG1GC
        -XX:MaxGCPauseMillis=100
        -Djava.security.egd=file:/dev/urandom
        -Duser.timezone=Asia/Shanghai
    ports:
      - "8443:8443"  # HTTPS only
      - "9990:9990"  # Management port
    command: 
      - start
      - --import-realm
      - --optimized
    volumes:
      - ./keycloak-data:/opt/keycloak/data
      - ./themes:/opt/keycloak/themes
      - ./providers:/opt/keycloak/providers
      - ./import:/opt/keycloak/data/import
      - ../certs/keycloak.crt:/opt/keycloak/conf/keycloak.crt:ro
      - ../certs/keycloak.key:/opt/keycloak/conf/keycloak.key:ro
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - keycloak-network
    healthcheck:
      test: ["CMD-SHELL", "curl -f https://localhost:8443/health/ready --insecure || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  # Reverse Proxy (Nginx)
  nginx:
    image: nginx:alpine
    container_name: keycloak-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ../certs/keycloak.crt:/etc/ssl/certs/keycloak.crt:ro
      - ../certs/keycloak.key:/etc/ssl/private/keycloak.key:ro
    depends_on:
      - keycloak
    networks:
      - keycloak-network

  mailhog:
    image: mailhog/mailhog:latest
    container_name: keycloak-mailhog
    restart: unless-stopped
    ports:
      - "1025:1025"
      - "8025:8025"
    networks:
      - keycloak-network

  adminer:
    image: adminer:latest
    container_name: keycloak-adminer
    restart: unless-stopped
    ports:
      - "8090:8080"
    environment:
      ADMINER_DEFAULT_SERVER: postgres
    networks:
      - keycloak-network
    depends_on:
      - postgres

volumes:
  postgres_data:
    driver: local

networks:
  keycloak-network:
    driver: bridge
EOF

echo -e "   ${GREEN}✓ HTTPS Docker Compose 配置创建完成${NC}"
echo ""

# ============================================
# 3. 创建 Nginx 反向代理配置
# ============================================
echo -e "${CYAN}3. 创建 Nginx 反向代理配置${NC}"

cat > "$SSL_DIR/nginx.conf" <<EOF
events {
    worker_connections 1024;
}

http {
    upstream keycloak {
        server keycloak:8443;
    }
    
    # HTTP 重定向到 HTTPS
    server {
        listen 80;
        server_name ${DOMAIN} localhost;
        
        # Let's Encrypt ACME 挑战
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }
        
        # 其他所有请求重定向到 HTTPS
        location / {
            return 301 https://\$server_name\$request_uri;
        }
    }
    
    # HTTPS 配置
    server {
        listen 443 ssl http2;
        server_name ${DOMAIN} localhost;
        
        # SSL 证书配置
        ssl_certificate /etc/ssl/certs/keycloak.crt;
        ssl_certificate_key /etc/ssl/private/keycloak.key;
        
        # SSL 安全配置
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;
        
        # 安全头
        add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "DENY" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self'" always;
        
        # 反向代理到 Keycloak
        location / {
            proxy_pass https://keycloak;
            proxy_ssl_verify off;  # 因为使用自签名证书
            
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Forwarded-Port \$server_port;
            
            # WebSocket 支持
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            
            # 缓冲配置
            proxy_buffering off;
            proxy_request_buffering off;
        }
    }
}
EOF

echo -e "   ${GREEN}✓ Nginx 配置创建完成${NC}"
echo ""

# ============================================
# 4. 创建生产环境启动脚本
# ============================================
echo -e "${CYAN}4. 创建生产环境启动脚本${NC}"

cat > "$SSL_DIR/start-https.sh" <<'EOF'
#!/bin/bash

# Keycloak HTTPS 生产环境启动脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 颜色
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}启动 Keycloak HTTPS 生产环境...${NC}"
echo ""

# 检查证书
if [ ! -f "../certs/keycloak.crt" ]; then
    echo -e "${YELLOW}警告: SSL 证书不存在，请先运行 setup-https-ssl.sh${NC}"
    exit 1
fi

# 切换到配置目录
cd "$SCRIPT_DIR"

# 停止现有服务
echo "停止现有服务..."
docker compose -f docker-compose-https.yml down 2>/dev/null || true
docker compose -f ../docker-compose.yml down 2>/dev/null || true

# 启动 HTTPS 服务
echo "启动 HTTPS 服务..."
docker compose -f docker-compose-https.yml up -d

echo ""
echo -e "${GREEN}✅ HTTPS 服务启动完成！${NC}"
echo ""
echo "访问地址："
echo "  - HTTPS 主站: https://localhost"
echo "  - 管理控制台: https://localhost/admin"
echo "  - 账户控制台: https://localhost/realms/test-realm/account"
echo ""
echo "服务状态检查："
echo "  docker compose -f docker-compose-https.yml ps"
echo ""
echo "查看日志："
echo "  docker compose -f docker-compose-https.yml logs -f keycloak"
EOF

chmod +x "$SSL_DIR/start-https.sh"

echo -e "   ${GREEN}✓ 启动脚本创建完成${NC}"
echo ""

# ============================================
# 5. 创建 Let's Encrypt 配置脚本
# ============================================
echo -e "${CYAN}5. 创建 Let's Encrypt 生产证书脚本${NC}"

cat > "$SSL_DIR/setup-letsencrypt.sh" <<EOF
#!/bin/bash

# Let's Encrypt 证书配置脚本（生产环境使用）

DOMAIN=\${1:-"your-domain.com"}
EMAIL=\${2:-"admin@your-domain.com"}

if [ "\$DOMAIN" = "your-domain.com" ]; then
    echo "使用方法: \$0 <域名> <邮箱>"
    echo "示例: \$0 keycloak.example.com admin@example.com"
    exit 1
fi

echo "配置 Let's Encrypt 证书..."
echo "域名: \$DOMAIN"
echo "邮箱: \$EMAIL"

# 安装 Certbot
if ! command -v certbot &> /dev/null; then
    echo "安装 Certbot..."
    sudo apt-get update
    sudo apt-get install -y certbot python3-certbot-nginx
fi

# 获取证书
sudo certbot --nginx -d \$DOMAIN --non-interactive --agree-tos --email \$EMAIL --redirect

# 设置自动更新
echo "设置证书自动更新..."
sudo crontab -l 2>/dev/null | { cat; echo "0 12 * * * /usr/bin/certbot renew --quiet"; } | sudo crontab -

echo "✅ Let's Encrypt 证书配置完成！"
EOF

chmod +x "$SSL_DIR/setup-letsencrypt.sh"

echo -e "   ${GREEN}✓ Let's Encrypt 脚本创建完成${NC}"
echo ""

# ============================================
# 6. 创建安全配置检查脚本
# ============================================
echo -e "${CYAN}6. 创建安全配置检查脚本${NC}"

cat > "$SSL_DIR/security-check.sh" <<'EOF'
#!/bin/bash

# Keycloak HTTPS 安全配置检查脚本

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DOMAIN=${1:-"localhost"}

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}          Keycloak HTTPS 安全检查${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

check_ssl() {
    local url=$1
    local name=$2
    
    echo -n "检查 $name SSL 配置: "
    
    if curl -s -I --insecure "https://$url" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ 可访问${NC}"
        
        # 检查证书详情
        echo -n "  证书有效期: "
        CERT_INFO=$(echo | openssl s_client -servername "$url" -connect "$url:443" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
        if [ $? -eq 0 ]; then
            EXPIRY=$(echo "$CERT_INFO" | grep "notAfter" | cut -d= -f2)
            echo -e "${GREEN}$EXPIRY${NC}"
        else
            echo -e "${YELLOW}无法获取${NC}"
        fi
        
        # 检查 TLS 版本
        echo -n "  TLS 1.2 支持: "
        if openssl s_client -tls1_2 -servername "$url" -connect "$url:443" < /dev/null > /dev/null 2>&1; then
            echo -e "${GREEN}✓ 支持${NC}"
        else
            echo -e "${RED}✗ 不支持${NC}"
        fi
        
        echo -n "  TLS 1.3 支持: "
        if openssl s_client -tls1_3 -servername "$url" -connect "$url:443" < /dev/null > /dev/null 2>&1; then
            echo -e "${GREEN}✓ 支持${NC}"
        else
            echo -e "${YELLOW}不支持${NC}"
        fi
        
    else
        echo -e "${RED}✗ 无法访问${NC}"
    fi
    echo ""
}

check_headers() {
    local url=$1
    
    echo "检查安全头配置:"
    
    HEADERS=$(curl -s -I --insecure "https://$url" 2>/dev/null || echo "")
    
    check_header() {
        local header=$1
        local name=$2
        
        echo -n "  $name: "
        if echo "$HEADERS" | grep -i "$header" > /dev/null; then
            echo -e "${GREEN}✓ 已配置${NC}"
        else
            echo -e "${YELLOW}未配置${NC}"
        fi
    }
    
    check_header "strict-transport-security" "HSTS"
    check_header "x-content-type-options" "Content-Type Options"
    check_header "x-frame-options" "Frame Options"
    check_header "x-xss-protection" "XSS Protection"
    check_header "content-security-policy" "CSP"
    
    echo ""
}

check_ports() {
    echo "检查端口配置:"
    
    echo -n "  HTTP (80): "
    if nc -z localhost 80 2>/dev/null; then
        echo -e "${GREEN}✓ 开放 (应该重定向到 HTTPS)${NC}"
    else
        echo -e "${YELLOW}关闭${NC}"
    fi
    
    echo -n "  HTTPS (443): "
    if nc -z localhost 443 2>/dev/null; then
        echo -e "${GREEN}✓ 开放${NC}"
    else
        echo -e "${RED}✗ 关闭${NC}"
    fi
    
    echo -n "  Keycloak HTTPS (8443): "
    if nc -z localhost 8443 2>/dev/null; then
        echo -e "${YELLOW}✓ 开放 (建议仅内部访问)${NC}"
    else
        echo -e "${GREEN}关闭 (推荐配置)${NC}"
    fi
    
    echo ""
}

# 执行检查
check_ssl "$DOMAIN" "主站"
check_headers "$DOMAIN"
check_ports

echo -e "${BLUE}安全检查完成！${NC}"
echo ""
echo "建议："
echo "1. 使用真实 CA 签发的证书替换自签名证书"
echo "2. 配置防火墙规则限制不必要的端口访问"
echo "3. 定期更新 SSL 证书"
echo "4. 启用 HTTP/2 和 HSTS"
EOF

chmod +x "$SSL_DIR/security-check.sh"

echo -e "   ${GREEN}✓ 安全检查脚本创建完成${NC}"
echo ""

# ============================================
# 总结
# ============================================
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                HTTPS/SSL 配置完成${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${GREEN}✅ 配置文件已创建：${NC}"
echo "  📁 证书目录: $CERTS_DIR"
echo "  📁 SSL 配置: $SSL_DIR"
echo "  🔐 SSL 证书: $CERTS_DIR/keycloak.crt"
echo "  🔑 私钥文件: $CERTS_DIR/keycloak.key"
echo "  📋 Docker Compose: $SSL_DIR/docker-compose-https.yml"
echo "  🌐 Nginx 配置: $SSL_DIR/nginx.conf"
echo ""

echo -e "${YELLOW}📋 下一步操作：${NC}"
echo ""
echo "1. 启动 HTTPS 服务："
echo "   cd $SSL_DIR && ./start-https.sh"
echo ""
echo "2. 安全检查："
echo "   cd $SSL_DIR && ./security-check.sh"
echo ""
echo "3. 生产环境证书（可选）："
echo "   cd $SSL_DIR && ./setup-letsencrypt.sh your-domain.com admin@your-domain.com"
echo ""
echo "4. 添加域名解析（可选）："
echo "   echo '127.0.0.1 $DOMAIN' | sudo tee -a /etc/hosts"
echo ""

echo -e "${CYAN}💡 提醒：${NC}"
echo "• 自签名证书浏览器会显示不安全警告，生产环境请使用正式证书"
echo "• 确保防火墙已开放 80 和 443 端口"
echo "• HTTPS 模式下原 HTTP 端口 8080 将不可用"