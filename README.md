# Banian Floor Studio — SketchUp tile & pattern generator

**فارسی** | [English](#english)

پلاگین ساخت کف، دیوار و سقف با کاشی سه‌بعدی، پارکت، جناغی، شورون، شش‌ضلعی، سنگ نامنظم و سایدینگ برای اسکچ‌آپ —
یا فقط **تقسیم‌بندی سطح** به الگو و ابعاد دلخواه.

- سازگار با **SketchUp 2017 تا 2027** (ویندوز و مک)
- رابط کاربری **فارسی / انگلیسی** (منوها و آیکون‌های اسکچ‌آپ انگلیسی)
- بدون کندی: موتور اصلی فقط با اولین استفاده بارگذاری می‌شود؛ کاشی‌های تکراری به‌صورت Component ساخته می‌شوند (فایل سبک)

## نصب
1. فایل `dist/banian_floor_studio_v1.1.0.rbz` را دانلود کنید.
2. در اسکچ‌آپ: `Extensions > Extension Manager > Install Extension` و فایل را انتخاب کنید.
3. از منوی `Extensions > Banian Floor Studio` یا نوار ابزار استفاده کنید.

## سه حالت کار
| حالت | کار |
|---|---|
| **3D Tiles** | کاشی سه‌بعدی واقعی با ضخامت، بندکشی با عمق، پروفیل لبه، متریال تصادفی و ناترازی |
| **Divide Face** | فقط سطح انتخاب‌شده را به الگو تقسیم می‌کند (بدون هندسه سه‌بعدی) و در صورت تمایل رنگ می‌کند |
| **Texture** | یک متریال تصویری (Seamless) از الگو می‌سازد و دقیق روی سطح می‌نشاند |

## الگوها
Grid (شطرنجی)، Brick (آجری با جابه‌جایی ۱/۲، ۱/۳، ۱/۴ …)، Planks (تخته با طول تصادفی، گام طول و فاصله درزها)،
Herringbone (جناغی)، Chevron (شورون با زاویه دلخواه)، Basket weave (حصیری)، Hexagon (شش‌ضلعی)،
Hopscotch (لی‌لی / پین‌ویل)، Stone (سنگ نامنظم Voronoi)، Siding (سایدینگ / کلَپ‌بورد با شیب تخته).

## امکانات
- سطوح **نامنظم و سوراخ‌دار** (ستون، داکت…)؛ کاشی‌ها دقیق برش می‌خورند و لبه‌های کارخانه‌ای پروفیل خود را حفظ می‌کنند
- کف، **دیوار** و سقف (هر سطحی با هر زاویه)
- **نقطه شروع دلخواه**: با کلیک/کشیدن روی پیش‌نمایش (با گیرکردن به گوشه‌ها) یا با «Pick in model» روی خود مدل؛ انتخاب اینکه درز کاشی یا وسط کاشی روی نقطه بیفتد
- چرخش، نقطه شروع آماده (گوشه / وسط‌چین / مبدأ جهانی برای پیوستگی بین چند سطح)، جهت (بلندترین لبه / محورها)، جابه‌جایی X/Y
- پروفیل لبه: Square، Chamfer، Round، Bullnose، Cove، Ogee
- چند متریال با وزن، توزیع تصادفی / شطرنجی / ترتیبی، سایه‌رنگ‌های تصادفی، جابه‌جایی و چرخش تصادفی تکسچر
- ناترازی (زاویه و ارتفاع)، Seed تکرارپذیر، حذف تکه‌های خیلی کوچک
- **ویرایش بعدی**: گروه ساخته‌شده را انتخاب کنید → پنل تنظیماتش را بارگذاری می‌کند → Update
- **Shuffle Randomness**: ساخت مجدد با Seed جدید با یک کلیک
- پیش‌نمایش زنده دوبعدی و آمار (تعداد کاشی کامل / برش‌خورده و مساحت)

---

<a name="english"></a>
## English

Generate real 3D tiles, parquet, herringbone, chevron, basket weave, hexagon, hopscotch, stone and siding on any
face (floors, walls, ceilings) — or just **divide a face** into the pattern. SketchUp 2017–2027, Windows & macOS,
Persian/English UI.

**Install:** `Extensions > Extension Manager > Install Extension` → `dist/banian_floor_studio_v1.1.0.rbz`.

**Use:** select one or more faces → `Extensions > Banian Floor Studio` (or the toolbar / right-click menu) →
pick a mode and pattern → Generate. Set a custom start point by clicking/dragging on the preview or with **Pick in model**. Select a generated group to edit it later.

### Performance design
- Lazy loading: only menus are registered at startup.
- Repeated full tiles become component instances of a few shared definitions.
- Cut tiles are computed by SketchUp's own geometry engine in one batch, only for boundary tiles.
- One undo step per operation, with UI updates suspended.

## Development
```
src/banian_floor_studio.rb        loader (extension registration)
src/banian_floor_studio/main.rb   menus, toolbar, context menu (lazy)
src/banian_floor_studio/core/     geometry + patterns (pure Ruby) and SketchUp builders
src/banian_floor_studio/ui/       HtmlDialog (HTML/CSS/JS, EN + FA)
tests/                            pure-Ruby tests + mocked SketchUp smoke test
tools/build_rbz.sh                builds dist/*.rbz
```
```bash
ruby tests/test_patterns.rb && ruby tests/test_smoke.rb && tools/build_rbz.sh
```
