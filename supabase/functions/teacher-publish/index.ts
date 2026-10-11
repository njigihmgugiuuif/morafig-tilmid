// مرافق التلميذ · دالة نشر دروس الأستاذ (Supabase Edge Function).
//
// كلمة مرور الأساتذة تُحفظ كسرّ على الخادم (TEACHER_PASSWORD) ولا تظهر في
// التطبيق ولا في المستودع. الكتابة (نشر / سحب) لا تتم إلا بها. القراءة عامة.
//
// الإجراءات: verify | publish | unpublish
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MAX_PACKAGE_CHARS = 24 * 1024 * 1024;
const FORMAT = "marafiq.teacher-lesson";

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

// إبطاء المحاولات الخاطئة (حماية بسيطة من التخمين، ليست حماية كاملة).
let failures = 0;
let windowStart = Date.now();

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reply(405, { message: "POST only" });

  const expected = Deno.env.get("TEACHER_PASSWORD") ?? "";
  if (expected.length < 8) {
    return reply(500, {
      message: "كلمة مرور الأساتذة لم تُضبط على الخادم بعد (TEACHER_PASSWORD).",
    });
  }

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
  if (typeof body.password !== "string" || !safeEqual(body.password, expected)) {
    failures++;
    await new Promise((r) => setTimeout(r, 800));
    return reply(401, { error: "wrong_password" });
  }

  const action = body.action;
  if (action === "verify") return reply(200, { ok: true });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  if (action === "publish") {
    const l = body.lesson ?? {};
    const pkg = body.package;
    const level = Number(l.internalLevel);
    const version = Number(l.versionNumber);
    if (
      typeof l.originLessonId !== "string" || l.originLessonId.length < 8 ||
      !/^[A-Za-z0-9_-]+$/.test(l.originLessonId) ||
      ![1, 2, 3].includes(level) || !Number.isInteger(version) || version < 1 ||
      typeof pkg !== "string" || pkg.length === 0 || pkg.length > MAX_PACKAGE_CHARS ||
      typeof l.fingerprint !== "string" || l.fingerprint.length === 0
    ) {
      return reply(400, { message: "بيانات الدرس ناقصة أو غير صالحة." });
    }
    let parsed: any;
    try {
      parsed = JSON.parse(pkg);
    } catch {
      return reply(400, { message: "ملف الدرس غير صالح." });
    }
    if (
      parsed?.format !== FORMAT || parsed?.fingerprint !== l.fingerprint ||
      parsed?.lesson?.originLessonId !== l.originLessonId ||
      parsed?.lesson?.versionNumber !== version ||
      parsed?.lesson?.internalLevel !== level
    ) {
      return reply(400, { message: "بيانات الدرس لا تطابق ملفه." });
    }

    const path = `packages/${l.originLessonId}-v${version}.json`;
    const up = await supabase.storage.from("lesson-files").upload(
      path,
      new Blob([pkg], { type: "application/json" }),
      { upsert: true, contentType: "application/json" },
    );
    if (up.error) return reply(500, { message: `تعذّر حفظ الملف: ${up.error.message}` });

    const prev = await supabase.from("lessons").select("package_path")
      .eq("origin_lesson_id", l.originLessonId).maybeSingle();

    const row = await supabase.from("lessons").upsert({
      origin_lesson_id: l.originLessonId,
      version_number: version,
      internal_level: level,
      title: String(l.title ?? ""),
      subject_name: String(l.subjectName ?? ""),
      teacher_name: String(l.teacherName ?? ""),
      fingerprint: l.fingerprint,
      package_path: path,
      updated_at: new Date().toISOString(),
    });
    if (row.error) return reply(500, { message: `تعذّر حفظ البيانات: ${row.error.message}` });

    const old = prev.data?.package_path;
    if (old && old !== path) {
      await supabase.storage.from("lesson-files").remove([old]);
    }
    return reply(200, { ok: true });
  }

  if (action === "unpublish") {
    const id = body.originLessonId;
    if (typeof id !== "string" || !/^[A-Za-z0-9_-]+$/.test(id)) {
      return reply(400, { message: "معرّف الدرس غير صالح." });
    }
    const prev = await supabase.from("lessons").select("package_path")
      .eq("origin_lesson_id", id).maybeSingle();
    const del = await supabase.from("lessons").delete().eq("origin_lesson_id", id);
    if (del.error) return reply(500, { message: `تعذّر السحب: ${del.error.message}` });
    if (prev.data?.package_path) {
      await supabase.storage.from("lesson-files").remove([prev.data.package_path]);
    }
    return reply(200, { ok: true });
  }

  return reply(400, { message: "إجراء غير معروف." });
});
