#!/bin/bash

# ================================================
# Keycloak 用户服务门户 UI 验证指南
# ================================================
# 验证时间：2025-08-10
# 验证方式：浏览器 UI 手动验证
# ================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置
KEYCLOAK_URL="http://localhost:8080"
REALM="test-realm"

# 打印函数
print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

print_step() {
    echo -e "${CYAN}步骤 $1: $2${NC}"
}

print_info() {
    echo -e "  ${YELLOW}→${NC} $1"
}

print_check() {
    echo -e "  ${GREEN}☐${NC} $1"
}

# ================================================
# 生成验证指南
# ================================================

clear

print_header "Keycloak 用户服务门户（Account Console）UI 验证指南"

echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                    验证前准备                                  ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"

echo -e "\n${YELLOW}测试账号信息：${NC}"
echo -e "  • 普通用户：demo_user / Demo@123"
echo -e "  • 管理员用户：demo_admin / Demo@123"
echo -e "  • MFA测试用户：mfa_test_user / MfaTest@123"

echo -e "\n${YELLOW}访问地址：${NC}"
echo -e "  • Account Console: ${CYAN}${KEYCLOAK_URL}/realms/${REALM}/account${NC}"
echo -e "  • 新版 Account Console: ${CYAN}${KEYCLOAK_URL}/realms/${REALM}/account/#/${NC}"

# ================================================
# 验证步骤
# ================================================

print_header "一、访问 Account Console"

print_step "1" "打开浏览器访问用户门户"
print_info "URL: ${KEYCLOAK_URL}/realms/${REALM}/account"
print_info "应该看到 Keycloak 登录页面"
print_check "登录页面正常显示"
print_check "显示 'test-realm' 领域名称"

print_step "2" "使用测试账号登录"
print_info "输入用户名: demo_user"
print_info "输入密码: Demo@123"
print_info "点击 'Sign In' 按钮"
print_check "登录成功"
print_check "跳转到 Account Console 主页"

# ================================================
print_header "二、验证个人信息管理"

print_step "3" "查看个人信息"
print_info "在主页查看 'Personal Info' 部分"
print_check "显示用户名: demo_user"
print_check "显示邮箱地址"
print_check "显示名字和姓氏"

print_step "4" "编辑个人信息"
print_info "点击 'Personal Info' 或编辑按钮"
print_info "修改 First name 为 'Demo'"
print_info "修改 Last name 为 'User'"
print_info "点击 'Save' 保存"
print_check "信息更新成功"
print_check "显示成功提示消息"

# ================================================
print_header "三、验证账户安全设置"

print_step "5" "访问账户安全页面"
print_info "点击左侧菜单 'Account Security'"
print_info "或点击 'Account Security' 卡片"
print_check "显示安全设置选项"

print_step "6" "查看签到活动"
print_info "查看 'Signing In' 部分"
print_check "显示密码设置状态"
print_check "显示两步验证（2FA）选项"
print_check "显示密码更新选项"

print_step "7" "设置两步验证（可选）"
print_info "点击 'Set up Two-Factor Authentication'"
print_info "选择 'Set up Authenticator application'"
print_check "显示 QR 码"
print_check "提供手动输入密钥"
print_check "可以使用 Google Authenticator 扫描"

# ================================================
print_header "四、验证设备活动管理"

print_step "8" "查看设备活动"
print_info "点击 'Device Activity' 标签"
print_info "查看当前登录的设备列表"
print_check "显示当前浏览器/设备"
print_check "显示 IP 地址"
print_check "显示最后访问时间"
print_check "显示操作系统和浏览器信息"

print_step "9" "管理设备会话"
print_info "查看活动会话列表"
print_check "可以看到 'Current session' 标记"
print_check "显示会话开始时间"
print_check "显示会话过期时间"
print_check "可以点击 'Sign out' 结束其他会话"

# ================================================
print_header "五、验证应用程序管理"

print_step "10" "查看授权应用"
print_info "点击 'Applications' 标签"
print_info "查看已授权的应用列表"
print_check "显示 account-console 应用"
print_check "显示其他已配置的客户端应用"
print_check "显示授权的权限范围"

print_step "11" "管理应用权限"
print_info "查看每个应用的权限"
print_check "显示 'Granted Permissions'"
print_check "显示 'Additional Permissions'"
print_check "可以撤销应用授权（如适用）"

# ================================================
print_header "六、验证资源管理（如果启用）"

print_step "12" "查看共享资源"
print_info "点击 'Resources' 标签（如果显示）"
print_check "显示与您共享的资源"
print_check "显示您共享给他人的资源"
print_check "可以管理资源权限"

# ================================================
print_header "七、其他功能验证"

print_step "13" "语言设置"
print_info "查看页面右上角或设置中的语言选项"
print_check "可以切换语言"
print_check "支持中文界面"

print_step "14" "注销功能"
print_info "点击右上角的用户菜单"
print_info "选择 'Sign Out'"
print_check "成功注销"
print_check "返回登录页面"

# ================================================
# 验证检查清单
# ================================================

print_header "验证检查清单"

echo -e "\n${GREEN}基本功能验证：${NC}"
echo "  ☐ Account Console 可访问"
echo "  ☐ 用户可以成功登录"
echo "  ☐ 个人信息查看正常"
echo "  ☐ 个人信息编辑功能正常"
echo "  ☐ 密码修改选项可用"

echo -e "\n${GREEN}安全功能验证：${NC}"
echo "  ☐ 两步验证设置可用"
echo "  ☐ 设备活动显示正确"
echo "  ☐ 会话管理功能正常"
echo "  ☐ 可以结束其他会话"

echo -e "\n${GREEN}应用管理验证：${NC}"
echo "  ☐ 授权应用列表显示"
echo "  ☐ 权限范围显示正确"
echo "  ☐ 可以管理应用授权"

echo -e "\n${GREEN}用户体验验证：${NC}"
echo "  ☐ 界面响应正常"
echo "  ☐ 操作有反馈提示"
echo "  ☐ 支持多语言切换"
echo "  ☐ 注销功能正常"

# ================================================
# 生成验证命令
# ================================================

print_header "快速验证命令"

echo -e "\n${YELLOW}1. 直接打开 Account Console:${NC}"
echo -e "   ${CYAN}xdg-open '${KEYCLOAK_URL}/realms/${REALM}/account' 2>/dev/null || open '${KEYCLOAK_URL}/realms/${REALM}/account' 2>/dev/null || echo '请手动打开浏览器访问'${NC}"

echo -e "\n${YELLOW}2. 使用 curl 测试 API 端点:${NC}"
echo -e "   ${CYAN}# 先获取 token（需要配置正确的客户端）${NC}"
echo -e "   ${CYAN}curl -X POST '${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token' \\
        -d 'client_id=webapp-client&grant_type=password&username=demo_user&password=Demo@123'${NC}"

echo -e "\n${YELLOW}3. 检查 Account Console 健康状态:${NC}"
echo -e "   ${CYAN}curl -I '${KEYCLOAK_URL}/realms/${REALM}/account'${NC}"

# ================================================
# 生成报告模板
# ================================================

print_header "验证报告模板"

REPORT_TEMPLATE="/mnt/d/Keycloak_project/user-portal-ui-validation-template.md"

cat > "$REPORT_TEMPLATE" << 'EOF'
# 用户服务门户 UI 验证报告

**验证日期**: 2025-08-10
**验证人员**: [您的名字]
**验证方式**: 浏览器 UI 手动验证

## 验证环境
- Keycloak 版本: 26.3.2
- 访问地址: http://localhost:8080/realms/test-realm/account
- 测试账号: demo_user / Demo@123

## 验证结果汇总

| 功能模块 | 验证状态 | 备注 |
|---------|---------|------|
| Account Console 访问 | ☐ 通过 ☐ 失败 | |
| 用户登录 | ☐ 通过 ☐ 失败 | |
| 个人信息查看 | ☐ 通过 ☐ 失败 | |
| 个人信息编辑 | ☐ 通过 ☐ 失败 | |
| 密码修改 | ☐ 通过 ☐ 失败 | |
| 两步验证设置 | ☐ 通过 ☐ 失败 | |
| 设备活动管理 | ☐ 通过 ☐ 失败 | |
| 会话管理 | ☐ 通过 ☐ 失败 | |
| 应用授权管理 | ☐ 通过 ☐ 失败 | |
| 多语言支持 | ☐ 通过 ☐ 失败 | |

## 详细验证记录

### 1. 基本访问功能
- [ ] 登录页面正常加载
- [ ] 登录功能正常
- [ ] 主页正确显示用户信息

### 2. 个人信息管理
- [ ] 可以查看个人信息
- [ ] 可以编辑姓名
- [ ] 可以更新邮箱
- [ ] 修改后信息保存成功

### 3. 安全设置
- [ ] 密码修改选项可见
- [ ] 两步验证可配置
- [ ] QR码正常生成
- [ ] 认证器应用可绑定

### 4. 会话管理
- [ ] 显示当前会话
- [ ] 显示设备信息
- [ ] 可以结束会话
- [ ] 显示登录历史

### 5. 应用管理
- [ ] 显示授权应用列表
- [ ] 显示权限范围
- [ ] 可以撤销授权

## 发现的问题

1. 问题描述：
   - 解决方案：

2. 问题描述：
   - 解决方案：

## 截图证据
（请在此处添加关键功能的截图）

## 验证结论

☐ 所有功能验证通过，用户门户可正常使用
☐ 部分功能存在问题，需要修复
☐ 存在严重问题，需要进一步调试

## 建议
1. 
2. 
3. 

---
验证人签名：_______________
日期：2025-08-10
EOF

echo -e "\n${GREEN}验证报告模板已生成：${NC}"
echo -e "  ${CYAN}$REPORT_TEMPLATE${NC}"

# ================================================
# 最终提示
# ================================================

echo -e "\n${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                    验证指南生成完成                            ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"

echo -e "\n${YELLOW}下一步操作：${NC}"
echo -e "1. 在浏览器中打开: ${CYAN}${KEYCLOAK_URL}/realms/${REALM}/account${NC}"
echo -e "2. 按照上述步骤进行手动验证"
echo -e "3. 填写验证报告模板"
echo -e "4. 记录任何发现的问题"

echo -e "\n${BLUE}提示：${NC}"
echo -e "• 使用 Chrome DevTools 或 Firefox Developer Tools 查看网络请求"
echo -e "• 截图保存关键验证步骤"
echo -e "• 注意检查控制台是否有错误信息"

echo -e "\n${GREEN}祝您验证顺利！${NC}\n"