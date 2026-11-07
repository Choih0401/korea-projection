// .github/scripts/route-car-report.js를 가짜 GitHub로 시험한다. 실행: node tests/route-car-report-test.js
const path = require('path');
const route = require(path.join(__dirname, '..', '.github', 'scripts', 'route-car-report.js'));

let fails = 0;
function check(name, ok) {
  console.log((ok ? 'ok   ' : 'FAIL ') + name);
  if (!ok) fails++;
}

function fakeGithub(models) {
  const calls = [];
  const rest = {
    issues: {
      listForRepo: async (args) => { calls.push(['list', args]); return { data: models }; },
      addLabels: async (args) => { calls.push(['label', args]); },
      createComment: async (args) => { calls.push(['comment', args]); },
      update: async (args) => { calls.push(['update', args]); },
    },
  };
  return {
    calls,
    rest,
    paginate: async (fn, args) => (await fn(args)).data,
  };
}
const core = { info: () => {} };
const ctx = (issue) => ({ payload: { issue }, repo: { owner: 'StopDragon', repo: 'korea-projection' } });
const models = [
  { number: 101, title: '📌 기아 니로 2020 하이브리드 (DE PE) · DEPEHEV' },
  { number: 102, title: '📌 기아 니로 2020 플러그인 하이브리드 (DE) · DEPEPHEV' },
  { number: 103, title: '📌 현대 팰리세이드 2023 (LX2 PE) · LX2_PE' },
];

(async () => {
  check('펌웨어 코드: 제목에서', route.findCode('차량 제보: DEPEHEV.KOR.0000.V039.001.260902', '') === 'DEPEHEV');
  check('  제목에 없으면 본문에서', route.findCode('차량 제보: 니로', '버전 DEPEPHEV.KOR.0000.V039') === 'DEPEPHEV');
  check('  밑줄 코드(LX2_PE)', route.findCode('차량 제보: LX2_PE.KOR.S5W_M.V039.001.260902', '') === 'LX2_PE');
  check('  없으면 null', route.findCode('차량 제보: 그랜저', '모름') === null);
  check('차종 이슈 제목 끝 코드가 정확히 같을 때만(DEPEHEV ≠ DEPEPHEV)', route.modelMatches(models[0].title, 'DEPEHEV') && !route.modelMatches(models[1].title, 'DEPEHEV'));

  // 1. 차종 이슈가 있는 차: 옮기고 닫음
  let g = fakeGithub(models);
  const issue = { number: 57, title: '차량 제보: DEPEHEV.KOR.0000.V039.001.260902', body: '### 결과\n\n연결됨\n\n[3-log.txt](https://github.com/user-attachments/files/1/3-log.txt)', user: { login: 'tester' }, labels: [{ name: '차량 제보' }] };
  let r = await route({ github: g, context: ctx(issue), core });
  const comments = g.calls.filter((c) => c[0] === 'comment');
  check('차종 이슈가 있으면 옮김', r === 'moved: DEPEHEV -> #101');
  check('  차종 이슈(#101)에 본문·첨부 링크·원래 번호·작성자를 댓글로', comments[0][1].issue_number === 101 && comments[0][1].body.includes('user-attachments/files/1/3-log.txt') && comments[0][1].body.includes('#57') && comments[0][1].body.includes('@tester'));
  check('  새 이슈(#57)에 안내 댓글, 옮김 라벨, 닫기(completed)', comments[1][1].issue_number === 57 && comments[1][1].body.includes('#101') && g.calls.some((c) => c[0] === 'label' && c[1].labels[0] === '↪ 차종 이슈로 옮김') && g.calls.some((c) => c[0] === 'update' && c[1].state === 'closed' && c[1].state_reason === 'completed'));
  check('  열린 📌 차종 이슈만 찾음', g.calls[0][0] === 'list' && g.calls[0][1].labels === '📌 차종 이슈' && g.calls[0][1].state === 'open');

  // 2. 새 차종: 라벨만, 닫지 않음
  g = fakeGithub(models);
  r = await route({ github: g, context: ctx({ number: 58, title: '차량 제보: CN7NPE.KOR.S5W_M.V039.001.260902', body: '', user: { login: 'x' }, labels: [] }), core });
  check('차종 이슈가 없으면 🆕 새 차종 라벨만, 댓글·닫기 없음', r === 'new: CN7NPE' && g.calls.some((c) => c[0] === 'label' && c[1].labels[0] === '🆕 새 차종') && !g.calls.some((c) => c[0] === 'comment' || c[0] === 'update'));

  // 3. 건너뛰기
  g = fakeGithub(models);
  r = await route({ github: g, context: ctx({ number: 59, title: '질문: 설치가 안 돼요', body: 'DEPEHEV.KOR.', labels: [] }), core });
  check('차량 제보가 아닌 이슈(질문)는 건드리지 않음', r === 'skip: not a car report' && g.calls.length === 0);
  r = await route({ github: g, context: ctx({ number: 60, title: '차량 제보: 그랜저', body: '버전 모름', labels: [] }), core });
  check('펌웨어 코드가 없으면 건드리지 않음', r === 'skip: no code' && g.calls.length === 0);
  r = await route({ github: g, context: ctx({ number: 61, title: '차량 제보: DEPEHEV.KOR.x', body: '', labels: [{ name: '📌 차종 이슈' }] }), core });
  check('차종 이슈 자신은 건드리지 않음', r === 'skip: model issue' && g.calls.length === 0);
  r = await route({ github: g, context: ctx({ number: 62, title: '차량 제보: DEPEHEV.KOR.x', pull_request: {} }), core });
  check('PR은 건드리지 않음', r === 'skip: not an issue');

  console.log(fails === 0 ? '모두 통과' : `실패 ${fails}개`);
  process.exit(fails === 0 ? 0 : 1);
})();
