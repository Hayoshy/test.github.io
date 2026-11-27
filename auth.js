// Общая настройка Supabase Auth для HTML-страниц.
(() => {
  if (window.citySupabase) return;
  const SUPABASE_URL = 'https://agxdytwqrstleltlazzh.supabase.co';
  // Publishable key — допустим для клиентского сайта. Никогда не вставляйте Secret/service_role key.
  const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_fwWLuLga2yUq3J9Or3ByjA_J0XHzXHb';
  window.citySupabase = window.supabase.createClient(
    SUPABASE_URL,
    SUPABASE_PUBLISHABLE_KEY,
    {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
        // Единый ключ хранения для index.html, login.html и остальных страниц.
        storageKey: 'sb-agxdytwqrstleltlazzh-auth-token'
      }
    }
  );
})();

// Переводит любую ошибку Supabase/сети в понятный русский текст.
// Использование: ruError(error, 'Что не получилось')
window.ruError = function ruError(err, fallback) {
  const raw = String((err && (err.message || err.error_description || err.msg)) || err || '');
  const code = String((err && (err.code || err.error_code)) || '');
  if (/[а-яё]/i.test(raw)) return raw; // уже по-русски
  const text = raw.toLowerCase();
  const rules = [
    [/schema cache|could not find the table|relation .* does not exist|pgrst205|42p01/, 'База данных ещё не настроена. Выполните файл supabase_problems_setup.sql в Supabase → SQL Editor.'],
    [/bucket not found/, 'Хранилище для фото и видео не создано. Выполните файл supabase_storage_setup.sql в Supabase → SQL Editor.'],
    [/row-level security|violates row|42501|permission denied|not authorized|unauthorized/, 'Недостаточно прав. Выйдите из аккаунта и войдите снова.'],
    [/jwt|not authenticated|invalid token|session/, 'Сессия устарела. Войдите в аккаунт снова.'],
    [/failed to fetch|networkerror|network request failed|load failed|fetch failed/, 'Нет соединения с сервером. Проверьте интернет и попробуйте ещё раз.'],
    [/payload too large|exceeded the maximum|too large|413/, 'Файл слишком большой.'],
    [/mime type|not supported|invalid file/, 'Этот тип файла не поддерживается.'],
    [/foreign key|23503/, 'Выбранная категория не найдена. Обновите страницу.'],
    [/duplicate key|already exists|23505/, 'Такая запись уже есть.'],
    [/invalid login credentials/, 'Неверное имя пользователя или пароль.'],
    [/user already registered|already been registered/, 'Пользователь с таким именем уже существует.'],
    [/password should be at least|weak password|password.*characters/, 'Пароль слишком короткий: нужно не менее 6 символов.'],
    [/rate limit|too many requests|429|over_request_rate_limit/, 'Слишком много попыток. Подождите немного и повторите.'],
    [/email not confirmed/, 'В Supabase включено подтверждение почты. Отключите его в Authentication → Providers → Email.'],
    [/signups? (not allowed|are disabled)|signup is disabled/, 'Регистрация отключена в настройках Supabase.'],
    [/timeout|timed out/, 'Сервер долго не отвечает. Попробуйте ещё раз.']
  ];
  for (const [re, ru] of rules) {
    if (re.test(text) || (code && re.test(code.toLowerCase()))) return ru;
  }
  if (raw) console.error('Необработанная ошибка:', err);
  return fallback || 'Что-то пошло не так. Попробуйте ещё раз.';
};
