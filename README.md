# 🌐 Cloudcaddy – Dynamic DNS Updater for Cloudflare

**cloudcaddy** is a secure, systemd-based dynamic DNS updater for Cloudflare A records. It automatically keeps your domain pointing to your current public IP address — ideal for home servers on dynamic IPs.

---

## ✅ Features

- ⏲ Runs every 5 minutes via `systemd`
- 🔐 Stores secrets in a root-owned directory (`/opt/cloudflare-ddns`)
- 🚀 Uses Cloudflare's official DNS API
- 🧠 Skips unnecessary API calls if your IP hasn't changed
- 🛠 Installs with a single script

---

## 📦 Requirements

- A domain registered and managed through [Cloudflare](https://cloudflare.com)
- A **Cloudflare API Token** with the following permissions:
  - Zone → Read
  - DNS → Edit
- A Linux system using `systemd`

---

## 🚀 Installation

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/DDNS.git
cd DDNS
```

### 2. Make the installer executable

```bash
chmod +x install.sh
```

### 3. Run the installer as root

```bash
sudo ./install.sh
```

---

## 📋 What the Installer Does

When you run `install.sh`, it will:

1. **Install dependencies** (`jq`, `curl`)
2. **Prompt for Cloudflare details**:
   - API Token
   - Zone Name (e.g. `example.com`)
   - Record Name (e.g. `home.example.com` or `example.com`)
3. **Write a secure config file** to `/opt/cloudflare-ddns/cf-ddns.env`
4. **Deploy the update script** to `/opt/cloudflare-ddns/ddns.sh`
5. **Set permissions** so only root can access secrets
6. **Create systemd units**:
   - `cloudcaddy.service`: runs the updater once
   - `cloudcaddy.timer`: runs the service every 5 minutes
7. **Enable and start the timer**

---

## 🛠 Verifying It Works

### ✔️ Check if the timer is active
```bash
systemctl list-timers --all | grep cloudcaddy
```

You should see a line like:
```
cloudcaddy.timer loaded active waiting Run Cloudcaddy DDNS update every 5 minutes
```

### ✔️ View logs from the updater
```bash
sudo journalctl -u cloudcaddy.service --no-pager
```

This will show your public IP and whether an update was made.

### ✔️ Manually trigger an update
```bash
sudo systemctl start cloudcaddy.service
```

---

## 🔧 Where Things Live

| Path | Description |
|------|-------------|
| `/opt/cloudflare-ddns/ddns.sh` | Main update script |
| `/opt/cloudflare-ddns/cf-ddns.env` | Configuration file (API token, zone, record) |
| `/etc/systemd/system/cloudcaddy.service` | Systemd service unit |
| `/etc/systemd/system/cloudcaddy.timer` | Systemd timer unit |

---

## 🧽 Uninstalling

To completely remove Cloudcaddy:

```bash
sudo systemctl disable --now cloudcaddy.timer
sudo rm /etc/systemd/system/cloudcaddy.{service,timer}
sudo rm -rf /opt/cloudflare-ddns
sudo systemctl daemon-reload
```

---

## 🔐 Security Notes

- Your API token is saved at `/opt/cloudflare-ddns/cf-ddns.env`, accessible only by `root`.
- The installer sets file and directory permissions to prevent unauthorized access.
- Use a **scoped Cloudflare API token** — *never use your global key*.

---

## 📄 License

MIT License

---

## 📌 Example Use Case

Let’s say you run a self-hosted site or Caddy server on your home internet connection, and your ISP gives you a dynamic IP. You want to reach your site at `home.example.com`, even if your IP changes. Just point your A record at your router once, install Cloudcaddy on the server, and it will handle updates automatically in the background.
