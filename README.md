## Cloudflare DDNS（IPv4 / A 记录）

一个 **单文件 Bash 脚本**，用于自动更新 Cloudflare DNS A 记录。


## 安装与卸载

```bash
# 安装（交互式配置 + 自动启用 systemd 定时任务）
curl -fsSL https://raw.githubusercontent.com/whatareyoudoing111/ddns-cf/refs/heads/main/cf-ddns.sh -o /tmp/cf-ddns.sh && sudo bash /tmp/cf-ddns.sh install

# 卸载（停止并删除定时任务，移除配置与脚本）
curl -fsSL https://raw.githubusercontent.com/whatareyoudoing111/ddns-cf/refs/heads/main/cf-ddns.sh -o /tmp/cf-ddns.sh && sudo bash /tmp/cf-ddns.sh uninstall

