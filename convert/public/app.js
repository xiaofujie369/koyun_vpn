'use strict';

const I18N = {
  zh: { step1_shadowrocket: '点击上方「复制内容」', step1_clash: '点击上方「下载文件」', software: '选择软件', shadowrocket: '小火箭', step2_shadowrocket: '打开小火箭，它会提示从剪贴板添加节点', step3_shadowrocket: '没有提示时，点右上角「+」，选择从剪贴板添加', step2_clash: '打开 FlClash 或 Clash Verge，进入配置页面', step3_clash: '选择导入本地文件，选中下载的文件', title: '订阅文件转换', subtitle: '把订阅链接转换成本地文件', label: '订阅链接', placeholder: '粘贴您的订阅链接', convert: '开始转换', converting: '转换中…', download: '下载文件', copy: '复制内容', copied: '已复制', copyFail: '复制失败，请改用下载文件', summary: '转换成功，共 {n} 个节点', used: '已用 {used} / 共 {total}', expire: '到期 {date}', step1: '下载文件，或复制内容', step2: '打开 Koyun，进入「导入文件或订阅链接」', step3: '拖入文件，或粘贴内容后点击导入', privacy: '服务器不保存您的链接和节点。文件里含有连接密钥和订阅地址，别人拿到后可以持续使用，请不要外传；如已泄露，请到官网重置订阅。', err_link: '这不是有效的订阅链接，请到官网用户中心复制', err_unavailable: '订阅不可用：链接已失效、套餐已到期或流量已用完', err_empty: '当前订阅没有可用节点', err_rate: '操作太频繁，请 1 分钟后再试', err_upstream: '服务器暂时取不到订阅，请稍后再试', err_network: '网络连接失败，请稍后再试' },
  zh_Hant: { step1_shadowrocket: '點擊上方「複製內容」', step1_clash: '點擊上方「下載檔案」', software: '選擇軟體', shadowrocket: '小火箭', step2_shadowrocket: '開啟小火箭，它會提示從剪貼簿新增節點', step3_shadowrocket: '沒有提示時，點右上角「+」，選擇從剪貼簿新增', step2_clash: '開啟 FlClash 或 Clash Verge，進入設定檔頁面', step3_clash: '選擇匯入本機檔案，選取下載的檔案', title: '訂閱檔案轉換', subtitle: '把訂閱連結轉換成本機檔案', label: '訂閱連結', placeholder: '貼上您的訂閱連結', convert: '開始轉換', converting: '轉換中…', download: '下載檔案', copy: '複製內容', copied: '已複製', copyFail: '複製失敗，請改用下載檔案', summary: '轉換成功，共 {n} 個節點', used: '已用 {used} / 共 {total}', expire: '到期 {date}', step1: '下載檔案，或複製內容', step2: '開啟 Koyun，進入「匯入檔案或訂閱連結」', step3: '拖入檔案，或貼上內容後點擊匯入', privacy: '伺服器不保存您的連結和節點。檔案含有連線金鑰和訂閱位址，他人取得後可持續使用，請勿外傳；如已外洩，請到官網重設訂閱。', err_link: '這不是有效的訂閱連結，請到官網使用者中心複製', err_unavailable: '訂閱不可用：連結已失效、方案已到期或流量已用完', err_empty: '目前訂閱沒有可用節點', err_rate: '操作太頻繁，請 1 分鐘後再試', err_upstream: '伺服器暫時取不到訂閱，請稍後再試', err_network: '網路連線失敗，請稍後再試' },
  en: { step1_shadowrocket: 'Tap "Copy content" above', step1_clash: 'Click "Download file" above', software: 'Choose your app', shadowrocket: 'Shadowrocket', step2_shadowrocket: 'Open Shadowrocket. It will offer to add servers from the clipboard', step3_shadowrocket: 'If it does not, tap "+" at the top right and add from the clipboard', step2_clash: 'Open FlClash or Clash Verge and go to Profiles', step3_clash: 'Import a local file and choose the downloaded file', title: 'Subscription file converter', subtitle: 'Turn your subscription link into a local file', label: 'Subscription link', placeholder: 'Paste your subscription link', convert: 'Convert', converting: 'Converting…', download: 'Download file', copy: 'Copy content', copied: 'Copied', copyFail: 'Copy failed. Please download the file instead', summary: 'Done: {n} servers', used: '{used} used of {total}', expire: 'Expires {date}', step1: 'Download the file or copy the content', step2: 'Open Koyun and go to "Import file or link"', step3: 'Drop the file in, or paste the content and tap Import', privacy: 'The server does not keep your link or servers. The file contains connection keys and your subscription address, so anyone who gets it can keep using it. Do not share it. If it leaks, reset your subscription on the website.', err_link: 'This is not a valid subscription link. Copy it from your account page', err_unavailable: 'Subscription unavailable: the link is invalid, the plan has expired or the data is used up', err_empty: 'This subscription has no available servers', err_rate: 'Too many attempts. Try again in a minute', err_upstream: 'The server cannot get the subscription right now. Try again later', err_network: 'Network error. Try again later' },
  ja: { step1_shadowrocket: '上の「内容をコピー」を押す', step1_clash: '上の「ファイルをダウンロード」を押す', software: 'アプリを選択', shadowrocket: 'Shadowrocket', step2_shadowrocket: 'Shadowrocket を開くと、クリップボードからの追加を提案します', step3_shadowrocket: '表示されない場合は右上の「+」からクリップボードの内容を追加します', step2_clash: 'FlClash または Clash Verge でプロファイル画面を開く', step3_clash: 'ローカルファイルのインポートでダウンロードしたファイルを選択', title: 'サブスクリプション変換', subtitle: 'リンクをローカルファイルに変換します', label: 'サブスクリプションリンク', placeholder: 'リンクを貼り付け', convert: '変換する', converting: '変換中…', download: 'ファイルをダウンロード', copy: '内容をコピー', copied: 'コピーしました', copyFail: 'コピーできませんでした。ファイルをダウンロードしてください', summary: '完了：{n} サーバー', used: '使用量 {used} / {total}', expire: '期限 {date}', step1: 'ファイルをダウンロード、または内容をコピー', step2: 'Koyun で「ファイルまたはリンクをインポート」を開く', step3: 'ファイルをドロップ、または内容を貼り付けてインポート', privacy: 'サーバーはリンクやノードを保存しません。ファイルには接続キーとサブスクリプションアドレスが含まれ、入手した人は使い続けられます。他人に渡さないでください。漏れた場合は公式サイトでリセットしてください。', err_link: '有効なリンクではありません。アカウントページからコピーしてください', err_unavailable: '利用できません：リンクが無効、プラン期限切れ、またはデータ使用済みです', err_empty: '利用可能なサーバーがありません', err_rate: '試行回数が多すぎます。1 分後にお試しください', err_upstream: '現在サブスクリプションを取得できません。後でお試しください', err_network: 'ネットワークエラーです。後でお試しください' },
  ko: { step1_shadowrocket: '위의 "내용 복사"를 누르세요', step1_clash: '위의 "파일 다운로드"를 누르세요', software: '앱 선택', shadowrocket: 'Shadowrocket', step2_shadowrocket: 'Shadowrocket을 열면 클립보드에서 추가하라는 안내가 나옵니다', step3_shadowrocket: '안내가 없으면 오른쪽 위 "+"에서 클립보드 내용을 추가하세요', step2_clash: 'FlClash 또는 Clash Verge에서 프로필 화면을 여세요', step3_clash: '로컬 파일 가져오기에서 다운로드한 파일을 선택하세요', title: '구독 파일 변환', subtitle: '구독 링크를 로컬 파일로 변환합니다', label: '구독 링크', placeholder: '구독 링크 붙여넣기', convert: '변환', converting: '변환 중…', download: '파일 다운로드', copy: '내용 복사', copied: '복사됨', copyFail: '복사하지 못했습니다. 파일을 다운로드하세요', summary: '완료: 서버 {n}개', used: '사용 {used} / 전체 {total}', expire: '만료 {date}', step1: '파일을 다운로드하거나 내용을 복사', step2: 'Koyun에서 "파일 또는 링크 가져오기" 열기', step3: '파일을 끌어다 놓거나 내용을 붙여넣고 가져오기', privacy: '서버는 링크와 서버 정보를 저장하지 않습니다. 파일에 연결 키와 구독 주소가 있어 다른 사람이 계속 사용할 수 있으니 공유하지 마세요. 유출되면 웹사이트에서 구독을 재설정하세요.', err_link: '유효한 구독 링크가 아닙니다. 계정 페이지에서 복사하세요', err_unavailable: '구독 사용 불가: 링크 무효, 요금제 만료 또는 데이터 소진', err_empty: '사용 가능한 서버가 없습니다', err_rate: '시도가 너무 많습니다. 1분 후 다시 시도하세요', err_upstream: '지금은 구독을 가져올 수 없습니다. 나중에 다시 시도하세요', err_network: '네트워크 오류입니다. 나중에 다시 시도하세요' },
  ru: { step1_shadowrocket: 'Нажмите «Скопировать» выше', step1_clash: 'Нажмите «Скачать файл» выше', software: 'Выберите приложение', shadowrocket: 'Shadowrocket', step2_shadowrocket: 'Откройте Shadowrocket: он предложит добавить серверы из буфера обмена', step3_shadowrocket: 'Если этого нет, нажмите «+» вверху справа и добавьте из буфера обмена', step2_clash: 'Откройте FlClash или Clash Verge и перейдите в профили', step3_clash: 'Импортируйте локальный файл и выберите скачанный файл', title: 'Конвертер подписки', subtitle: 'Превратите ссылку подписки в локальный файл', label: 'Ссылка подписки', placeholder: 'Вставьте ссылку подписки', convert: 'Конвертировать', converting: 'Конвертация…', download: 'Скачать файл', copy: 'Скопировать', copied: 'Скопировано', copyFail: 'Не удалось скопировать. Скачайте файл', summary: 'Готово: серверов {n}', used: 'Использовано {used} из {total}', expire: 'Истекает {date}', step1: 'Скачайте файл или скопируйте содержимое', step2: 'Откройте Koyun и выберите «Импорт файла или ссылки»', step3: 'Перетащите файл или вставьте содержимое и нажмите «Импортировать»', privacy: 'Сервер не хранит вашу ссылку и серверы. В файле есть ключи подключения и адрес подписки: получивший его сможет пользоваться им и дальше. Не передавайте его другим. При утечке сбросьте подписку на сайте.', err_link: 'Это недействительная ссылка. Скопируйте её в личном кабинете', err_unavailable: 'Подписка недоступна: ссылка недействительна, тариф истёк или трафик исчерпан', err_empty: 'В подписке нет доступных серверов', err_rate: 'Слишком много попыток. Повторите через минуту', err_upstream: 'Сейчас не удаётся получить подписку. Повторите позже', err_network: 'Ошибка сети. Повторите позже' },
  vi: { step1_shadowrocket: 'Bấm "Sao chép nội dung" ở trên', step1_clash: 'Bấm "Tải tệp" ở trên', software: 'Chọn ứng dụng', shadowrocket: 'Shadowrocket', step2_shadowrocket: 'Mở Shadowrocket, ứng dụng sẽ đề nghị thêm máy chủ từ bộ nhớ tạm', step3_shadowrocket: 'Nếu không thấy, bấm "+" ở góc trên bên phải và thêm từ bộ nhớ tạm', step2_clash: 'Mở FlClash hoặc Clash Verge và vào mục cấu hình', step3_clash: 'Nhập tệp cục bộ và chọn tệp đã tải', title: 'Chuyển đổi đăng ký', subtitle: 'Chuyển liên kết đăng ký thành tệp cục bộ', label: 'Liên kết đăng ký', placeholder: 'Dán liên kết đăng ký', convert: 'Chuyển đổi', converting: 'Đang chuyển đổi…', download: 'Tải tệp', copy: 'Sao chép nội dung', copied: 'Đã sao chép', copyFail: 'Không sao chép được. Hãy tải tệp', summary: 'Xong: {n} máy chủ', used: 'Đã dùng {used} / {total}', expire: 'Hết hạn {date}', step1: 'Tải tệp hoặc sao chép nội dung', step2: 'Mở Koyun, vào "Nhập tệp hoặc liên kết"', step3: 'Kéo tệp vào, hoặc dán nội dung rồi bấm Nhập', privacy: 'Máy chủ không lưu liên kết và máy chủ của bạn. Tệp có khóa kết nối và địa chỉ đăng ký, người có tệp có thể tiếp tục sử dụng. Đừng chia sẻ. Nếu bị lộ, hãy đặt lại đăng ký trên trang web.', err_link: 'Liên kết không hợp lệ. Hãy sao chép từ trang tài khoản', err_unavailable: 'Không khả dụng: liên kết sai, gói đã hết hạn hoặc hết dung lượng', err_empty: 'Đăng ký không có máy chủ khả dụng', err_rate: 'Thử quá nhiều lần. Hãy thử lại sau 1 phút', err_upstream: 'Hiện không lấy được đăng ký. Hãy thử lại sau', err_network: 'Lỗi mạng. Hãy thử lại sau' },
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

const selectedFormat = () => $('format').value;

function showSteps() {
  const f = selectedFormat();
  $('step1').textContent = t(f === 'koyun' ? 'step1' : 'step1_' + f);
  $('step2').textContent = t(f === 'koyun' ? 'step2' : 'step2_' + f);
  $('step3').textContent = t(f === 'koyun' ? 'step3' : 'step3_' + f);
}

// 换软件后旧结果就不对了，收起来让客户重新转换
$('format').addEventListener('change', () => {
  current = null;
  $('result').hidden = true;
  $('error').hidden = true;
});

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
  showSteps();
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
      body: JSON.stringify({ link, format: selectedFormat() }),
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
  const url = URL.createObjectURL(new Blob([current.content], { type: 'application/octet-stream' }));
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
