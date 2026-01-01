## Cloudflare DDNS（IPv4 / A 记录）

一个 **单文件 Bash 脚本**，用于自动更新 Cloudflare DNS A 记录。

### 特性
- 使用 `curl ip.sb` 获取公网 IPv4
- 自动更新 Cloudflare A 记录
- 交互式配置
- systemd 定时运行（默认 5 分钟）
- 无需 jq / Python

### 安装
```bash
curl -fsSL https://raw.githubusercontent.com/whatareyoudoing111/ddns-cf/refs/heads/main/cf-ddns.sh | sudo bash -s install
### 卸载
```bash
curl -fsSL https://raw.githubusercontent.com/whatareyoudoing111/ddns-cf/refs/heads/main/cf-ddns.sh | sudo bash -s uninstall


