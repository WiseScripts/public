#!/bin/bash

# 脚本名称: refresh_tokens.sh
# 描述: 自动执行云存储列表命令以刷新访问令牌。
# 注意:
# 1. 确保 onedrive-uploader, dbxcli, rclone 已经安装并配置好。
# 2. 确保脚本中使用的路径正确（例如 rclone 的远程名称 'gd-anonymous'）。
# 3. 将此脚本放在一个安全的位置，例如 ~/scripts/。

# crontab -e
# 0 */1 * * * "/data/scripts/refresh_tokens.sh"

LOG_FILE="/var/log/refresh_tokens.log"
DATE_TIME=$(date '+%Y-%m-%d %H:%M:%S')

echo -e "\n--- 令牌刷新任务开始: $DATE_TIME ---" >> "$LOG_FILE"

# 1. OneDrive Uploader (假设已配置)
echo -e "\n执行 onedrive-uploader ls / ..." >> "$LOG_FILE"
# 使用 > /dev/null 2>&1 忽略命令的输出和错误，只记录执行结果
# 成功退出代码为 0，失败为非 0
onedrive-uploader ls / > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "onedrive-uploader 刷新成功。" >> "$LOG_FILE"
else
    echo "onedrive-uploader 刷新失败 (请检查其配置/日志)。" >> "$LOG_FILE"
fi

# 2. dbxcli (Dropbox) (假设已配置)
echo -e "\n执行 dbxcli ls / ..." >> "$LOG_FILE"
dbxcli ls / > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "dbxcli 刷新成功。" >> "$LOG_FILE"
else
    echo "dbxcli 刷新失败 (请检查其配置/日志)。" >> "$LOG_FILE"
fi

# 3. rclone (Google Drive) (假设远程名称为 gd-anonymous:)
echo -e "\n执行 rclone lsd gd-anonymous:/ ..." >> "$LOG_FILE"
# 确保在非交互式环境中运行 rclone 时，它能找到配置文件。
# 如果 rclone 配置在默认位置 (~/.config/rclone/rclone.conf)，通常没问题。
# 如果 rclone 远程名称不是 gd-anonymous，请修改它。
rclone lsd gd-anonymous:/ > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "rclone gd-anonymous:/ 刷新成功。" >> "$LOG_FILE"
else
    echo "rclone gd-anonymous:/ 刷新失败 (请检查其配置/日志)。" >> "$LOG_FILE"
fi

# 4. rclone (Google Drive) (假设远程名称为 gd-username:)
echo -e "\n执行 rclone lsd gd-username:/ ..." >> "$LOG_FILE"
# 确保在非交互式环境中运行 rclone 时，它能找到配置文件。
# 如果 rclone 配置在默认位置 (~/.config/rclone/rclone.conf)，通常没问题。
# 如果 rclone 远程名称不是 gd-username，请修改它。
rclone lsd gd-username:/ > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "rclone gd-username:/ 刷新成功。" >> "$LOG_FILE"
else
    echo "rclone gd-username:/ 刷新失败 (请检查其配置/日志)。" >> "$LOG_FILE"
fi

# 5. rclone (Google Drive) (假设远程名称为 od-admin:)
echo -e "\n执行 rclone lsd od-admin:/ ..." >> "$LOG_FILE"
# 确保在非交互式环境中运行 rclone 时，它能找到配置文件。
# 如果 rclone 配置在默认位置 (~/.config/rclone/rclone.conf)，通常没问题。
# 如果 rclone 远程名称不是 od-admin，请修改它。
rclone lsd od-admin:/ > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "rclone od-admin:/ 刷新成功。" >> "$LOG_FILE"
else
    echo "rclone od-admin:/ 刷新失败 (请检查其配置/日志)。" >> "$LOG_FILE"
fi

# 6. rclone (Google Drive) (假设远程名称为 od-backup:)
echo -e "\n执行 rclone lsd od-backup:/ ..." >> "$LOG_FILE"
# 确保在非交互式环境中运行 rclone 时，它能找到配置文件。
# 如果 rclone 配置在默认位置 (~/.config/rclone/rclone.conf)，通常没问题。
# 如果 rclone 远程名称不是 od-backup，请修改它。
rclone lsd od-backup:/ > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "rclone od-backup:/ 刷新成功。" >> "$LOG_FILE"
else
    echo "rclone od-backup:/ 刷新失败 (请检查其配置/日志)。" >> "$LOG_FILE"
fi

echo -e "\n--- 令牌刷新任务结束: $DATE_TIME ---\n" >> "$LOG_FILE"

# 为了防止日志文件无限增大，只保留最新的 1000 行
tail -n 1000 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
