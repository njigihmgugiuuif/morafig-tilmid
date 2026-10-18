// مرافق التلميذ · دالة نشر دروس الأستاذ (Supabase Edge Function) — الإصدار 3.
//
// لكل أستاذ(ة) رقم خاص به، وهي أسرار على الخادم لا تظهر في التطبيق ولا في
// المستودع:
//   TEACHER_CODES    : نص JSON  {"48291736":"أ. سعاد","90517362":"أ. كريم"}
//                      (الرقم من 6 إلى 12 خانة أرقام فقط، والقيمة اسم الأستاذ(ة)).
//   TEACHER_PASSWORD : (اختياري) كلمة مرور المسؤول (8 أحرف فأكثر): تدير كل
//                      الدروس. وإن لم يوجد TEACHER_CODES تعمل الدالة بالطريقة
//                      القديمة (كلمة مرور واحدة للجميع) دون أي تغيير في القاعدة.
// هوية الأستاذ(ة) هي اسمه في TEACHER_CODES: لا تعطِ الاسم نفسه لأستاذين مختلفين،
// ولا تغيّر الاسم بعد أن ينشر دروسه. (يجوز أن يكون لأستاذ واحد أكثر من رقم.)
// عند وجود TEACHER_CODES:
//   - اسم الأستاذ(ة) على الدرس يأتي من الخادم لا من الجهاز.
//   - كل درس يحمل صاحبه (العمود owner): لا يغيّر أستاذ(ة) درس غيره ولا يسحبه
//     ولا يرفع ملفات فوق ملفاته. المسؤول وحده يتجاوز ذلك.
// الكتابة لا تتم إلا بأحد هذه الأرقام. القراءة عامة.
//
// الإجراءات:
//   verify    : فحص كلمة المرور.
//   putFile   : رفع ملف واحد (صورة صفحة أو مرفق) إلى lesson-files.
//   commit    : بعد رفع كل الملفات: تتحقق الدالة أن كل ملف موجود بحجمه
//               المعلن، ثم تحفظ ملف الفهرس وسطر الدرس في جدول lessons.
//   unpublish : سحب الدرس وحذف ملفاته.
//   wipeAll   : للمسؤول وحده (TEACHER_PASSWORD): يمحو كل الدروس وكل الملفات
//               (حتى الصور اليتيمة من رفع لم يكتمل). لا رجعة فيه.
//
// كل صورة ملف مستقل: لا طلب واحد ضخم، وتُعاد المحاولة لكل ملف على حدة.
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const VERSION = 3;
const BUCKET = "lesson-files";
const FORMAT = "marafiq.teacher-lesson";
const MAX_FILE_BYTES = 8 * 1024 * 1024; // لكل ملف بعد فكّ الترميز
const MAX_FILES = 80;
const PATH_RE = /^lessons\/([A-Za-z0-9_-]{8,64})\/v([0-9]{1,6})\/([A-Za-z0-9._-]{1,80})$/;
const MIME_RE = /^[a-z0-9][a-z0-9.+-]*\/[a-z0-9][a-z0-9.+-]*$/;

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json; charset=utf-8" },
  });
}

function safeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let diff = ea.length ^ eb.length;
  const n = Math.max(ea.length, eb.length);
  for (let i = 0; i < n; i++) diff |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  return diff === 0;
}

function decodeBase64(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

// أرقام الأساتذة من السرّ TEACHER_CODES (تجاهل أي مدخل غير صالح).
function loadCodes(): { code: string; name: string }[] {
  const raw = Deno.env.get("TEACHER_CODES");
  if (!raw) return [];
  try {
    const obj = JSON.parse(raw);
    const out: { code: string; name: string }[] = [];
    if (obj && typeof obj === "object" && !Array.isArray(obj)) {
      for (const [code, name] of Object.entries(obj)) {
        if (
          /^[0-9]{6,12}$/.test(code) && typeof name === "string" &&
          name.trim().length > 0
        ) out.push({ code, name: name.trim() });
      }
    }
    return out;
  } catch {
    return [];
  }
}

type Caller = { id: string; name: string | null; admin: boolean };

// صاحب الدرس الحالي (إن وُجد). يفشل بوضوح إن لم يُضف عمود owner بعد.
async function ownerOf(
  supabase: any,
  lessonId: string,
): Promise<
  { ok: true; owner: string | null; exists: boolean } | {
    ok: false;
    message: string;
  }
> {
  const r = await supabase.from("lessons").select("owner")
    .eq("origin_lesson_id", lessonId).maybeSingle();
  if (r.error) {
    const msg = String(r.error.message ?? "");
    if (msg.includes("owner")) {
      return {
        ok: false,
        message:
          "قاعدة البيانات تحتاج تحديثًا: أضف عمود owner (الأمر في SUPABASE_SETUP_AR.md).",
      };
    }
    return { ok: false, message: `تعذّر فحص صاحب الدرس: ${msg}` };
  }
  return {
    ok: true,
    owner: (r.data?.owner ?? null) as string | null,
    exists: !!r.data,
  };
}

function canWrite(caller: Caller, owner: string | null): boolean {
  return caller.admin || owner === null || owner === caller.id;
}


// يعدّ كل الملفات تحت مجلد (يدخل المجلدات الفرعية). عنصر بلا id مجلد.
async function listAllFiles(supabase: any, folder: string): Promise<string[]> {
  const out: string[] = [];
  const stack = [folder];
  while (stack.length > 0) {
    const dir = stack.pop()!;
    let offset = 0;
    while (true) {
      const l = await supabase.storage.from(BUCKET).list(dir, {
        limit: 1000,
        offset,
      });
      if (l.error) throw new Error(l.error.message);
      const items = (l.data ?? []) as { name: string; id: string | null }[];
      for (const o of items) {
        if (o.id === null) stack.push(`${dir}/${o.name}`);
        else out.push(`${dir}/${o.name}`);
      }
      if (items.length < 1000) break;
      offset += 1000;
    }
  }
  return out;
}

// إبطاء المحاولات الخاطئة (حماية بسيطة من التخمين، ليست حماية كاملة).
let failures = 0;
let windowStart = Date.now();

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reply(405, { message: "POST only" });

  const adminPassword = Deno.env.get("TEACHER_PASSWORD") ?? "";
  const codes = loadCodes();
  if (adminPassword.length < 8 && codes.length === 0) {
    return reply(500, {
      message:
        "أرقام الأساتذة لم تُضبط على الخادم بعد (TEACHER_CODES أو TEACHER_PASSWORD).",
    });
  }
  // الملكية لا تعمل إلا حين تُضبط أرقام الأساتذة.
  const ownershipOn = codes.length > 0;

  let body: Record<string, any>;
  try {
    body = await req.json();
  } catch {
    return reply(400, { message: "طلب غير صالح." });
  }

  if (Date.now() - windowStart > 10 * 60 * 1000) {
    failures = 0;
    windowStart = Date.now();
  }
  if (failures >= 20) {
    return reply(429, { message: "محاولات كثيرة. انتظر قليلًا." });
  }
  let caller: Caller | null = null;
  if (typeof body.password === "string" && body.password.length > 0) {
    for (const c of codes) {
      if (safeEqual(body.password, c.code)) {
        // هوية الأستاذ(ة) = اسمه في TEACHER_CODES (لا رقمه، فالرقم سرّ والاسم علني).
        caller = { id: `t:${c.name}`, name: c.name, admin: false };
      }
    }
    if (
      !caller && adminPassword.length >= 8 &&
      safeEqual(body.password, adminPassword)
    ) {
      caller = { id: "admin", name: null, admin: true };
    }
  }
  if (!caller) {
    failures++;
    await new Promise((r) => setTimeout(r, 800));
    return reply(401, { error: "wrong_password" });
  }

  const action = body.action;
  if (action === "verify") {
    return reply(200, {
      ok: true,
      version: VERSION,
      teacher: caller.name,
      admin: caller.admin,
    });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // ------------------------------------------------------------ putFile
  if (action === "putFile") {
    const path = body.path;
    const mime = body.mimeType;
    const data = body.data;
    if (typeof path !== "string" || !PATH_RE.test(path)) {
      return reply(400, { message: "مسار الملف غير صالح." });
    }
    if (ownershipOn) {
      const o = await ownerOf(supabase, PATH_RE.exec(path)![1]);
      if (!o.ok) return reply(500, { message: o.message });
      if (!canWrite(caller, o.owner)) {
        return reply(403, { message: "هذا الدرس يخص أستاذًا آخر." });
      }
    }
    if (typeof mime !== "string" || !MIME_RE.test(mime)) {
      return reply(400, { message: "نوع الملف غير صالح." });
    }
    if (typeof data !== "string" || data.length === 0) {
      return reply(400, { message: "محتوى الملف فارغ." });
    }
    let bytes: Uint8Array;
    try {
      bytes = decodeBase64(data);
    } catch {
      return reply(400, { message: "ترميز الملف غير صالح." });
    }
    if (bytes.length === 0 || bytes.length > MAX_FILE_BYTES) {
      return reply(400, {
        message: `حجم الملف ${bytes.length} بايت خارج الحد المسموح (${MAX_FILE_BYTES}).`,
      });
    }
    const up = await supabase.storage.from(BUCKET).upload(path, bytes, {
      upsert: true,
      contentType: mime,
    });
    if (up.error) {
      return reply(500, { message: `تعذّر حفظ الملف: ${up.error.message}` });
    }
    return reply(200, { ok: true, size: bytes.length });
  }

  // ------------------------------------------------------------- commit
  if (action === "commit") {
    const l = body.lesson ?? {};
    const manifestText = body.manifest;
    const level = Number(l.internalLevel);
    const version = Number(l.versionNumber);
    if (
      typeof l.originLessonId !== "string" ||
      !/^[A-Za-z0-9_-]{8,64}$/.test(l.originLessonId) ||
      ![1, 2, 3].includes(level) || !Number.isInteger(version) || version < 1 ||
      typeof manifestText !== "string" || manifestText.length === 0 ||
      manifestText.length > 1024 * 1024 ||
      typeof l.fingerprint !== "string" || l.fingerprint.length === 0
    ) {
      return reply(400, { message: "بيانات الدرس ناقصة أو غير صالحة." });
    }
    let m: any;
    try {
      m = JSON.parse(manifestText);
    } catch {
      return reply(400, { message: "فهرس الدرس غير صالح." });
    }
    if (
      m?.format !== FORMAT || m?.fingerprint !== l.fingerprint ||
      m?.lesson?.originLessonId !== l.originLessonId ||
      m?.lesson?.versionNumber !== version ||
      m?.lesson?.internalLevel !== level ||
      !Array.isArray(m?.pages) || m.pages.length === 0 ||
      !Array.isArray(m?.attachments)
    ) {
      return reply(400, { message: "بيانات الدرس لا تطابق فهرسه." });
    }
    const folder = `lessons/${l.originLessonId}/v${version}`;
    const wanted = new Map<string, number>();
    for (const f of [...m.pages, ...m.attachments]) {
      if (
        typeof f?.path !== "string" || !f.path.startsWith(`${folder}/`) ||
        !PATH_RE.test(f.path) || !Number.isInteger(f.size) || f.size <= 0 ||
        typeof f.sha256 !== "string"
      ) {
        return reply(400, { message: "فهرس الدرس يحوي مسارًا غير صالح." });
      }
      wanted.set(f.path.substring(folder.length + 1), f.size);
    }
    if (wanted.size > MAX_FILES) {
      return reply(400, { message: "عدد ملفات الدرس كبير جدًا." });
    }

    // تحقّق: كل ملف موجود على التخزين وبالحجم المعلن.
    const listed = await supabase.storage.from(BUCKET).list(folder, {
      limit: 1000,
    });
    if (listed.error) {
      return reply(500, { message: `تعذّر فحص الملفات: ${listed.error.message}` });
    }
    const present = new Map<string, number>();
    for (const o of listed.data ?? []) {
      present.set(o.name, Number((o as any).metadata?.size ?? -1));
    }
    const bad: string[] = [];
    for (const [name, size] of wanted) {
      const got = present.get(name);
      if (got === undefined) bad.push(`${name} (مفقود)`);
      else if (got !== size) bad.push(`${name} (حجمه ${got} بدل ${size})`);
    }
    if (bad.length > 0) {
      return reply(409, {
        message: `ملفات ناقصة أو غير مكتملة على الخادم: ${bad.join("، ")}`,
        missing: bad,
      });
    }

    const manifestPath = `${folder}/manifest.json`;
    const upM = await supabase.storage.from(BUCKET).upload(
      manifestPath,
      new Blob([manifestText], { type: "application/json" }),
      { upsert: true, contentType: "application/json" },
    );
    if (upM.error) {
      return reply(500, { message: `تعذّر حفظ الفهرس: ${upM.error.message}` });
    }

    const prev = await supabase.from("lessons").select("package_path")
      .eq("origin_lesson_id", l.originLessonId).maybeSingle();

    const rowData: Record<string, unknown> = {
      origin_lesson_id: l.originLessonId,
      version_number: version,
      internal_level: level,
      title: String(l.title ?? ""),
      subject_name: String(l.subjectName ?? ""),
      // مع أرقام الأساتذة: الاسم من الخادم، فلا يمكن انتحال اسم أستاذ(ة) آخر.
      teacher_name: caller.name ?? String(l.teacherName ?? ""),
      fingerprint: l.fingerprint,
      package_path: manifestPath,
      updated_at: new Date().toISOString(),
    };
    if (ownershipOn) {
      const o = await ownerOf(supabase, l.originLessonId);
      if (!o.ok) return reply(500, { message: o.message });
      if (!canWrite(caller, o.owner)) {
        return reply(403, { message: "هذا الدرس يخص أستاذًا آخر." });
      }
      // المسؤول يبقي صاحب الدرس كما هو.
      rowData.owner = o.owner ?? caller.id;
    }
    const row = await supabase.from("lessons").upsert(rowData);
    if (row.error) {
      return reply(500, { message: `تعذّر حفظ بيانات الدرس: ${row.error.message}` });
    }

    // تنظيف: ملفات زائدة في المجلد نفسه، ومجلد الإصدار السابق.
    const extras = [...present.keys()]
      .filter((n) => !wanted.has(n) && n !== "manifest.json")
      .map((n) => `${folder}/${n}`);
    if (extras.length > 0) await supabase.storage.from(BUCKET).remove(extras);
    const old = prev.data?.package_path as string | undefined;
    if (old && !old.startsWith(`${folder}/`)) {
      const oldFolder = old.substring(0, old.lastIndexOf("/"));
      if (oldFolder.startsWith("lessons/")) {
        const oldList = await supabase.storage.from(BUCKET).list(oldFolder, {
          limit: 1000,
        });
        const names = (oldList.data ?? []).map((o) => `${oldFolder}/${o.name}`);
        if (names.length > 0) await supabase.storage.from(BUCKET).remove(names);
      } else {
        await supabase.storage.from(BUCKET).remove([old]);
      }
    }
    return reply(200, { ok: true, files: wanted.size });
  }

  // ------------------------------------------------------------ wipeAll
  if (action === "wipeAll") {
    if (!caller.admin) {
      return reply(403, { message: "المسح الكامل للمسؤول وحده." });
    }
    if (body.confirm !== "WIPE") {
      return reply(400, { message: "التأكيد ناقص." });
    }
    const del = await supabase.from("lessons").delete()
      .neq("origin_lesson_id", "");
    if (del.error) {
      return reply(500, { message: `تعذّر مسح الدروس: ${del.error.message}` });
    }
    let files: string[];
    try {
      files = await listAllFiles(supabase, "lessons");
    } catch (e) {
      return reply(500, { message: `تعذّر سرد الملفات: ${String(e)}` });
    }
    let removed = 0;
    for (let i = 0; i < files.length; i += 100) {
      const chunk = files.slice(i, i + 100);
      const r = await supabase.storage.from(BUCKET).remove(chunk);
      if (r.error) {
        return reply(500, {
          message: `تعذّر حذف الملفات: ${r.error.message}`,
          removed,
        });
      }
      removed += chunk.length;
    }
    const left = await supabase.from("lessons").select("origin_lesson_id", {
      count: "exact",
      head: true,
    });
    return reply(200, {
      ok: true,
      filesRemoved: removed,
      lessonsLeft: left.count ?? 0,
    });
  }

  // ---------------------------------------------------------- unpublish
  if (action === "unpublish") {
    const id = body.originLessonId;
    if (typeof id !== "string" || !/^[A-Za-z0-9_-]{8,64}$/.test(id)) {
      return reply(400, { message: "معرّف الدرس غير صالح." });
    }
    if (ownershipOn) {
      const o = await ownerOf(supabase, id);
      if (!o.ok) return reply(500, { message: o.message });
      if (!canWrite(caller, o.owner)) {
        return reply(403, { message: "هذا الدرس يخص أستاذًا آخر." });
      }
    }
    const prev = await supabase.from("lessons").select("package_path")
      .eq("origin_lesson_id", id).maybeSingle();
    const del = await supabase.from("lessons").delete().eq("origin_lesson_id", id);
    if (del.error) return reply(500, { message: `تعذّر السحب: ${del.error.message}` });
    const path = prev.data?.package_path as string | undefined;
    if (path) {
      const folder = path.substring(0, path.lastIndexOf("/"));
      if (folder.startsWith("lessons/")) {
        const l = await supabase.storage.from(BUCKET).list(folder, { limit: 1000 });
        const names = (l.data ?? []).map((o) => `${folder}/${o.name}`);
        if (names.length > 0) await supabase.storage.from(BUCKET).remove(names);
      } else {
        await supabase.storage.from(BUCKET).remove([path]);
      }
    }
    return reply(200, { ok: true });
  }

  return reply(400, { message: "إجراء غير معروف. حدّث دالة الخادم بالنص الجديد." });
});
