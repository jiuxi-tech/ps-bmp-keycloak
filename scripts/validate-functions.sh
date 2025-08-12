#!/bin/bash

# Keycloak 功能验证脚本
# 根据 keycloak-deployment-validation-plan.md 执行功能验证

set -e

# 配置
KEYCLOAK_URL="http://localhost:8080"
REALM_NAME="test-realm"
ADMIN_USER="admin"
ADMIN_PASSWORD="admin123"

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 测试结果统计
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 打印函数
test_header() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=========================================${NC}"
}

test_item() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "  测试: $1 ... "
}

test_pass() {
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo -e "${GREEN}✓ 通过${NC}"
    if [ -n "$1" ]; then
        echo "    详情: $1"
    fi
}

test_fail() {
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo -e "${RED}✗ 失败${NC}"
    if [ -n "$1" ]; then
        echo "    错误: $1"
    fi
}

# 获取访问令牌
get_token() {
    local username=$1
    local password=$2
    local client_id=${3:-"admin-cli"}
    local realm=${4:-"master"}
    
    local response=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${realm}/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${username}" \
        -d "password=${password}" \
        -d "grant_type=password" \
        -d "client_id=${client_id}")
    
    echo $response | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo ""
}

# 获取管理员令牌
ADMIN_TOKEN=$(get_token "$ADMIN_USER" "$ADMIN_PASSWORD")

if [ -z "$ADMIN_TOKEN" ]; then
    echo -e "${RED}错误：无法获取管理员访问令牌${NC}"
    exit 1
fi

# ============================================
# 一、用户管理功能验证
# ============================================
test_header "一、用户管理功能验证"

# 1.1 用户 CRUD 操作
test_item "用户查询功能"
USER_COUNT=$(curl -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/count")
if [ "$USER_COUNT" -gt 0 ]; then
    test_pass "当前用户数: $USER_COUNT"
else
    test_fail "无法获取用户数量"
fi

# 1.2 创建新用户
test_item "创建新用户"
NEW_USER_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "username": "test_new_user",
        "enabled": true,
        "email": "new_user@test.local",
        "firstName": "新",
        "lastName": "用户",
        "credentials": [{
            "type": "password",
            "value": "Test@123",
            "temporary": false
        }]
    }' \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users")

if [ "$NEW_USER_RESPONSE" = "201" ] || [ "$NEW_USER_RESPONSE" = "409" ]; then
    test_pass "用户创建成功或已存在"
else
    test_fail "HTTP 状态码: $NEW_USER_RESPONSE"
fi

# 1.3 用户搜索
test_item "用户搜索功能"
SEARCH_RESULT=$(curl -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users?search=test_" | \
    python3 -c "import json, sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

if [ "$SEARCH_RESULT" -gt 0 ]; then
    test_pass "找到 $SEARCH_RESULT 个匹配用户"
else
    test_fail "搜索功能异常"
fi

# ============================================
# 二、认证功能验证
# ============================================
test_header "二、认证功能验证"

# 2.1 用户登录测试
test_item "用户密码认证"
USER_TOKEN=$(get_token "test_user1" "Test@123" "frontend-app" "$REALM_NAME")
if [ -n "$USER_TOKEN" ]; then
    test_pass "用户登录成功"
else
    test_fail "用户登录失败"
fi

# 2.2 错误密码测试
test_item "错误密码拒绝"
INVALID_TOKEN=$(get_token "test_user1" "wrong_password" "frontend-app" "$REALM_NAME")
if [ -z "$INVALID_TOKEN" ]; then
    test_pass "错误密码正确拒绝"
else
    test_fail "错误密码未被拒绝"
fi

# 2.3 客户端凭证测试
test_item "客户端凭证授权"
CLIENT_TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials" \
    -d "client_id=backend-api" \
    -d "client_secret=backend-secret-123" | \
    python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo "")

if [ -n "$CLIENT_TOKEN" ]; then
    test_pass "客户端凭证授权成功"
else
    test_fail "客户端凭证授权失败"
fi

# ============================================
# 三、角色和权限管理验证
# ============================================
test_header "三、角色和权限管理验证"

# 3.1 角色列表
test_item "角色查询功能"
ROLE_COUNT=$(curl -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/roles" | \
    python3 -c "import json, sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

if [ "$ROLE_COUNT" -gt 0 ]; then
    test_pass "找到 $ROLE_COUNT 个角色"
else
    test_fail "无法获取角色列表"
fi

# 3.2 用户角色分配
test_item "用户角色分配"
# 获取用户ID
USER_ID=$(curl -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users?username=test_user1" | \
    python3 -c "import json, sys; users=json.load(sys.stdin); print(users[0]['id'] if users else '')" 2>/dev/null || echo "")

if [ -n "$USER_ID" ]; then
    # 获取角色
    ROLE_ID=$(curl -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/roles/user" | \
        python3 -c "import json, sys; role=json.load(sys.stdin); print(role.get('id', ''))" 2>/dev/null || echo "")
    
    if [ -n "$ROLE_ID" ]; then
        # 分配角色
        ASSIGN_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
            -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "[{\"id\":\"${ROLE_ID}\",\"name\":\"user\"}]" \
            "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${USER_ID}/role-mappings/realm")
        
        if [ "$ASSIGN_RESPONSE" = "204" ] || [ "$ASSIGN_RESPONSE" = "409" ]; then
            test_pass "角色分配成功"
        else
            test_fail "角色分配失败: $ASSIGN_RESPONSE"
        fi
    else
        test_fail "无法获取角色ID"
    fi
else
    test_fail "无法获取用户ID"
fi

# ============================================
# 四、客户端和应用集成验证
# ============================================
test_header "四、客户端和应用集成验证"

# 4.1 客户端列表
test_item "客户端查询"
CLIENT_COUNT=$(curl -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients" | \
    python3 -c "import json, sys; clients=json.load(sys.stdin); print(len([c for c in clients if not c['clientId'].startswith('$')]))" 2>/dev/null || echo "0")

if [ "$CLIENT_COUNT" -gt 0 ]; then
    test_pass "找到 $CLIENT_COUNT 个自定义客户端"
else
    test_fail "无法获取客户端列表"
fi

# 4.2 OpenID Connect 发现端点
test_item "OIDC 发现端点"
OIDC_CONFIG=$(curl -s -o /dev/null -w "%{http_code}" \
    "${KEYCLOAK_URL}/realms/${REALM_NAME}/.well-known/openid-configuration")

if [ "$OIDC_CONFIG" = "200" ]; then
    test_pass "OIDC 配置端点可访问"
else
    test_fail "OIDC 配置端点不可用: $OIDC_CONFIG"
fi

# ============================================
# 五、审计和事件验证
# ============================================
test_header "五、审计和事件验证"

# 5.1 事件配置检查
test_item "事件记录配置"
EVENT_CONFIG=$(curl -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" | \
    python3 -c "import json, sys; realm=json.load(sys.stdin); print('enabled' if realm.get('eventsEnabled') else 'disabled')" 2>/dev/null || echo "unknown")

if [ "$EVENT_CONFIG" = "enabled" ]; then
    test_pass "事件记录已启用"
else
    test_fail "事件记录未启用: $EVENT_CONFIG"
fi

# 5.2 管理事件配置
test_item "管理事件配置"
ADMIN_EVENT_CONFIG=$(curl -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" | \
    python3 -c "import json, sys; realm=json.load(sys.stdin); print('enabled' if realm.get('adminEventsEnabled') else 'disabled')" 2>/dev/null || echo "unknown")

if [ "$ADMIN_EVENT_CONFIG" = "enabled" ]; then
    test_pass "管理事件记录已启用"
else
    test_fail "管理事件记录未启用: $ADMIN_EVENT_CONFIG"
fi

# ============================================
# 六、邮件服务验证
# ============================================
test_header "六、邮件服务验证"

# 6.1 SMTP 配置检查
test_item "SMTP 服务配置"
SMTP_CONFIG=$(curl -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" | \
    python3 -c "import json, sys; realm=json.load(sys.stdin); smtp=realm.get('smtpServer', {}); print('configured' if smtp.get('host') else 'not configured')" 2>/dev/null || echo "unknown")

if [ "$SMTP_CONFIG" = "configured" ]; then
    test_pass "SMTP 服务已配置"
else
    test_fail "SMTP 服务未配置: $SMTP_CONFIG"
fi

# 6.2 MailHog 连接测试
test_item "MailHog 服务"
MAILHOG_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8025/api/v2/messages")
if [ "$MAILHOG_STATUS" = "200" ]; then
    test_pass "MailHog 服务正常"
else
    test_fail "MailHog 服务不可用: $MAILHOG_STATUS"
fi

# ============================================
# 测试结果汇总
# ============================================
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}测试结果汇总${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo -e "总测试数: ${TOTAL_TESTS}"
echo -e "${GREEN}通过: ${PASSED_TESTS}${NC}"
echo -e "${RED}失败: ${FAILED_TESTS}${NC}"

SUCCESS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
echo ""
if [ $SUCCESS_RATE -ge 80 ]; then
    echo -e "${GREEN}✅ 功能验证通过 (成功率: ${SUCCESS_RATE}%)${NC}"
    echo ""
    echo "下一步建议："
    echo "1. 继续进行高级功能测试（MFA、LDAP集成等）"
    echo "2. 执行性能和压力测试"
    echo "3. 配置生产环境设置"
else
    echo -e "${YELLOW}⚠️  功能验证部分通过 (成功率: ${SUCCESS_RATE}%)${NC}"
    echo ""
    echo "建议检查："
    echo "1. 查看 Keycloak 日志: docker compose logs keycloak"
    echo "2. 确认服务状态: docker compose ps"
    echo "3. 重新运行初始化脚本: ./scripts/simple-init.sh"
fi

echo ""
echo "详细测试报告已保存至: validation-report-$(date +%Y%m%d-%H%M%S).txt"

# 保存详细报告
{
    echo "Keycloak 功能验证报告"
    echo "生成时间: $(date)"
    echo ""
    echo "环境信息:"
    echo "  Keycloak URL: ${KEYCLOAK_URL}"
    echo "  Realm: ${REALM_NAME}"
    echo ""
    echo "测试结果:"
    echo "  总测试数: ${TOTAL_TESTS}"
    echo "  通过: ${PASSED_TESTS}"
    echo "  失败: ${FAILED_TESTS}"
    echo "  成功率: ${SUCCESS_RATE}%"
} > "validation-report-$(date +%Y%m%d-%H%M%S).txt"