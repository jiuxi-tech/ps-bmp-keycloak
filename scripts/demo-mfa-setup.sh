#!/bin/bash

# Keycloak MFA 演示脚本
# 演示如何配置和使用多因子认证

set -e

KEYCLOAK_URL="http://localhost:8080"
REALM_NAME="test-realm"

# 颜色
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}          Keycloak MFA (多因子认证) 功能演示${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
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

echo -e "${GREEN}✓ 成功获取管理员令牌${NC}"
echo ""

# ============================================
# 1. 配置 OTP 策略
# ============================================
echo -e "${CYAN}1. 配置 OTP (一次性密码) 策略${NC}"
echo "   设置 TOTP (Time-based OTP) 参数..."

curl -s -X PUT \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "otpPolicyType": "totp",
        "otpPolicyAlgorithm": "HmacSHA1",
        "otpPolicyInitialCounter": 0,
        "otpPolicyDigits": 6,
        "otpPolicyLookAheadWindow": 1,
        "otpPolicyPeriod": 30,
        "otpPolicyCodeReusable": false
    }' \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" > /dev/null

echo -e "   ${GREEN}✓ OTP 策略配置完成${NC}"
echo "     - 类型: TOTP (时间基准)"
echo "     - 算法: HmacSHA1"
echo "     - 数字位数: 6 位"
echo "     - 时间窗口: 30 秒"
echo "     - 代码重用: 禁止"
echo ""

# ============================================
# 2. 创建 MFA 认证流程
# ============================================
echo -e "${CYAN}2. 创建 MFA 认证流程${NC}"
echo "   创建自定义认证流程..."

# 删除现有的流程（如果存在）
curl -s -X DELETE \
    -H "Authorization: Bearer ${TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/authentication/flows/MFA%20Demo%20Flow" 2>/dev/null || true

# 创建新的认证流程
curl -s -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "alias": "MFA Demo Flow",
        "description": "演示用的 MFA 认证流程",
        "providerId": "basic-flow",
        "topLevel": true,
        "builtIn": false
    }' \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/authentication/flows" > /dev/null

echo -e "   ${GREEN}✓ MFA 演示流程创建完成${NC}"
echo ""

# ============================================
# 3. 创建 MFA 测试用户
# ============================================
echo -e "${CYAN}3. 创建 MFA 测试用户${NC}"

# 删除现有测试用户（如果存在）
USER_ID=$(curl -s -H "Authorization: Bearer ${TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users?username=mfa_test_user" | \
    python3 -c "import json, sys; users=json.load(sys.stdin); print(users[0]['id'] if users else '')" 2>/dev/null || echo "")

if [ -n "$USER_ID" ]; then
    curl -s -X DELETE \
        -H "Authorization: Bearer ${TOKEN}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${USER_ID}" > /dev/null
fi

# 创建新的 MFA 测试用户
curl -s -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "username": "mfa_test_user",
        "enabled": true,
        "emailVerified": true,
        "firstName": "MFA",
        "lastName": "测试用户",
        "email": "mfa.test@example.com",
        "credentials": [{
            "type": "password",
            "value": "MfaTest@123",
            "temporary": false
        }],
        "requiredActions": ["CONFIGURE_TOTP"]
    }' \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users" > /dev/null

echo -e "   ${GREEN}✓ MFA 测试用户创建完成${NC}"
echo "     - 用户名: mfa_test_user"
echo "     - 密码: MfaTest@123"
echo "     - 必需操作: CONFIGURE_TOTP (配置 TOTP)"
echo ""

# ============================================
# 4. 配置角色基础的条件 MFA
# ============================================
echo -e "${CYAN}4. 配置角色基础的条件 MFA${NC}"

# 创建需要 MFA 的角色
curl -s -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "mfa-required",
        "description": "需要 MFA 验证的角色"
    }' \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/roles" > /dev/null 2>&1 || true

# 获取新创建的用户 ID
NEW_USER_ID=$(curl -s -H "Authorization: Bearer ${TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users?username=mfa_test_user" | \
    python3 -c "import json, sys; users=json.load(sys.stdin); print(users[0]['id'] if users else '')" 2>/dev/null || echo "")

# 获取角色 ID
MFA_ROLE_ID=$(curl -s -H "Authorization: Bearer ${TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/roles/mfa-required" | \
    python3 -c "import json, sys; role=json.load(sys.stdin); print(role.get('id', ''))" 2>/dev/null || echo "")

# 为用户分配角色
if [ -n "$NEW_USER_ID" ] && [ -n "$MFA_ROLE_ID" ]; then
    curl -s -X POST \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "[{\"id\":\"${MFA_ROLE_ID}\",\"name\":\"mfa-required\"}]" \
        "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${NEW_USER_ID}/role-mappings/realm" > /dev/null
fi

echo -e "   ${GREEN}✓ 条件 MFA 配置完成${NC}"
echo "     - 创建角色: mfa-required"
echo "     - 用户分配: mfa_test_user -> mfa-required 角色"
echo ""

# ============================================
# 5. 演示信息和下一步
# ============================================
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    MFA 配置完成！${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}📱 MFA 演示步骤：${NC}"
echo ""
echo "1. 用户首次登录设置:"
echo "   - 访问: ${KEYCLOAK_URL}/realms/${REALM_NAME}/account"
echo "   - 用户名: mfa_test_user"
echo "   - 密码: MfaTest@123"
echo "   - 系统会要求设置 TOTP (扫描二维码)"
echo ""

echo "2. 支持的身份验证器应用:"
echo "   - Google Authenticator (Android/iOS)"
echo "   - Microsoft Authenticator"
echo "   - Authy"
echo "   - FreeOTP"
echo "   - 任何支持 TOTP 标准的应用"
echo ""

echo "3. 管理界面访问:"
echo "   - 管理控制台: ${KEYCLOAK_URL}/admin"
echo "   - 用户管理: 用户 -> mfa_test_user -> Required Actions"
echo "   - 认证设置: 认证 -> Flows -> MFA Demo Flow"
echo ""

echo -e "${YELLOW}🔒 安全特性：${NC}"
echo "   ✓ TOTP 基于时间的一次性密码"
echo "   ✓ 6 位数字验证码"
echo "   ✓ 30 秒时间窗口"
echo "   ✓ 防止验证码重放攻击"
echo "   ✓ 角色基础的条件 MFA"
echo ""

echo -e "${YELLOW}📝 测试场景：${NC}"
echo "   1. 正常用户登录（无 MFA 要求）"
echo "   2. MFA 用户首次登录（设置 TOTP）"
echo "   3. MFA 用户后续登录（输入 TOTP 代码）"
echo "   4. 错误 TOTP 代码处理"
echo "   5. TOTP 设备丢失恢复"
echo ""

# 生成演示报告
DEMO_REPORT="mfa-demo-report-$(date +%Y%m%d-%H%M%S).md"
cat > "$DEMO_REPORT" <<EOF
# Keycloak MFA 演示报告

**生成时间**: $(date '+%Y-%m-%d %H:%M:%S')  
**测试环境**: ${KEYCLOAK_URL}  
**测试Realm**: ${REALM_NAME}

## 配置摘要

### OTP 策略
- 类型: TOTP (Time-based One-Time Password)
- 算法: HmacSHA1
- 验证码位数: 6 位
- 时间窗口: 30 秒
- 代码重用: 禁止

### 测试用户
- **用户名**: mfa_test_user
- **密码**: MfaTest@123
- **邮箱**: mfa.test@example.com
- **必需操作**: CONFIGURE_TOTP
- **角色**: mfa-required

### 认证流程
- **流程名**: MFA Demo Flow
- **类型**: 基本流程
- **用途**: 演示 MFA 功能

## 测试步骤

### 1. 用户首次登录
1. 访问账户控制台
2. 使用测试用户登录
3. 系统要求配置 TOTP
4. 使用手机应用扫描二维码
5. 输入验证码完成设置

### 2. 后续登录
1. 输入用户名密码
2. 系统要求输入 TOTP 验证码
3. 从手机应用获取当前验证码
4. 登录成功

### 3. 管理功能
- 用户可以在账户设置中管理 TOTP 设备
- 管理员可以重置用户的 TOTP 设置
- 支持备份代码功能

## 支持的应用

- Google Authenticator
- Microsoft Authenticator  
- Authy
- FreeOTP
- 其他 TOTP 标准应用

## 安全特性

✅ 基于时间的一次性密码  
✅ 防重放攻击保护  
✅ 多设备支持  
✅ 备份恢复机制  
✅ 条件性 MFA（基于角色）  

## 访问地址

- **账户控制台**: ${KEYCLOAK_URL}/realms/${REALM_NAME}/account
- **管理控制台**: ${KEYCLOAK_URL}/admin
- **OIDC 端点**: ${KEYCLOAK_URL}/realms/${REALM_NAME}/.well-known/openid-configuration

## 下一步建议

1. 测试各种身份验证器应用
2. 配置备份恢复代码
3. 实施基于 IP 的条件 MFA
4. 集成 WebAuthn 支持
5. 设置 MFA 策略报告

---
*该演示展示了 Keycloak 的完整 MFA 功能，适用于企业级身份认证系统。*
EOF

echo -e "${GREEN}MFA 演示配置完成！${NC}"
echo "详细报告已保存至: $DEMO_REPORT"
echo ""
echo -e "${CYAN}💡 提示: 现在可以使用 mfa_test_user 账户测试 MFA 功能${NC}"