#!/bin/bash

# 清除可能存在的旧进程
pkill -x "npm start" 2>/dev/null
pkill -x "cloudflared" 2>/dev/null

# 设置环境变量，默认为空
export auth=${auth:-''}

# 验证 Cloudflare Tunnel token（184 位 Base64 编码字符串）
validate_auth() {
    local auth=$1
    if [[ $auth =~ ^[A-Za-z0-9+/=]{184}$ ]]; then
        return 0
    else
        return 1
    fi
}

# 检查并提示输入未设置的变量
if [ -z "$auth" ]; then
    while true; do
        read -p "请输入 Cloudflare Tunnel token (184 位 Base64 编码字符串): " auth
        if validate_auth "$auth"; then
            export auth
            break
        else
            echo "无效的 Cloudflare Tunnel token 格式（需 184 位 Base64 字符串），请重新输入"
        fi
    done
fi

# 获取用户名
username=$(uname -n | cut -d'-' -f2)

# 创建必要的目录
mkdir -p /home/user/$username/cloudflared

# 下载cloudflared
curl -Lo /home/user/$username/cloudflared/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x /home/user/$username/cloudflared/cloudflared

# 创建自动运行脚本
cat >> /home/user/$username/autorun.sh <<EOF
#!/bin/bash

# 检查koishi和cloudflared是否正在运行
if pgrep -x "npm start" >/dev/null && pgrep -x "cloudflared" >/dev/null; then
    echo "Both koishi and cloudflared are running. Exiting..."
    exit 1
fi

# 清除可能存在的旧进程
pkill -x "npm start" 2>/dev/null
pkill -x "cloudflared" 2>/dev/null

# 运行cloudflared
nohup /home/user/$username/cloudflared/cloudflared tunnel --no-autoupdate --edge-ip-version 4 --protocol http2 run --token "$auth" >/dev/null 2>&1 &

# 运行koishi
cd /home/user/$username/koishi-app
nohup npm start >/dev/null 2>&1 &
EOF

chmod +x /home/user/$username/autorun.sh

# 添加到.bashrc以便自动运行
sed -i '/autorun/d' ~/.bashrc
echo "bash /home/user/$username/autorun.sh" >> ~/.bashrc

# 运行cloudflared
nohup /home/user/$username/cloudflared/cloudflared tunnel --no-autoupdate --edge-ip-version 4 --protocol http2 run --token "$auth" >/dev/null 2>&1 &

# 安装koishi
cd /home/user/$username
npm init -y koishi@latest koishi-app -- --yes
cd koishi-app
npm install

# 修改默认启动后打开webui
sed -i 's/open: true/open: false/' koishi.yml

# 替换插件源
sed -i 's|https://registry.koishi.chat/index.json|https://koishi-registry.yumetsuki.moe/index.json|' koishi.yml

# 启动koishi
nohup npm start >/dev/null 2>&1 &

echo "已成功安装cloudflared和koishi并启动"
echo "请使用cloudflare tunnel连接http://localhost:5140访问koishi webui"
