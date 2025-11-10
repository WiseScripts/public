#!/bin/bash

# ==============================================================================
# 动态目录备份脚本
#
# 功能: 从 .txt 文件读取目录列表, 使用 fsarchiver 备份, 上传到 Dropbox,
#       清理旧备份, 并通过 ntfy 发送通知。
# ==============================================================================
# /root
# /etc/nginx
# /docker/ntfy

# --- 配置区域 (请根据您的环境修改) ---
HOSTNAME=$(hostname)

# 1. 本地临时备份目录 (确保存在且有写入权限)
BACKUP_TMP_DIR="/tmp/backups"

# 2. Dropbox 上的备份根目录
DROPBOX_BASE_DIR="$HOSTNAME"

# 3. 备份文件保留天数 (超过此天数的备份将被删除)
RETENTION_DAYS=30

# 4. fsarchiver 压缩使用的 CPU 线程数
COMPRESSION_THREADS=2

# --- ntfy 通知配置 ---
# 5. 自托管 ntfy 服务器的地址 (例如: https://your-ntfy-server.com)
NTFY_SERVER="https://ntfy.example.com"

# 6. ntfy 主题 (Topic)
NTFY_TOPIC="notification"

# 7. 如果您的 ntfy 服务器需要认证 - Token
#    如果不需要认证，请将此项留空 (e.g., NTFY_TOKEN="")
NTFY_TOKEN="tk_56vt4ejkp" # <<< 请替换为您实际的 Token

# 8. 如果您的 ntfy 服务器需要认证 - 用户名和口令认证
#    如果不需要认证，请将这两项留空 (e.g., NTFY_USERNAME="")
NTFY_USERNAME="ntfy"
NTFY_PASSWORD="ntfy-KQHRwhBVpM4zP" 

# --- 脚本核心逻辑 (通常无需修改) ---

# 封装 curl 命令以处理认证 (Token)
NTFY_AUTH_HEADER=""
if [[ -n "$NTFY_TOKEN" ]]; then
    # 使用 Bearer Token 认证
    NTFY_AUTH_HEADER="Authorization: Bearer $NTFY_TOKEN"
elif [[ -n "$NTFY_USERNAME" && -n "$NTFY_PASSWORD" ]]; then
    # 使用 Basic Auth
    auth_b64=$(echo -n "$NTFY_USERNAME:$NTFY_PASSWORD" | base64)
    NTFY_AUTH_HEADER="Authorization: Basic $auth_b64"
fi

FSARCHIVER_PASSWORD="N3WM4zPK66uyBqadHgN2QU"

# 封装发送通知的函数
send_notification() {
    local priority="$1"
    local title="$2"
    local message="$3"
    local tags="$4"
    
    # 构建 curl 命令
    local curl_cmd=(
        "curl" "-s"
        "-H" "Priority: $priority"
        "-H" "Title: $title"
        "-H" "Tags: $tags"
    )

    # 如果需要认证，添加认证头 (使用 Token)
    if [[ -n "$NTFY_AUTH_HEADER" ]]; then
        curl_cmd+=("-H" "$NTFY_AUTH_HEADER")
    fi
    curl_cmd+=("-d" "$message" "${NTFY_SERVER}/${NTFY_TOPIC}")

    # 执行命令
    "${curl_cmd[@]}" > /dev/null 2>&1
}

# 脚本异常退出处理
handle_fatal_error() {
    local error_message="致命错误: ${1:-'未知错误'} at line ${BASH_LINENO[0]}."
    echo "$(date): $error_message"
    send_notification "urgent" "备份任务严重失败!" "$error_message" "rotating_light,skull"
    exit 1
}

# 设置陷阱，在非零退出码时调用 handle_fatal_error
trap 'handle_fatal_error' ERR

# 检查依赖

# 检查 curl 命令是否存在
# command -v curl >/dev/null 2>&1 || handle_fatal_error "curl 命令未找到, 请先安装。"
if ! command -v curl &> /dev/null; then
    echo "$(date): 错误: curl 命令未找到。请先安装它 (e.g., sudo apt-get install curl)。"
    exit 1
fi

command -v fsarchiver >/dev/null 2>&1 || handle_fatal_error "fsarchiver 命令未找到, 请先安装。"
command -v dbxcli >/dev/null 2>&1 || handle_fatal_error "dbxcli 命令未找到, 请先安装。"


# 任务开始

# 获取脚本自身所在的目录
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_NAME=$(basename "$0")
# 从脚本名推断出 .txt 配置文件名 (e.g., backup.sh -> backup.txt)
CONFIG_FILE="${SCRIPT_DIR}/${SCRIPT_NAME%.*}.txt"
[ -f "$CONFIG_FILE" ] || handle_fatal_error "配置文件 $CONFIG_FILE 未找到。"


send_notification "low" "[$HOSTNAME] 备份任务已开始" "动态目录备份流程已启动。" "computer,hourglass"
echo "-------------------------------------"
echo "备份任务开始于: $(date)"
echo "读取配置文件: $CONFIG_FILE"

mkdir -p "$BACKUP_TMP_DIR"
DBXCLI_PATH=$(which dbxcli)
declare -a summary_log

# 读取配置文件并开始备份
# (此部分逻辑与原脚本保持一致，仅省略注释以保持简洁，核心功能不变)
while IFS= read -r SOURCE_DIR || [[ -n "$SOURCE_DIR" ]]; do
    # 忽略空行和以'#'开头的注释行
    [[ -z "$SOURCE_DIR" || "$SOURCE_DIR" =~ ^\s*# ]] && continue
    
    echo ""
    echo ">>> 正在处理目录: $SOURCE_DIR"
    
    if [ ! -d "$SOURCE_DIR" ]; then
        log_message="警告: 目录 $SOURCE_DIR 不存在, 已跳过。"
        echo "$log_message"
        summary_log+=("$log_message")
        continue
    fi
    
    ## BASENAME=$(basename "$SOURCE_DIR")
    BASENAME=$(echo "$SOURCE_DIR" | sed 's#^/##; s#/#_#g')
    ## DROPBOX_TARGET_DIR="${DROPBOX_BASE_DIR}/${BASENAME}"
    DROPBOX_TARGET_DIR="${DROPBOX_BASE_DIR}"
    #3 DATE=$(date +"%Y-%m-%d_%H-%M-%S")
    ## ARCHIVE_NAME="${BASENAME}-${DATE}.fsa"
    DATE=$(date +"%Y_%m_%d_%H_%M_%S")
    ARCHIVE_NAME="${BASENAME}_${DATE}.fsa"
    LOCAL_ARCHIVE_PATH="${BACKUP_TMP_DIR}/${ARCHIVE_NAME}"
    
    # 1. 创建备份
    if ! fsarchiver savedir -v -o -A -c ${FSARCHIVER_PASSWORD} -j ${COMPRESSION_THREADS} "$LOCAL_ARCHIVE_PATH" "$SOURCE_DIR"; then
        log_message="❌ 失败: 为 $SOURCE_DIR 创建备份失败。"
        echo "$log_message"
        summary_log+=("$log_message")
        continue
    fi
    
    # 2. 上传备份
    if ! "$DBXCLI_PATH" put "$LOCAL_ARCHIVE_PATH" "${DROPBOX_TARGET_DIR}/${ARCHIVE_NAME}"; then
        log_message="❌ 失败: 上传 $ARCHIVE_NAME 失败 (本地文件已保留)。"
        echo "$log_message"
        summary_log+=("$log_message")
        continue
    fi
    
    # 3. 删除本地临时文件
    rm "$LOCAL_ARCHIVE_PATH"
    
    # 4. 清理 Dropbox 上的旧备份
    "$DBXCLI_PATH" ls "$DROPBOX_TARGET_DIR" | grep -E '\.fsa$' | while read -r line; do
        filename=$(echo "$line" | awk '{print $NF}')
        ## file_date_str=$(echo "$filename" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
        file_date_str=$(echo "$filename" | sed 's/_/-/g' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
        
        if [ -n "$file_date_str" ]; then
            file_date_epoch=$(date -d "$file_date_str" +%s)
            current_date_epoch=$(date +%s)
            days_diff=$(( (current_date_epoch - file_date_epoch) / 86400 ))
            if [ "$days_diff" -gt "$RETENTION_DAYS" ]; then
                echo "删除旧备份: ${DROPBOX_TARGET_DIR}/${filename}"
                "$DBXCLI_PATH" rm "${DROPBOX_TARGET_DIR}/${filename}"
            fi
        fi
    done
    
    log_message="✅ 成功: $SOURCE_DIR"
    echo "$log_message"
    summary_log+=("$log_message")

done < "$CONFIG_FILE"

# 任务结束
summary_string=$(printf "%s\n" "${summary_log[@]}")
send_notification "default" "[$HOSTNAME] 备份任务已完成" "备份流程已结束。
---
摘要:
$summary_string" "tada,white_check_mark"

echo ""
echo "所有备份任务处理完毕于: $(date)"
echo "-------------------------------------"

exit 0
