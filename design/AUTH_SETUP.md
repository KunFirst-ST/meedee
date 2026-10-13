# การตั้งค่าบัญชีปัจจุบัน

ระบบบัญชีย้ายจาก Firebase ไป Laravel + MySQL ตามคำขอผู้ใช้แล้ว อ่าน [MYSQL_AUTH_SETUP.md](MYSQL_AUTH_SETUP.md) สำหรับ API URL, secure session, อีเมล, สิทธิ์ลูกค้า/ร้านค้า และการทดสอบก่อนเปิดจริง

Firebase project เดิม `msu-foodnaja` เป็นแหล่งข้อมูลที่จะนำเข้า ไม่ใช่ระบบบัญชี runtime ของแอปปัจจุบัน อย่าลบข้อมูลเดิมจนกว่าจะ export/import และตรวจสอบครบ การตั้งค่า Firebase provider, Web App ID หรือ SHA-1 ไม่ได้เปิด Google Login ของ backend ใหม่นี้

ไฟล์ทดสอบ Firebase emulator ที่ยังเก็บไว้ใช้ตรวจระบบก่อนย้าย ไม่ใช่คำสั่งตรวจ Laravel production
