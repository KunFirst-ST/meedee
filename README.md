# MSU Food

แอป Flutter/Dart ภาษาไทยสำหรับสั่งอาหารล่วงหน้าและรับที่ร้าน มีหน้าลูกค้าและเจ้าของร้าน ใช้ Laravel + MySQL แทน Firebase runtime แล้ว

## รุ่นปัจจุบัน

- เว็บ: https://103.114.201.109/ พร้อม HTTPS ใบรับรอง IP ที่ตรวจสอบได้
- API: https://103.114.201.109/api/v1
- เริ่มฐานข้อมูลใหม่ตามคำยืนยันผู้ใช้วันที่ 13 ตุลาคม 2026 ไม่ย้ายและไม่ลบข้อมูล Firebase เดิม
- ไม่มีบัญชี ร้าน เมนู หรือออเดอร์ทดลองในฐานข้อมูล production
- Google OAuth สำหรับเข้าสู่ระบบผ่าน API บน VPS ตั้งค่าและตรวจสอบแล้ว; SMTP ยังไม่ตั้งค่า จึงยังไม่รองรับการยืนยันอีเมลและกู้รหัสผ่านทางอีเมล

## เปิดด้วย Android Studio

เปิดโฟลเดอร์ที่มี pubspec.yaml ติดตั้ง Flutter/Dart plugins เลือก configuration **MSU Food** และอุปกรณ์ Android จากนั้น Run ได้ Configuration ใน .run/MSU Food.run.xml ใส่ API_BASE_URL ของ VPS แล้ว

```powershell
flutter pub get
flutter run --dart-define=API_BASE_URL=https://103.114.201.109/api/v1
flutter run -d chrome --web-hostname=localhost --web-port=5173 --dart-define=API_BASE_URL=https://103.114.201.109/api/v1
```

ต้องกำหนด API_BASE_URL ที่ลงท้าย /api/v1 เสมอ แอปไม่ส่งข้อมูลบัญชีผ่าน HTTP สาธารณะ และไม่ข้ามการตรวจ TLS certificate

## สร้างไฟล์แอปและทดสอบ

```powershell
flutter test
flutter analyze
flutter build web --release --dart-define=API_BASE_URL=https://103.114.201.109/api/v1
flutter build apk --debug --dart-define=API_BASE_URL=https://103.114.201.109/api/v1
node scripts/serve-preview.mjs
```

Preview อยู่ที่ http://localhost:5173 ส่วน APK สำหรับพัฒนาอยู่ใน build/app/outputs/flutter-apk/app-debug.apk ต้องมี emulator/เครื่องจริงก่อนติดตั้ง รุ่น debug ยังไม่ใช่ release ที่เซ็นสำหรับ Play Store

## ระบบที่เชื่อม API แล้ว

บัญชีอีเมล/Google, session, ยืนยันอีเมล, รีเซ็ตรหัสผ่าน, เปลี่ยนรหัสผ่าน, โปรไฟล์, เลือกบทบาท, ร้านโปรด, จัดการร้านและเมนู, ตะกร้า, checkout, สถานะออเดอร์, ประวัติร้าน/ลูกค้า และรีวิวร้านจากออเดอร์ที่รับอาหารแล้ว

ลูกค้าส่งคะแนน 1–5 ดาวและความคิดเห็นได้หนึ่งครั้งต่อออเดอร์ที่เสร็จสมบูรณ์ หน้าร้านแสดงคะแนนเฉลี่ยและจำนวนรีวิว พร้อมรายการล่าสุดแบบแบ่งหน้า เจ้าของร้านเปิดดูความคิดเห็นได้จากหน้าข้อมูลร้าน โดยแสดงเพียงชื่อเรียกของลูกค้า

เซิร์ฟเวอร์ตรวจสิทธิ์และราคาอาหารจริง ใช้จำนวนเงินเป็นสตางค์, transaction และ requestId ป้องกันออเดอร์ซ้ำ การหมดอายุของ session ปิดหน้าส่วนตัวและล้างตะกร้าบัญชีนั้น การอ่านร้าน/ออเดอร์รีเฟรชผ่าน API ทุก 5 วินาที การเขียนที่ล้มเหลวแสดงข้อผิดพลาด

## Backend และการตั้งค่าที่เหลือ

โค้ดอยู่ใน backend ใช้ PHP 8.3+, GD, Composer, Laravel, Sanctum และ Socialite ดู design/MYSQL_AUTH_SETUP.md และ design/MYSQL_API_CONTRACT.md

VPS แยก MySQL 8.4 ไว้ที่ 127.0.0.1:3307 ใช้ฐานข้อมูล/ผู้ใช้เฉพาะแอป แยกจาก MariaDB และบริการเดิม มี PHP-FPM user/pool ของแอปและ timer ต่ออายุ TLS อัตโนมัติ Secrets อยู่บน VPS เท่านั้น ไม่อยู่ใน Flutter หรือ ZIP ส่งมอบ

ก่อนเปิดรับผู้ใช้ทั่วไปยังต้องทดสอบ Google OAuth แบบครบ flow ด้วยบัญชีที่เลือกเอง ส่วนบัญชีอีเมลยังต้องตั้ง SMTP จริงสำหรับยืนยันบัญชีและกู้รหัสผ่าน Google OAuth และ HTTPS callback ตั้งค่าไว้บน VPS แล้ว

เครื่องมือ export/import ข้อมูล Firebase ถูกเก็บไว้เป็นตัวเลือกเท่านั้น ไม่ได้รันกับข้อมูลจริง และไม่มีความจำเป็นสำหรับฐานข้อมูลใหม่ที่ผู้ใช้เลือกแล้ว ดู scripts/firebase-export/README.md หากเปลี่ยนแผนภายหลัง

ผลตรวจล่าสุดและข้อจำกัดอยู่ใน design/VALIDATION.md คู่มือและสคริปต์ Firebase emulator เดิมเป็นข้อมูลย้อนหลัง ไม่ใช่การตรวจ backend MySQL ปัจจุบัน
