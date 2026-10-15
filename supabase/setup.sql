-- مرافق التلميذ · إعداد التخزين المشترك للدروس (Supabase، الخطة المجانية)
-- شغّل هذا الملف مرة واحدة في: SQL Editor داخل مشروعك.

create table if not exists public.lessons (
  origin_lesson_id text primary key,
  version_number   integer not null check (version_number >= 1),
  internal_level   integer not null check (internal_level in (1, 2, 3)),
  title            text not null,
  subject_name     text not null,
  teacher_name     text not null,
  fingerprint      text not null,
  package_path     text not null,
  owner            text,
  updated_at       timestamptz not null default now()
);

-- لمن أنشأ الجدول من قبل: أضف عمود صاحب الدرس (آمن إن كان موجودًا).
alter table public.lessons add column if not exists owner text;

create index if not exists lessons_level_idx
  on public.lessons (internal_level, updated_at desc);

-- القراءة للجميع (التلاميذ). لا توجد أي سياسة كتابة: الكتابة تتم فقط من
-- الدالة teacher-publish بمفتاح الخدمة السري على الخادم.
alter table public.lessons enable row level security;

drop policy if exists "lessons are readable by everyone" on public.lessons;
create policy "lessons are readable by everyone"
  on public.lessons for select
  to anon, authenticated
  using (true);

-- حاوية ملفات الدروس: قراءة عامة، والكتابة عبر الدالة فقط.
insert into storage.buckets (id, name, public, file_size_limit)
values ('lesson-files', 'lesson-files', true, 26214400)
on conflict (id) do update set public = true, file_size_limit = 26214400;
