#!/bin/bash

# 修复应用接入认证问题脚本

set -e

KEYCLOAK_URL="http://localhost:8080"
REALM_NAME="test-realm"

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}        修复应用接入认证问题${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# 获取管理员令牌
get_admin_token() {
    local response=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin" \
        -d "password=admin123" \
        -d "grant_type=password" \
        -d "client_id=admin-cli")
    
    echo $response | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo ""
}

ADMIN_TOKEN=$(get_admin_token)

if [ -z "$ADMIN_TOKEN" ]; then
    echo -e "${RED}错误：无法获取管理员访问令牌${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 获取管理员令牌成功${NC}"
echo ""

# 1. 修复 webapp-client 配置
echo -e "${YELLOW}1. 修复 webapp-client 配置...${NC}"

# 获取客户端ID
CLIENT_ID=$(curl -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients?clientId=webapp-client" | \
    python3 -c "import json, sys; clients=json.load(sys.stdin); print(clients[0]['id'] if clients else '')" 2>/dev/null || echo "")

if [ -n "$CLIENT_ID" ]; then
    # 更新客户端配置
    curl -s -X PUT \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "webapp-client",
            "name": "Web应用客户端",
            "enabled": true,
            "publicClient": false,
            "protocol": "openid-connect",
            "secret": "webapp-secret-123",
            "rootUrl": "http://localhost:3000",
            "baseUrl": "/app",
            "redirectUris": ["http://localhost:3000/callback", "http://localhost:3000/*"],
            "webOrigins": ["http://localhost:3000", "*"],
            "standardFlowEnabled": true,
            "implicitFlowEnabled": false,
            "directAccessGrantsEnabled": true,
            "serviceAccountsEnabled": false,
            "authorizationServicesEnabled": false,
            "fullScopeAllowed": true,
            "consentRequired": false,
            "attributes": {
                "post.logout.redirect.uris": "http://localhost:3000/logout",
                "backchannel.logout.session.required": "true",
                "access.token.lifespan": "300",
                "client.session.idle.timeout": "1800",
                "client.session.max.lifespan": "36000"
            }
        }' \
        "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients/${CLIENT_ID}" > /dev/null
    
    echo -e "   ${GREEN}✓ webapp-client 配置已更新${NC}"
else
    echo -e "   ${RED}✗ 无法找到 webapp-client${NC}"
fi

# 2. 修复前端应用客户端配置
echo -e "${YELLOW}2. 修复 frontend-app 配置...${NC}"

FRONTEND_CLIENT_ID=$(curl -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients?clientId=frontend-app" | \
    python3 -c "import json, sys; clients=json.load(sys.stdin); print(clients[0]['id'] if clients else '')" 2>/dev/null || echo "")

if [ -n "$FRONTEND_CLIENT_ID" ]; then
    curl -s -X PUT \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "frontend-app",
            "name": "前端应用",
            "enabled": true,
            "publicClient": true,
            "protocol": "openid-connect",
            "rootUrl": "http://localhost:3000",
            "baseUrl": "/",
            "redirectUris": ["http://localhost:3000/*"],
            "webOrigins": ["*"],
            "standardFlowEnabled": true,
            "implicitFlowEnabled": false,
            "directAccessGrantsEnabled": true,
            "serviceAccountsEnabled": false,
            "fullScopeAllowed": true,
            "consentRequired": false,
            "attributes": {
                "pkce.code.challenge.method": "S256",
                "post.logout.redirect.uris": "+"
            }
        }' \
        "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients/${FRONTEND_CLIENT_ID}" > /dev/null
    
    echo -e "   ${GREEN}✓ frontend-app 配置已更新${NC}"
else
    echo -e "   ${RED}✗ 无法找到 frontend-app${NC}"
fi

# 3. 配置 Realm 设置
echo -e "${YELLOW}3. 优化 Realm 配置...${NC}"

curl -s -X PUT \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "accessTokenLifespan": 300,
        "accessTokenLifespanForImplicitFlow": 900,
        "ssoSessionIdleTimeout": 1800,
        "ssoSessionMaxLifespan": 36000,
        "ssoSessionIdleTimeoutRememberMe": 0,
        "ssoSessionMaxLifespanRememberMe": 0,
        "offlineSessionIdleTimeout": 2592000,
        "offlineSessionMaxLifespanEnabled": false,
        "accessCodeLifespan": 60,
        "accessCodeLifespanUserAction": 300,
        "accessCodeLifespanLogin": 1800,
        "actionTokenGeneratedByAdminLifespan": 43200,
        "actionTokenGeneratedByUserLifespan": 300,
        "bruteForceProtected": true,
        "permanentLockout": false,
        "maxFailureWaitSeconds": 900,
        "minimumQuickLoginWaitSeconds": 60,
        "waitIncrementSeconds": 60,
        "quickLoginCheckMilliSeconds": 1000,
        "maxDeltaTimeSeconds": 43200,
        "failureFactor": 3,
        "defaultSignatureAlgorithm": "RS256"
    }' \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" > /dev/null

echo -e "   ${GREEN}✓ Realm 配置已优化${NC}"

echo ""

# 4. 验证修复效果
echo -e "${YELLOW}4. 验证修复效果...${NC}"

# 测试密码凭证流程
echo -n "   测试密码凭证流程: "
PASSWORD_TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=webapp-client" \
    -d "client_secret=webapp-secret-123" \
    -d "username=test_user1" \
    -d "password=Test@123" | \
    python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo "")

if [ -n "$PASSWORD_TOKEN" ]; then
    echo -e "${GREEN}✓ 成功${NC}"
    
    # 测试令牌刷新
    echo -n "   测试令牌刷新: "
    REFRESH_TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=password" \
        -d "client_id=webapp-client" \
        -d "client_secret=webapp-secret-123" \
        -d "username=test_user1" \
        -d "password=Test@123" | \
        python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('refresh_token', ''))" 2>/dev/null || echo "")
    
    if [ -n "$REFRESH_TOKEN" ]; then
        NEW_TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=refresh_token" \
            -d "client_id=webapp-client" \
            -d "client_secret=webapp-secret-123" \
            -d "refresh_token=${REFRESH_TOKEN}" | \
            python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo "")
        
        if [ -n "$NEW_TOKEN" ]; then
            echo -e "${GREEN}✓ 成功${NC}"
        else
            echo -e "${RED}✗ 失败${NC}"
        fi
    else
        echo -e "${RED}✗ 无刷新令牌${NC}"
    fi
else
    echo -e "${RED}✗ 失败${NC}"
fi

# 测试公共客户端
echo -n "   测试公共客户端: "
PUBLIC_TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=frontend-app" \
    -d "username=test_user1" \
    -d "password=Test@123" | \
    python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo "")

if [ -n "$PUBLIC_TOKEN" ]; then
    echo -e "${GREEN}✓ 成功${NC}"
else
    echo -e "${RED}✗ 失败${NC}"
fi

# 测试作用域限制
echo -n "   测试作用域限制: "
SCOPED_TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=webapp-client" \
    -d "client_secret=webapp-secret-123" \
    -d "username=test_user1" \
    -d "password=Test@123" \
    -d "scope=openid profile email" | \
    python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo "")

if [ -n "$SCOPED_TOKEN" ]; then
    echo -e "${GREEN}✓ 成功${NC}"
else
    echo -e "${RED}✗ 失败${NC}"
fi

echo ""

# 5. 创建测试脚本
echo -e "${YELLOW}5. 创建持续测试脚本...${NC}"

cat > "/mnt/d/Keycloak_project/scripts/quick-auth-test.sh" <<'EOF'
#!/bin/bash

# 快速认证测试脚本

KEYCLOAK_URL="http://localhost:8080"
REALM_NAME="test-realm"

echo "=== Keycloak 认证快速测试 ==="
echo ""

# 1. 密码凭证流程 (机密客户端)
echo -n "1. 密码凭证流程 (webapp-client): "
RESPONSE1=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=webapp-client" \
    -d "client_secret=webapp-secret-123" \
    -d "username=test_user1" \
    -d "password=Test@123")

TOKEN1=$(echo $RESPONSE1 | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo "")
if [ -n "$TOKEN1" ]; then
    echo "✓ 成功"
else
    echo "✗ 失败"
    echo "  错误: $(echo $RESPONSE1 | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('error_description', data.get('error', '未知错误')))" 2>/dev/null || echo "解析错误")"
fi

# 2. 密码凭证流程 (公共客户端)
echo -n "2. 密码凭证流程 (frontend-app): "
RESPONSE2=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=frontend-app" \
    -d "username=test_user1" \
    -d "password=Test@123")

TOKEN2=$(echo $RESPONSE2 | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo "")
if [ -n "$TOKEN2" ]; then
    echo "✓ 成功"
else
    echo "✗ 失败"
    echo "  错误: $(echo $RESPONSE2 | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('error_description', data.get('error', '未知错误')))" 2>/dev/null || echo "解析错误")"
fi

# 3. 客户端凭证流程
echo -n "3. 客户端凭证流程 (service-account): "
RESPONSE3=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials" \
    -d "client_id=service-account" \
    -d "client_secret=service-secret-456")

TOKEN3=$(echo $RESPONSE3 | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo "")
if [ -n "$TOKEN3" ]; then
    echo "✓ 成功"
else
    echo "✗ 失败"
    echo "  错误: $(echo $RESPONSE3 | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('error_description', data.get('error', '未知错误')))" 2>/dev/null || echo "解析错误")"
fi

# 4. 令牌刷新测试
if [ -n "$TOKEN1" ]; then
    echo -n "4. 令牌刷新测试: "
    REFRESH_TOKEN=$(echo $RESPONSE1 | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('refresh_token', ''))" 2>/dev/null || echo "")
    
    if [ -n "$REFRESH_TOKEN" ]; then
        REFRESH_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=refresh_token" \
            -d "client_id=webapp-client" \
            -d "client_secret=webapp-secret-123" \
            -d "refresh_token=${REFRESH_TOKEN}")
        
        NEW_TOKEN=$(echo $REFRESH_RESPONSE | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo "")
        if [ -n "$NEW_TOKEN" ]; then
            echo "✓ 成功"
        else
            echo "✗ 失败"
        fi
    else
        echo "✗ 无刷新令牌"
    fi
fi

echo ""
echo "测试完成！"
EOF

chmod +x "/mnt/d/Keycloak_project/scripts/quick-auth-test.sh"
echo -e "   ${GREEN}✓ 快速测试脚本已创建: scripts/quick-auth-test.sh${NC}"

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                  修复完成${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${GREEN}✅ 认证问题修复完成！${NC}"
echo ""
echo "已完成的修复："
echo "  • webapp-client 配置优化 (启用密码凭证流程)"
echo "  • frontend-app 配置优化 (公共客户端配置)" 
echo "  • Realm 令牌生命周期优化"
echo "  • CORS 和跨域访问配置"
echo "  • 创建快速测试脚本"
echo ""
echo "下一步建议："
echo "  1. 运行快速测试: ./scripts/quick-auth-test.sh"
echo "  2. 重新运行完整测试: ./scripts/test-app-integration.sh"
echo "  3. 使用生成的集成示例进行实际测试"