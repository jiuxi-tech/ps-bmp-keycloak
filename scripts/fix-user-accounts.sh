#!/bin/bash

# 修复用户账户设置问题脚本

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
echo -e "${BLUE}        修复用户账户设置问题${NC}"
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

# 1. 检查和修复测试用户
echo -e "${YELLOW}1. 检查和修复测试用户...${NC}"

fix_user() {
    local username=$1
    local password=$2
    local first_name=$3
    local last_name=$4
    
    echo -n "   修复用户 $username: "
    
    # 获取用户ID
    USER_ID=$(curl -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users?username=${username}" | \
        python3 -c "import json, sys; users=json.load(sys.stdin); print(users[0]['id'] if users else '')" 2>/dev/null || echo "")
    
    if [ -n "$USER_ID" ]; then
        # 更新用户配置
        curl -s -X PUT \
            -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{
                \"username\": \"${username}\",
                \"enabled\": true,
                \"emailVerified\": true,
                \"firstName\": \"${first_name}\",
                \"lastName\": \"${last_name}\",
                \"email\": \"${username}@test.local\",
                \"requiredActions\": [],
                \"attributes\": {
                    \"department\": [\"技术部\"],
                    \"position\": [\"${first_name}\"]
                }
            }" \
            "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${USER_ID}" > /dev/null
        
        # 重置密码
        curl -s -X PUT \
            -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{
                \"type\": \"password\",
                \"value\": \"${password}\",
                \"temporary\": false
            }" \
            "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${USER_ID}/reset-password" > /dev/null
        
        echo -e "${GREEN}✓ 成功${NC}"
    else
        echo -e "${RED}✗ 用户不存在${NC}"
    fi
}

# 修复所有测试用户
fix_user "test_user1" "Test@123" "测试用户" "1号"
fix_user "test_user2" "Test@123" "测试用户" "2号"
fix_user "test_admin" "Test@123" "管理员" "测试"
fix_user "test_manager" "Test@123" "经理" "测试"
fix_user "test_dev" "Test@123" "开发者" "测试"

echo ""

# 2. 创建完全新的测试用户（以防万一）
echo -e "${YELLOW}2. 创建全新的测试用户...${NC}"

create_new_user() {
    local username=$1
    local password=$2
    local first_name=$3
    local role=$4
    
    echo -n "   创建用户 $username: "
    
    # 删除现有用户（如果存在）
    EXISTING_USER_ID=$(curl -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users?username=${username}" | \
        python3 -c "import json, sys; users=json.load(sys.stdin); print(users[0]['id'] if users else '')" 2>/dev/null || echo "")
    
    if [ -n "$EXISTING_USER_ID" ]; then
        curl -s -X DELETE \
            -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${EXISTING_USER_ID}" > /dev/null
    fi
    
    # 创建新用户
    CREATE_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"username\": \"${username}\",
            \"enabled\": true,
            \"emailVerified\": true,
            \"firstName\": \"${first_name}\",
            \"lastName\": \"用户\",
            \"email\": \"${username}@example.com\",
            \"credentials\": [{
                \"type\": \"password\",
                \"value\": \"${password}\",
                \"temporary\": false
            }],
            \"requiredActions\": [],
            \"attributes\": {
                \"department\": [\"测试部门\"],
                \"position\": [\"${first_name}\"]
            }
        }" \
        "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users")
    
    if [ "$CREATE_RESPONSE" = "201" ]; then
        # 获取新创建用户的ID
        NEW_USER_ID=$(curl -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users?username=${username}" | \
            python3 -c "import json, sys; users=json.load(sys.stdin); print(users[0]['id'] if users else '')" 2>/dev/null || echo "")
        
        # 分配角色
        if [ -n "$NEW_USER_ID" ] && [ -n "$role" ]; then
            ROLE_ID=$(curl -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
                "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/roles/${role}" | \
                python3 -c "import json, sys; role=json.load(sys.stdin); print(role.get('id', ''))" 2>/dev/null || echo "")
            
            if [ -n "$ROLE_ID" ]; then
                curl -s -X POST \
                    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
                    -H "Content-Type: application/json" \
                    -d "[{\"id\":\"${ROLE_ID}\",\"name\":\"${role}\"}]" \
                    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${NEW_USER_ID}/role-mappings/realm" > /dev/null
            fi
        fi
        
        echo -e "${GREEN}✓ 成功${NC}"
    else
        echo -e "${RED}✗ 失败 (HTTP $CREATE_RESPONSE)${NC}"
    fi
}

# 创建全新测试用户
create_new_user "demo_user" "Demo@123" "演示用户" "user"
create_new_user "demo_admin" "Demo@123" "演示管理员" "admin"

echo ""

# 3. 验证修复效果
echo -e "${YELLOW}3. 验证修复效果...${NC}"

test_user_auth() {
    local username=$1
    local password=$2
    
    echo -n "   测试用户 $username 认证: "
    
    # 测试机密客户端
    TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=password" \
        -d "client_id=webapp-client" \
        -d "client_secret=webapp-secret-123" \
        -d "username=${username}" \
        -d "password=${password}")
    
    ACCESS_TOKEN=$(echo $TOKEN_RESPONSE | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo "")
    ERROR_DESC=$(echo $TOKEN_RESPONSE | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('error_description', data.get('error', '')))" 2>/dev/null || echo "")
    
    if [ -n "$ACCESS_TOKEN" ]; then
        echo -e "${GREEN}✓ 成功${NC}"
        
        # 测试令牌有效性
        USER_INFO=$(curl -s \
            -H "Authorization: Bearer ${ACCESS_TOKEN}" \
            "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/userinfo" | \
            python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('preferred_username', ''))" 2>/dev/null || echo "")
        
        if [ -n "$USER_INFO" ]; then
            echo "     用户信息获取: ${GREEN}✓ $USER_INFO${NC}"
        fi
        
        # 测试公共客户端
        echo -n "     公共客户端测试: "
        PUBLIC_TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=password" \
            -d "client_id=frontend-app" \
            -d "username=${username}" \
            -d "password=${password}" | \
            python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo "")
        
        if [ -n "$PUBLIC_TOKEN" ]; then
            echo -e "${GREEN}✓ 成功${NC}"
        else
            echo -e "${RED}✗ 失败${NC}"
        fi
        
    else
        echo -e "${RED}✗ 失败${NC}"
        if [ -n "$ERROR_DESC" ]; then
            echo "     错误: $ERROR_DESC"
        fi
    fi
    
    echo ""
}

# 测试修复后的用户
test_user_auth "demo_user" "Demo@123"
test_user_auth "demo_admin" "Demo@123"

# 4. 创建完整的测试脚本
echo -e "${YELLOW}4. 创建完整的认证测试脚本...${NC}"

cat > "/mnt/d/Keycloak_project/scripts/comprehensive-auth-test.sh" <<'EOF'
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
EOF

chmod +x "/mnt/d/Keycloak_project/scripts/comprehensive-auth-test.sh"
echo -e "   ${GREEN}✓ 完整测试脚本已创建: scripts/comprehensive-auth-test.sh${NC}"

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                  用户修复完成${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${GREEN}✅ 用户账户修复完成！${NC}"
echo ""
echo "已完成的操作："
echo "  • 修复现有测试用户配置"
echo "  • 移除所有必需操作 (Required Actions)"
echo "  • 创建全新的演示用户账号"
echo "  • 设置正确的密码和邮箱验证状态"
echo "  • 创建完整的认证测试脚本"
echo ""
echo "新创建的测试用户："
echo "  • demo_user / Demo@123 (普通用户)"
echo "  • demo_admin / Demo@123 (管理员)"
echo ""
echo "下一步测试："
echo "  1. 运行完整测试: ./scripts/comprehensive-auth-test.sh"
echo "  2. 重新运行应用集成测试: ./scripts/test-app-integration.sh"