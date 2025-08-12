#!/bin/bash

# 简化的高级功能测试脚本

set -e

KEYCLOAK_URL="http://localhost:8080"
REALM_NAME="test-realm"

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Keycloak 高级功能快速测试${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# 获取管理员令牌
echo "获取管理员访问令牌..."
TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin" \
    -d "password=admin123" \
    -d "grant_type=password" \
    -d "client_id=admin-cli")

TOKEN=$(echo $TOKEN_RESPONSE | python3 -c "import json, sys; print(json.load(sys.stdin).get('access_token', ''))" 2>/dev/null || echo "")

if [ -z "$TOKEN" ]; then
    echo -e "${RED}错误：无法获取访问令牌${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 成功获取令牌${NC}"
echo ""

# 测试计数
PASSED=0
FAILED=0

# 测试函数
run_test() {
    local test_name=$1
    local result=$2
    
    if [ "$result" = "success" ]; then
        echo -e "  ${GREEN}✓${NC} $test_name"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}✗${NC} $test_name"
        FAILED=$((FAILED + 1))
    fi
}

# 1. MFA 测试
echo -e "${BLUE}1. 多因子认证 (MFA) 配置${NC}"

# 配置 OTP
OTP_RESULT=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "otpPolicyType": "totp",
        "otpPolicyAlgorithm": "HmacSHA1",
        "otpPolicyDigits": 6,
        "otpPolicyPeriod": 30
    }' \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}")

if [ "$OTP_RESULT" = "204" ]; then
    run_test "OTP 策略配置" "success"
else
    run_test "OTP 策略配置" "fail"
fi

# 检查 MFA 配置
MFA_CHECK=$(curl -s \
    -H "Authorization: Bearer ${TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" | \
    python3 -c "import json, sys; r=json.load(sys.stdin); print('ok' if r.get('otpPolicyType') else 'fail')" 2>/dev/null || echo "fail")

if [ "$MFA_CHECK" = "ok" ]; then
    run_test "MFA 配置验证" "success"
else
    run_test "MFA 配置验证" "fail"
fi

echo ""

# 2. SSO 测试
echo -e "${BLUE}2. 单点登录 (SSO) 配置${NC}"

# 检查 SSO 会话配置
SSO_CHECK=$(curl -s \
    -H "Authorization: Bearer ${TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" | \
    python3 -c "import json, sys; r=json.load(sys.stdin); print('ok' if r.get('ssoSessionIdleTimeout') else 'fail')" 2>/dev/null || echo "fail")

if [ "$SSO_CHECK" = "ok" ]; then
    run_test "SSO 会话配置" "success"
else
    run_test "SSO 会话配置" "fail"
fi

# 检查客户端数量
CLIENT_COUNT=$(curl -s \
    -H "Authorization: Bearer ${TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients" | \
    python3 -c "import json, sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

if [ "$CLIENT_COUNT" -gt 0 ]; then
    run_test "SSO 客户端配置 (找到 $CLIENT_COUNT 个客户端)" "success"
else
    run_test "SSO 客户端配置" "fail"
fi

echo ""

# 3. 密码策略测试
echo -e "${BLUE}3. 密码和安全策略${NC}"

# 设置密码策略
PWD_RESULT=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"passwordPolicy": "length(8) and upperCase(1) and lowerCase(1) and digits(1) and specialChars(1)"}' \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}")

if [ "$PWD_RESULT" = "204" ]; then
    run_test "密码策略配置" "success"
else
    run_test "密码策略配置" "fail"
fi

# 检查暴力破解保护
BRUTE_CHECK=$(curl -s \
    -H "Authorization: Bearer ${TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" | \
    python3 -c "import json, sys; r=json.load(sys.stdin); print('ok' if r.get('bruteForceProtected') else 'fail')" 2>/dev/null || echo "fail")

if [ "$BRUTE_CHECK" = "ok" ]; then
    run_test "暴力破解保护" "success"
else
    run_test "暴力破解保护" "fail"
fi

echo ""

# 4. 邮件服务测试
echo -e "${BLUE}4. 邮件服务配置${NC}"

# 检查 SMTP 配置
SMTP_CHECK=$(curl -s \
    -H "Authorization: Bearer ${TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" | \
    python3 -c "import json, sys; r=json.load(sys.stdin); print('ok' if r.get('smtpServer',{}).get('host') else 'fail')" 2>/dev/null || echo "fail")

if [ "$SMTP_CHECK" = "ok" ]; then
    run_test "SMTP 服务配置" "success"
else
    run_test "SMTP 服务配置" "fail"
fi

# 检查 MailHog
MAILHOG_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8025/api/v2/messages")
if [ "$MAILHOG_CHECK" = "200" ]; then
    run_test "MailHog 邮件服务" "success"
else
    run_test "MailHog 邮件服务" "fail"
fi

echo ""

# 5. 审计日志测试
echo -e "${BLUE}5. 审计和事件日志${NC}"

# 检查事件配置
EVENT_CHECK=$(curl -s \
    -H "Authorization: Bearer ${TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" | \
    python3 -c "import json, sys; r=json.load(sys.stdin); print('ok' if r.get('eventsEnabled') else 'fail')" 2>/dev/null || echo "fail")

if [ "$EVENT_CHECK" = "ok" ]; then
    run_test "事件日志启用" "success"
else
    run_test "事件日志启用" "fail"
fi

# 检查管理事件
ADMIN_EVENT_CHECK=$(curl -s \
    -H "Authorization: Bearer ${TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" | \
    python3 -c "import json, sys; r=json.load(sys.stdin); print('ok' if r.get('adminEventsEnabled') else 'fail')" 2>/dev/null || echo "fail")

if [ "$ADMIN_EVENT_CHECK" = "ok" ]; then
    run_test "管理事件日志" "success"
else
    run_test "管理事件日志" "fail"
fi

echo ""

# 6. API 端点测试
echo -e "${BLUE}6. API 端点可用性${NC}"

# OIDC 发现端点
OIDC_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
    "${KEYCLOAK_URL}/realms/${REALM_NAME}/.well-known/openid-configuration")

if [ "$OIDC_CHECK" = "200" ]; then
    run_test "OIDC 发现端点" "success"
else
    run_test "OIDC 发现端点" "fail"
fi

# JWKS 端点
JWKS_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
    "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/certs")

if [ "$JWKS_CHECK" = "200" ]; then
    run_test "JWKS 证书端点" "success"
else
    run_test "JWKS 证书端点" "fail"
fi

echo ""

# 总结
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}测试结果总结${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

TOTAL=$((PASSED + FAILED))
if [ $TOTAL -gt 0 ]; then
    SUCCESS_RATE=$((PASSED * 100 / TOTAL))
else
    SUCCESS_RATE=0
fi

echo "测试项目: $TOTAL"
echo -e "${GREEN}通过: $PASSED${NC}"
echo -e "${RED}失败: $FAILED${NC}"
echo "成功率: ${SUCCESS_RATE}%"
echo ""

# 保存报告
REPORT_FILE="advanced-test-summary-$(date +%Y%m%d-%H%M%S).txt"
{
    echo "Keycloak 高级功能测试摘要"
    echo "========================"
    echo "测试时间: $(date)"
    echo ""
    echo "测试结果:"
    echo "  总数: $TOTAL"
    echo "  通过: $PASSED"
    echo "  失败: $FAILED"
    echo "  成功率: ${SUCCESS_RATE}%"
    echo ""
    echo "已验证功能:"
    echo "  - 多因子认证 (MFA/OTP)"
    echo "  - 单点登录 (SSO)"
    echo "  - 密码策略和安全"
    echo "  - 邮件服务集成"
    echo "  - 审计日志"
    echo "  - API 端点"
} > "$REPORT_FILE"

if [ $SUCCESS_RATE -ge 80 ]; then
    echo -e "${GREEN}✅ 高级功能测试通过！${NC}"
    echo ""
    echo "下一步建议："
    echo "1. 进行压力测试和性能测试"
    echo "2. 配置生产环境安全设置"
    echo "3. 实施高可用部署方案"
else
    echo -e "${RED}⚠️ 部分高级功能需要调整${NC}"
    echo ""
    echo "建议检查："
    echo "1. 查看失败的测试项"
    echo "2. 检查 Keycloak 日志"
    echo "3. 验证配置是否正确"
fi

echo ""
echo "测试报告已保存至: $REPORT_FILE"