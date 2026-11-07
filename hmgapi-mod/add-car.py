#!/usr/bin/env python3
"""새 한국 차를 "시험 지원"으로 추가한다 (PC에서만 실행, 차에서는 돌리지 않는다).

차주가 GitHub 이슈에 올린 제보 폴더(KoreaProjection-report)의 파일 두 개로 다음을 만든다.
  - 2-car-report.json (HMG-API Car Report): 그 차에서 직접 찾은 훅 지점 → HMG-API 지도
  - 1-report.md (Korea Projection 리포트): 순정 파일 체크섬 13개 → 무선 모드 패치 세트
그리고 다음을 고친다.
  1. nemesis-pkg/korea.projection/hmgapi/maps/<제조사>/<차종>/<지역>/<펌웨어>/  (지도)
  2. mod-kor/wireless-carplay-aa/ (한국 차 빌드 모드 소스): mod.json system, patches.json cars, patches/<세트>/
     - 순정 체크섬이 이미 있는 세트와 똑같으면 그 세트를 같이 쓴다(새 세트를 만들지 않음).
  3. 모드를 개발 키로 서명해 nemesis-pkg/korea.projection/hmgapi/wireless-carplay-aa.zip을 바꾸고,
     svc/hotspot.sh의 MOD_MD5와 CARS_TRY(시험 지원 차 목록)를 고친다.
버전 올리기, README 지원 목록(🧪 시험 중), 테스트, 리뷰, 공개는 사람이 한다(마지막에 안내).

사용:
  python3 -I scripts/add-car.py <제보 폴더> --make hyundai --dir sonata --name "Hyundai Sonata Hybrid (DN8)"
  python3 -I scripts/add-car.py <제보 폴더> ... --check     # 바꾸지 않고 읽은 값만 보여 준다
  python3 -I scripts/add-car.py --sign-only                 # 모드 소스만 다시 서명해 패키지에 넣는다
옵션:
  --set <이름>   새 패치 세트 이름(기본: 모델 코드 소문자, 예 dn822hev)
  --key <파일>   모드 서명 키(기본 niro-carplay-build/devkey). 키 내용은 출력하지 않는다.
  --hmgapi <폴더> 서명에 쓸 HMG-API 소스(기본 niro-carplay-build/pr22-rebase). 복사본에서 서명한다.
"""
import argparse, hashlib, json, os, re, shutil, subprocess, sys, tempfile

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # niro-carplay-build
MOD_ID = 'wireless-carplay-aa'
# 1-report.md "순정 파일 체크섬" 칸의 파일 순서 = 패치 세트 stock의 순서(bin/status.sh와 같아야 한다)
STOCK = ['HKMC_DiPO.apk', 'HKMC_DiPO.odex', 'HKMC_GPM.apk', 'HKMC_GPM.odex', 'HKMC_Navi_ExSL.apk',
         'HKMC_Navi_ExSL.odex', 'Iap2ServerApp.apk', 'Iap2ServerApp.odex', 'libautoreceiver_infobank.so',
         'libCarPlayCore.so', 'libCarPlayAudio.so', 'libCarPlayUtils.so', 'HKMC_BtSettings.apk']


def die(msg):
    sys.exit('멈춤: ' + msg)


def paths(root):
    pkg = os.path.join(root, 'nemesis-pkg', 'korea.projection')
    return {
        'pkg': pkg,
        'maps': os.path.join(pkg, 'hmgapi', 'maps'),
        'zip': os.path.join(pkg, 'hmgapi', MOD_ID + '.zip'),
        'hotspot': os.path.join(pkg, 'svc', 'hotspot.sh'),
        'mod': os.path.join(root, 'mod-kor', MOD_ID),
    }


def read_car_report(f):
    r = json.load(open(f, encoding='utf-8'))
    if r.get('report') != 'hmgapi car report 1' or 'map_car' not in r:
        die('%s: HMG-API Car Report(지도 결과 포함)가 아닙니다' % f)
    u = r['unit']
    for k in ('model', 'region', 'firmware', 'product'):
        if not u.get(k):
            die('Car Report에 %s가 없습니다' % k)
    return r


def read_stock(f):
    """1-report.md의 순정 파일 체크섬 13개. 하나라도 없으면 멈춘다(세트를 만들 수 없음)."""
    text = open(f, encoding='utf-8').read()
    sec = text.split('## 순정 파일 체크섬', 1)
    if len(sec) < 2:
        die('%s에 "순정 파일 체크섬" 칸이 없습니다(Korea Projection 1.5.1 이상 리포트가 필요)' % f)
    got = {}
    for line in sec[1].split('\n## ', 1)[0].splitlines():
        m = re.match(r'^(\S+) ([0-9a-f]{32})\b', line.strip())
        if m:
            got[m.group(1)] = m.group(2)
    miss = [n for n in STOCK if n not in got]
    if miss:
        die('체크섬이 없는 파일: %s (USB를 꽂은 채 Launch로 만든 리포트인지 확인)' % ', '.join(miss))
    return ''.join('%s %s\n' % (n, got[n]) for n in STOCK)


def precheck(rep, args, ps):
    """무엇이든 바꾸기 전에 막힐 일을 모두 본다(중간에 멈춰 반쯤 바뀐 상태가 남지 않게)."""
    u = rep['unit']
    key = '%s.%s.' % (u['model'], u['region'])
    if key in json.load(open(os.path.join(ps['mod'], 'patches.json')))['cars']:
        die('patches.json에 이미 %s가 있습니다(이미 추가된 차)' % key)
    dest = os.path.join(ps['maps'], args.make, args.dir, u['region'].lower(), u['firmware'])
    if os.path.exists(dest):
        die('지도 폴더가 이미 있습니다: %s' % os.path.relpath(dest, args.root))
    for f in (args.key, os.path.join(args.hmgapi, 'tools', 'mkmodpkg.sh'),
              os.path.join(args.hmgapi, 'tools', 'report-map.py'), ps['hotspot']):
        if not os.path.isfile(f):
            die('필요한 파일이 없습니다: %s' % f)
    if args.set and os.path.exists(os.path.join(ps['mod'], 'patches', args.set)):
        die('세트 폴더가 이미 있습니다: patches/%s' % args.set)


def make_map(rep, args, dest_root, hmgapi):
    """HMG-API tools/report-map.py로 지도를 만들고, 니로·쏘나타 지도와 같은 형식으로 맞춘다."""
    u = rep['unit']
    dest = os.path.join(dest_root, args.make, args.dir, u['region'].lower(), u['firmware'])
    if os.path.exists(os.path.join(dest, 'car.json')):
        die('지도가 이미 있습니다: %s' % os.path.relpath(dest, B))
    with tempfile.TemporaryDirectory() as t:
        fixed = dict(rep)
        fixed['unit'] = dict(u, make=args.make.capitalize(), name=args.name)
        rp = os.path.join(t, 'report.json')
        json.dump(fixed, open(rp, 'w'))
        out = os.path.join(t, 'maps')
        subprocess.run([sys.executable, '-I', os.path.join(hmgapi, 'tools', 'report-map.py'), rp, '--maps', out],
                       check=True, stdout=subprocess.DEVNULL)
        src = os.path.join(out, args.make.lower(), u['model'].lower(), u['region'].lower(), u['firmware'])
        cj = os.path.join(src, 'car.json')
        c = json.load(open(cj))
        c['model'] = args.dir
        # report-map.py는 리포트의 not_found를 car.json "missing"으로 옮기지 않는다: 직접 넣는다
        nf = rep['map_car'].get('not_found') or {}
        if nf:
            c['missing'] = dict(sorted(nf.items()))
        order = ['make', 'model', 'name', 'region', 'firmware', 'products', 'status', 'verified',
                 'files', 'apps', 'app_files', 'missing', 'by_reference']
        c = {k: c[k] for k in order if k in c}
        with open(cj, 'w') as f:
            json.dump(c, f, indent=2)
            f.write('\n')
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copytree(src, dest)
    for f in os.listdir(dest):
        os.chmod(os.path.join(dest, f), 0o700)   # 니로 지도와 같은 권한(차에서 다시 700으로 맞춘다)
    return dest


def edit_mod(rep, stock, args, mod):
    """모드 소스에 이 차를 더한다. 세트 이름을 돌려준다."""
    u = rep['unit']
    model, region, fw = u['model'], u['region'], u['firmware']
    pj_path, mj_path = os.path.join(mod, 'patches.json'), os.path.join(mod, 'mod.json')
    pj, mj = json.load(open(pj_path)), json.load(open(mj_path))
    key = '%s.%s.' % (model, region)
    if key in pj['cars']:
        die('patches.json에 이미 %s가 있습니다' % key)
    # 같은 순정 파일이면 기존 세트를 같이 쓴다
    st = None
    for s in sorted(set(pj['cars'].values())):
        p = os.path.join(mod, 'patches', s, 'stock')
        if os.path.isfile(p) and open(p).read() == stock:
            st = s
            print('순정 체크섬이 기존 세트 %s와 같아서 그 세트를 같이 씁니다' % s)
    if st is None:
        st = args.set or model.lower()
        d = os.path.join(mod, 'patches', st)
        if os.path.exists(d):
            die('세트 폴더가 이미 있습니다: patches/%s (--set으로 다른 이름을 주세요)' % st)
        os.makedirs(d)
        open(os.path.join(d, 'stock'), 'w').write(stock)
        open(os.path.join(d, 'expect'), 'w').close()      # 니로 세트처럼 빈 파일
    pj['cars'][key] = st
    # system: 같은 지역·펌웨어 항목이 있으면 model에 더하고, 없으면 니로처럼 features 조건 없이 새로 만든다
    for e in mj['system']:
        if e.get('region') == region and e.get('firmware') == fw and 'features' not in e:
            if model not in e['model']:
                e['model'].append(model)
            break
    else:
        mj['system'].append({'model': [model], 'region': region, 'firmware': fw})
    # 원래 파일처럼 들여쓰기 2, 끝 줄바꿈 없음
    for p, j in ((pj_path, pj), (mj_path, mj)):
        open(p, 'w', encoding='utf-8').write(json.dumps(j, indent=2, ensure_ascii=False))
    return st


def sign(ps, args):
    """HMG-API 소스 복사본에서 tools/mkmodpkg.sh로 서명하고 검증한 뒤 패키지에 넣는다. md5를 돌려준다."""
    key = os.path.abspath(args.key)
    if not os.path.isfile(key):
        die('서명 키가 없습니다: %s' % key)
    with tempfile.TemporaryDirectory() as t:
        h = os.path.join(t, 'hmgapi')
        shutil.copytree(args.hmgapi, h, ignore=shutil.ignore_patterns('.git', 'out'))
        m = os.path.join(h, 'mods', MOD_ID)
        shutil.rmtree(m)
        shutil.copytree(ps['mod'], m)      # src/ 없음: hooks.jar는 소스에 든 것을 그대로 쓴다
        r = subprocess.run(['sh', 'tools/mkmodpkg.sh', 'mods/' + MOD_ID, key], cwd=h,
                           capture_output=True, text=True)
        if r.returncode != 0:
            die('서명 실패:\n' + r.stdout + r.stderr)
        z = r.stdout.strip().splitlines()[-1]
        print(r.stdout.strip().splitlines()[-2])     # "ok: wireless-carplay-aa ..." (Signing verify)
        shutil.copyfile(z, ps['zip'])
    md5 = hashlib.md5(open(ps['zip'], 'rb').read()).hexdigest()
    t = open(ps['hotspot'], encoding='utf-8').read()
    t, n = re.subn(r'^MOD_MD5=[0-9a-f]{32}$', 'MOD_MD5=' + md5, t, flags=re.M)
    if n != 1:
        die('hotspot.sh에서 MOD_MD5 줄을 찾지 못했습니다')
    open(ps['hotspot'], 'w', encoding='utf-8').write(t)
    return md5


def add_try(ps, rep):
    u = rep['unit']
    pat = '%s.%s.*.%s' % (u['model'], u['region'], u['firmware'])
    t = open(ps['hotspot'], encoding='utf-8').read()
    m = re.search(r"^CARS_TRY='([^']*)'$", t, flags=re.M)
    if not m:
        die("hotspot.sh에서 CARS_TRY='…' 줄을 찾지 못했습니다")
    items = m.group(1).split()
    if pat in items:
        return pat
    new = "CARS_TRY='%s'" % ' '.join(items + [pat])
    open(ps['hotspot'], 'w', encoding='utf-8').write(t[:m.start()] + new + t[m.end():])
    return pat


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('folder', nargs='?')
    ap.add_argument('--make')
    ap.add_argument('--dir')
    ap.add_argument('--name')
    ap.add_argument('--set')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--sign-only', action='store_true')
    ap.add_argument('--root', default=B, help=argparse.SUPPRESS)        # 테스트용
    ap.add_argument('--key', default=os.path.join(B, 'devkey'))
    ap.add_argument('--hmgapi', default=os.path.join(B, 'pr22-rebase'))
    a = ap.parse_args()
    ps = paths(a.root)
    if a.sign_only:
        print('모드 zip md5', sign(ps, a))
        return
    if not a.folder:
        ap.error('제보 폴더를 주세요')
    rep = read_car_report(os.path.join(a.folder, '2-car-report.json'))
    stock = read_stock(os.path.join(a.folder, '1-report.md'))
    u = rep['unit']
    vm = rep.get('verify_map') or {}
    print('차: %s (모델 %s, 지역 %s, 펌웨어 %s, Wi-Fi 칩 %s)' % (u['product'], u['model'], u['region'],
                                                         u['firmware'], u.get('wifi_chip')))
    print('지도: %d개 지점 찾음, 못 찾음 %s' % (rep['map_car'].get('found', 0), list((rep['map_car'].get('not_found') or {}))))
    print('차에서 지도 확인: %s' % ('통과 (%s개)' % vm.get('points') if vm.get('ok') else '안 함 또는 실패'))
    if not u.get('wifi_chip'):
        print('주의: Wi-Fi 칩이 없다고 나옵니다. 무선 카플레이는 불가능합니다.')
    if a.check:
        return
    if not (a.make and a.dir and a.name):
        ap.error('--make, --dir, --name이 필요합니다 (예: --make hyundai --dir sonata --name "Hyundai Sonata Hybrid (DN8)")')
    precheck(rep, a, ps)
    dest = make_map(rep, a, ps['maps'], a.hmgapi)
    print('지도 만듦:', os.path.relpath(dest, a.root))
    st = edit_mod(rep, stock, a, ps['mod'])
    print('모드 소스에 더함: patches.json "%s.%s." → %s' % (u['model'], u['region'], st))
    print('모드 zip md5', sign(ps, a))
    print('시험 지원 차 목록(CARS_TRY)에 더함:', add_try(ps, rep))
    print('''
다음은 사람이 합니다 (docs/car-onboarding.md):
  1. nemesis-pkg/korea.projection/NEMESIS.data의 package-version 올리기, detailed-desc(256자 이하) 확인
  2. hmgapi/README.txt "지금 들어 있는 차"와 지도 줄, 공개 README 지원 목록에 "🧪 시험 중" 줄 더하기
  3. sh tests/stub-test.sh, HMG-API tools/check-maps.py(지도를 pr22-rebase 복사본 maps/에 넣고)
  4. 코드 리뷰 → 패키지 zip·USB 묶음 만들기 → 소유자 승인 후 공개
  5. FINDINGS.md에 "PC에서 확인 / 확인 안 함" 기록''')


if __name__ == '__main__':
    main()
