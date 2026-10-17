# 3x-ui روی Railway (نسخه v3.10.2 – نسخه‌ی سبک)

## مراحل
1. این پوشه رو تو یه ریپوی GitHub آپلود کن (یا ریپوی قبلی رو جایگزین کن) و تو Railway ازش Deploy کن.
2. **همه‌ی Variableهای قبلی رو پاک کن** (`XUI_BIN_FOLDER`, `XUI_DB_FOLDER`, `XUI_LOG_FOLDER` و ...). مقادیر درست داخل Dockerfile هست و Variableهای Railway بر اونا غالب میشن.
3. سرویس → Settings → **Volumes** → یه Volume بساز با Mount Path: `/etc/x-ui`
   (اگه ولوم قدیمی `ee-volume` رو داری حذف و دوباره بساز.)
4. سرویس → Settings → Networking → **Generate Domain**.
   پورتی که می‌پرسه رو همون چیزی بذار که Railway خودش پیشنهاد می‌ده (متغیر `PORT`). دستی 2053 نذار.
5. Deploy. بعد از بالا اومدن، تو **Deploy Logs** بلوک «first-run credentials» رو پیدا کن: آدرس کامل پنل (با مسیر مخفی)، یوزر و پسورد اونجاست.

## Variableهای اختیاری
| نام | کاربرد |
|---|---|
| `PANEL_USERNAME` / `PANEL_PASSWORD` | یوزر/پسورد دلخواه (وگرنه رندوم ساخته میشه) |
| `PANEL_BASE_PATH` | مسیر پنل، مثلاً `mypanel` (وگرنه رندوم) |

## نکات
- فقط پنل از طریق دامنه‌ی HTTP Railway باز میشه. برای inboundهای VPN باید تو Networking یه **TCP Proxy** برای پورت inbound اضافه کنی.
- fail2ban (محدودیت IP) روی Railway کار نمی‌کنه و غیرفعاله.
- بدون Volume، با هر Deploy دیتابیس پاک میشه.
