#!/bin/bash

# Keycloak 部署脚本
# 使用方法: ./deploy.sh [start|stop|restart|status|logs|reset]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 Docker 和 Docker Compose
check_dependencies() {
    log_info "检查依赖..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi
    
    log_success "依赖检查通过"
}

# 创建必要的目录
create_directories() {
    log_info "创建必要的目录..."
    
    cd "$PROJECT_DIR"
    
    mkdir -p keycloak-data
    mkdir -p themes
    mkdir -p providers
    mkdir -p import
    mkdir -p backups
    
    # 设置权限
    chmod -R 755 keycloak-data
    
    log_success "目录创建完成"
}

# 启动服务
start_services() {
    log_info "启动 Keycloak 服务..."
    
    cd "$PROJECT_DIR"
    
    # 拉取最新镜像
    docker-compose pull
    
    # 启动服务
    docker-compose up -d
    
    log_info "等待服务启动..."
    
    # 等待 PostgreSQL 就绪
    log_info "等待 PostgreSQL 启动..."
    for i in {1..30}; do
        if docker-compose exec -T postgres pg_isready -U keycloak >/dev/null 2>&1; then
            log_success "PostgreSQL 已就绪"
            break
        fi
        if [ $i -eq 30 ]; then
            log_error "PostgreSQL 启动超时"
            exit 1
        fi
        sleep 2
    done
    
    # 等待 Keycloak 就绪
    log_info "等待 Keycloak 启动（这可能需要1-2分钟）..."
    for i in {1..60}; do
        if curl -f http://localhost:8080/health/ready >/dev/null 2>&1; then
            log_success "Keycloak 已就绪"
            break
        fi
        if [ $i -eq 60 ]; then
            log_error "Keycloak 启动超时"
            exit 1
        fi
        sleep 5
    done
    
    log_success "Keycloak 部署完成！"
    print_access_info
}

# 停止服务
stop_services() {
    log_info "停止 Keycloak 服务..."
    
    cd "$PROJECT_DIR"
    docker-compose down
    
    log_success "服务已停止"
}

# 重启服务
restart_services() {
    log_info "重启 Keycloak 服务..."
    
    stop_services
    start_services
}

# 查看状态
show_status() {
    cd "$PROJECT_DIR"
    
    echo "=== 容器状态 ==="
    docker-compose ps
    
    echo -e "\n=== 健康检查 ==="
    
    # 检查 PostgreSQL
    if docker-compose exec -T postgres pg_isready -U keycloak >/dev/null 2>&1; then
        echo -e "PostgreSQL: ${GREEN}✓ 运行中${NC}"
    else
        echo -e "PostgreSQL: ${RED}✗ 异常${NC}"
    fi
    
    # 检查 Keycloak
    if curl -f http://localhost:8080/health/ready >/dev/null 2>&1; then
        echo -e "Keycloak: ${GREEN}✓ 运行中${NC}"
    else
        echo -e "Keycloak: ${RED}✗ 异常${NC}"
    fi
    
    print_access_info
}

# 查看日志
show_logs() {
    cd "$PROJECT_DIR"
    
    if [ "$2" = "follow" ] || [ "$2" = "-f" ]; then
        docker-compose logs -f
    else
        docker-compose logs --tail=100
    fi
}

# 重置环境
reset_environment() {
    log_warning "⚠️  这将删除所有数据，包括用户、配置等！"
    read -p "确认重置环境？(y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "重置环境中..."
        
        cd "$PROJECT_DIR"
        
        # 停止并删除容器
        docker-compose down -v
        
        # 删除数据
        rm -rf keycloak-data/*
        
        # 重新启动
        start_services
        
        log_success "环境重置完成"
    else
        log_info "取消重置"
    fi
}

# 打印访问信息
print_access_info() {
    echo -e "\n${GREEN}=== 访问信息 ===${NC}"
    echo -e "Keycloak 管理控制台: ${BLUE}http://localhost:8080${NC}"
    echo -e "管理员账号: ${YELLOW}admin${NC}"
    echo -e "管理员密码: ${YELLOW}admin123${NC}"
    echo -e "\nMailHog (邮件测试): ${BLUE}http://localhost:8025${NC}"
    echo -e "Adminer (数据库): ${BLUE}http://localhost:8090${NC}"
    echo -e "\n数据库连接信息:"
    echo -e "  主机: localhost:5432"
    echo -e "  数据库: keycloak"
    echo -e "  用户名: keycloak"
    echo -e "  密码: keycloak123"
    echo -e "\n${GREEN}部署完成！${NC}"
}

# 备份数据
backup_data() {
    log_info "备份 Keycloak 数据..."
    
    cd "$PROJECT_DIR"
    
    BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # 备份数据库
    log_info "备份数据库..."
    docker-compose exec -T postgres pg_dump -U keycloak keycloak > "$BACKUP_DIR/database.sql"
    
    # 备份配置文件
    log_info "备份配置文件..."
    cp -r keycloak-data "$BACKUP_DIR/" 2>/dev/null || true
    cp docker-compose.yml "$BACKUP_DIR/"
    
    log_success "备份完成: $BACKUP_DIR"
}

# 显示使用帮助
show_help() {
    echo "Keycloak 部署脚本"
    echo ""
    echo "使用方法:"
    echo "  $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "命令:"
    echo "  start          启动服务"
    echo "  stop           停止服务"
    echo "  restart        重启服务"
    echo "  status         查看状态"
    echo "  logs           查看日志"
    echo "  logs follow    实时查看日志"
    echo "  reset          重置环境（删除所有数据）"
    echo "  backup         备份数据"
    echo "  help           显示帮助"
    echo ""
    echo "示例:"
    echo "  $0 start       # 启动服务"
    echo "  $0 logs -f     # 实时查看日志"
    echo "  $0 backup      # 备份数据"
}

# 主函数
main() {
    case "${1:-help}" in
        start)
            check_dependencies
            create_directories
            start_services
            ;;
        stop)
            stop_services
            ;;
        restart)
            restart_services
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs "$@"
            ;;
        reset)
            reset_environment
            ;;
        backup)
            backup_data
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"