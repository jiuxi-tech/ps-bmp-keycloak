#!/bin/bash

# 完整的认证功能测试脚本

KEYCLOAK_URL="http://localhost:8080"
REALM_NAME="test-realm"

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Keycloak 完整认证功能测试 ===${NC}"
echo ""

run_test() {
    local test_name="$1"
    local username="$2"
    local password="$3"
    local client_id="$4"
    local client_secret="$5"
    
    echo -e "${YELLOW}测试: $test_name${NC}"
    
    # 构建请求参数
    local auth_data="grant_type=password&client_id=$client_id&username=$username&password=$password"
    if [ -n "$client_secret" ]; then
        auth_data="${auth_data}&client_secret=$client_secret"
    fi
    
    # 执行请求
    local response=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "$auth_data")
    
    # 解析结果
    local access_token=$(echo "$response" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo "")
    local error_desc=$(echo "$response" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('error_description', data.get('error', '')))" 2>/dev/null || echo "")
    
    if [ -n "$access_token" ]; then
        echo -e "  状态: ${GREEN}✓ 成功${NC}"
        
        # 获取用户信息
        local user_info=$(curl -s \
            -H "Authorization: Bearer $access_token" \
            "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/userinfo")
        local preferred_username=$(echo "$user_info" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('preferred_username', ''))" 2>/dev/null || echo "")
        local email=$(echo "$user_info" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('email', ''))" 2>/dev/null || echo "")
        
        echo "  用户: $preferred_username"
        echo "  邮箱: $email"
        
        # 测试令牌刷新（如果是机密客户端）
        if [ -n "$client_secret" ]; then
            local refresh_token=$(echo "$response" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('refresh_token', ''))" 2>/dev/null || echo "")
            if [ -n "$refresh_token" ]; then
                echo -n "  令牌刷新: "
                local refresh_response=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
                    -H "Content-Type: application/x-www-form-urlencoded" \
                    -d "grant_type=refresh_token&client_id=$client_id&client_secret=$client_secret&refresh_token=$refresh_token")
                local new_token=$(echo "$refresh_response" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo "")
                if [ -n "$new_token" ]; then
                    echo -e "${GREEN}✓ 成功${NC}"
                else
                    echo -e "${RED}✗ 失败${NC}"
                fi
            fi
        fi
        
    else
        echo -e "  状态: ${RED}✗ 失败${NC}"
        if [ -n "$error_desc" ]; then
            echo "  错误: $error_desc"
        fi
    fi
    
    echo ""
}

# 运行各种测试场景
run_test "机密客户端 + demo_user" "demo_user" "Demo@123" "webapp-client" "webapp-secret-123"
run_test "公共客户端 + demo_user" "demo_user" "Demo@123" "frontend-app" ""
run_test "机密客户端 + demo_admin" "demo_admin" "Demo@123" "webapp-client" "webapp-secret-123"
run_test "公共客户端 + demo_admin" "demo_admin" "Demo@123" "frontend-app" ""

# 客户端凭证测试
echo -e "${YELLOW}测试: 客户端凭证流程${NC}"
SERVICE_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials&client_id=service-account&client_secret=service-secret-456")

SERVICE_TOKEN=$(echo "$SERVICE_RESPONSE" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo "")
if [ -n "$SERVICE_TOKEN" ]; then
    echo -e "  状态: ${GREEN}✓ 成功${NC}"
    echo "  令牌类型: 服务账号"
else
    echo -e "  状态: ${RED}✗ 失败${NC}"
fi

echo ""
echo -e "${BLUE}测试完成！${NC}"
