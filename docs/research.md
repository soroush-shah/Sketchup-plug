# تحقیق: پلاگین‌های تاسیسات مکانیکی و الکتریکی برای اسکچ‌آپ

تاریخ: نوامبر ۲۰۲۶

## ۱. پلاگین‌های موجود

| پلاگین | حوزه | وضعیت / سازگاری | نقاط قوت | کمبودها |
|---|---|---|---|---|
| **Medeek HVAC** (بخشی از مجموعه mdkMEP) | داکت، اتصالات، دستگاه‌ها (AC، کوره، هیت‌پمپ) | نسخه بتا از ژوئیه ۲۰۲۵ (0.9.x) | داکت و اتصالات پارامتریک، در حال توسعه | خود سازنده آن را بتای اولیه با مشکلات زیاد معرفی کرده. فن کویل جداگانه ندارد. تمرکزش ساختمان مسکونی آمریکایی است. پولی. |
| **Medeek Electrical** | برق ساختمان مسکونی: پریز، کلید، چراغ، سیم، لوله برق | نسخه 1.5.8 (فوریه ۲۰۲۶)، سازگار با SketchUp 2026. حدود ۹۰ دلار | متره و خروجی CSV، لجند علائم، استاندارد NEMA و BS انگلیس | فقط برق، آن هم مسکونی. سینی کابل و تداخل ندارد. |
| **Medeek Plumbing** | لوله‌کشی آب و فاضلاب | جدید (۲۰۲۵) | — | در مراحل اولیه |
| **3skeng** (Pipe، Channel، Mount، Steelwork) | لوله‌کشی صنعتی/MEP، کانال، ساپورت | نسخه 2025.3، سازگار با SketchUp 2023 تا 2025 | کتابخانه اتصالات دقیق، ابزار ساپورت، مسیر خودکار لوله | گران و صنعتی. سینی کابل و فن کویل ندارد. سازگاری 2026/2027 تأیید نشده. |
| **VBO Ducting Basic** | داکت از روی مسیر | فعال | ساخت داکت از روی خطوط گروه‌شده | به گزارش کاربران، اگر مسیر از صفحه اولیه خارج شود (مثلاً رایزر)، جهت مقطع درست نمی‌ماند |
| **PipeDraft** | لوله‌کشی با کاتالوگ | ابری، مبتنی بر Spec | اتصالات از روی کاتالوگ | مخصوص اطفای حریق نیست |
| **Trimble MEPdesigner** | داکت، لوله، سینی کابل، کاندوئیت | **از Extension Warehouse حذف شده** | تنها راهکار جامع رسمی بود | دیگر در دسترس نیست |
| **Engineering ToolBox** | قطعات پارامتریک (لوله، تیر ...) | فقط تا SketchUp 2023 | رایگان | روی 2024 به بعد کار نمی‌کند |

## ۲. خلأهای مهم بازار (که این پلاگین پر می‌کند)

1. **Clash Detection درون اسکچ‌آپ عملاً وجود ندارد.** خود اسکچ‌آپ هیچ ابزار تداخل‌یابی ندارد. روال رایج این است که خروجی IFC گرفته شود و در Trimble Connect یا Navisworks بررسی شود، که خودکار هم نیست. چند اسکریپت قدیمی فقط Bounding Box را مقایسه می‌کنند و برای اجسام غیرمکعبی تداخل کاذب می‌دهند.
2. **فن کویل و جانمایی آن** در هیچ پلاگینی به‌صورت پارامتریک (با کانکتور خروجی و اتصال خودکار داکت) وجود ندارد. فقط مدل‌های ثابت در 3D Warehouse پیدا می‌شود.
3. **جانمایی اسپرینکلر و سایزینگ لوله** برای اسکچ‌آپ وجود ندارد. ابزارهای اسپرینکلر (SprinkCAD، HydraCAD، پلاگین‌های Revit) همه برای Revit یا AutoCAD هستند.
4. **سازگاری نسخه‌های آینده:** اسکچ‌آپ 2026 از Ruby 3.2 استفاده می‌کند و تیم اسکچ‌آپ اعلام کرده در نسخه آینده به **Ruby 3.4** می‌رود. همه پلاگین‌هایی که فایل باینری C دارند باید دوباره کامپایل شوند. پلاگین‌هایی که روی کتابخانه‌های جانبی Ruby (مثل csv و base64) تکیه دارند هم در 3.4 مشکل پیدا می‌کنند.

## ۳. تصمیم‌های طراحی MEP Studio

* **Ruby خالص، بدون باینری و بدون gem.** فقط از `json` (که gem پیش‌فرض است) استفاده شده. خروجی CSV دستی نوشته شده و به کتابخانه `csv` (که در Ruby 3.4 از stdlib خارج شد) وابسته نیست.
* `# frozen_string_literal: true` در همه فایل‌ها، که برای رفتار پیش‌فرض رشته‌ها در Ruby 3.4 به بعد آماده است. از `it` به‌عنوان نام متغیر استفاده نشده، چون در 3.4 کلمه کلیدی است.
* فقط API‌های پایدار اسکچ‌آپ (از ۲۰۱۷ به بعد): `HtmlDialog`، `followme`، `InputPoint`، `PickHelper`. آبزرور یا ترفند نسخه‌خاص به کار نرفته. این ترکیب روی SketchUp 2021 تا 2026 کار می‌کند و برای 2027 هم مشکل شناخته‌شده‌ای ندارد.
* **داکت روی مسیر با Follow Me و زانوی شعاع‌دار.** گوشه‌های مسیر به کمان (fillet) تبدیل می‌شوند، پس یک Solid تمیز ساخته می‌شود. مقطع با محور «بالا = Z» جهت‌دهی می‌شود. این همان مشکل VBO است که اینجا برای رایزرها حل شده.
* **کانکتورها.** هر فن کویل، دریچه و هد یک لیست کانکتور (موقعیت، جهت، سایز، سیستم) دارد. ابزار داکت روی آن‌ها Snap می‌کند و سایز را از دستگاه برمی‌دارد.
* **Clash دقیق.** هر قطعه داکت/لوله یک OBB (جعبه جهت‌دار) است. بین لوله‌ها فاصله دقیق دو پاره‌خط محاسبه می‌شود. تاسیسات با تاسیسات با آزمون SAT بین OBBها بررسی می‌شود. تاسیسات با سازه/معماری با **مثلث‌های واقعی سطوح** (SAT مثلث و جعبه) بررسی می‌شود، نه با Bounding Box. برای سرعت از Spatial Hash یک‌متری استفاده شده. اتصالات واقعی (داکت به فن کویل، انشعاب همان سیستم، دراپ اسپرینکلر) تداخل حساب نمی‌شوند. دو سطح Hard و Soft (حریم/فاصله مجاز) وجود دارد.

## منابع

- [Medeek HVAC – SketchUp Forum](https://forums.sketchup.com/t/medeek-hvac/93865)
- [Development and Updates for the Medeek HVAC Plugin](https://design.medeek.com/smf/index.php?msg=3143)
- [Medeek Electrical](https://design.medeek.com/resources/medeekelectricalplugin.pl) · [Changelog](https://design.medeek.com/resources/electricalpluginchangelog.html)
- [Medeek Plumbing](https://forums.sketchup.com/t/medeek-plumbing/331798)
- [3skeng Pipe – Sketchucation](https://sketchucation.com/plugin/1048-3skeng_pipe) · [3skeng Mount](https://sketchucation.com/plugin/1858-3skeng_mount) · [3skeng forum thread](https://forums.sketchup.com/t/3skeng-3d-engineering-extensions-for-sketchup/33569)
- [VBO Ducting Basic](https://forums.sketchup.com/t/vbo-ducting-basic/175849)
- [MEP Solutions – SketchUp Forum](https://forums.sketchup.com/t/mep-mechanical-electrical-plumbing-solutions/99816.md)
- [Review: Trimble MEPdesigner for SketchUp](https://aecmag.com/news/review-trimble-mepdesigner-for-sketchup/)
- [Revit vs SketchUp for MEP Modelling](https://www.novatr.com/blog/revit-vs-sketchup-for-mep-modelling)
- [New Plugin for Piping: Pipedraft](https://community.sketchucation.com/post/1399666)
- [SketchUp Clash Detection – forum](https://forums.sketchup.com/t/sketchup-clash-detection-urgent/42464) · [MEP clash detection – Sketchucation](https://community.sketchucation.com/post/1392231) · [Finding overlapping solids](https://forums.sketchup.com/t/finding-overlapping-solids/88366)
- [Engineering ToolBox SketchUp extension](https://sketchup.engineeringtoolbox.com/)
- [Hi-Velocity Fan Coil Unit – 3D Warehouse](https://3dwarehouse-classic.sketchup.com/model/18da968e35fd0a86689857cbfae30a96/Hi-Velocity-Fan-Coil-Unit)
- [Important – Upcoming Ruby Update (Ruby 3.4)](https://forums.sketchup.com/t/important-upcoming-ruby-update/348793)
- [SketchUp Ruby API Release Notes](https://ruby.sketchup.com/file.ReleaseNotes.html)
- [Ruby plugin failing in 2026](https://forums.sketchup.com/t/ruby-plugin-failing-in-2026-after-migrating-works-sometimes/342169)
