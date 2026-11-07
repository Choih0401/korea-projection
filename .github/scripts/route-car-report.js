// 새 "차량 제보" 이슈를 같은 차종의 📌 차종 이슈로 옮긴다(.github/workflows/route-car-report.yml이 부른다).
// 내비 화면의 QR은 늘 새 이슈 양식을 연다(GitHub는 링크로 댓글을 미리 채울 수 없다). 그래서 이슈가 생긴 뒤
// 여기서 옮긴다: 제목·본문의 펌웨어 코드(예 DEPEHEV.KOR…)로 열린 차종 이슈를 찾고, 있으면 본문(첨부 링크 포함)을
// 그 이슈에 댓글로 옮기고 새 이슈는 안내 댓글과 함께 닫는다. 없으면(새 차종) 라벨만 붙이고 열어 둔다.
// 이슈 내용은 사용자가 쓴 것이므로 코드로 실행하지 않고 글로만 옮긴다.

const MODEL_LABEL = '📌 차종 이슈';
const NEW_LABEL = '🆕 새 차종';
const MOVED_LABEL = '↪ 차종 이슈로 옮김';
const TITLE_PREFIX = '차량 제보';
// 펌웨어 코드: 영문 대문자·숫자·밑줄, 뒤에 ".KOR."
const CODE_RE = /([A-Z0-9_]{2,20})\.KOR\./;

/** 제목, 없으면 본문에서 펌웨어 코드를 찾는다 */
function findCode(title, body) {
  const m = CODE_RE.exec(title || '') || CODE_RE.exec(body || '');
  return m ? m[1] : null;
}

/** 차종 이슈 제목의 끝 "· CODE"가 code와 같은가 */
function modelMatches(title, code) {
  const m = /·\s*([A-Z0-9_]+)\s*$/.exec(title || '');
  return !!m && m[1] === code;
}

/** 차종 이슈에 남길 댓글 */
function movedComment(issue) {
  const who = issue.user && issue.user.login ? `@${issue.user.login}` : '차주';
  return [
    `**${who} 님의 제보** (원래 #${issue.number}, 자동으로 옮김)`,
    '',
    `> 제목: ${(issue.title || '').replace(/\r?\n/g, ' ')}`,
    '',
    issue.body || '(본문 없음)',
  ].join('\n');
}

/** 새 이슈에 남길 안내 */
function closeComment(modelNumber) {
  return [
    `제보해 주셔서 감사합니다. 같은 차종의 제보는 한곳에 모읍니다. 이 내용을 #${modelNumber} 에 옮겼습니다.`,
    '',
    `**파일이나 추가 내용은 #${modelNumber} 에 댓글로 남겨 주세요.** 이 이슈는 닫지만, 여기에 단 댓글도 확인합니다.`,
  ].join('\n');
}

async function route({ github, context, core }) {
  const issue = context.payload.issue;
  const { owner, repo } = context.repo;
  if (!issue || issue.pull_request) return 'skip: not an issue';
  if (!(issue.title || '').startsWith(TITLE_PREFIX)) return 'skip: not a car report';
  const labels = (issue.labels || []).map((l) => (typeof l === 'string' ? l : l.name));
  if (labels.includes(MODEL_LABEL)) return 'skip: model issue';

  const code = findCode(issue.title, issue.body);
  if (!code) {
    core.info(`#${issue.number}: 펌웨어 코드를 찾지 못함`);
    return 'skip: no code';
  }

  const models = await github.paginate(github.rest.issues.listForRepo, {
    owner, repo, state: 'open', labels: MODEL_LABEL, per_page: 100,
  });
  const model = models.find((m) => !m.pull_request && m.number !== issue.number && modelMatches(m.title, code));

  if (!model) {
    await github.rest.issues.addLabels({ owner, repo, issue_number: issue.number, labels: [NEW_LABEL] });
    core.info(`#${issue.number}: ${code} 차종 이슈 없음 → ${NEW_LABEL}`);
    return `new: ${code}`;
  }

  await github.rest.issues.createComment({ owner, repo, issue_number: model.number, body: movedComment(issue) });
  await github.rest.issues.createComment({ owner, repo, issue_number: issue.number, body: closeComment(model.number) });
  await github.rest.issues.addLabels({ owner, repo, issue_number: issue.number, labels: [MOVED_LABEL] });
  await github.rest.issues.update({ owner, repo, issue_number: issue.number, state: 'closed', state_reason: 'completed' });
  core.info(`#${issue.number}: ${code} → #${model.number}`);
  return `moved: ${code} -> #${model.number}`;
}

module.exports = route;
module.exports.findCode = findCode;
module.exports.modelMatches = modelMatches;
module.exports.movedComment = movedComment;
module.exports.closeComment = closeComment;
