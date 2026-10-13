# Google Login ปัจจุบัน

ใช้ Google OAuth ผ่าน Laravel และ browser callback อ่านขั้นตอนใน [MYSQL_AUTH_SETUP.md](MYSQL_AUTH_SETUP.md#google-oauth)

โค้ดใหม่ใช้ state + S256 PKCE + one-time exchange code แล้วรับ Sanctum token จาก API ไม่ใช้ Firebase Auth, `google-services.json`, Firebase Web App ID หรือ Android SHA-1 ในการยืนยัน Google ของแอป

ต้องตั้งค่า Google Web OAuth client และ callback ของ backend จริงก่อนใช้งาน หากยังไม่ครบ แอปแสดงข้อผิดพลาด ไม่รายงานว่าล็อกอินสำเร็จ การผ่าน unit/widget tests ยังไม่ยืนยันการเลือกบัญชี Google production บนเครื่องผู้ใช้
