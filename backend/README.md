# MSU Food API

Laravel REST API สำหรับแอป Flutter ลูกค้า/เจ้าของร้าน ใช้ MySQL และ Sanctum bearer tokens. โค้ด API อยู่ใต้ /api/v1 และคืน JSON envelope data หรือสถานะ error ที่ไม่ใช่ 2xx.

ต้องมี PHP 8.3+, PDO MySQL, GD, mbstring, curl, openssl, XML และ Composer. ตั้งค่า .env จาก .env.example โดยเก็บ DB_PASSWORD, APP_KEY และ OAuth/SMTP secrets ไว้เฉพาะเซิร์ฟเวอร์.

```sh
composer install --no-dev --optimize-autoloader
php artisan key:generate
php artisan migrate --force
php artisan config:cache
php artisan route:cache
php artisan view:cache
```

ห้ามใช้ migrate:fresh หรือ seed บน production. ไม่มีบัญชีตัวอย่างใน seeder.

SMTP/Google ที่ยังไม่ตั้งค่าแสดง capabilities=false และคืน 503 เมื่อลองใช้ ไม่ส่ง mail ผ่าน log/array แล้วอ้างว่าสำเร็จ. Production API ต้อง HTTPS.

ทดสอบบนฐานข้อมูลแยกเท่านั้น. phpunit.xml ใช้ SQLite in-memory สำหรับ local tests; scripts/test-vps-backend.py รัน MySQL integration ด้วยบัญชี/ฐานข้อมูลที่ชื่อแยกจาก production และปฏิเสธ release ที่มี config cache.

```sh
php artisan test
```

VPS ปัจจุบันใช้ /srv/msu-food/releases, current symlink, PHP pool msu-food และ MySQL container msu-food-mysql บน localhost:3307. .env ไม่รวมใน source archive. ข้อมูล Firebase เดิมไม่ได้ย้ายหรือลบตามคำยืนยันผู้ใช้ให้เริ่มฐานข้อมูลใหม่.

ดู ../design/MYSQL_API_CONTRACT.md และ ../design/MYSQL_AUTH_SETUP.md สำหรับ DTO, routes, OAuth และขั้นตอนตรวจรับ.
