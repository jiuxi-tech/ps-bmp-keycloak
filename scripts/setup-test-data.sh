#!/bin/bash

# Keycloak 测试数据初始化脚本
# 使用方法: ./setup-test-data.sh

set -e

# 颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 配置变量
KEYCLOAK_URL="http://localhost:8080"
ADMIN_USERNAME="admin"
ADMIN_PASSWORD="admin123"
TEST_REALM="test-realm"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 获取管理员 Token
get_admin_token() {
    log_info "获取管理员令牌..."
    
    ADMIN_TOKEN=$(curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=$ADMIN_USERNAME" \
        -d "password=$ADMIN_PASSWORD" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" | \
        jq -r '.access_token')
    
    if [ "$ADMIN_TOKEN" = "null" ] || [ -z "$ADMIN_TOKEN" ]; then
        echo "获取管理员令牌失败"
        exit 1
    fi
    
    log_success "管理员令牌获取成功"
}

# 创建测试 Realm
create_test_realm() {
    log_info "创建测试 Realm: $TEST_REALM"
    
    curl -s -X POST "$KEYCLOAK_URL/admin/realms" \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "realm": "'$TEST_REALM'",
            "displayName": "测试租户",
            "enabled": true,
            "registrationAllowed": true,
            "registrationEmailAsUsername": false,
            "rememberMe": true,
            "verifyEmail": false,
            "resetPasswordAllowed": true,
            "editUsernameAllowed": false,
            "bruteForceProtected": true,
            "permanentLockout": false,
            "maxFailureWait": 900,
            "minimumQuickLoginWait": 60,
            "waitIncrementSeconds": 60,
            "quickLoginCheckMilliSeconds": 1000,
            "maxDeltaTimeSeconds": 43200,
            "failureFactor": 30,
            "defaultLocale": "zh-CN",
            "internationalizationEnabled": true,
            "supportedLocales": ["zh-CN", "en"],
            "loginTheme": "keycloak",
            "adminTheme": "keycloak",
            "accountTheme": "keycloak",
            "emailTheme": "keycloak"
        }' || log_warning "Realm 可能已存在"
    
    log_success "测试 Realm 创建完成"
}

# 创建角色
create_roles() {
    log_info "创建角色..."
    
    # 创建 Realm 角色
    local roles=("admin" "manager" "user" "guest" "analyst" "operator")
    
    for role in "${roles[@]}"; do
        curl -s -X POST "$KEYCLOAK_URL/admin/realms/$TEST_REALM/roles" \
            -H "Authorization: Bearer $ADMIN_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "'$role'",
                "description": "测试角色 - '$role'"
            }' >/dev/null 2>&1 || true
    done
    
    # 创建复合角色
    curl -s -X POST "$KEYCLOAK_URL/admin/realms/$TEST_REALM/roles" \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "super-admin",
            "description": "超级管理员（复合角色）",
            "composite": true
        }' >/dev/null 2>&1 || true
    
    log_success "角色创建完成"
}

# 创建组织结构（Groups）
create_groups() {
    log_info "创建组织结构..."
    
    # 创建顶级组织
    local top_groups=("总部" "研发部" "市场部" "运营部")
    
    for group in "${top_groups[@]}"; do
        GROUP_ID=$(curl -s -X POST "$KEYCLOAK_URL/admin/realms/$TEST_REALM/groups" \
            -H "Authorization: Bearer $ADMIN_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "'$group'",
                "attributes": {
                    "description": ["'$group'组织"]
                }
            }' -w "%{http_code}" -o /tmp/group_response)
        
        # 为研发部创建子组
        if [ "$group" = "研发部" ]; then
            GROUP_ID=$(grep -o '"id":"[^"]*"' /tmp/group_response | cut -d'"' -f4)
            if [ ! -z "$GROUP_ID" ]; then
                local sub_groups=("前端组" "后端组" "测试组" "运维组")
                for sub_group in "${sub_groups[@]}"; do
                    curl -s -X POST "$KEYCLOAK_URL/admin/realms/$TEST_REALM/groups/$GROUP_ID/children" \
                        -H "Authorization: Bearer $ADMIN_TOKEN" \
                        -H "Content-Type: application/json" \
                        -d '{
                            "name": "'$sub_group'",
                            "attributes": {
                                "department": ["研发部"],
                                "team": ["'$sub_group'"]
                            }
                        }' >/dev/null 2>&1 || true
                done
            fi
        fi
    done
    
    log_success "组织结构创建完成"
}

# 创建测试用户
create_test_users() {
    log_info "创建测试用户..."
    
    # 管理员用户
    local admin_users=(
        "admin:admin123:管理员:admin@example.com:admin"
        "manager:manager123:经理:manager@example.com:manager"
    )
    
    for user_info in "${admin_users[@]}"; do
        IFS=':' read -r username password firstName email role <<< "$user_info"
        
        create_user "$username" "$password" "$firstName" "$lastName" "$email" "$role"
    done
    
    # 普通用户
    for i in {1..10}; do
        create_user "user$i" "User123!" "测试用户$i" "Test" "user$i@example.com" "user"
    done
    
    # 特殊用户
    local special_users=(
        "analyst:Analyst123!:数据分析师:Test:analyst@example.com:analyst"
        "operator:Operator123!:运维工程师:Test:operator@example.com:operator"
        "guest:Guest123!:访客用户:Test:guest@example.com:guest"
    )
    
    for user_info in "${special_users[@]}"; do
        IFS=':' read -r username password firstName lastName email role <<< "$user_info"
        create_user "$username" "$password" "$firstName" "$lastName" "$email" "$role"
    done
    
    log_success "测试用户创建完成"
}

# 创建单个用户
create_user() {
    local username=$1
    local password=$2
    local firstName=$3
    local lastName=$4
    local email=$5
    local role=$6
    
    # 创建用户
    local user_data='{
        "username": "'$username'",
        "email": "'$email'",
        "firstName": "'$firstName'",
        "lastName": "'$lastName'",
        "enabled": true,
        "emailVerified": true,
        "credentials": [{
            "type": "password",
            "value": "'$password'",
            "temporary": false
        }],
        "attributes": {
            "department": ["'$role'部门"],
            "employeeId": ["EMP'$(date +%s)'"],
            "phone": ["1380000'$(printf "%04d" $RANDOM)'"]
        }
    }'
    
    # 发送创建用户请求
    USER_RESPONSE=$(curl -s -X POST "$KEYCLOAK_URL/admin/realms/$TEST_REALM/users" \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$user_data" \
        -w "%{http_code}" -o /tmp/user_response)
    
    if [ "$USER_RESPONSE" = "201" ]; then
        # 获取用户 ID
        local USER_ID=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/$TEST_REALM/users?username=$username" \
            -H "Authorization: Bearer $ADMIN_TOKEN" | \
            jq -r '.[0].id')
        
        if [ "$USER_ID" != "null" ] && [ ! -z "$USER_ID" ]; then
            # 分配角色
            assign_role_to_user "$USER_ID" "$role"
        fi
    fi
}

# 为用户分配角色
assign_role_to_user() {
    local user_id=$1
    local role_name=$2
    
    # 获取角色信息
    local ROLE_INFO=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/$TEST_REALM/roles/$role_name" \
        -H "Authorization: Bearer $ADMIN_TOKEN")
    
    if [ "$ROLE_INFO" != "" ] && [ "$ROLE_INFO" != "null" ]; then
        # 分配角色
        curl -s -X POST "$KEYCLOAK_URL/admin/realms/$TEST_REALM/users/$user_id/role-mappings/realm" \
            -H "Authorization: Bearer $ADMIN_TOKEN" \
            -H "Content-Type: application/json" \
            -d "[$ROLE_INFO]" >/dev/null 2>&1 || true
    fi
}

# 创建客户端应用
create_test_clients() {
    log_info "创建测试客户端..."
    
    # 创建前端应用（Public Client）
    curl -s -X POST "$KEYCLOAK_URL/admin/realms/$TEST_REALM/clients" \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "frontend-app",
            "name": "前端应用",
            "description": "前端测试应用",
            "enabled": true,
            "publicClient": true,
            "protocol": "openid-connect",
            "redirectUris": [
                "http://localhost:3000/*",
                "http://localhost:8081/*"
            ],
            "webOrigins": [
                "http://localhost:3000",
                "http://localhost:8081"
            ],
            "standardFlowEnabled": true,
            "implicitFlowEnabled": false,
            "directAccessGrantsEnabled": true,
            "serviceAccountsEnabled": false
        }' >/dev/null 2>&1 || true
    
    # 创建后端应用（Confidential Client）
    curl -s -X POST "$KEYCLOAK_URL/admin/realms/$TEST_REALM/clients" \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "backend-service",
            "name": "后端服务",
            "description": "后端API服务",
            "enabled": true,
            "publicClient": false,
            "protocol": "openid-connect",
            "secret": "backend-secret-123",
            "redirectUris": [
                "http://localhost:8080/*"
            ],
            "serviceAccountsEnabled": true,
            "standardFlowEnabled": true,
            "directAccessGrantsEnabled": true,
            "authorizationServicesEnabled": true
        }' >/dev/null 2>&1 || true
    
    # 创建 SAML 应用
    curl -s -X POST "$KEYCLOAK_URL/admin/realms/$TEST_REALM/clients" \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "saml-app",
            "name": "SAML应用",
            "description": "SAML测试应用",
            "enabled": true,
            "protocol": "saml",
            "attributes": {
                "saml.authnstatement": "true",
                "saml.server.signature": "true",
                "saml.signature.algorithm": "RSA_SHA256",
                "saml.client.signature": "false"
            },
            "redirectUris": [
                "http://localhost:8082/saml/*"
            ]
        }' >/dev/null 2>&1 || true
    
    log_success "测试客户端创建完成"
}

# 配置身份提供商
configure_identity_providers() {
    log_info "配置身份提供商..."
    
    # 配置 Google Identity Provider（示例）
    curl -s -X POST "$KEYCLOAK_URL/admin/realms/$TEST_REALM/identity-provider/instances" \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "alias": "google",
            "displayName": "Google",
            "providerId": "google",
            "enabled": false,
            "config": {
                "clientId": "your-google-client-id",
                "clientSecret": "your-google-client-secret",
                "defaultScope": "openid profile email"
            }
        }' >/dev/null 2>&1 || true
    
    log_success "身份提供商配置完成"
}

# 配置认证流程
configure_authentication_flows() {
    log_info "配置认证流程..."
    
    # 这里可以配置自定义认证流程
    # 例如：条件化 MFA、IP 限制等
    
    log_success "认证流程配置完成"
}

# 配置邮件设置
configure_email_settings() {
    log_info "配置邮件设置..."
    
    curl -s -X PUT "$KEYCLOAK_URL/admin/realms/$TEST_REALM" \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "smtpServer": {
                "host": "mailhog",
                "port": "1025",
                "from": "keycloak@example.com",
                "fromDisplayName": "Keycloak测试",
                "ssl": false,
                "starttls": false,
                "auth": false
            }
        }' >/dev/null 2>&1 || true
    
    log_success "邮件设置配置完成"
}

# 启用事件监听
configure_events() {
    log_info "配置事件监听..."
    
    curl -s -X PUT "$KEYCLOAK_URL/admin/realms/$TEST_REALM/events/config" \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "eventsEnabled": true,
            "eventsExpiration": 604800,
            "eventsListeners": ["jboss-logging"],
            "enabledEventTypes": [
                "LOGIN", "LOGIN_ERROR", "LOGOUT", "REGISTER",
                "UPDATE_PROFILE", "UPDATE_PASSWORD", "VERIFY_EMAIL",
                "REMOVE_TOTP", "UPDATE_TOTP", "GRANT_CONSENT",
                "UPDATE_CONSENT_ERROR", "SEND_VERIFY_EMAIL",
                "SEND_RESET_PASSWORD", "SEND_IDENTITY_PROVIDER_LINK",
                "RESET_PASSWORD", "RESTART_AUTHENTICATION",
                "INVALID_SIGNATURE", "REGISTER_ERROR", "NOT_ALLOWED",
                "CODE_TO_TOKEN_ERROR", "CUSTOM_REQUIRED_ACTION",
                "OAUTH2_DEVICE_AUTH", "OAUTH2_DEVICE_VERIFY_USER_CODE",
                "PERMISSION_TOKEN"
            ],
            "adminEventsEnabled": true,
            "adminEventsDetailsEnabled": true
        }' >/dev/null 2>&1 || true
    
    log_success "事件监听配置完成"
}

# 打印测试信息
print_test_info() {
    echo -e "\n${GREEN}=== 测试数据创建完成 ===${NC}"
    echo -e "\n${BLUE}测试 Realm:${NC} $TEST_REALM"
    echo -e "${BLUE}访问地址:${NC} $KEYCLOAK_URL/realms/$TEST_REALM/account"
    echo -e "\n${BLUE}测试用户账号:${NC}"
    echo "管理员: admin / admin123"
    echo "经理: manager / manager123"
    echo "用户: user1-user10 / User123!"
    echo "分析师: analyst / Analyst123!"
    echo "运维: operator / Operator123!"
    echo "访客: guest / Guest123!"
    echo -e "\n${BLUE}测试客户端:${NC}"
    echo "前端应用: frontend-app (Public)"
    echo "后端服务: backend-service / backend-secret-123 (Confidential)"
    echo "SAML应用: saml-app"
    echo -e "\n${BLUE}邮件测试:${NC} http://localhost:8025"
    echo -e "\n${GREEN}可以开始功能验证了！${NC}"
}

# 检查 Keycloak 是否运行
check_keycloak() {
    if ! curl -f "$KEYCLOAK_URL/health/ready" >/dev/null 2>&1; then
        echo "Keycloak 未运行或未就绪，请先启动服务"
        echo "运行: ./deploy.sh start"
        exit 1
    fi
}

# 检查依赖工具
check_tools() {
    if ! command -v curl &> /dev/null; then
        echo "curl 命令未找到，请先安装"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo "jq 命令未找到，请先安装"
        echo "Ubuntu/Debian: sudo apt install jq"
        echo "CentOS/RHEL: sudo yum install jq"
        echo "macOS: brew install jq"
        exit 1
    fi
}

# 主函数
main() {
    echo "Keycloak 测试数据初始化脚本"
    echo "==============================="
    
    check_tools
    check_keycloak
    
    get_admin_token
    create_test_realm
    create_roles
    create_groups
    create_test_users
    create_test_clients
    configure_identity_providers
    configure_authentication_flows
    configure_email_settings
    configure_events
    
    print_test_info
}

# 执行主函数
main "$@"