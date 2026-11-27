-- Выполните ПОСЛЕ supabase_problems_setup.sql, тоже один раз в Supabase → SQL Editor.
-- Создаёт хранилище для фото и видео к меткам.

insert into storage.buckets (id, name, public)
values ('problem-media', 'problem-media', true)
on conflict (id) do nothing;

-- Загружать можно только в свою папку: <user_id>/файл
drop policy if exists "Users upload own media" on storage.objects;
create policy "Users upload own media"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'problem-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Media is public" on storage.objects;
create policy "Media is public"
on storage.objects for select to anon, authenticated
using (bucket_id = 'problem-media');

notify pgrst, 'reload schema';
