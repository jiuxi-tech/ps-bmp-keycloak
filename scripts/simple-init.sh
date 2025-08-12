#!/bin/bash

# 简化的 Keycloak 初始化脚本

set -e

echo "========================================="
echo "开始 Keycloak 初始化配置"
echo "========================================="

# 1. 获取访问令牌
echo "1. 获取管理员访问令牌..."
RESPONSE=$(curl -s -X POST "http://localhost:8080/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin" \
    -d "password=admin123" \
    -d "grant_type=password" \
    -d "client_id=admin-cli")

TOKEN=$(echo $RESPONSE | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('access_token', ''))")

if [ -z "$TOKEN" ]; then
    echo "错误：无法获取访问令牌"
    echo "响应: $RESPONSE"
    exit 1
fi

echo "✓ 成功获取访问令牌"

# 2. 创建测试 Realm
echo "2. 创建测试 Realm..."

# 简化的 Realm 配置
cat > /tmp/test-realm.json <<'EOF'
{
    "realm": "test-realm",
    "enabled": true,
    "displayName": "测试环境",
    "registrationAllowed": true,
    "resetPasswordAllowed": true,
    "rememberMe": true,
    "loginWithEmailAllowed": true,
    "duplicateEmailsAllowed": false,
    "bruteForceProtected": true,
    "failureFactor": 3,
    "internationalizationEnabled": true,
    "supportedLocales": ["en", "zh-CN"],
    "defaultLocale": "zh-CN",
    "smtpServer": {
        "host": "mailhog",
        "port": "1025",
        "from": "noreply@test.local",
        "fromDisplayName": "Keycloak Test"
    },
    "eventsEnabled": true,
    "eventsListeners": ["jboss-logging"],
    "adminEventsEnabled": true,
    "adminEventsDetailsEnabled": true
}
EOF

# 检查 Realm 是否已存在
REALM_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${TOKEN}" \
    "http://localhost:8080/admin/realms/test-realm")

if [ "$REALM_CHECK" = "200" ]; then
    echo "✓ Realm test-realm 已存在"
else
    # 创建 Realm
    CREATE_RESULT=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d @/tmp/test-realm.json \
        "http://localhost:8080/admin/realms")
    
    if [ "$CREATE_RESULT" = "201" ]; then
        echo "✓ 成功创建 Realm: test-realm"
    else
        echo "警告：创建 Realm 返回状态码: $CREATE_RESULT"
    fi
fi

# 3. 创建角色
echo "3. 创建角色..."
for role in admin manager user developer tester; do
    curl -s -X POST \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"${role}\", \"description\": \"${role} role\"}" \
        "http://localhost:8080/admin/realms/test-realm/roles" 2>/dev/null || true
    echo "  - 角色 ${role}"
done
echo "✓ 角色创建完成"

# 4. 创建测试用户
echo "4. 创建测试用户..."
users=("test_admin:管理员" "test_manager:经理" "test_user1:用户1" "test_user2:用户2" "test_dev:开发者")

for user_info in "${users[@]}"; do
    IFS=':' read -r username fullname <<< "$user_info"
    
    # 创建用户 JSON
    cat > /tmp/user.json <<EOF
{
    "username": "${username}",
    "enabled": true,
    "emailVerified": true,
    "firstName": "${fullname}",
    "email": "${username}@test.local",
    "credentials": [{
        "type": "password",
        "value": "Test@123",
        "temporary": false
    }]
}
EOF
    
    curl -s -X POST \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d @/tmp/user.json \
        "http://localhost:8080/admin/realms/test-realm/users" 2>/dev/null || true
    
    echo "  - 用户 ${username} (密码: Test@123)"
done
echo "✓ 用户创建完成"

# 5. 创建客户端应用
echo "5. 创建客户端应用..."

# 前端应用
cat > /tmp/frontend-client.json <<'EOF'
{
    "clientId": "frontend-app",
    "name": "前端应用",
    "rootUrl": "http://localhost:3000",
    "baseUrl": "/",
    "enabled": true,
    "publicClient": true,
    "protocol": "openid-connect",
    "redirectUris": ["http://localhost:3000/*"],
    "webOrigins": ["http://localhost:3000"]
}
EOF

curl -s -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d @/tmp/frontend-client.json \
    "http://localhost:8080/admin/realms/test-realm/clients" 2>/dev/null || true

echo "  - frontend-app (公共客户端)"

# 后端 API
cat > /tmp/backend-client.json <<'EOF'
{
    "clientId": "backend-api",
    "name": "后端API",
    "enabled": true,
    "publicClient": false,
    "protocol": "openid-connect",
    "secret": "backend-secret-123",
    "serviceAccountsEnabled": true,
    "directAccessGrantsEnabled": true
}
EOF

curl -s -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d @/tmp/backend-client.json \
    "http://localhost:8080/admin/realms/test-realm/clients" 2>/dev/null || true

echo "  - backend-api (机密客户端)"
echo "✓ 客户端创建完成"

# 清理临时文件
rm -f /tmp/test-realm.json /tmp/user.json /tmp/frontend-client.json /tmp/backend-client.json

echo ""
echo "========================================="
echo "✅ Keycloak 初始化配置完成！"
echo "========================================="
echo ""
echo "📋 配置摘要："
echo ""
echo "管理控制台："
echo "  URL: http://localhost:8080/admin"
echo "  账号: admin / admin123"
echo ""
echo "测试 Realm："
echo "  名称: test-realm"
echo "  账户控制台: http://localhost:8080/realms/test-realm/account"
echo ""
echo "测试用户 (密码: Test@123)："
echo "  - test_admin   (管理员)"
echo "  - test_manager (经理)"
echo "  - test_user1   (用户1)"
echo "  - test_user2   (用户2)"
echo "  - test_dev     (开发者)"
echo ""
echo "测试客户端："
echo "  - frontend-app (前端应用)"
echo "  - backend-api  (后端API, 密钥: backend-secret-123)"
echo ""
echo "邮件服务："
echo "  SMTP: mailhog:1025"
echo "  Web UI: http://localhost:8025"
echo ""
echo "已启用功能："
echo "  ✓ 中文界面 (默认语言)"
echo "  ✓ 审计日志"
echo "  ✓ 邮件服务"
echo "  ✓ 暴力破解保护"
echo "========================================="