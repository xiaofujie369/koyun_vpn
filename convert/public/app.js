'use strict';

const I18N = {
  zh: { title: '订阅文件转换', subtitle: '把订阅链接转换成 Koyun 可导入的本地文件', label: '订阅链接', placeholder: '粘贴您的订阅链接', convert: '开始转换', converting: '转换中…', download: '下载文件', copy: '复制内容', copied: '已复制', copyFail: '复制失败，请改用下载文件', summary: '转换成功，共 {n} 个节点', used: '已用 {used} / 共 {total}', expire: '到期 {date}', step1: '下载文件，或复制内容', step2: '打开 Koyun，进入「导入本地文件」', step3: '拖入文件，或粘贴内容后点击导入', privacy: '服务器不保存您的链接和节点。文件里含有连接密钥，请不要发给别人。', err_link: '这不是有效的订阅链接，请到官网用户中心复制', err_unavailable: '订阅不可用：链接已失效、套餐已到期或流量已用完', err_empty: '当前订阅没有可用节点', err_rate: '操作太频繁，请 1 分钟后再试', err_upstream: '服务器暂时取不到订阅，请稍后再试', err_network: '网络连接失败，请稍后再试' },
  zh_Hant: { title: '訂閱檔案轉換', subtitle: '把訂閱連結轉換成 Koyun 可匯入的本機檔案', label: '訂閱連結', placeholder: '貼上您的訂閱連結', convert: '開始轉換', converting: '轉換中…', download: '下載檔案', copy: '複製內容', copied: '已複製', copyFail: '複製失敗，請改用下載檔案', summary: '轉換成功，共 {n} 個節點', used: '已用 {used} / 共 {total}', expire: '到期 {date}', step1: '下載檔案，或複製內容', step2: '開啟 Koyun，進入「匯入本機檔案」', step3: '拖入檔案，或貼上內容後點擊匯入', privacy: '伺服器不保存您的連結和節點。檔案含有連線金鑰，請勿傳給他人。', err_link: '這不是有效的訂閱連結，請到官網使用者中心複製', err_unavailable: '訂閱不可用：連結已失效、方案已到期或流量已用完', err_empty: '目前訂閱沒有可用節點', err_rate: '操作太頻繁，請 1 分鐘後再試', err_upstream: '伺服器暫時取不到訂閱，請稍後再試', err_network: '網路連線失敗，請稍後再試' },
  en: { title: 'Subscription file converter', subtitle: 'Turn your subscription link into a local file for Koyun', label: 'Subscription link', placeholder: 'Paste your subscription link', convert: 'Convert', converting: 'Converting…', download: 'Download file', copy: 'Copy content', copied: 'Copied', copyFail: 'Copy failed. Please download the file instead', summary: 'Done: {n} servers', used: '{used} used of {total}', expire: 'Expires {date}', step1: 'Download the file or copy the content', step2: 'Open Koyun and go to "Import local file"', step3: 'Drop the file in, or paste the content and tap Import', privacy: 'The server does not keep your link or servers. The file contains connection keys, so do not share it.', err_link: 'This is not a valid subscription link. Copy it from your account page', err_unavailable: 'Subscription unavailable: the link is invalid, the plan has expired or the data is used up', err_empty: 'This subscription has no available servers', err_rate: 'Too many attempts. Try again in a minute', err_upstream: 'The server cannot get the subscription right now. Try again later', err_network: 'Network error. Try again later' },
  ja: { title: 'サブスクリプション変換', subtitle: 'リンクを Koyun で読み込めるローカルファイルに変換します', label: 'サブスクリプションリンク', placeholder: 'リンクを貼り付け', convert: '変換する', converting: '変換中…', download: 'ファイルをダウンロード', copy: '内容をコピー', copied: 'コピーしました', copyFail: 'コピーできませんでした。ファイルをダウンロードしてください', summary: '完了：{n} サーバー', used: '使用量 {used} / {total}', expire: '期限 {date}', step1: 'ファイルをダウンロード、または内容をコピー', step2: 'Koyun で「ローカルファイルをインポート」を開く', step3: 'ファイルをドロップ、または内容を貼り付けてインポート', privacy: 'サーバーはリンクやノードを保存しません。ファイルには接続キーが含まれるため、他人に渡さないでください。', err_link: '有効なリンクではありません。アカウントページからコピーしてください', err_unavailable: '利用できません：リンクが無効、プラン期限切れ、またはデータ使用済みです', err_empty: '利用可能なサーバーがありません', err_rate: '試行回数が多すぎます。1 分後にお試しください', err_upstream: '現在サブスクリプションを取得できません。後でお試しください', err_network: 'ネットワークエラーです。後でお試しください' },
  ko: { title: '구독 파일 변환', subtitle: '구독 링크를 Koyun용 로컬 파일로 변환합니다', label: '구독 링크', placeholder: '구독 링크 붙여넣기', convert: '변환', converting: '변환 중…', download: '파일 다운로드', copy: '내용 복사', copied: '복사됨', copyFail: '복사하지 못했습니다. 파일을 다운로드하세요', summary: '완료: 서버 {n}개', used: '사용 {used} / 전체 {total}', expire: '만료 {date}', step1: '파일을 다운로드하거나 내용을 복사', step2: 'Koyun에서 "로컬 파일 가져오기" 열기', step3: '파일을 끌어다 놓거나 내용을 붙여넣고 가져오기', privacy: '서버는 링크와 서버 정보를 저장하지 않습니다. 파일에 연결 키가 있으니 다른 사람에게 보내지 마세요.', err_link: '유효한 구독 링크가 아닙니다. 계정 페이지에서 복사하세요', err_unavailable: '구독 사용 불가: 링크 무효, 요금제 만료 또는 데이터 소진', err_empty: '사용 가능한 서버가 없습니다', err_rate: '시도가 너무 많습니다. 1분 후 다시 시도하세요', err_upstream: '지금은 구독을 가져올 수 없습니다. 나중에 다시 시도하세요', err_network: '네트워크 오류입니다. 나중에 다시 시도하세요' },
  ru: { title: 'Конвертер подписки', subtitle: 'Превратите ссылку подписки в локальный файл для Koyun', label: 'Ссылка подписки', placeholder: 'Вставьте ссылку подписки', convert: 'Конвертировать', converting: 'Конвертация…', download: 'Скачать файл', copy: 'Скопировать', copied: 'Скопировано', copyFail: 'Не удалось скопировать. Скачайте файл', summary: 'Готово: серверов {n}', used: 'Использовано {used} из {total}', expire: 'Истекает {date}', step1: 'Скачайте файл или скопируйте содержимое', step2: 'Откройте Koyun и выберите «Импорт файла»', step3: 'Перетащите файл или вставьте содержимое и нажмите «Импортировать»', privacy: 'Сервер не хранит вашу ссылку и серверы. В файле есть ключи подключения, не передавайте его другим.', err_link: 'Это недействительная ссылка. Скопируйте её в личном кабинете', err_unavailable: 'Подписка недоступна: ссылка недействительна, тариф истёк или трафик исчерпан', err_empty: 'В подписке нет доступных серверов', err_rate: 'Слишком много попыток. Повторите через минуту', err_upstream: 'Сейчас не удаётся получить подписку. Повторите позже', err_network: 'Ошибка сети. Повторите позже' },
  vi: { title: 'Chuyển đổi đăng ký', subtitle: 'Chuyển liên kết đăng ký thành tệp cục bộ cho Koyun', label: 'Liên kết đăng ký', placeholder: 'Dán liên kết đăng ký', convert: 'Chuyển đổi', converting: 'Đang chuyển đổi…', download: 'Tải tệp', copy: 'Sao chép nội dung', copied: 'Đã sao chép', copyFail: 'Không sao chép được. Hãy tải tệp', summary: 'Xong: {n} máy chủ', used: 'Đã dùng {used} / {total}', expire: 'Hết hạn {date}', step1: 'Tải tệp hoặc sao chép nội dung', step2: 'Mở Koyun, vào "Nhập tệp cục bộ"', step3: 'Kéo tệp vào, hoặc dán nội dung rồi bấm Nhập', privacy: 'Máy chủ không lưu liên kết và máy chủ của bạn. Tệp có khóa kết nối, đừng gửi cho người khác.', err_link: 'Liên kết không hợp lệ. Hãy sao chép từ trang tài khoản', err_unavailable: 'Không khả dụng: liên kết sai, gói đã hết hạn hoặc hết dung lượng', err_empty: 'Đăng ký không có máy chủ khả dụng', err_rate: 'Thử quá nhiều lần. Hãy thử lại sau 1 phút', err_upstream: 'Hiện không lấy được đăng ký. Hãy thử lại sau', err_network: 'Lỗi mạng. Hãy thử lại sau' },
};

function pickLang() {
  const lang = (navigator.language || 'zh').toLowerCase();
  if (/^zh-(tw|hk|mo|hant)/.test(lang)) return 'zh_Hant';
  const base = lang.split('-')[0];
  return I18N[base] ? base : 'en';
}

const lang = pickLang();
const t = (key, vars) => {
  let s = I18N[lang][key];
  for (const [k, v] of Object.entries(vars || {})) s = s.replace('{' + k + '}', v);
  return s;
};
const $ = (id) => document.getElementById(id);

document.documentElement.lang = lang.replace('_', '-');
document.title = t('title') + ' · Koyun';
document.querySelectorAll('[data-i18n]').forEach((el) => { el.textContent = t(el.dataset.i18n); });
document.querySelectorAll('[data-i18n-placeholder]').forEach((el) => { el.placeholder = t(el.dataset.i18nPlaceholder); });

function formatBytes(n) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let i = 0;
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++; }
  return (i === 0 ? n : n.toFixed(2)) + ' ' + units[i];
}

let current = null;

function showError(code) {
  const key = 'err_' + code;
  $('error').textContent = t(I18N[lang][key] ? key : 'err_upstream');
  $('error').hidden = false;
}

function showResult(data) {
  current = data;
  $('summary').textContent = t('summary', { n: data.count });
  const parts = [];
  if (data.info.total > 0) {
    parts.push(t('used', { used: formatBytes(data.info.upload + data.info.download), total: formatBytes(data.info.total) }));
  }
  if (data.info.expire > 0) {
    parts.push(t('expire', { date: new Date(data.info.expire * 1000).toLocaleDateString() }));
  }
  $('detail').textContent = parts.join(' · ');
  $('detail').hidden = parts.length === 0;
  $('copy').textContent = t('copy');
  $('result').hidden = false;
  $('result').scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

$('form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const link = $('link').value.trim();
  $('error').hidden = true;
  $('result').hidden = true;
  current = null;
  if (!link) { showError('link'); return; }
  const btn = $('convert');
  btn.disabled = true;
  btn.textContent = t('converting');
  try {
    const res = await fetch('convert.php', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ link }),
      cache: 'no-store',
    });
    const data = await res.json();
    if (data.ok) showResult(data); else showError(data.error);
  } catch (_) {
    showError('network');
  } finally {
    btn.disabled = false;
    btn.textContent = t('convert');
  }
});

$('download').addEventListener('click', () => {
  if (!current) return;
  const url = URL.createObjectURL(new Blob([current.content], { type: 'application/json' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = current.filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});

$('copy').addEventListener('click', async () => {
  if (!current) return;
  let ok = false;
  try {
    await navigator.clipboard.writeText(current.content);
    ok = true;
  } catch (_) {
    const ta = document.createElement('textarea');
    ta.value = current.content;
    document.body.appendChild(ta);
    ta.select();
    try { ok = document.execCommand('copy'); } catch (_) { ok = false; }
    ta.remove();
  }
  $('copy').textContent = t(ok ? 'copied' : 'copyFail');
});
