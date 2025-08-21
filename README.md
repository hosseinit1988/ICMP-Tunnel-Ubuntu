
# ICMP Tunnel Manager (Hossein.IT)

یک اسکریپت Bash برای ساخت تونل **ICMP (Ping Tunnel)** بین دو سرور Ubuntu:  
- **سرور ایران = Client**  
- **سرور خارج = Server**  
به‌طوری‌که تمام ترافیک سرور ایران از طریق سرور خارج عبور کند.

## فایل‌ها
- `icmp-tunnel.sh` — اسکریپت تعاملی با منو رنگی، نصب خودکار، سرویس systemd، NAT و پاکسازی.

## اجرای سریع
روی هر سرور (با `sudo` اجرا کنید):
```bash
chmod +x icmp-tunnel.sh
sudo ./icmp-tunnel.sh
```
سپس از منو:
1. روی سرور ایران گزینه **1 (Client)** را بزنید و IP سرور آلمان را وارد کنید.  
2. روی سرور خارج گزینه **2 (Server)** را بزنید.

> پس از راه‌اندازی، سرویس‌ها پایدار هستند و پس از ریبوت به‌طور خودکار بالا می‌آیند.

## جزئیات فنی
- ریپو سورس: `https://github.com/DhavalKapil/icmptunnel`
- اینترفیس اینترنتی به‌صورت خودکار شناسایی می‌شود.
- آدرس‌های تونل:
  - Server (خارج): `10.0.0.1/24`
  - Client (ایران): `10.0.0.2/24`
- روی سرور خارج: `IP Forwarding` به‌صورت پایدار فعال می‌شود و `MASQUERADE` روی اینترفیس اینترنتی تنظیم می‌گردد.
- روی سرور ایران: مسیر پیش‌فرض به سمت `10.0.0.1` روی `tun0` تنظیم می‌شود.

## دستورات مفید
نمایش وضعیت:
```bash
systemctl status icmptunnel
```
توقف/شروع:
```bash
sudo systemctl stop icmptunnel
sudo systemctl start icmptunnel
```

## حذف کامل تونل
از منو گزینه **4** را بزنید یا:
```bash
sudo systemctl stop icmptunnel
sudo systemctl disable icmptunnel
sudo rm -f /etc/systemd/system/icmptunnel.service
sudo systemctl daemon-reload
sudo pkill -x icmptunnel || true
sudo ip link set tun0 down || true
sudo ip route del default via 10.0.0.1 dev tun0 || true
sudo iptables -t nat -D POSTROUTING -o <iface> -j MASQUERADE  # در صورت وجود
sudo rm -f /etc/sysctl.d/99-icmp-tunnel.conf && sudo sysctl --system
```

## نکات و رفع اشکال
- اگر فایروال/ACL شبکه ICMP را مسدود کرده باشد، تونل برقرار نمی‌شود.
- اگر روی سرور آلمان به‌جای `iptables` از nftables استفاده می‌کنید، هسته Ubuntu به‌طور پیش‌فرض iptables (nft) را نگاشت می‌کند و دستورها کار می‌کنند.
- اگر اینترفیس اینترنت `eth0` نیست، اسکریپت آن را خودکار شناسایی می‌کند.
- برای مشاهده IP خروجی از سرور ایران:
```bash
curl ifconfig.me
```

## مسئولیت
استفاده از تونل ICMP ممکن است در برخی شبکه‌ها/کشورها محدودیت داشته باشد. قبل از استفاده، قوانین محلی و سیاست‌های ارائه‌دهنده را بررسی کنید.
