/* Banian Profile Builder - panel strings (English / Persian) */
window.I18N = {
  en: {
    t_component: 'component', add_component: '+ My component', component: 'Component',
    pick_component: 'Use selected', comp_size: 'Component size', scale_len: 'Stretch to piece length',
    elevation: 'Front view', eyedropper: 'Eyedropper: reuse an object from the model',
    add_profile: 'Add my profile', add_profile_help: 'Click any face in the model (or select one first) to save it as your profile',
    import_lib: 'Import library', export_lib: 'Export library',
    edit_path: 'Edit path', edit_shape: 'Edit shape', continue_path: 'Build same on selected path', replace_path: 'Move to selected path',
    shape_title: 'Editing the profile shape', shape_help: 'Change the face with any SketchUp tool (Push/Pull not needed), then press Update. Every object using this profile follows.',
    shape_done: 'Update', cancel: 'Cancel',
    pc_railing: 'Railings', pc_fence: 'Fences', pc_wall: 'Walls & partitions', pc_trim: 'Trim', pc_structure: 'Structure',
    app_name: 'Banian Profile Builder',
    app_sub: 'Profiles · Assemblies · Quantities',
    lang_btn: 'فارسی',
    tab_member: 'Profile', tab_assembly: 'Assembly', tab_qty: 'Quantities', tab_guide: 'Guide',
    new_mode: 'New object — pick settings, then Draw or Build on selection.',
    editing: 'Editing {n} selected {k} — changes apply live.',
    k_member: 'profile(s)', k_assembly: 'assembly(s)',
    other_kind: 'A {k} is selected. Open its tab to edit it.',
    similar: 'Also update identical profiles in the model',
    cat_basic: 'Basic', cat_steel: 'Steel', cat_trim: 'Trim & molding', cat_custom: 'My profiles',
    search: 'Search profiles…',
    size: 'Size', position: 'Position on path', rotation: 'Rotation', flip: 'Flip side',
    offset_u: 'Offset across', offset_v: 'Offset up', material: 'Material', none: '— none —',
    preview: 'Section preview', path_point: 'path', outside: 'right / outside',
    draw: 'Draw path', build: 'Build on selection', extend: 'Extend / trim', rotate90: 'Rotate 90°',
    save_face: 'Save selected face as profile', refresh: 'Refresh',
    preset: 'Type', preset_custom: 'Custom (edited)', my_assemblies: 'My assemblies',
    preset_settings: 'Settings', parts: 'Parts', openings: 'Openings (doors, windows, gates)',
    add_layer: '+ Continuous part', add_repeat: '+ Repeated part',
    add_door: '+ Door', add_window: '+ Window', add_gate: '+ Gap / gate',
    t_layer: 'continuous', t_repeat: 'repeated',
    name: 'Name', profile: 'Profile', anchor: 'Anchor', visible: 'Visible',
    v0: 'Start height', length: 'Piece length', spacing: 'Spacing', setback_start: 'Start setback',
    setback_end: 'End setback', mode: 'Layout', mode_even: 'Even (max spacing)', mode_fixed: 'Fixed from start',
    at_corners: 'Also at corners', jambs: 'Add jamb at openings',
    at: 'From path start', width: 'Width', sill: 'Bottom', head: 'Top', remove: 'Remove',
    duplicate: 'Duplicate', up: 'Move up', down: 'Move down',
    save_assembly: 'Save to my assemblies', flip_all: 'Flip whole assembly',
    q_item: 'Item', q_size: 'Size (mm)', q_count: 'Pcs', q_length: 'Length (m)', q_volume: 'Vol. (m³)',
    q_price: 'Price / m', q_cost: 'Cost', q_total: 'Total', q_empty: 'No Banian objects in this model yet.',
    q_export: 'Export CSV', q_hint: 'Click an item to select it in the model. Prices are saved in the model.',
    del_confirm: 'Remove from your library?',
    anchors: { tl: 'top left', tc: 'top center', tr: 'top right', ml: 'middle left', mc: 'center',
      mr: 'middle right', bl: 'bottom left', bc: 'bottom center', br: 'bottom right' },
    guide_html: `
<h3>Start in 30 seconds</h3>
<ol>
<li>Choose a profile in the <b>Profile</b> tab and type its size.</li>
<li>Click <b>Draw path</b> and click points in the model like the Line tool. Press <b>Enter</b>, double-click or <b>right-click</b> to finish. Click the first point to make a closed loop.</li>
<li>Or select existing edges, arcs or a face and click <b>Build on selection</b>. Faces give a closed loop (perfect for baseboards around a floor).</li>
</ol>
<h3>Edit any time</h3>
<p>Select a Banian object: the panel switches to <b>editing</b>. Every change rebuilds only that object, and all changes in a row merge into one Undo step.</p>
<p>Tick <i>Also update identical profiles</i> to change every equal profile in the model at once.</p>
<h3>Position</h3>
<p>The 3×3 grid sets which point of the section sits on the path. The red dot in the preview is the path. On closed loops the right side is the outside.</p>
<h3>Assemblies</h3>
<p>Pick a type from the picture gallery (9 railings, 2 fences, walls, partitions, trim, pergola), type the main sizes and draw. <b>Continuous parts</b> run along the path, <b>repeated parts</b> (studs, posts, balusters) repeat at a spacing. Add <b>openings</b> for doors and windows: plates are cut, studs are trimmed and jambs added automatically.</p>
<h3>Extend</h3>
<p>Extend tool: click near an end, move and click — or type <code>500</code> (longer), <code>-200</code> (shorter) or <code>3000s</code> (total length).</p>
<h3>Drawing keys</h3>
<p>Arrow keys lock axes (→ red, ← green, ↑ blue, ↓ off). Shift locks inference. Backspace removes the last point. Esc cancels.</p>
<h3>Your own profile (2 clicks)</h3>
<p>Draw your section as a face anywhere, at any angle. Click the dashed <b>+ Add my profile</b> card, then click the face. Done: it is in <i>My profiles</i> and ready to draw.</p>
<h3>Change the shape later</h3>
<p>Select a profile, press <b>Edit shape</b>. The section appears in place: change it with any SketchUp tool and press <b>Update</b>. Every object using it (members and assembly parts) updates.</p>
<h3>Edit the path</h3>
<p>Select an object, press <b>Edit path</b>: drag the red squares, click a green + to add a point, hover a point and press Delete to remove it. No need to open groups.</p>
<p>Or select the object <i>and</i> some edges: <b>Build same on selected path</b> continues it there (e.g. the same railing on the stairs), <b>Move to selected path</b> moves it.</p>
<h3>Eyedropper</h3>
<p>🎯 Click any Banian object in the model, then simply draw: you get the same profile or railing on a new path.</p>
<h3>Your own components</h3>
<p>In an assembly press <b>+ My component</b>, select a component in the model and press <b>Use selected</b>. Decorative balusters, lamps or planters repeat along the path like any part.</p>
<h3>Quantities</h3>
<p>Instant list of every piece with count, length and volume. Enter a price per metre for a cost estimate and export to Excel (CSV).</p>
<h3>Speed tips</h3>
<p>Banian builds each object as one mesh and repeated parts share one component, so even large models stay fast. Use the Rotate / Flip toolbar buttons for quick changes.</p>`
  },
  fa: {
    t_component: 'کامپوننت', add_component: '+ کامپوننت من', component: 'کامپوننت',
    pick_component: 'استفاده از انتخاب‌شده', comp_size: 'ابعاد کامپوننت', scale_len: 'کشیده شود تا طول قطعه',
    elevation: 'نمای روبه‌رو', eyedropper: 'قطره‌چکان: استفاده از یک شیء داخل مدل',
    add_profile: 'افزودن پروفایل من', add_profile_help: 'روی هر سطحی در مدل کلیک کنید (یا اول انتخابش کنید) تا پروفایل شما شود',
    import_lib: 'ورود کتابخانه', export_lib: 'خروجی کتابخانه',
    edit_path: 'ویرایش مسیر', edit_shape: 'ویرایش شکل', continue_path: 'ساخت همین روی مسیر انتخابی', replace_path: 'انتقال به مسیر انتخابی',
    shape_title: 'در حال ویرایش شکل پروفایل', shape_help: 'سطح را با هر ابزار اسکچ‌آپ تغییر دهید، بعد «به‌روزرسانی» را بزنید. همه اشیایی که این پروفایل را دارند به‌روز می‌شوند.',
    shape_done: 'به‌روزرسانی', cancel: 'لغو',
    pc_railing: 'نرده‌ها', pc_fence: 'فنس و حصار', pc_wall: 'دیوار و پارتیشن', pc_trim: 'ابزار و قرنیز', pc_structure: 'سازه',
    app_name: 'بانیان پروفایل بیلدر',
    app_sub: 'پروفایل · اسمبلی · متره',
    lang_btn: 'English',
    tab_member: 'پروفایل', tab_assembly: 'اسمبلی', tab_qty: 'متره و برآورد', tab_guide: 'راهنما',
    new_mode: 'ساخت جدید — تنظیمات را انتخاب کنید، بعد «رسم مسیر» یا «ساخت روی انتخاب».',
    editing: 'در حال ویرایش {n} {k} انتخاب‌شده — تغییرات زنده اعمال می‌شود.',
    k_member: 'پروفایل', k_assembly: 'اسمبلی',
    other_kind: 'یک {k} انتخاب شده. برای ویرایش، تب مربوطه را باز کنید.',
    similar: 'پروفایل‌های مشابه در کل مدل هم به‌روز شوند',
    cat_basic: 'پایه', cat_steel: 'فلزی', cat_trim: 'ابزار و قرنیز', cat_custom: 'پروفایل‌های من',
    search: 'جستجوی پروفایل…',
    size: 'ابعاد', position: 'محل قرارگیری روی مسیر', rotation: 'چرخش', flip: 'برعکس کردن سمت',
    offset_u: 'فاصله عرضی', offset_v: 'فاصله ارتفاعی', material: 'متریال', none: '— بدون متریال —',
    preview: 'پیش‌نمایش مقطع', path_point: 'مسیر', outside: 'راست / بیرون',
    draw: 'رسم مسیر', build: 'ساخت روی انتخاب', extend: 'افزایش / کاهش طول', rotate90: 'چرخش ۹۰°',
    save_face: 'ذخیره سطح انتخاب‌شده به‌عنوان پروفایل', refresh: 'به‌روزرسانی',
    preset: 'نوع', preset_custom: 'سفارشی (ویرایش‌شده)', my_assemblies: 'اسمبلی‌های من',
    preset_settings: 'تنظیمات', parts: 'اجزا', openings: 'بازشوها (در، پنجره، ورودی)',
    add_layer: '+ جزء پیوسته', add_repeat: '+ جزء تکراری',
    add_door: '+ در', add_window: '+ پنجره', add_gate: '+ فاصله / ورودی',
    t_layer: 'پیوسته', t_repeat: 'تکراری',
    name: 'نام', profile: 'پروفایل', anchor: 'نقطه اتصال', visible: 'نمایش',
    v0: 'ارتفاع شروع', length: 'طول قطعه', spacing: 'فاصله', setback_start: 'فاصله از ابتدا',
    setback_end: 'فاصله از انتها', mode: 'چیدمان', mode_even: 'یکنواخت (حداکثر فاصله)', mode_fixed: 'ثابت از ابتدا',
    at_corners: 'در گوشه‌ها هم باشد', jambs: 'کنار بازشوها قطعه اضافه شود',
    at: 'فاصله از ابتدای مسیر', width: 'عرض', sill: 'پایین', head: 'بالا', remove: 'حذف',
    duplicate: 'کپی', up: 'بالا', down: 'پایین',
    save_assembly: 'ذخیره در اسمبلی‌های من', flip_all: 'برعکس کردن کل اسمبلی',
    q_item: 'آیتم', q_size: 'ابعاد (mm)', q_count: 'تعداد', q_length: 'طول (m)', q_volume: 'حجم (m³)',
    q_price: 'قیمت هر متر', q_cost: 'هزینه', q_total: 'جمع کل', q_empty: 'هنوز هیچ شیء بانیانی در مدل نیست.',
    q_export: 'خروجی اکسل (CSV)', q_hint: 'روی هر آیتم کلیک کنید تا در مدل انتخاب شود. قیمت‌ها داخل فایل مدل ذخیره می‌شوند.',
    del_confirm: 'از کتابخانه شما حذف شود؟',
    anchors: { tl: 'بالا چپ', tc: 'بالا وسط', tr: 'بالا راست', ml: 'وسط چپ', mc: 'مرکز',
      mr: 'وسط راست', bl: 'پایین چپ', bc: 'پایین وسط', br: 'پایین راست' },
    guide_html: `
<h3>شروع در ۳۰ ثانیه</h3>
<ol>
<li>در تب <b>پروفایل</b> یک پروفایل انتخاب کنید و ابعادش را بنویسید.</li>
<li>روی <b>رسم مسیر</b> بزنید و مثل ابزار Line در مدل کلیک کنید. با <b>Enter</b>، دابل‌کلیک یا <b>کلیک راست</b> تمام کنید. اگر روی نقطه اول کلیک کنید، مسیر بسته می‌شود.</li>
<li>یا خط‌ها، کمان‌ها یا یک سطح موجود را انتخاب کنید و <b>ساخت روی انتخاب</b> را بزنید. انتخاب سطح، یک مسیر بسته می‌دهد (مثلاً قرنیز دور تا دور کف).</li>
</ol>
<h3>ویرایش در هر زمان</h3>
<p>یک شیء بانیان را انتخاب کنید؛ پنل به حالت <b>ویرایش</b> می‌رود. هر تغییر فقط همان شیء را دوباره می‌سازد و تغییرات پشت‌سرهم در یک Undo جمع می‌شوند.</p>
<p>با تیک <i>پروفایل‌های مشابه هم به‌روز شوند</i>، همه پروفایل‌های یکسان در مدل با هم عوض می‌شوند.</p>
<h3>محل قرارگیری</h3>
<p>جدول ۳×۳ تعیین می‌کند کدام نقطه مقطع روی مسیر بنشیند. نقطه قرمز در پیش‌نمایش همان مسیر است. در مسیرهای بسته، سمت راست یعنی بیرون.</p>
<h3>اسمبلی‌ها</h3>
<p>از گالری تصویری یک نوع انتخاب کنید (۹ مدل نرده، ۲ مدل فنس، دیوار، پارتیشن، ابزار، آلاچیق)، ابعاد اصلی را بنویسید و رسم کنید. <b>اجزای پیوسته</b> در طول مسیر کشیده می‌شوند و <b>اجزای تکراری</b> (استاد، ستون، میله) با فاصله مشخص تکرار می‌شوند. برای در و پنجره <b>بازشو</b> اضافه کنید: کف‌کش‌ها بریده می‌شوند، استادها کوتاه و کنار بازشو خودکار قطعه اضافه می‌شود.</p>
<h3>افزایش طول</h3>
<p>ابزار Extend: نزدیک یک سر کلیک کنید، حرکت دهید و کلیک کنید — یا تایپ کنید <code>500</code> (بلندتر)، <code>-200</code> (کوتاه‌تر) یا <code>3000s</code> (طول کل).</p>
<h3>کلیدهای رسم</h3>
<p>کلیدهای جهت محور را قفل می‌کنند (→ قرمز، ← سبز، ↑ آبی، ↓ آزاد). Shift قفل اینفرنس. Backspace حذف آخرین نقطه. Esc لغو.</p>
<h3>پروفایل اختصاصی شما (با دو کلیک)</h3>
<p>مقطع خودتان را به‌صورت یک سطح، هر جای مدل و با هر زاویه‌ای بکشید. روی کارت خط‌چین <b>+ افزودن پروفایل من</b> بزنید و بعد روی آن سطح کلیک کنید. تمام! در «پروفایل‌های من» آماده رسم است.</p>
<h3>تغییر شکل پروفایل در هر زمان</h3>
<p>پروفایل را انتخاب کنید و <b>ویرایش شکل</b> را بزنید. مقطع همان‌جا ظاهر می‌شود. با هر ابزار اسکچ‌آپ تغییرش دهید و <b>به‌روزرسانی</b> را بزنید. همه اشیایی که این پروفایل را دارند (حتی داخل اسمبلی‌ها) به‌روز می‌شوند.</p>
<h3>ویرایش مسیر</h3>
<p>شیء را انتخاب کنید و <b>ویرایش مسیر</b> را بزنید. مربع‌های قرمز را بکشید، روی + سبز کلیک کنید تا نقطه اضافه شود، و روی یک نقطه بروید و Delete بزنید تا حذف شود. لازم نیست وارد گروه شوید.</p>
<p>یا شیء را <i>همراه با</i> چند خط انتخاب کنید: <b>ساخت همین روی مسیر انتخابی</b> آن را روی خط‌ها ادامه می‌دهد (مثلاً همین نرده روی پله) و <b>انتقال به مسیر انتخابی</b> مسیرش را عوض می‌کند.</p>
<h3>قطره‌چکان</h3>
<p>🎯 روی هر شیء بانیان در مدل کلیک کنید و بعد فقط رسم کنید: همان پروفایل یا نرده روی مسیر جدید ساخته می‌شود.</p>
<h3>کامپوننت‌های خودتان</h3>
<p>در اسمبلی <b>+ کامپوننت من</b> را بزنید، یک کامپوننت را در مدل انتخاب کنید و <b>استفاده از انتخاب‌شده</b> را بزنید. نرده تزئینی، چراغ یا گلدان مثل بقیه اجزا در طول مسیر تکرار می‌شود.</p>
<h3>متره و برآورد</h3>
<p>لیست فوری همه قطعات با تعداد، طول و حجم. قیمت هر متر را وارد کنید تا هزینه حساب شود و خروجی اکسل (CSV) بگیرید.</p>
<h3>نکته سرعت</h3>
<p>بانیان هر شیء را به‌صورت یک مش واحد می‌سازد و قطعات تکراری یک کامپوننت مشترک دارند؛ برای همین مدل‌های بزرگ هم روان می‌مانند.</p>`
  }
};
