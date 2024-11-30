#!/bin/bash

# 配置
ARIA2_RPC_URL="http://localhost:6800/jsonrpc"      # aria2 RPC 地址
ARIA2_RPC_SECRET="your_secret_token"               # RPC 密钥（如未设置，请留空）
MAX_SIZE=500000000                                 # 最大文件大小限制（500MB，单位：字节）
BLOCKED_URL_KEYWORDS=("example.com" "malware.com") # 不允许的 URL 关键字
BLOCKED_NAME_KEYWORDS=("hacktool" "illegalfile")   # 不允许的任务名关键字
CHECK_INTERVAL=5                                   # 检测间隔（秒）
CONDITION_THRESHOLD=1                              # 触发终止的条件数值（1=任何一个条件符合，2=两个条件符合，3=三个条件符合, 以此类推）

# 检查活动任务
check_tasks() {
    # 获取所有活动任务信息
    tasks=$(curl -s -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":\"qwer\",\"method\":\"aria2.tellActive\",\"params\":[\"token:${ARIA2_RPC_SECRET}\"]}" \
        "${ARIA2_RPC_URL}" | jq -r '.result')

    # 遍历任务
    echo "$tasks" | jq -c '.[]' | while read -r task; do
        gid=$(echo "$task" | jq -r '.gid')                 # 任务 GID
        url=$(echo "$task" | jq -r '.files[0].uris[0].uri') # 获取第一个 URL
        fileName=$(echo "$task" | jq -r '.files[0].path' | awk -F'/' '{print $NF}') # 获取文件名
        completedLength=$(echo "$task" | jq -r '.completedLength') # 已完成大小

        # 检查条件是否满足
        match_conditions=0  # 记录满足的条件数

        # 你可以根据以下for循环进行额外限制条件添加
        # 检查 URL 是否包含禁止的关键字
        for keyword in "${BLOCKED_URL_KEYWORDS[@]}"; do
            if [[ "$url" == *"$keyword"* ]]; then
                echo "发现不允许的 URL：$url"
                ((match_conditions++))
                break  # 找到一个匹配就停止检查该项
            fi
        done

        # 检查任务名是否包含禁止的关键字
        for keyword in "${BLOCKED_NAME_KEYWORDS[@]}"; do
            if [[ "$fileName" == *"$keyword"* ]]; then
                echo "发现不允许的任务名：$fileName"
                ((match_conditions++))
                break  # 找到一个匹配就停止检查该项
            fi
        done

        # 检查下载大小是否超出限制
        if (( completedLength > MAX_SIZE )); then
            echo "任务 $gid 超过大小限制（已下载：$completedLength 字节）"
            ((match_conditions++))
        fi

        # 判断是否满足条件数值要求
        if (( match_conditions >= CONDITION_THRESHOLD )); then
            echo "任务 $gid 符合条件，正在中止任务..."
            terminate_task "$gid"
        fi
    done
}

# 中止任务
terminate_task() {
    local gid="$1"
    curl -s -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":\"qwer\",\"method\":\"aria2.remove\",\"params\":[\"token:${ARIA2_RPC_SECRET}\",\"$gid\"]}" \
        "${ARIA2_RPC_URL}" > /dev/null
}

# 主循环：每隔 CHECK_INTERVAL 秒检测一次
while true; do
    check_tasks
    sleep "$CHECK_INTERVAL"
done
