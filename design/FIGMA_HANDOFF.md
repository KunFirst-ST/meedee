# MSU Food — UX/UI & Figma handoff

สร้างไฟล์ Figma ที่แก้ไขข้อความ สี คอมโพเนนต์ รูปภาพ และโครงสร้าง Auto Layout ต่อได้ สำหรับแอปสั่งอาหารแบบรับเองในมหาวิทยาลัยมหาสารคาม

## เปิดงาน

- [งานออกแบบ 4 หน้าจอ](https://www.figma.com/design/k4t7B4lBmGxj1b4Guwt8PE?node-id=2-43)
- [คอมโพเนนต์และสี](https://www.figma.com/design/k4t7B4lBmGxj1b4Guwt8PE?node-id=13-220)
- [จุดเริ่มต้น Prototype](https://www.figma.com/design/k4t7B4lBmGxj1b4Guwt8PE?node-id=11-251) — เปิด Present ใน Figma เพื่อทดสอบเส้นทาง
- ภาพตรวจงาน: `figma-review.png`, `figma-components.png`
- Ledger สำหรับแก้ต่อ: `figma-final-state.json` พร้อม ID จริงของหน้าจอและคอมโพเนนต์

## เส้นทางลูกค้า

1. **Discover** (`2:50`): ค้นหาร้าน/เมนู, มื้อไม่เกิน ฿50, ร้านโปรด, ร้านที่เปิดรับออเดอร์ และ navigation หลัก
2. **Restaurant Menu** (`2:53`): รายละเอียดร้านครัวมอ, ประเภทเมนู, ราคาแต่ละรายการ, เพิ่มอาหาร และปุ่มตะกร้าที่เห็นจำนวนกับยอดรวม
3. **Checkout** (`2:56`): จุดรับอาหาร, รายการและจำนวน, หมายเหตุถึงร้าน, ชำระเงินกับร้านเมื่อรับอาหาร และแจกแจงยอดรวมก่อนยืนยัน
4. **Pickup Tracking** (`2:59`): หมายเลขออเดอร์, timeline ส่งแล้ว → กำลังทำ → พร้อมรับ → รับแล้ว พร้อมคำแนะนำให้ดูสถานะก่อนเดินไปร้าน

ตัวอย่างตะกร้า: ข้าวผัดกุ้ง 1 × ฿55 และข้าวไข่เจียว 1 × ฿35 รวม ฿90 ค่าจัดส่ง ฿0 เนื่องจากรับเอง

แยกหน้าจอ Prototype แบบ top-level ไว้ด้านล่างบอร์ด มีลิงก์นำทางที่ตรวจสอบแล้ว 7 จุด ได้แก่ เลือกร้าน → เมนู → ตะกร้า → ติดตามออเดอร์ และปุ่มย้อนกลับ/กลับหน้าแรก การค้นหา ตัวกรอง และร้านโปรดใน Figma เป็นรายละเอียดออกแบบ ไม่ใช่การจำลองฐานข้อมูล

## Design tokens และ Flutter

| หน้าที่ | ค่า | การจับคู่หลัก |
|---|---|---|
| ปุ่มหลัก / สีแบรนด์ | `#F46B38` | `AppTheme.orange` |
| ตัวหนังสือบนปุ่มและเนื้อหาหลัก | `#182B33` | `AppTheme.ink` |
| ข้อความรอง | `#617179` | `AppTheme.muted` |
| พื้นหลัง | `#F7F8FA` | `AppTheme.background` |
| เส้นแบ่ง / ขอบ | `#E6EAEC` | `AppTheme.line` |
| สำเร็จ / เปิดบริการ | `#217A55` | `AppTheme.green` |
| ข้อความสีแบรนด์บนพื้นอ่อน | `#B94317` | สี semantic `color/primaryText` |

ใช้ **Noto Sans Thai** ทั้ง 93 text layers; text styles 7 ระดับ: Display 28/38, Title 22/32, Section 18/28, Body 14/22, Label 14/22, Caption 12/18 และ Price 18/28 px

ระยะห่างหลัก 4, 8, 12, 16, 20, 24, 32, 48 px; รัศมี 8, 12, 16, 24 และ full ขนาดหน้าจอตัวอย่าง 390 × 844 px การวางเนื้อหาใช้ Auto Layout และปุ่มหลักเต็มความกว้างพื้นที่เนื้อหา Flutter ควรรองรับพื้นที่กดอย่างน้อย 44 px แม้ตัวบวกที่มองเห็นจะเล็กกว่า

ปุ่มสีส้มใช้ตัวหนังสือสีเข้ม ส่วนข้อความสีส้มบนพื้นอ่อนใช้ `#B94317` เพื่อให้อ่านชัด

## คอมโพเนนต์ที่ส่งมอบ

| คอมโพเนนต์ | ID | States / properties |
|---|---|---|
| Button | `5:57` | Primary, Secondary, Disabled; Label |
| FilterChip | `5:62` | Selected, Default; Label |
| StatusStep | `5:102` | Complete, Active, Upcoming; Title, Detail |
| RestaurantCard | `5:63` | Title, Metadata, Price info; รูปเปลี่ยนได้ |
| MenuRow | `5:69` | Title, Description, Price; รูปเปลี่ยนได้ |
| Material Icons Outlined | ดู ledger | SVG vector components 12 รายการ |

มี variables 33 รายการใน collection `MSU Food` โหมด Light เดียว ตาม Starter plan ของบัญชี สี semantic alias กลับไปยัง primitive, กำหนด scopes และ code syntax ครบ รูปอาหารเป็น content image fill แยกจากข้อความและโครงสร้าง UI

## หลักฐานตรวจรับ

- บอร์ดหลักมี descendants 259 รายการ: text 93, instances 34, vectors 33, frames 98, group 1
- รูปภาพ 5 layers เป็นภาพอาหารแยกรายชิ้น ไม่มีรูปแคปหน้าจอหรือ UI ที่ถูก flatten อยู่ในงานออกแบบ
- ตรวจอ่านกลับว่าข้อความทั้งหมดใช้ Noto Sans Thai และตัวแปร semantic ไม่มี `ALL_SCOPES`
- ปุ่มยืนยัน/ตะกร้ากว้าง 350 px ภายในหน้าจอ 390 px หลังแก้ปัญหา HUG
- ตรวจ screenshot ของ 4 หน้าจอและคอมโพเนนต์หลังแก้ไขไอคอนกับ layout แล้ว
- เส้นทาง Prototype 7 จุดมีปลายทางเป็น top-level frames ที่มีอยู่จริง

ภาพอาหารใช้ไฟล์เดโมที่บันเดิลใน `assets/images/` เป็นภาพประกอบ ไม่ใช่รูปอาหารจริงของร้าน ก่อนเปิดใช้งานจริงให้ร้านอัปโหลดรูปเมนูของตนเอง และใช้สถานะเปิดร้าน/ออเดอร์จากข้อมูลจริง

## ที่มาของไอคอน

SVG ใน `design/icons/` มาจาก [Google Material Design Icons](https://github.com/google/material-design-icons) ชุด Material Icons Outlined ภายใต้ Apache License 2.0 นำเข้าเป็น vector layer ที่แก้ไขต่อได้
