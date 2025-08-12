#!/bin/bash

# Keycloak 性能和负载测试脚本
# 测试系统在并发用户访问下的性能表现

set -e

KEYCLOAK_URL="http://localhost:8080"
REALM_NAME="test-realm"
CLIENT_ID="frontend-app"

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 测试参数
CONCURRENT_USERS=10
TEST_DURATION=60  # 秒
RAMP_UP_TIME=10   # 秒

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}          Keycloak 性能和负载测试${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "测试参数："
echo "  - 并发用户数: $CONCURRENT_USERS"
echo "  - 测试持续时间: $TEST_DURATION 秒"
echo "  - 爬坡时间: $RAMP_UP_TIME 秒"
echo "  - 目标服务: $KEYCLOAK_URL"
echo ""

# 获取管理员令牌
echo "准备测试环境..."
TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin" \
    -d "password=admin123" \
    -d "grant_type=password" \
    -d "client_id=admin-cli")

TOKEN=$(echo $TOKEN_RESPONSE | python3 -c "import json, sys; print(json.load(sys.stdin).get('access_token', ''))" 2>/dev/null || echo "")

if [ -z "$TOKEN" ]; then
    echo -e "${RED}错误：无法获取管理员令牌${NC}"
    exit 1
fi

# ============================================
# 1. 基线性能测试
# ============================================
echo -e "${CYAN}1. 基线性能测试${NC}"
echo "   测试单用户响应时间..."

# OIDC 发现端点测试
echo -n "   - OIDC 发现端点: "
OIDC_TIME=$(curl -s -w "%{time_total}" -o /dev/null "${KEYCLOAK_URL}/realms/${REALM_NAME}/.well-known/openid-configuration")
echo -e "${GREEN}${OIDC_TIME}s${NC}"

# JWKS 端点测试  
echo -n "   - JWKS 证书端点: "
JWKS_TIME=$(curl -s -w "%{time_total}" -o /dev/null "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/certs")
echo -e "${GREEN}${JWKS_TIME}s${NC}"

# 用户认证测试
echo -n "   - 用户认证响应: "
AUTH_TIME=$(curl -s -w "%{time_total}" -o /dev/null -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=test_user1" \
    -d "password=Test@123" \
    -d "grant_type=password" \
    -d "client_id=${CLIENT_ID}")
echo -e "${GREEN}${AUTH_TIME}s${NC}"

# Admin API 测试
echo -n "   - Admin API 查询: "
ADMIN_TIME=$(curl -s -w "%{time_total}" -o /dev/null \
    -H "Authorization: Bearer ${TOKEN}" \
    "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/count")
echo -e "${GREEN}${ADMIN_TIME}s${NC}"

echo ""

# ============================================
# 2. 并发用户测试
# ============================================
echo -e "${CYAN}2. 并发用户认证测试${NC}"
echo "   创建并发测试脚本..."

# 创建并发测试脚本
cat > /tmp/concurrent_auth_test.sh <<'EOF'
#!/bin/bash
KEYCLOAK_URL="$1"
REALM_NAME="$2" 
CLIENT_ID="$3"
USER_ID="$4"
RESULTS_FILE="$5"

# 执行认证请求
start_time=$(date +%s.%3N)
response=$(curl -s -w "%{http_code}:%{time_total}" -o /tmp/auth_response_$USER_ID.json \
    -X POST "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=test_user1" \
    -d "password=Test@123" \
    -d "grant_type=password" \
    -d "client_id=${CLIENT_ID}")
end_time=$(date +%s.%3N)

http_code=$(echo $response | cut -d':' -f1)
response_time=$(echo $response | cut -d':' -f2)

echo "${USER_ID},${http_code},${response_time},$(echo "$end_time - $start_time" | bc)" >> $RESULTS_FILE
EOF

chmod +x /tmp/concurrent_auth_test.sh

# 清理结果文件
RESULTS_FILE="/tmp/perf_test_results.csv"
echo "user_id,http_code,response_time,total_time" > $RESULTS_FILE

echo "   启动 $CONCURRENT_USERS 个并发用户认证测试..."

# 启动并发测试
pids=()
for i in $(seq 1 $CONCURRENT_USERS); do
    /tmp/concurrent_auth_test.sh "$KEYCLOAK_URL" "$REALM_NAME" "$CLIENT_ID" "$i" "$RESULTS_FILE" &
    pids+=($!)
    
    # 逐步启动用户（爬坡）
    if [ $i -lt $CONCURRENT_USERS ]; then
        sleep $(echo "$RAMP_UP_TIME / $CONCURRENT_USERS" | bc -l)
    fi
done

# 等待所有测试完成
echo "   等待测试完成..."
for pid in "${pids[@]}"; do
    wait $pid
done

echo -e "${GREEN}   ✓ 并发测试完成${NC}"
echo ""

# ============================================
# 3. 分析测试结果
# ============================================
echo -e "${CYAN}3. 性能测试结果分析${NC}"

if [ -f "$RESULTS_FILE" ]; then
    # 统计成功率
    total_requests=$(tail -n +2 $RESULTS_FILE | wc -l)
    successful_requests=$(tail -n +2 $RESULTS_FILE | awk -F',' '$2 == 200 {count++} END {print count+0}')
    success_rate=$(echo "scale=2; $successful_requests * 100 / $total_requests" | bc)
    
    # 计算响应时间统计
    avg_response_time=$(tail -n +2 $RESULTS_FILE | awk -F',' '{sum+=$3; count++} END {printf "%.3f", sum/count}')
    min_response_time=$(tail -n +2 $RESULTS_FILE | awk -F',' 'NR==2{min=$3} {if($3<min) min=$3} END {print min}')
    max_response_time=$(tail -n +2 $RESULTS_FILE | awk -F',' '{if($3>max) max=$3} END {print max}')
    
    echo "   📊 测试结果统计："
    echo "   ├─ 总请求数: $total_requests"
    echo "   ├─ 成功请求: $successful_requests"
    echo "   ├─ 成功率: ${success_rate}%"
    echo "   ├─ 平均响应时间: ${avg_response_time}s"
    echo "   ├─ 最快响应时间: ${min_response_time}s"
    echo "   └─ 最慢响应时间: ${max_response_time}s"
    
    # 判断性能等级
    if (( $(echo "$avg_response_time < 1.0" | bc -l) )); then
        echo -e "   ${GREEN}性能等级: 优秀 (<1s)${NC}"
    elif (( $(echo "$avg_response_time < 3.0" | bc -l) )); then
        echo -e "   ${YELLOW}性能等级: 良好 (<3s)${NC}"
    else
        echo -e "   ${RED}性能等级: 需要优化 (>3s)${NC}"
    fi
    
    echo ""
fi

# ============================================
# 4. 系统资源监控
# ============================================
echo -e "${CYAN}4. 系统资源监控${NC}"

# Docker 容器资源使用情况
echo "   📈 容器资源使用："
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" keycloak keycloak-postgres | \
    while IFS= read -r line; do
        echo "   $line"
    done

echo ""

# 数据库连接数
echo -n "   🗄️  数据库连接数: "
DB_CONNECTIONS=$(docker exec keycloak-postgres psql -U keycloak -d keycloak -c "SELECT count(*) FROM pg_stat_activity WHERE datname = 'keycloak';" -t | tr -d ' ')
echo -e "${GREEN}${DB_CONNECTIONS}${NC}"

# 检查 Keycloak 日志中的警告或错误
echo -n "   📋 近期错误日志: "
ERROR_COUNT=$(docker logs keycloak --since=1m 2>&1 | grep -c -E "(ERROR|WARN)" || echo "0")
echo -e "${GREEN}${ERROR_COUNT} 条${NC}"

echo ""

# ============================================
# 5. 压力测试（使用 Apache Bench）
# ============================================
echo -e "${CYAN}5. HTTP 压力测试${NC}"

# 检查是否有 ab (Apache Bench)
if command -v ab &> /dev/null; then
    echo "   使用 Apache Bench 进行压力测试..."
    
    # 测试 OIDC 发现端点
    echo -n "   - OIDC 端点压力测试 (100 请求, 10 并发): "
    AB_RESULT=$(ab -n 100 -c 10 -q "${KEYCLOAK_URL}/realms/${REALM_NAME}/.well-known/openid-configuration" 2>&1)
    
    # 提取关键指标
    RPS=$(echo "$AB_RESULT" | grep "Requests per second" | awk '{print $4}')
    AVG_TIME=$(echo "$AB_RESULT" | grep "Time per request" | head -1 | awk '{print $4}')
    
    echo -e "${GREEN}${RPS} req/sec, 平均 ${AVG_TIME}ms${NC}"
else
    echo "   ⚠️  Apache Bench 未安装，跳过 HTTP 压力测试"
    echo "   安装命令: sudo apt-get install apache2-utils"
fi

echo ""

# ============================================
# 6. 生成性能报告
# ============================================
PERF_REPORT="performance-test-report-$(date +%Y%m%d-%H%M%S).md"

cat > "$PERF_REPORT" <<EOF
# Keycloak 性能测试报告

**测试时间**: $(date '+%Y-%m-%d %H:%M:%S')  
**测试环境**: ${KEYCLOAK_URL}  
**测试Realm**: ${REALM_NAME}

## 测试配置

- **并发用户数**: $CONCURRENT_USERS
- **测试持续时间**: $TEST_DURATION 秒
- **爬坡时间**: $RAMP_UP_TIME 秒

## 基线性能

| 端点类型 | 响应时间 | 状态 |
|----------|----------|------|
| OIDC 发现端点 | ${OIDC_TIME}s | ✅ |
| JWKS 证书端点 | ${JWKS_TIME}s | ✅ |
| 用户认证 | ${AUTH_TIME}s | ✅ |
| Admin API | ${ADMIN_TIME}s | ✅ |

## 并发测试结果

EOF

if [ -f "$RESULTS_FILE" ]; then
    cat >> "$PERF_REPORT" <<EOF
- **总请求数**: $total_requests
- **成功请求**: $successful_requests  
- **成功率**: ${success_rate}%
- **平均响应时间**: ${avg_response_time}s
- **最快响应**: ${min_response_time}s
- **最慢响应**: ${max_response_time}s

EOF
fi

cat >> "$PERF_REPORT" <<EOF
## 系统资源

- **数据库连接数**: ${DB_CONNECTIONS}
- **近期错误日志**: ${ERROR_COUNT} 条

## 性能建议

1. **当前性能表现**: $(if (( $(echo "$avg_response_time < 1.0" | bc -l) )); then echo "优秀"; elif (( $(echo "$avg_response_time < 3.0" | bc -l) )); then echo "良好"; else echo "需要优化"; fi)
2. **建议优化项**:
   - 数据库连接池调优
   - JVM 内存参数优化
   - 缓存策略配置
   - 集群负载均衡

## 下一步测试

- [ ] 增加并发用户数至 100
- [ ] 长时间稳定性测试 (24小时)
- [ ] 数据库性能专项测试
- [ ] 内存泄漏检测

---
*该测试使用简化的并发模拟，生产环境建议使用专业工具如 JMeter 或 Gatling 进行更全面的测试。*
EOF

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                 性能测试完成${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

if [ -f "$RESULTS_FILE" ]; then
    if (( $(echo "$success_rate > 95" | bc -l) )) && (( $(echo "$avg_response_time < 2.0" | bc -l) )); then
        echo -e "${GREEN}✅ 性能测试通过${NC}"
        echo "   系统在 $CONCURRENT_USERS 并发用户下表现良好"
    elif (( $(echo "$success_rate > 90" | bc -l) )); then
        echo -e "${YELLOW}⚠️  性能测试部分通过${NC}"
        echo "   建议进行性能调优"
    else
        echo -e "${RED}❌ 性能测试未通过${NC}"
        echo "   需要排查性能问题"
    fi
else
    echo -e "${YELLOW}⚠️  测试数据不完整${NC}"
fi

echo ""
echo "详细报告: $PERF_REPORT"
echo ""

# 清理临时文件
rm -f /tmp/concurrent_auth_test.sh /tmp/auth_response_*.json $RESULTS_FILE

# 给出下一步建议
echo -e "${CYAN}💡 下一步建议：${NC}"
echo "1. 安装 Apache Bench: sudo apt-get install apache2-utils"
echo "2. 使用 JMeter 进行更全面的压力测试"
echo "3. 监控长期稳定性和内存使用"
echo "4. 配置生产级数据库和缓存优化"