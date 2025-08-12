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
