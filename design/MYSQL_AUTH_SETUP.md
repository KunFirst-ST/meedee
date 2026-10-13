# บัญชีผู้ใช้ Laravel + MySQL

แอป Flutter ปัจจุบันใช้ Laravel REST API และ Sanctum แทน Firebase Auth ทั้งหน้าลูกค้าและร้านค้า เว็บและ API ขึ้น VPS ที่ https://103.114.201.109/ แล้ว Google OAuth สำหรับเข้าสู่ระบบตั้งค่าและตรวจสอบบน VPS แล้ว ส่วน SMTP ยังไม่ตั้งค่า จึงยังยืนยันอีเมลหรือกู้รหัสผ่านทางอีเมลไม่ได้ ผู้ใช้เลือกเริ่มฐานข้อมูลใหม่โดยไม่ย้ายและไม่ลบ Firebase เดิม

## เชื่อมต่อแอป

กำหนด `API_BASE_URL` เป็น URL ของ API ที่ลงท้าย `/api/v1`:

```powershell
flutter run --dart-define=API_BASE_URL=https://api.your-domain.example/api/v1
flutter build apk --debug --dart-define=API_BASE_URL=https://api.your-domain.example/api/v1
flutter build web --dart-define=API_BASE_URL=https://api.your-domain.example/api/v1
```

URL ด้านบนเป็นรูปแบบตัวอย่าง ต้องแทนด้วย HTTPS ที่มีใบรับรองถูกต้องของ VPS จริง แอปไม่มีค่า API เริ่มต้นที่เดาเอง ไม่มีการข้ามการตรวจใบรับรอง และไม่ส่งข้อมูลบัญชีผ่าน HTTP สาธารณะ การทดสอบ HTTP อนุญาตเฉพาะ loopback `localhost`, `127.0.0.1`, `::1` และ `10.0.2.2` สำหรับ Android emulator เท่านั้น Android production ยังใช้ HTTPS

แอปตรวจ `/capabilities` ก่อนเปิดฟอร์มล็อกอิน หากเชื่อมต่อไม่ได้หรือไม่กำหนด URL จะเปิดหน้าข้อผิดพลาดพร้อมปุ่มลองใหม่ ไม่แสดงผู้ใช้หรือข้อมูลร้านจำลอง

## เซสชันและสิทธิ์

- Android/iOS ใช้ `flutter_secure_storage` เก็บ Sanctum token ในพื้นที่จัดเก็บของระบบ Android ปิดการสำรองข้อมูลแอป เพื่อไม่ให้สำรอง encrypted session ไปเปิดบนเครื่องอื่น
- เว็บใช้ `sessionStorage` แยกตามแท็บ ไม่เก็บ token ใน `localStorage` และไม่ใส่ token ใน URL เว็บต้องเสิร์ฟผ่าน HTTPS พร้อม CSP และ CORS ที่กำหนด origin จริงบนเซิร์ฟเวอร์ โค้ด JavaScript ภายใต้ origin เดียวกันเข้าถึง sessionStorage ได้ จึงต้องจำกัดสคริปต์จากภายนอก
- API ใช้ bearer header ไม่ใช้ cookie สำหรับยืนยันตัวตนอัตโนมัติของเบราว์เซอร์ การเขียนข้อมูลทุกครั้งต้องตรวจ token และสิทธิ์ฝั่ง Laravel เพิ่มเติม
- การเปิดแอปใหม่จะตรวจ token ผ่าน `/auth/me` ก่อนแสดงบัญชี ไม่มีการเชื่อข้อมูลผู้ใช้ที่บันทึกไว้ในเครื่องแทนผลตรวจเซิร์ฟเวอร์
- บัญชีที่ยังไม่ยืนยันอีเมลอยู่ในหน้าตรวจอีเมล การกด “ยืนยันแล้ว” อ่าน `/auth/me` ใหม่เท่านั้น ไม่แก้สถานะยืนยันในเครื่อง
- HTTP 401 ล้างเซสชัน ตะกร้าของบัญชีนั้น และปิดหน้าข้อมูลส่วนตัวที่เปิดค้างอยู่ การตัดอินเทอร์เน็ตไม่ทำให้ API write สำเร็จ
- ออกจากระบบเรียก `/auth/logout` เพื่อยกเลิก token บนเซิร์ฟเวอร์ หากเซิร์ฟเวอร์ล้มเหลวแอปแจ้งข้อผิดพลาดและไม่อ้างว่ายกเลิกเซสชันสำเร็จ

## Google OAuth

Google web-server OAuth ไม่อนุญาต public raw IP เป็น redirect host จึงใช้ hostname ที่ Google ยอมรับสำหรับ callback แม้เว็บ/API จะใช้ HTTPS บน IP เดิมได้ ดู [กฎ redirect URI ของ Google](https://developers.google.com/identity/protocols/oauth2/web-server#uri-validation)

ตั้งค่า production แล้ว โดยใช้ callback และ allowlist ดังนี้:

```text
OAuth redirect: https://msu-food.103.114.201.109.nip.io/api/v1/auth/google/callback
App callback:   msufood://auth/callback
Web callback:   https://103.114.201.109/auth/callback
```

OAuth Web client ของโปรเจกต์ `msu-foodnaja` ถูกติดตั้งบน VPS แล้ว ค่า secret อยู่เฉพาะ environment ของ Laravel และถูกจัดเก็บด้วยสิทธิ์ไฟล์จำกัด ไม่อยู่ใน source, APK หรือเว็บ build ตัวติดตั้งตรวจ project number และ redirect URI ก่อนส่งไฟล์ไปยัง VPS แล้วอัปเดตเฉพาะค่าที่เกี่ยวกับ Google OAuth

API capabilities ยืนยัน `googleConfigured=true` และ `emailConfigured=false`; ตรวจเส้นทาง start/callback, redirect allowlist และหน้า web callback แล้ว การทดสอบนี้ยืนยันการตั้งค่าฝั่งระบบ แต่ยังไม่ใช่การลงชื่อเข้า Google ด้วยบัญชีผู้ใช้จริง ต้องทดสอบด้วยบัญชีที่ผู้ใช้เลือกเองก่อนเปิดให้ลูกค้าทั่วไป Google Login ใช้อีเมลที่ Google ยืนยัน จึงไม่ต้องใช้ SMTP ของแอป ส่วน email verification/reset ยังต้องตั้ง SMTP

ห้ามสร้าง client ซ้ำหรือคัดลอก Client secret ลง source/แชตโดยไม่จำเป็น หากต้องเปลี่ยน client ในอนาคต ให้ตั้งค่าผ่าน secret environment ของ Laravel เท่านั้น

Flutter สร้าง state และ PKCE verifier แบบสุ่ม แล้วส่ง S256 challenge ไป `/auth/google/start` เซิร์ฟเวอร์ส่ง URL ของ `accounts.google.com` ให้เปิดด้วยเบราว์เซอร์ Android รับ deep link ที่ MainActivity และเว็บกลับในแท็บเดิมที่ `/auth/callback` (เว็บเซิร์ฟเวอร์ต้อง fallback path นี้ไป `index.html`)

callback มีเฉพาะ one-time code และ state แอปตรวจ state/อายุคำขอก่อนส่ง code พร้อม verifier ไป `/auth/google/exchange` จึงรับ Sanctum token จาก JSON response จริง หากไม่ได้ตั้งค่า Google ฝั่งเซิร์ฟเวอร์จะคืนข้อผิดพลาดชัดเจน ไม่สร้างบัญชีหรือทำให้ล็อกอินสำเร็จแทน

## อีเมลและรหัสผ่าน

กำหนด SMTP จริงใน Laravel พร้อมผู้ส่งที่ใช้งานได้ การใช้ mailer `log` หรือ `array` ไม่ถือว่าส่งอีเมลสำเร็จ สำหรับบัญชีอีเมลมีสมัครสมาชิก ยืนยันอีเมล ส่งลิงก์ซ้ำ ลืมรหัสผ่าน และเปลี่ยนรหัสผ่านโดยยืนยันรหัสเดิม

ลิงก์รีเซ็ตรหัสผ่านเปิดฟอร์มของ backend ซึ่งตรวจ token และยกเลิกเซสชันเดิมเมื่อสำเร็จ รหัสผ่านใหม่มี 8–128 ตัวอักษรและต้องยืนยันให้ตรงกัน บัญชี Google ที่ไม่มี password provider ไม่แสดงฟอร์มเปลี่ยนรหัสผ่าน

## ข้อมูลเดิมและการตรวจรับ

ใช้ตัวนำเข้าของ backend เพื่อคง Firebase UID เดิมและความสัมพันธ์เจ้าของร้าน/ออเดอร์ ห้ามล้าง Firebase หรือเปลี่ยนเจ้าของร้านก่อนตรวจจำนวนและความสัมพันธ์หลังนำเข้า ผู้ใช้ Firebase ที่ไม่สามารถนำรหัสผ่านเดิมมาตรวจด้วย Laravel ได้ต้องใช้ขั้นตอนตั้งรหัสผ่านใหม่ ไม่ใช้รหัสผ่านที่สร้างแทนผู้ใช้

ก่อนเปิดจริงให้ทดสอบบัญชีลูกค้าและร้านค้าคนละบัญชี: Google กลับเข้าแอปแล้วไปหน้าถัดไป, email verification, reset email ที่ได้รับจริง, token หมดอายุ/ออกจากระบบ, การปฏิเสธอ่านร้านหรือออเดอร์ผู้อื่น และ API ที่ไม่มีอินเทอร์เน็ต การผ่าน Flutter unit/widget tests เป็นหลักฐานโค้ดภายใน ไม่ใช่หลักฐานส่งอีเมลหรือเข้าสู่ Google production สำเร็จ
