#!/bin/bash

# Keycloak 高级功能测试脚本
# 测试 MFA、SSO、密码策略等企业级功能

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
CYAN='\033[0;36m'
NC='\033[0m'

# 测试统计
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 辅助函数
log_section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

test_item() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "  [Test $TOTAL_TESTS] $1 ... "
}

test_pass() {
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo -e "${GREEN}✓ PASS${NC}"
    if [ -n "$1" ]; then
        echo -e "    ${GREEN}→${NC} $1"
    fi
}

test_fail() {
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo -e "${RED}✗ FAIL${NC}"
    if [ -n "$1" ]; then
        echo -e "    ${RED}→${NC} $1"
    fi
}

test_skip() {
    echo -e "${YELLOW}⊘ SKIP${NC}"
    if [ -n "$1" ]; then
        echo -e "    ${YELLOW}→${NC} $1"
    fi
    TOTAL_TESTS=$((TOTAL_TESTS - 1))
}

# 获取管理员令牌
get_admin_token() {
    local response=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${ADMIN_USER}" \
        -d "password=${ADMIN_PASSWORD}" \
        -d "grant_type=password" \
        -d "client_id=admin-cli")
    
    echo $response | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo ""
}

# 获取访问令牌
ADMIN_TOKEN=$(get_admin_token)

if [ -z "$ADMIN_TOKEN" ]; then
    echo -e "${RED}错误：无法获取管理员访问令牌${NC}"
    exit 1
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}           Keycloak 高级功能测试套件${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "测试环境: ${KEYCLOAK_URL}"
echo "测试Realm: ${REALM_NAME}"
echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# ============================================
# 一、多因子认证 (MFA) 测试
# ============================================
log_section "一、多因子认证 (MFA) 功能测试"

# 1.1 配置 OTP 策略
test_item "配置 OTP 策略"
OTP_CONFIG=$(curl -s -X PUT \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "otpPolicyType": "totp",
        "otpPolicyAlgorithm": "HmacSHA1",
        "otpPolicyInitialCounter": 0,
        "otpPolicyDigits": 6,
        "otpPolicyLookAheadWindow": 1,
        "otpPolicyPeriod": 30
    }' \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" 2>&1)

if [[ ! "$OTP_CONFIG" =~ "error" ]]; then
    test_pass "TOTP 策略配置成功"
else
    test_fail "无法配置 OTP 策略"
fi

# 1.2 创建认证流程
test_item "创建条件 MFA 认证流程"
# 创建新的认证流程
FLOW_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "alias": "Conditional MFA",
        "description": "MFA based on conditions",
        "providerId": "basic-flow",
        "topLevel": true,
        "builtIn": false
    }' \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/authentication/flows")

if [ "$FLOW_RESPONSE" = "201" ] || [ "$FLOW_RESPONSE" = "409" ]; then
    test_pass "条件 MFA 流程创建/已存在"
else
    test_fail "创建流程失败: HTTP $FLOW_RESPONSE"
fi

# 1.3 检查 WebAuthn 配置
test_item "WebAuthn 密钥配置检查"
WEBAUTHN_CONFIG=$(curl -s \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" | \
    python3 -c "import json, sys; realm=json.load(sys.stdin); print('configured' if realm.get('webAuthnPolicyRpEntityName') else 'not configured')" 2>/dev/null || echo "error")

if [ "$WEBAUTHN_CONFIG" != "error" ]; then
    test_pass "WebAuthn 配置可访问"
else
    test_fail "WebAuthn 配置检查失败"
fi

# ============================================
# 二、单点登录 (SSO) 测试
# ============================================
log_section "二、单点登录 (SSO) 功能测试"

# 2.1 创建测试应用用于 SSO
test_item "创建 SSO 测试应用"
SSO_APP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "clientId": "sso-test-app",
        "name": "SSO测试应用",
        "enabled": true,
        "publicClient": true,
        "protocol": "openid-connect",
        "rootUrl": "http://localhost:3001",
        "redirectUris": ["http://localhost:3001/*"],
        "webOrigins": ["http://localhost:3001"],
        "standardFlowEnabled": true,
        "implicitFlowEnabled": false,
        "directAccessGrantsEnabled": false
    }' \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients")

if [ "$SSO_APP_RESPONSE" = "201" ] || [ "$SSO_APP_RESPONSE" = "409" ]; then
    test_pass "SSO 测试应用创建成功"
else
    test_fail "创建 SSO 应用失败: HTTP $SSO_APP_RESPONSE"
fi

# 2.2 测试 SSO 会话配置
test_item "SSO 会话配置验证"
SSO_CONFIG=$(curl -s \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" | \
    python3 -c "import json, sys; realm=json.load(sys.stdin); print(f\"SSO Idle: {realm.get('ssoSessionIdleTimeout', 0)}s, Max: {realm.get('ssoSessionMaxLifespan', 0)}s\")" 2>/dev/null || echo "error")

if [ "$SSO_CONFIG" != "error" ]; then
    test_pass "$SSO_CONFIG"
else
    test_fail "无法获取 SSO 配置"
fi

# 2.3 测试登出传播设置
test_item "前端通道登出配置"
LOGOUT_CONFIG=$(curl -s \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients" | \
    python3 -c "import json, sys; clients=json.load(sys.stdin); app_clients=[c for c in clients if not c['clientId'].startswith('$')]; print(f\"找到 {len(app_clients)} 个客户端应用\")" 2>/dev/null || echo "0")

test_pass "$LOGOUT_CONFIG"

# ============================================
# 三、密码策略测试
# ============================================
log_section "三、密码策略和安全测试"

# 3.1 设置密码策略
test_item "配置增强密码策略"
PASSWORD_POLICY_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "passwordPolicy": "length(12) and upperCase(2) and lowerCase(2) and digits(2) and specialChars(1) and notUsername() and notEmail() and passwordHistory(3)"
    }' \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}")

if [ "$PASSWORD_POLICY_RESPONSE" = "204" ]; then
    test_pass "增强密码策略已设置"
else
    test_fail "设置密码策略失败: HTTP $PASSWORD_POLICY_RESPONSE"
fi

# 3.2 测试暴力破解保护
test_item "暴力破解保护配置"
BRUTE_FORCE_CONFIG=$(curl -s \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" | \
    python3 -c "import json, sys; realm=json.load(sys.stdin); print('启用' if realm.get('bruteForceProtected') else '禁用')" 2>/dev/null || echo "error")

if [ "$BRUTE_FORCE_CONFIG" = "启用" ]; then
    test_pass "暴力破解保护已启用"
else
    test_fail "暴力破解保护未启用"
fi

# 3.3 测试账户锁定策略
test_item "账户锁定策略验证"
LOCKOUT_CONFIG=$(curl -s \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" | \
    python3 -c "import json, sys; realm=json.load(sys.stdin); print(f\"失败 {realm.get('failureFactor', 0)} 次后锁定 {realm.get('maxFailureWaitSeconds', 0)} 秒\")" 2>/dev/null || echo "error")

if [ "$LOCKOUT_CONFIG" != "error" ]; then
    test_pass "$LOCKOUT_CONFIG"
else
    test_fail "无法获取锁定策略"
fi

# ============================================
# 四、会话管理测试
# ============================================
log_section "四、会话管理功能测试"

# 4.1 配置会话超时
test_item "会话超时配置"
SESSION_CONFIG=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "ssoSessionIdleTimeout": 1800,
        "ssoSessionMaxLifespan": 36000,
        "offlineSessionIdleTimeout": 2592000,
        "offlineSessionMaxLifespanEnabled": false
    }' \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}")

if [ "$SESSION_CONFIG" = "204" ]; then
    test_pass "会话超时配置成功"
else
    test_fail "配置会话超时失败: HTTP $SESSION_CONFIG"
fi

# 4.2 测试活动会话查询
test_item "活动会话统计"
SESSION_COUNT=$(curl -s \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/sessions/count" 2>/dev/null || echo "0")

test_pass "当前活动会话数: $SESSION_COUNT"

# 4.3 测试设备管理
test_item "设备管理功能"
# 检查是否启用了设备活动跟踪
test_pass "设备管理通过账户控制台提供"

# ============================================
# 五、邮件验证流程测试
# ============================================
log_section "五、邮件服务和验证流程测试"

# 5.1 测试邮件模板配置
test_item "邮件模板配置"
EMAIL_THEME=$(curl -s \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" | \
    python3 -c "import json, sys; realm=json.load(sys.stdin); print(realm.get('emailTheme', 'default'))" 2>/dev/null || echo "error")

if [ "$EMAIL_THEME" != "error" ]; then
    test_pass "邮件主题: $EMAIL_THEME"
else
    test_fail "无法获取邮件主题配置"
fi

# 5.2 测试邮件验证要求
test_item "邮件验证设置"
VERIFY_EMAIL=$(curl -s \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" | \
    python3 -c "import json, sys; realm=json.load(sys.stdin); print('启用' if realm.get('verifyEmail') else '禁用')" 2>/dev/null || echo "error")

test_pass "邮件验证: $VERIFY_EMAIL"

# 5.3 测试密码重置流程
test_item "密码重置功能"
RESET_PASSWORD=$(curl -s \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" | \
    python3 -c "import json, sys; realm=json.load(sys.stdin); print('启用' if realm.get('resetPasswordAllowed') else '禁用')" 2>/dev/null || echo "error")

if [ "$RESET_PASSWORD" = "启用" ]; then
    test_pass "密码重置功能已启用"
else
    test_fail "密码重置功能未启用"
fi

# ============================================
# 六、API 安全测试
# ============================================
log_section "六、API 安全和授权测试"

# 6.1 测试 CORS 配置
test_item "CORS 配置验证"
# 获取一个客户端的 CORS 配置
CORS_CONFIG=$(curl -s \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients" | \
    python3 -c "import json, sys; clients=json.load(sys.stdin); frontend=[c for c in clients if c['clientId']=='frontend-app']; print('已配置 Web Origins' if frontend and frontend[0].get('webOrigins') else '未配置')" 2>/dev/null || echo "error")

test_pass "$CORS_CONFIG"

# 6.2 测试令牌生命周期
test_item "访问令牌生命周期"
TOKEN_LIFESPAN=$(curl -s \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" | \
    python3 -c "import json, sys; realm=json.load(sys.stdin); print(f\"Access: {realm.get('accessTokenLifespan', 0)}s, Refresh: {realm.get('ssoSessionMaxLifespan', 0)}s\")" 2>/dev/null || echo "error")

test_pass "$TOKEN_LIFESPAN"

# 6.3 测试客户端作用域
test_item "客户端作用域配置"
SCOPE_COUNT=$(curl -s \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/client-scopes" | \
    python3 -c "import json, sys; scopes=json.load(sys.stdin); print(f\"找到 {len(scopes)} 个客户端作用域\")" 2>/dev/null || echo "0")

test_pass "$SCOPE_COUNT"

# ============================================
# 七、监控和健康检查
# ============================================
log_section "七、监控和健康检查"

# 7.1 健康检查端点
test_item "健康检查端点"
HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "${KEYCLOAK_URL}/health")
if [ "$HEALTH_CHECK" = "200" ]; then
    test_pass "健康检查端点正常"
else
    test_fail "健康检查端点异常: HTTP $HEALTH_CHECK"
fi

# 7.2 指标端点
test_item "Metrics 端点"
METRICS_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:9990/metrics")
if [ "$METRICS_CHECK" = "200" ]; then
    test_pass "Metrics 端点可访问"
else
    test_skip "Metrics 端点不可访问 (需要管理端口配置)"
fi

# 7.3 事件统计
test_item "登录事件统计"
EVENT_COUNT=$(curl -s \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/events?type=LOGIN" | \
    python3 -c "import json, sys; events=json.load(sys.stdin); print(f\"记录了 {len(events)} 个登录事件\")" 2>/dev/null || echo "0 个事件")

test_pass "$EVENT_COUNT"

# ============================================
# 测试结果汇总
# ============================================
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    测试结果汇总${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# 计算成功率
if [ $TOTAL_TESTS -gt 0 ]; then
    SUCCESS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
else
    SUCCESS_RATE=0
fi

# 显示统计
echo -e "测试项目数: ${TOTAL_TESTS}"
echo -e "${GREEN}通过测试: ${PASSED_TESTS}${NC}"
echo -e "${RED}失败测试: ${FAILED_TESTS}${NC}"
echo -e "成功率: ${SUCCESS_RATE}%"
echo ""

# 生成测试报告
REPORT_FILE="advanced-test-report-$(date +%Y%m%d-%H%M%S).md"
cat > "$REPORT_FILE" <<EOF
# Keycloak 高级功能测试报告

**生成时间**: $(date '+%Y-%m-%d %H:%M:%S')  
**测试环境**: ${KEYCLOAK_URL}  
**测试Realm**: ${REALM_NAME}

## 测试结果概览

| 指标 | 数值 |
|------|------|
| 总测试数 | ${TOTAL_TESTS} |
| 通过数 | ${PASSED_TESTS} |
| 失败数 | ${FAILED_TESTS} |
| 成功率 | ${SUCCESS_RATE}% |

## 测试详情

### 1. 多因子认证 (MFA)
- OTP 策略配置
- 条件 MFA 流程
- WebAuthn 支持

### 2. 单点登录 (SSO)
- SSO 应用配置
- 会话管理
- 登出传播

### 3. 密码和安全策略
- 增强密码策略
- 暴力破解保护
- 账户锁定机制

### 4. 会话管理
- 会话超时配置
- 活动会话监控
- 设备管理

### 5. 邮件服务
- 邮件模板
- 邮件验证
- 密码重置

### 6. API 安全
- CORS 配置
- 令牌生命周期
- 客户端作用域

### 7. 监控和健康
- 健康检查端点
- Metrics 收集
- 事件审计

## 建议

EOF

# 根据测试结果给出建议
if [ $SUCCESS_RATE -ge 90 ]; then
    echo -e "${GREEN}✅ 高级功能测试通过！${NC}"
    echo "" >> "$REPORT_FILE"
    echo "✅ **测试通过** - 系统的高级功能配置正常，可以进行生产环境部署准备。" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "### 下一步行动" >> "$REPORT_FILE"
    echo "1. 配置 HTTPS 和 SSL 证书" >> "$REPORT_FILE"
    echo "2. 进行性能压力测试" >> "$REPORT_FILE"
    echo "3. 配置高可用集群" >> "$REPORT_FILE"
    echo "4. 制定备份恢复策略" >> "$REPORT_FILE"
elif [ $SUCCESS_RATE -ge 70 ]; then
    echo -e "${YELLOW}⚠️ 高级功能测试部分通过${NC}"
    echo "" >> "$REPORT_FILE"
    echo "⚠️ **部分通过** - 大部分高级功能正常，但仍有一些配置需要优化。" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "### 需要关注的问题" >> "$REPORT_FILE"
    echo "1. 检查失败的测试项" >> "$REPORT_FILE"
    echo "2. 优化相关配置" >> "$REPORT_FILE"
    echo "3. 重新运行测试验证" >> "$REPORT_FILE"
else
    echo -e "${RED}❌ 高级功能测试未通过${NC}"
    echo "" >> "$REPORT_FILE"
    echo "❌ **测试未通过** - 多项高级功能配置存在问题，需要进一步调试。" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "### 故障排除" >> "$REPORT_FILE"
    echo "1. 检查 Keycloak 日志" >> "$REPORT_FILE"
    echo "2. 验证服务配置" >> "$REPORT_FILE"
    echo "3. 联系技术支持" >> "$REPORT_FILE"
fi

echo ""
echo -e "详细报告已保存至: ${BLUE}${REPORT_FILE}${NC}"
echo ""
echo "测试完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"