#!/bin/bash

# @Author  : yuanz
# @Time    : 2024/12/19 15:30
# Website: https://www.yzgsa.com
# Copyright (c) <yuanzigsa@gmail.com>

# udpshooter CentOS 部署脚本
# 功能：从指定URL下载udpshooter，配置systemd服务，设置中国时区

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 配置DNS确保正确解析域名
check_configure_dns() {
    log_info "检测和配置DNS..."
    if ! grep -E '^nameserver' '/etc/resolv.conf' &> /dev/null; then
        cat >> /etc/resolv.conf <<EOF
nameserver 114.114.114.114
nameserver 114.114.115.115
nameserver 223.5.5.5
nameserver 223.6.6.6
nameserver 119.29.29.29
nameserver 8.8.8.8
EOF
        log_info "DNS已配置为114DNS、阿里DNS、腾讯DNS和Google DNS"
    fi
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
}


# 检查系统版本
check_system() {
    if ! grep -q "CentOS\|Red Hat\|Rocky\|AlmaLinux" /etc/os-release; then
        log_error "此脚本仅支持CentOS/RHEL系列系统"
        exit 1
    fi
    log_info "系统检查通过"
}

# 设置中国时区
set_timezone() {
    log_step "设置中国时区..."
    
    # 检查时区是否已经设置
    CURRENT_TIMEZONE=$(timedatectl | grep "Time zone" | awk '{print $3}')
    if [[ "$CURRENT_TIMEZONE" == "Asia/Shanghai" ]]; then
        log_info "时区已经是Asia/Shanghai，跳过设置"
        return
    fi
    
    # 设置时区
    timedatectl set-timezone Asia/Shanghai
    
    # 验证设置
    NEW_TIMEZONE=$(timedatectl | grep "Time zone" | awk '{print $3}')
    if [[ "$NEW_TIMEZONE" == "Asia/Shanghai" ]]; then
        log_info "时区设置成功: $NEW_TIMEZONE"
    else
        log_error "时区设置失败"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    log_step "安装依赖包..."
    
    # 更新包管理器
    yum update -y
    
    # 安装必要的工具
    yum install -y wget curl systemd systemd-sysv
    
    log_info "依赖安装完成"
}

# 下载udpshooter和配置文件
download_udpshooter() {
    log_step "下载udpshooter和配置文件..."
    
    # 默认下载URL，可以通过参数传入
    DOWNLOAD_URL=${1:-"https://gitee.com/yzgsa/public_res/releases/download/udpshooter/udpshooter"}
    CONFIG_URL="https://gitee.com/yzgsa/public_res/releases/download/udpshooter/config.json"
    INSTALL_DIR="/opt/udpshooter"
    BINARY_NAME="udpshooter"
    CONFIG_NAME="config.json"
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    
    # 下载二进制文件
    log_info "从 $DOWNLOAD_URL 下载udpshooter..."
    
    if wget -O "$INSTALL_DIR/$BINARY_NAME" "$DOWNLOAD_URL"; then
        log_info "udpshooter下载成功"
    else
        log_error "udpshooter下载失败，请检查URL是否正确"
        exit 1
    fi
    
    # 下载配置文件
    log_info "从 $CONFIG_URL 下载配置文件..."
    
    if wget -O "$INSTALL_DIR/$CONFIG_NAME" "$CONFIG_URL"; then
        log_info "配置文件下载成功"
    else
        log_error "配置文件下载失败，请检查URL是否正确"
        exit 1
    fi
    
    # 设置执行权限
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    
    # 设置配置文件权限
    chmod 644 "$INSTALL_DIR/$CONFIG_NAME"
    
    # 验证文件
    if [[ -x "$INSTALL_DIR/$BINARY_NAME" ]]; then
        log_info "udpshooter安装成功: $INSTALL_DIR/$BINARY_NAME"
    else
        log_error "udpshooter安装失败"
        exit 1
    fi
    
    if [[ -f "$INSTALL_DIR/$CONFIG_NAME" ]]; then
        log_info "配置文件安装成功: $INSTALL_DIR/$CONFIG_NAME"
    else
        log_error "配置文件安装失败"
        exit 1
    fi
}

# 创建systemd服务
create_systemd_service() {
    log_step "创建systemd服务..."
    
    SERVICE_NAME="udpshooter"
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
    BINARY_PATH="/opt/udpshooter/udpshooter"
    
    # 检查二进制文件是否存在
    if [[ ! -f "$BINARY_PATH" ]]; then
        log_error "udpshooter二进制文件不存在: $BINARY_PATH"
        exit 1
    fi
    
    # 创建服务文件
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=UDP Shooter Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/udpshooter
ExecStart=$BINARY_PATH
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal
SyslogIdentifier=udpshooter

# 安全设置
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log /tmp /opt/udpshooter

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载systemd配置
    systemctl daemon-reload
    
    # 启用服务
    systemctl enable "$SERVICE_NAME"
    
    log_info "systemd服务创建成功: $SERVICE_FILE"
    log_info "服务已启用，可以使用以下命令管理："
    log_info "  启动: systemctl start $SERVICE_NAME"
    log_info "  停止: systemctl stop $SERVICE_NAME"
    log_info "  重启: systemctl restart $SERVICE_NAME"
    log_info "  状态: systemctl status $SERVICE_NAME"
}

# 创建日志目录
create_log_directory() {
    log_step "创建日志目录..."
    
    LOG_DIR="/var/log/udpshooter"
    mkdir -p "$LOG_DIR"
    chmod 755 "$LOG_DIR"
    
    log_info "日志目录创建成功: $LOG_DIR"
}

# 启动服务
start_service() {
    log_step "启动udpshooter服务..."
    
    if systemctl start udpshooter; then
        log_info "服务启动成功"
        
        # 检查服务状态
        sleep 2
        if systemctl is-active --quiet udpshooter; then
            log_info "服务运行正常"
        else
            log_warn "服务可能未正常运行，请检查日志: journalctl -u udpshooter"
        fi
    else
        log_error "服务启动失败"
        log_info "请检查日志: journalctl -u udpshooter"
        exit 1
    fi
}

# 显示安装信息
show_install_info() {
    log_step "安装完成！"
    echo
    echo "=========================================="
    echo "           udpshooter 安装信息"
    echo "=========================================="
    echo "安装路径: /opt/udpshooter/udpshooter"
    echo "配置文件: /opt/udpshooter/config.json"
    echo "服务名称: udpshooter"
    echo "日志目录: /var/log/udpshooter"
    echo "时区设置: $(timedatectl | grep "Time zone" | awk '{print $3}')"
    echo
    echo "常用命令:"
    echo "  查看服务状态: systemctl status udpshooter"
    echo "  查看服务日志: journalctl -u udpshooter -f"
    echo "  重启服务: systemctl restart udpshooter"
    echo "  停止服务: systemctl stop udpshooter"
    echo "=========================================="
}

# 主函数
main() {
    log_info "开始安装udpshooter..."
    
    # 检查系统要求
    check_root
    check_system
    check_configure_dns
    
    # 执行安装步骤
    set_timezone
    install_dependencies
    download_udpshooter "$1"
    create_log_directory
    create_systemd_service
    start_service
    
    # 显示安装信息
    show_install_info
}

# 显示帮助信息
show_help() {
    echo "用法: $0 [下载URL]"
    echo
    echo "参数:"
    echo "  下载URL    可选，udpshooter的下载地址"
    echo "             如果不提供，将使用默认地址"
    echo
    echo "示例:"
    echo "  $0                                    # 使用默认下载地址"
    echo "  $0 https://example.com/udpshooter    # 使用指定下载地址"
    echo
    echo "注意: 此脚本需要root权限运行"
}

# 脚本入口
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# 执行主函数
main "$1"
