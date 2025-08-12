#!/bin/bash

# Keycloak 初始化配置脚本
# 用于完成部署验证计划中的初始化配置步骤

set -e

# 配置变量
KEYCLOAK_URL="http://localhost:8080"
ADMIN_USER="admin"
ADMIN_PASSWORD="admin123"
REALM_NAME="test-realm"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 等待 Keycloak 就绪
wait_for_keycloak() {
    log_info "等待 Keycloak 服务就绪..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s "${KEYCLOAK_URL}" > /dev/null 2>&1; then
            log_info "Keycloak 服务已就绪"
            return 0
        fi
        attempt=$((attempt + 1))
        echo -n "."
        sleep 2
    done
    
    log_error "Keycloak 服务未能在预期时间内就绪"
    return 1
}

# 获取访问令牌
get_access_token() {
    log_info "获取管理员访问令牌..."
    
    TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${ADMIN_USER}" \
        -d "password=${ADMIN_PASSWORD}" \
        -d "grant_type=password" \
        -d "client_id=admin-cli")
    
    ACCESS_TOKEN=$(echo $TOKEN_RESPONSE | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
    
    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "无法获取访问令牌"
        echo "响应: $TOKEN_RESPONSE"
        exit 1
    fi
    
    log_info "成功获取访问令牌"
    echo $ACCESS_TOKEN
}

# 创建测试 Realm
create_test_realm() {
    local token=$1
    log_info "创建测试 Realm: ${REALM_NAME}..."
    
    # 检查 Realm 是否已存在
    REALM_EXISTS=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}")
    
    if [ "$REALM_EXISTS" = "200" ]; then
        log_warning "Realm ${REALM_NAME} 已存在，跳过创建"
        return 0
    fi
    
    # 创建 Realm 配置
    cat > /tmp/realm-config.json <<EOF
{
    "realm": "${REALM_NAME}",
    "enabled": true,
    "displayName": "测试环境",
    "displayNameHtml": "<h3>测试环境</h3>",
    "loginTheme": "keycloak",
    "accountTheme": "keycloak.v2",
    "adminTheme": "keycloak.v2",
    "emailTheme": "keycloak",
    "internationalizationEnabled": true,
    "supportedLocales": ["en", "zh-CN"],
    "defaultLocale": "zh-CN",
    "registrationAllowed": true,
    "registrationEmailAsUsername": false,
    "rememberMe": true,
    "verifyEmail": false,
    "resetPasswordAllowed": true,
    "editUsernameAllowed": false,
    "bruteForceProtected": true,
    "permanentLockout": false,
    "maxFailureWaitSeconds": 900,
    "minimumQuickLoginWaitSeconds": 60,
    "waitIncrementSeconds": 60,
    "quickLoginCheckMilliSeconds": 1000,
    "maxDeltaTimeSeconds": 43200,
    "failureFactor": 3,
    "sslRequired": "external",
    "eventsEnabled": true,
    "eventsListeners": ["jboss-logging"],
    "enabledEventTypes": [
        "SEND_RESET_PASSWORD",
        "UPDATE_CONSENT_ERROR",
        "LOGIN",
        "CLIENT_INITIATED_ACCOUNT_LINKING",
        "REMOVE_TOTP",
        "REVOKE_GRANT",
        "UPDATE_TOTP",
        "LOGIN_ERROR",
        "CLIENT_LOGIN",
        "RESET_PASSWORD_ERROR",
        "IMPERSONATE_ERROR",
        "CODE_TO_TOKEN_ERROR",
        "CUSTOM_REQUIRED_ACTION",
        "RESTART_AUTHENTICATION",
        "UPDATE_PROFILE_ERROR",
        "IMPERSONATE",
        "LOGIN_ERROR",
        "UPDATE_PASSWORD_ERROR",
        "LOGOUT_ERROR",
        "LOGOUT",
        "REGISTER",
        "DELETE_ACCOUNT_ERROR",
        "CLIENT_DELETE",
        "IDENTITY_PROVIDER_LINK_ACCOUNT",
        "DELETE_ACCOUNT",
        "UPDATE_PASSWORD",
        "CLIENT_LOGIN_ERROR",
        "FEDERATED_IDENTITY_LINK_ERROR",
        "IDENTITY_PROVIDER_FIRST_LOGIN",
        "REGISTER_ERROR",
        "SEND_VERIFY_EMAIL",
        "EXECUTE_ACTIONS",
        "SEND_VERIFY_EMAIL_ERROR",
        "REVOKE_GRANT_ERROR",
        "EXECUTE_ACTIONS_ERROR",
        "REMOVE_FEDERATED_IDENTITY_ERROR",
        "IDENTITY_PROVIDER_POST_LOGIN",
        "UPDATE_EMAIL",
        "EMAIL_VERIFY_ERROR",
        "FEDERATED_IDENTITY_LINK",
        "IDENTITY_PROVIDER_LINK_ACCOUNT_ERROR",
        "UPDATE_CONSENT",
        "EMAIL_VERIFY",
        "LOGOUT",
        "AUTHREQID_TO_TOKEN",
        "UPDATE_EMAIL_ERROR",
        "REMOVE_FEDERATED_IDENTITY",
        "AUTHREQID_TO_TOKEN_ERROR",
        "IDENTITY_PROVIDER_POST_LOGIN_ERROR",
        "USER_DISABLED_BY_PERMANENT_LOCKOUT"
    ],
    "adminEventsEnabled": true,
    "adminEventsDetailsEnabled": true,
    "smtpServer": {
        "host": "mailhog",
        "port": "1025",
        "from": "noreply@test-realm.local",
        "fromDisplayName": "Keycloak 测试环境",
        "replyTo": "support@test-realm.local",
        "replyToDisplayName": "技术支持",
        "envelopeFrom": "",
        "ssl": "false",
        "starttls": "false",
        "auth": "false"
    },
    "loginWithEmailAllowed": true,
    "duplicateEmailsAllowed": false,
    "passwordPolicy": "length(8) and upperCase(1) and lowerCase(1) and digits(1) and notUsername()",
    "offlineSessionIdleTimeout": 2592000,
    "offlineSessionMaxLifespanEnabled": false,
    "offlineSessionMaxLifespan": 5184000,
    "accessTokenLifespan": 300,
    "accessTokenLifespanForImplicitFlow": 900,
    "ssoSessionIdleTimeout": 1800,
    "ssoSessionMaxLifespan": 36000,
    "ssoSessionIdleTimeoutRememberMe": 0,
    "ssoSessionMaxLifespanRememberMe": 0,
    "accessCodeLifespan": 60,
    "accessCodeLifespanUserAction": 300,
    "accessCodeLifespanLogin": 1800,
    "actionTokenGeneratedByAdminLifespan": 43200,
    "actionTokenGeneratedByUserLifespan": 300
}
EOF
    
    # 创建 Realm
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d @/tmp/realm-config.json \
        "${KEYCLOAK_URL}/admin/realms")
    
    if [ "$RESPONSE" = "201" ]; then
        log_info "成功创建 Realm: ${REALM_NAME}"
    else
        log_error "创建 Realm 失败，HTTP 状态码: $RESPONSE"
        return 1
    fi
    
    rm -f /tmp/realm-config.json
}

# 创建测试角色
create_roles() {
    local token=$1
    log_info "创建测试角色..."
    
    # 角色列表
    local roles=("admin" "manager" "user" "developer" "tester")
    
    for role in "${roles[@]}"; do
        log_info "创建角色: $role"
        
        # 检查角色是否存在
        ROLE_EXISTS=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer ${token}" \
            "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/roles/${role}")
        
        if [ "$ROLE_EXISTS" = "200" ]; then
            log_warning "角色 ${role} 已存在，跳过创建"
            continue
        fi
        
        # 创建角色
        curl -s -X POST \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"${role}\",
                \"description\": \"${role} 角色\",
                \"composite\": false
            }" \
            "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/roles"
    done
}

# 创建组织结构
create_groups() {
    local token=$1
    log_info "创建组织结构..."
    
    # 创建总部
    local hq_response=$(curl -s -X POST \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "总部",
            "path": "/总部"
        }' \
        "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/groups")
    
    # 获取总部组ID
    local hq_id=$(curl -s \
        -H "Authorization: Bearer ${token}" \
        "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/groups?search=总部" | \
        grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
    
    if [ -n "$hq_id" ]; then
        log_info "创建部门..."
        
        # 创建部门
        local departments=("技术部" "市场部" "财务部" "人事部")
        for dept in "${departments[@]}"; do
            curl -s -X POST \
                -H "Authorization: Bearer ${token}" \
                -H "Content-Type: application/json" \
                -d "{
                    \"name\": \"${dept}\",
                    \"path\": \"/总部/${dept}\"
                }" \
                "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/groups/${hq_id}/children"
        done
    fi
}

# 创建测试用户
create_test_users() {
    local token=$1
    log_info "创建测试用户..."
    
    # 用户列表
    local users=(
        "test_admin:管理员:admin"
        "test_manager:经理:manager"
        "test_user1:普通用户1:user"
        "test_user2:普通用户2:user"
        "test_dev:开发者:developer"
    )
    
    for user_info in "${users[@]}"; do
        IFS=':' read -r username fullname role <<< "$user_info"
        
        log_info "创建用户: $username"
        
        # 检查用户是否存在
        USER_EXISTS=$(curl -s \
            -H "Authorization: Bearer ${token}" \
            "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users?username=${username}" | \
            grep -c "\"username\":\"${username}\"")
        
        if [ "$USER_EXISTS" -gt 0 ]; then
            log_warning "用户 ${username} 已存在，跳过创建"
            continue
        fi
        
        # 创建用户
        USER_RESPONSE=$(curl -s -X POST \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            -d "{
                \"username\": \"${username}\",
                \"enabled\": true,
                \"emailVerified\": true,
                \"firstName\": \"${fullname}\",
                \"lastName\": \"测试\",
                \"email\": \"${username}@test.local\",
                \"credentials\": [{
                    \"type\": \"password\",
                    \"value\": \"Test@123\",
                    \"temporary\": false
                }],
                \"realmRoles\": [\"${role}\"],
                \"attributes\": {
                    \"department\": [\"技术部\"],
                    \"position\": [\"${fullname}\"]
                }
            }" \
            "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users")
        
        # 获取用户ID并分配角色
        USER_ID=$(curl -s \
            -H "Authorization: Bearer ${token}" \
            "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users?username=${username}" | \
            grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
        
        if [ -n "$USER_ID" ]; then
            # 获取角色ID
            ROLE_ID=$(curl -s \
                -H "Authorization: Bearer ${token}" \
                "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/roles/${role}" | \
                grep -o '"id":"[^"]*' | cut -d'"' -f4)
            
            if [ -n "$ROLE_ID" ]; then
                # 分配角色
                curl -s -X POST \
                    -H "Authorization: Bearer ${token}" \
                    -H "Content-Type: application/json" \
                    -d "[{\"id\":\"${ROLE_ID}\",\"name\":\"${role}\"}]" \
                    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${USER_ID}/role-mappings/realm"
            fi
        fi
    done
}

# 创建测试客户端应用
create_test_clients() {
    local token=$1
    log_info "创建测试客户端应用..."
    
    # 前端应用
    log_info "创建前端应用客户端..."
    curl -s -X POST \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "frontend-app",
            "name": "前端应用",
            "description": "测试前端应用",
            "rootUrl": "http://localhost:3000",
            "baseUrl": "/",
            "enabled": true,
            "publicClient": true,
            "protocol": "openid-connect",
            "redirectUris": ["http://localhost:3000/*"],
            "webOrigins": ["http://localhost:3000"],
            "standardFlowEnabled": true,
            "implicitFlowEnabled": false,
            "directAccessGrantsEnabled": true
        }' \
        "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients"
    
    # 后端 API
    log_info "创建后端 API 客户端..."
    curl -s -X POST \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "backend-api",
            "name": "后端API",
            "description": "测试后端API",
            "enabled": true,
            "publicClient": false,
            "protocol": "openid-connect",
            "secret": "backend-secret-123",
            "serviceAccountsEnabled": true,
            "authorizationServicesEnabled": true,
            "standardFlowEnabled": false,
            "implicitFlowEnabled": false,
            "directAccessGrantsEnabled": true
        }' \
        "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients"
}

# 输出配置摘要
print_summary() {
    echo ""
    echo "========================================="
    echo -e "${GREEN}Keycloak 初始化配置完成！${NC}"
    echo "========================================="
    echo ""
    echo "访问信息："
    echo "  管理控制台: ${KEYCLOAK_URL}/admin"
    echo "  管理员账号: ${ADMIN_USER} / ${ADMIN_PASSWORD}"
    echo ""
    echo "测试 Realm 信息："
    echo "  Realm 名称: ${REALM_NAME}"
    echo "  账户控制台: ${KEYCLOAK_URL}/realms/${REALM_NAME}/account"
    echo ""
    echo "测试用户（密码均为 Test@123）："
    echo "  test_admin   - 管理员角色"
    echo "  test_manager - 经理角色"
    echo "  test_user1   - 普通用户角色"
    echo "  test_user2   - 普通用户角色"
    echo "  test_dev     - 开发者角色"
    echo ""
    echo "测试客户端："
    echo "  frontend-app - 前端应用（公共客户端）"
    echo "  backend-api  - 后端API（机密客户端，密钥: backend-secret-123）"
    echo ""
    echo "邮件服务器："
    echo "  SMTP 服务器: mailhog:1025"
    echo "  Web 界面: http://localhost:8025"
    echo ""
    echo "组织结构："
    echo "  总部"
    echo "    ├── 技术部"
    echo "    ├── 市场部"
    echo "    ├── 财务部"
    echo "    └── 人事部"
    echo ""
    echo "已启用功能："
    echo "  ✓ 审计日志（事件和管理事件）"
    echo "  ✓ 邮件服务（使用 MailHog）"
    echo "  ✓ 中文界面（默认语言）"
    echo "  ✓ 密码策略（8位+大小写+数字）"
    echo "  ✓ 暴力破解保护（3次失败锁定）"
    echo "========================================="
}

# 主函数
main() {
    log_info "开始 Keycloak 初始化配置..."
    
    # 等待服务就绪
    wait_for_keycloak
    
    # 获取访问令牌
    TOKEN=$(get_access_token)
    
    # 执行初始化配置
    create_test_realm "$TOKEN"
    create_roles "$TOKEN"
    create_groups "$TOKEN"
    create_test_users "$TOKEN"
    create_test_clients "$TOKEN"
    
    # 输出摘要
    print_summary
    
    log_info "初始化配置脚本执行完成！"
}

# 执行主函数
main