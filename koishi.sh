#!/bin/bash

# 获取用户名
username=$(uname -n | cut -d'-' -f2)

# 检查是否配置noto-fonts
if ! grep -qE '\bpkgs\.noto-fonts\b' "/home/user/$username/.idx/dev.nix"; then
    echo "检测dev.nix中尚未配置noto-fonts，使用puppeteer时将无法渲染文字"
    echo "请在默认打开的dev.nix文件中（或在左侧文件浏览器.idx文件夹中）添加pkgs.noto-fonts"
    echo "然后点击右下Rebuild Environment按钮重建工作区后再次运行脚本"
    echo "如果找不到按钮也可退回idx首页，点击工作区右方三个点选择Restart即可重建"
    echo "如无渲染文字需求，输入任意内容回车继续执行脚本"
    echo "直接回车退出脚本进行配置"
    read -r user_input

    if [[ -z "$user_input" ]]; then
        exit 1
    fi
fi

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
echo "正在安装koishi，请耐心等待"
npm install

# 修改默认启动后打开webui
sed -i 's/open: true/open: false/' koishi.yml

# 替换插件源
sed -i 's|https://registry.koishi.chat/index.json|https://koishi-registry.yumetsuki.moe/index.json|' koishi.yml

# 启动koishi
nohup npm start >/dev/null 2>&1 &

echo "已成功安装cloudflared和koishi并启动"
echo "请使用cloudflare tunnel连接http://localhost:5140访问koishi webui"
