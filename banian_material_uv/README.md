# Banian Material UV (بانیان متریال یو‌وی) — v1.0.0

Banian Material UV maps textures correctly on curved surfaces in SketchUp: spheres, domes, cylinders, arches, curved walls, tori and free-form meshes.

پلاگینی برای متریال‌دهی درست روی سطوح منحنی در اسکچ‌آپ. پنل آن دوزبانه است (فارسی/انگلیسی) و منوهای داخل اسکچ‌آپ انگلیسی‌اند.

**Download / دانلود:** [`dist/Banian_Material_UV_v1.0.0.rbz`](../dist/Banian_Material_UV_v1.0.0.rbz)

**Compatibility / سازگاری:** SketchUp 2017 تا 2027 (HtmlDialog) و نسخه‌های 2014 تا 2016 (WebDialog). کد با Ruby 2.0 تا Ruby 3.x سازگار است.

## نصب
`Extensions > Extension Manager > Install Extension` و انتخاب فایل `.rbz`.

## استفاده
- `Extensions > Banian Material UV > Banian Material UV Panel`: باز کردن پنل.
- یا روی انتخاب راست‌کلیک کنید و از زیرمنوی `Banian Material UV` استفاده کنید.
- یا از تولبار **Banian Material UV** استفاده کنید (چهار دکمه: Panel، UV Paint Tool، Apply، Reset).

مراحل:
1. متریال را انتخاب کنید: از لیست، از سطل رنگ (Paint Bucket) یا با «متریال فعلی صفحه‌ها» (در این حالت متریال صفحه‌ها عوض نمی‌شود و فقط UV آن‌ها درست می‌شود).
2. صفحه، چند صفحه، گروه یا کامپوننت را انتخاب کنید و «اعمال روی انتخاب» را بزنید. یا «ابزار رنگ» را بزنید و روی سطح کلیک کنید (Shift = یک صفحه، Ctrl = کل آبجکت، Alt = برداشتن متریال).

| روش (Mapping) | مناسب برای |
|---|---|
| Auto | کره، استوانه، سطح گسترش‌پذیر، مش چهارضلعی و سطح تخت را خودش تشخیص می‌دهد |
| Natural / Unfold | صفحه به صفحه و بدون کشیدگی باز می‌کند؛ دیوار منحنی، قوس، مخروط، پنل خم‌شده |
| Quad Grid | بافت ردیف و ستون مش را دنبال می‌کند؛ چنبره، لوله، Sweep، احجام آزاد. مثلث‌های دارای قطر نرم هم به چهارضلعی تبدیل می‌شوند |
| Cylindrical | ستون، لوله، دیوار گرد (درز تمیز، کف و سقف جداگانه تخت نگاشت می‌شوند) |
| Spherical | کره، گنبد، کره زمین (Fit 1×1) |
| Box / Tri-planar | مبلمان، جعبه گردگوشه، احجام ارگانیک |
| Planar | زمین و توپوگرافی، فرش، برچسب؛ تابش از نرمال، دید دوربین، بالا، روبه‌رو یا کنار |

گزینه‌های دیگر:
- اندازه بافت: اندازه واقعی (از خود متریال یا اندازه کاشی دلخواه) یا Fit با تعداد تکرار U×V.
- مقیاس U/V، چرخش، جابه‌جایی، آینه افقی و عمودی، و زاویه درز برای حالت‌های استوانه‌ای و کروی.
- وجه رو، پشت یا هر دو.
- نگاشت ۴ نقطه‌ای (Distort) روی چهارضلعی‌ها.
- گسترش صفحه‌های انتخاب‌شده تا کل سطح نرم.
- دکمه «تشخیص» روش پیشنهادی را نشان می‌دهد و «ریست UV» موقعیت بافت را به حالت پیش‌فرض اسکچ‌آپ برمی‌گرداند.
- هر بار اعمال یک مرحله Undo است و گروه یا کامپوننتی Explode نمی‌شود.

## How it works (technical)
- For each island of connected faces, UVs are computed per vertex in world space with the chosen method (cylindrical/spherical fit with least-squares circle/sphere fitting, unfold via BFS across shared edges with orientation tracking, quad-grid topology walk with triangle-pair diagonal detection, tri-planar, planar).
- Each face then gets 3 point pairs (an exact affine mapping), or 4 pairs (a projective mapping) when a quad really needs it. N-gons get a least-squares affine fit. These pairs are written with `Face#position_material`. That is the same API call ThruPaint relies on.
- Auto mode checks the surface in this order: flat, sphere fit, cylinder fit (axis = smallest eigenvector of the face-normal covariance), developable (Gaussian angle-defect ≈ 0), quad mesh, height field, then falls back to box.

## Tests
```
ruby -I banian_material_uv/src banian_material_uv/test/core_test.rb
ruby banian_material_uv/test/sketchup_mock_test.rb
```
