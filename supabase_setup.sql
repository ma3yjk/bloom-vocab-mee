-- BLOOM VOCAB: chạy toàn bộ file này trong Supabase > SQL Editor > New query
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'member' check (role in ('member','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.topics (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.words (
  id uuid primary key default gen_random_uuid(),
  english text not null,
  pronunciation text,
  meaning text not null,
  example text,
  image_url text,
  topic_id uuid references public.topics(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create or replace function public.is_bloom_admin()
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

create or replace function public.handle_new_bloom_user()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.profiles(id,email,role)
  values(new.id,new.email,'member')
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists on_bloom_auth_user_created on auth.users;
create trigger on_bloom_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_bloom_user();

alter table public.profiles enable row level security;
alter table public.topics enable row level security;
alter table public.words enable row level security;

drop policy if exists "Profiles: read own" on public.profiles;
create policy "Profiles: read own" on public.profiles
for select to authenticated using (id = auth.uid() or public.is_bloom_admin());

drop policy if exists "Profiles: admin update" on public.profiles;
create policy "Profiles: admin update" on public.profiles
for update to authenticated using (public.is_bloom_admin()) with check (public.is_bloom_admin());

drop policy if exists "Topics: public read" on public.topics;
create policy "Topics: public read" on public.topics
for select to anon, authenticated using (true);

drop policy if exists "Topics: admin insert" on public.topics;
create policy "Topics: admin insert" on public.topics
for insert to authenticated with check (public.is_bloom_admin());

drop policy if exists "Topics: admin update" on public.topics;
create policy "Topics: admin update" on public.topics
for update to authenticated using (public.is_bloom_admin()) with check (public.is_bloom_admin());

drop policy if exists "Topics: admin delete" on public.topics;
create policy "Topics: admin delete" on public.topics
for delete to authenticated using (public.is_bloom_admin());

drop policy if exists "Words: public read" on public.words;
create policy "Words: public read" on public.words
for select to anon, authenticated using (true);

drop policy if exists "Words: signed-in insert" on public.words;
create policy "Words: signed-in insert" on public.words
for insert to authenticated with check (created_by = auth.uid());

drop policy if exists "Words: admin update" on public.words;
create policy "Words: admin update" on public.words
for update to authenticated using (public.is_bloom_admin()) with check (public.is_bloom_admin());

drop policy if exists "Words: admin delete" on public.words;
create policy "Words: admin delete" on public.words
for delete to authenticated using (public.is_bloom_admin());

grant usage on schema public to anon, authenticated;
grant select on public.topics, public.words to anon, authenticated;
grant select, update on public.profiles to authenticated;
grant insert, update, delete on public.topics to authenticated;
grant insert, update, delete on public.words to authenticated;

insert into public.topics(name) values
('Animals'),('Food & Drinks'),('Family'),('School'),('Colors'),('Clothes'),('Daily Activities')
on conflict (name) do nothing;

-- Sau khi đăng nhập Google lần đầu, lấy User UID tại Authentication > Users.
-- Thay YOUR_USER_UUID bằng UID của bạn rồi chạy riêng lệnh:
-- update public.profiles set role = 'admin' where id = 'YOUR_USER_UUID';


-- 15 từ mẫu ban đầu (chỉ thêm nếu từ đó chưa tồn tại trong chủ đề tương ứng).
insert into public.words(english, pronunciation, meaning, example, topic_id)
select v.english, v.pronunciation, v.meaning, v.example, t.id
from (values
 ('apple','/ˈæp.əl/','quả táo','I eat an apple.','Food & Drinks'),
 ('banana','/bəˈnɑː.nə/','quả chuối','A banana is yellow.','Food & Drinks'),
 ('bread','/bred/','bánh mì','I have bread for breakfast.','Food & Drinks'),
 ('cat','/kæt/','con mèo','The cat is sleeping.','Animals'),
 ('dog','/dɒɡ/','con chó','My dog is friendly.','Animals'),
 ('bird','/bɜːd/','con chim','A bird can fly.','Animals'),
 ('mother','/ˈmʌð.ər/','mẹ','My mother is kind.','Family'),
 ('father','/ˈfɑː.ðər/','bố','My father works hard.','Family'),
 ('sister','/ˈsɪs.tər/','chị/em gái','My sister likes music.','Family'),
 ('teacher','/ˈtiː.tʃər/','giáo viên','Our teacher is helpful.','School'),
 ('book','/bʊk/','quyển sách','This is my book.','School'),
 ('pencil','/ˈpen.səl/','bút chì','I write with a pencil.','School'),
 ('red','/red/','màu đỏ','The flower is red.','Colors'),
 ('blue','/bluː/','màu xanh dương','The sky is blue.','Colors'),
 ('shirt','/ʃɜːt/','áo sơ mi','He wears a white shirt.','Clothes')
) as v(english,pronunciation,meaning,example,topic_name)
join public.topics t on t.name = v.topic_name
where not exists (
  select 1 from public.words w
  where lower(w.english) = lower(v.english) and w.topic_id = t.id
);

-- Kho ảnh công khai: khách có thể xem ảnh; thành viên đã đăng nhập được tải ảnh của mình lên.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('vocab-images', 'vocab-images', true, 5242880, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update set
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif'];

drop policy if exists "Bloom images: public read" on storage.objects;
create policy "Bloom images: public read" on storage.objects
for select to anon, authenticated
using (bucket_id = 'vocab-images');

drop policy if exists "Bloom images: members upload own folder" on storage.objects;
create policy "Bloom images: members upload own folder" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'vocab-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Bloom images: admin delete" on storage.objects;
create policy "Bloom images: admin delete" on storage.objects
for delete to authenticated
using (bucket_id = 'vocab-images' and public.is_bloom_admin());
