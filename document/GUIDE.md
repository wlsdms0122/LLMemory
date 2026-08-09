# llmemory

자기성장형 에이전트의 메모리 CLI. `<state-root>/cortex/` 의 markdown 노트를
`<state-root>/data/memory.db` (SQLite + FTS5) 와 동기화해 검색·연상 탐색·재구조화를 한다.

llmemory 는 anchor-free — `--home <state-root>` 로 상태 위치만 주면 binary 위치와
무관하게 동작한다. 상태(사용자 지식)는 이 패키지 밖에 있다.

## 첫 사용

```
llmemory init --home <state-root>
```

`data/` 와 `cortex/` 를 만들고 빈 schema 를 적용한다. idempotent — 기존 상태는 보존된다.

함께 두 가지가 심긴다:
- `<state-root>/README.md` — 이 문서의 파생 카피(뇌 *바깥*의 매뉴얼). 매 init 갱신.
- **운용 정책 노트** — `cortex/<axis>/<id>.md` 에 `locked: true` 노트로(뇌 *안*의 지식).
  일반 노트라서 연상 하강으로 인출된다. 이미 있는 씨드 파일은 init 이 건드리지 않는다.

바이너리를 올린 뒤 기존 brain 에 이 둘을 다시 심으려면:

```
llmemory update --home <state-root>
```

씨드 노트를 바이너리의 사본으로 덮고 README 를 갱신하고 재색인한다. **범위는 씨드 id 뿐** —
저작한 노트는 절대 안 건드린다. 사람이 지운 씨드는 되살린다(운용 정책 없는 brain 이
이 명령이 막으려는 실패다). **씨드 id 는 항상 출고본이다** — 로컬 분기가 필요하면 내용을
새 id 노트로 복제하라. `locked` 는 "operations 수정 차단" 그 이상을 의미하지 않는다(소유권 아님).

## 호출 패턴

```
llmemory <subcommand> [options] --home <state-root>
```

**중요**: `--home` 은 subcommand 뒤에. swift-argument-parser 가 leaf option 이라
앞에 두면 `Unknown option '--home'` 으로 거절된다.

## 명령 그룹

전부 `--help` 가 가이드이며, 모든 subcommand 에 abstract + discussion + example 이
들어있다. 첫 표면은 항상 help.

```
llmemory --help                                  # 전체 그룹
llmemory query --help                            # 그룹 안내
llmemory query search --help                     # 옵션 + 예시
llmemory operations vocab --home <state-root>           # 최신 op 카탈로그
llmemory operations describe <op> --home <state-root>   # op 별 field schema + 예시
```

정본 철자는 `operations`, 축약 `ops` 도 같은 그룹에 닿는다 (alias).

| 그룹 | 역할 |
|------|------|
| `init` | 최초 setup (idempotent) — 스키마 + README + 운용 정책 씨드 |
| `update` | 기존 brain 에 씨드·README 재적용 (저작 노트 불침범) |
| `query` | 읽기 — search / get / related / neighbors / entity / meta / structure / stats / list / axes / history / lint / enrichment / template |
| `operations` | 쓰기 — apply / dry-run (atomic transaction) / vocab / describe |
| `index` | DB 유지보수 — build / verify (integrity/sources/terms) / vector |
| `consolidate` | 주기 정리 (관심사 분리) — integrate(A 비파괴) / prune(B 시냅스 가지치기) / homeostasis(H 메타가소성 틱) / candidates / report |
| `genome` | 가소성 파라미터 — list(카탈로그·현재값·provenance) / history(변이 이력) / shadow(후보값 offline reranking) |

## 인출 표면 — 연상 하강 (retrieval descent)

읽기 표면은 두 부류다. **연상 표면**(related / search / neighbors / entity)은 다음
탐색을 결정할 수 있는 정보 — 모든 히트의 `summary`, anchor 의 이웃 — 를 출력에
동반한다. 나머지(get / list / stats / …)는 각자의 역할(본문 읽기·열거·관측)만 한다.

표준 하강 루프 — 충분한 지식에 도달할 때까지:

```
1. 진입   query related --input '{"text":"<태스크 맥락>"}' --json     # cue 기반 연상
          (또는 키워드가 명확하면 query search "<키워드>" --json)
2. 본문   query get <id>                                              # 후보 읽기
3. 하강   query neighbors --id <id> --json                            # anchor 의 이웃 → 다음 hop
4. 반복   2–3 을 summary 를 보고 판단하며 반복
```

출력 파싱은 항상 `--json`. plain 출력은 사람이 읽는 테이블이다.

**대화 맥락에서 관련 노트 찾기** (capture/retrieval agent 의 표준 진입):
```
llmemory query related --input '{"text":"..."}' --json --home <state-root>
```
입력은 `--input` 또는 stdin.

**키워드 FTS 검색**:
```
llmemory query search "transfer" --axis tech --home <state-root>
```

**노트 본문 읽기** (직접 file Read 대신 — id 로 조회, 여러 개 동시 가능):
```
llmemory query get principles --home <state-root>
llmemory query get identity principles tone --home <state-root>
```

**긴 노트의 부분 읽기** (섹션 단위 — search/related 결과의 `section` path 를 그대로 사용):
```
llmemory query get <id> --toc --home <state-root>          # 섹션 목차 + 단어수
llmemory query get <id> --section '## 섹션명' --home <state-root>
llmemory query get <id> --budget 800 --home <state-root>   # 단어 예산까지만 — 어디를 열지 모를 때
```
FTS 인덱스도 섹션 단위 — 검색 결과에 매치 섹션 path 가 실리고(head 매치면 비어있음),
BM25 가 섹션 길이로 정규화돼 긴 멀티토픽 노트가 길이 패널티를 받지 않는다.

`--budget` 은 섹션 경계에서만 자른다(문장 중간 절단 없음). 잘리면 **잘렸다는 사실이 명시적으로
드러난다** — 생략된 섹션 전부가 단어수와 함께 나열되고, 이어 읽을 `--section` 명령이 그대로
붙는다(JSON 은 `truncated`/`omitted_sections`). 단일 wrapper 헤딩 아래 전부가 들어있는 노트는
wrapper 의 자식 단위로 내려가 자르고, 헤딩이 아예 없는 본문은 자를 경계가 없으므로 통짜로 나온다
— 그건 노트 모양의 문제라 lint(`note-oversized`)가 잡는다.

**조건으로 노트 나열** (eager/stale 등 — plain 은 axis/id/title/summary 테이블,
스크립트에서 id 추출은 `--json` 파싱으로):
```
llmemory query list --priority eager --home <state-root>
llmemory query list --axis skill --json --home <state-root>
```
필터는 AND 조합: `--priority` / `--axis` / `--stale` / `--source-stale` / `--limit`.

**분화·승격의 사실 엣지**: `split_note` 는 자식들 사이에 `sibling` 을 자동으로 심는다.
승격(낱개 → 요지/면)은 `link_lineage` 로 남긴다 — `propose_link`(감쇠하는 연상 제안)와 달리
weight 1.0 사실 엣지이고 decay 면제다. 방향은 **`src <kind> dst` 를 문장으로 읽는다** — 하나의
"새것→옛것" 규약이 아니다: 원본 journal 이 추출된 노트로 `promoted_to` 되고(src=원본), 대체 노트가
옛것을 `supersedes` 한다(src=새것).

단 **사실성과 랭킹 발언권은 분리**돼 있다: `sibling` 은 저장 weight 1.0 그대로 가족 인식·삭제
가드·decay 면제에 쓰이지만, 연상 표면(related 확장·neighbors)의 랭킹에는 할인돼 들어간다
(`links.sibling_rank_weight`, 기본 0.3). N-clique 의 구성원마다 N-1개 만점 엣지가 생겨 형제가
연상을 도배하고 요지를 밀어내기 때문 — 사실은 남기고 확성기만 뺏는다.

```
llmemory operations apply --input '{"ops":[{"op":"link_lineage","src":"<원본 회차>","dst":"<추출된 원리>","kind":"promoted_to","reason":"..."}],"rationale":"..."}' --home <state-root>
```

**transaction 쓰기**:
```
llmemory operations apply --input '{"ops":[...],"rationale":"..."}' --json --home <state-root>
```
입력은 `--input` 또는 stdin (heredoc).

**주기 정리** (LLM 0) — 관심사별로 분리됨. cadence 가 다르니 따로 호출:
```
llmemory consolidate integrate --home <state-root>   # A: 비파괴 정리·벡터 재생성 (자주, 복구용)
llmemory consolidate prune --home <state-root>       # B: 시냅스 가지치기 — 학습 엣지 감쇠 (드물게)
```

## 구조화 문서 (document / template / locked)

대부분 노트는 포맷 없는 지식이지만, *문서*(테크스펙 등)는 정해진 뼈대를 따른다. 동작은
**frontmatter 2필드**가 운반한다 (axis 무관):

- `template: <id>` — 이 노트는 그 템플릿 노트의 heading **frame** 을 따른다. operations mutation 이
  frame 을 깨면(필수 섹션 삭제·개명·외래 섹션·순서) 거부된다. 내용·빈 섹션·더 깊은 하위 heading 은 자유.
  정리(split/merge) 후보에서 제외되되 검색·랭킹은 일반 노트와 동일.
- `locked: true` — 봇 전용 operations mutation 차단(사람이 파일 직접 수정). `flag` 등 DB-only 신호는 허용.
  템플릿 노트가 대표 사례. 범용 — 아무 노트에나 붙는다.

```
llmemory query template <template-id> --home <state-root>      # 뼈대 + 섹션별 가이드
# 문서 생성 (content 비우면 frame 이 빈 섹션으로 scaffold):
llmemory operations apply --input '{"ops":[{"op":"create_note","axis":"spec","id":"...","title":"...","summary":"...","tags":["spec"],"template":"<template-id>"}],"rationale":"..."}' --json --home <state-root>
```

템플릿 frame: 선언된 모든 heading 이 필수다(마커 없음). 선언 레벨은 닫힘(외래 섹션 거부)·순서
보존, 잎 아래(`###`+) 와 섹션 내용은 자유(빈 섹션 OK). heading 매칭은 정규화(NFC·소문자·선행
번호/불릿 제거). 템플릿을 사람이 고쳐 frame 이 바뀌면 `query lint` 의 `template-drift` 가
어긋난 문서를 표면화한다.

## 출력 / Exit code — 레벨 × 포맷 직교

출력은 두 직교 축의 곱이다. **레벨**(데이터 양)과 **포맷**(표현식)은 독립이며,
같은 레벨이면 plain 이든 `--json` 이든 **같은 데이터**를 담는다.

- 레벨: 기본 = 의미 코어(axis/id/title/summary + 랭킹 점수). `--verbose` = +메타데이터
  (타임스탬프·path·tags·라이프사이클 플래그·점수 성분·candidates 상세·related 의
  axes/cooccur/vocab 섹션). 레벨은 모델 구성 단계에서 결정 — 기본 레벨의 JSON 엔
  detail 키 자체가 없다. `--verbose` 는 레벨 차가 실존하는 커맨드에만 있다
  (list / search / get / neighbors / related / candidates).
- 포맷: 기본 = 사람이 읽는 plain 테이블, `--json` = JSON 한 줄 (mutating 명령은
  결과 요약, query 는 데이터). 예외: `query axes`, `consolidate report` 은 plain 전용.
- 디테일이 필요한 소비자는 `--verbose --json` (capture/consolidate 워크플로우가 이 형태).
- stderr: 에러·진단.
- exit code: `0` 정상, `1` 검증 실패 또는 결과 status≠ok, `2` 옵션 누락.

## lint — 유도하는 관측층

`query lint` 는 결정론적 관측이다. **error** = 무결성 위반(고쳐야 함), **warn** = 판단 요청.
llmemory 는 강제하지 않는다 — 규칙을 세워도 운용은 전적으로 agent 가 하므로, 할 수 있는 일은
*큰 범위의 가이드와 가드*, 즉 "이건 문제로 보인다"를 짚고 **다음 hop 을 손에 쥐여주는 것**이다.
그래서 warn 메시지는 판정 근거 수치와 다음 명령을 같이 싣는다("too large" 로 끝나는 경고는
매번 다시 읽히고 매번 무시된다).

분화 정책(brain `knowledge-fragmentation`)을 살리는 룰 셋:

| code | 무엇을 본다 | 왜 |
|------|-----------|-----|
| `note-oversized` | 절대 크기 | 한 질문에 답하려 통째로 로드하는 낭비 |
| `growth-unbounded` | 날짜 섹션이 쌓이는 성장 *구조* | 크기와 무관 — 시점 문제일 뿐이고, 커진 뒤엔 푸는 비용이 크다. 이미 기간을 id 에 박은 노트(봉인된 버킷)는 제외 |
| `fragment-unlinked` | 파편 가족에 요지·형제 링크가 없음 | 분화가 손실로 끝난 상태. 링크 없는 분할은 정리가 아니다. 가족당 1건으로 보고 |

> 가족 인식은 **`sibling` 엣지의 연결 컴포넌트가 1차**다(도구가 심은 사실 — 엣지가 증거라 2개면
> 성립). 어느 컴포넌트에도 안 속한 노트만 이름 stem 으로 묶는다(작명 관례 오라클 — 약하지만 우리
> 관례). 순서가 오탐을 막는다: 한 가족 안에서 더 긴 접두를 공유하는 구성원들이 유령 하위 가족으로
> 재해석되지 않는다. 도구로 쪼갠 가족은 `sibling` 이 직접 심기므로 고립된 채로 태어날 수 없다.

**warn 은 닫을 수 있다 (습관화).** 검토하고 그대로 두기로 했으면
`dismiss_candidate kind="lint:<code>"`. 기각은 **finding 하나에 묶인다** — 한 노트에 같은 코드
finding 이 여럿이면 `finding` 필드로 어느 것인지 지목해야 하고(안 하면 거부), 그 하나만 노트
형태가 의미 있게 달라지거나 corpus 재편이 재개방할 때까지 조용해진다. 코드째 닫히면 나머지 진짜
결함과 나중에 생길 것까지 묻히기 때문이다. 살아있는 finding 이 없는 기각도 거부된다(조용한 no-op
방지). 닫을 방법이 없으면 같은 오탐을 매 사이클 재심하게 된다
(실측: cleaner 가 dangling-ref 59건을 네 회차 연속 전수 재심해 동일 결론에 도달). 억제된 것을
보려면 `--include-dismissed`. **error 는 기각 불가** — 무결성 위반은 의견의 문제가 아니다.

**finding 의 대상은 두 종류다 (`target_scope`/`subject`).** `target_scope=note` 면 `subject` 가 노트 id 이고
`id` 로 기각한다 — 재개방은 그 노트의 형태 발산(탈습관화) 또는 corpus 재편. `target_scope=corpus` 면
어떤 노트도 소유하지 않는 사실(예: 태그 쌍 `tag-pair:금리|금융`)이고 `target` 으로 기각한다 —
노트 형태는 코퍼스 사실의 증거가 아니므로 **재개방은 corpus 재편뿐**이다. 둘을 하나의 note id
슬롯에 밀어넣었던 시절엔 corpus warn 이 `note_id:""` 로 흘러 억제도 기각도 불가능했다 — 카탈로그는
dismissible 이라 광고하는데 문은 닫혀 있는, 습관화가 막으려던 바로 그 상태.

## 원칙

- **Single source of truth**: cortex/ 의 markdown 이 진실. DB 는 파생.
- **본문 통째 덮어쓰기 없음**: 모든 mutation 은 `operations apply` 의 op vocabulary 안에서.
  가장 거친 단위는 `patch_section`.
- **Atomic transaction**: 다중 op 은 한 transaction 으로 묶여 validate → snapshot →
  apply → rollback. 부분 실패 시 새로 만든 파일·DB row 까지 cleanup.
- **Anchor-free**: `--home` 만 받음. 외부 경로 가정 없음.
- **차가움은 비용이 아니다**: 활성 사다리도, "보관하되 숨기는" 층도 없다 — 안 불리는 노트는
  인출 비용을 만들지 않으므로 감출 이유가 없다. `hit_count`/`last_retrieved_at` 은 순수
  관측값이고 **노트의 생애주기를 파생하지 않는다** (활성화 기록이 조정하는 것은 아래 genome 의
  read-path 파라미터뿐, 노트가 아니다). 인출 품질의 전제는 망각이 아니라 **분화** — 비대한
  지식은 숨기지 말고 쪼갠다 (요지/면/낱개). 폐기는 판단으로 `delete_note`(→ `.trash/`).
- **연상 동반**: 연상 표면(related/search/neighbors/entity)의 모든 히트는 summary 를
  싣는다 — 출력은 답이 아니라 다음 하강을 결정하는 경유지다.

## 활성화 기록 + Genome (기질의 자기 관측과 가소성 파라미터)

뇌는 발화 로그를 원본으로 남기지 않는다 — 발화는 구조에 흔적을 남기고 신호는 사라진다.
같은 원리로 raw `events` 는 retention(기본 30일) 후 폐기되되, 폐기 전에 영속 흔적으로
**승계**된다 (integrate 가 순서를 강제):

- `activity_windows` — 태스크 세션의 *추정*. 호출자 correlation id(`--session-id`,
  `MEMORY_SESSION_ID`)가 있으면 그 라벨로, 없으면 시간 근접(gap)으로 묶는다. 추정임을
  타입 이름에 남긴다 — retrieval_session 이 아니다. gap 은 라벨에도 적용된다(닫힌
  윈도는 다시 열리지 않는다 — exactly-once 가 라벨 연속성보다 우선).
- `retrieval_hits` — surfaced(무엇이 떠올랐나) + `used_signal`(약한 사용 신호:
  reported=호출자 신고 / content_overlap=응답 겹침 휴리스틱 — 인과 증명이 아니다).
  used 마킹은 `mark_used` op 로, 최근 윈도에 출현한 노트만 수용한다.

**Genome** — 가소성 파라미터의 카탈로그를 데이터로 만든 층. *선언*(유전자 목록·bounds·
wild-type·mutable 여부)은 코드가 SSoT — 종-수준이고 바이너리와 함께 버전된다. *브레인별
현재값*(epigenome)만 DB 에 있고, 행이 없는 유전자는 wild-type 로 동작한다. 같은 바이너리의
두 브레인이 파라미터까지 다른 뇌가 되는 자리다.

쓰기 문은 둘뿐:
- **`set_gene` op** — 직접 값 설정. 전 유전자, bounds 검증, value 생략 = wild-type 리셋.
  모든 변경은 genome_events 에 provenance 로 남는다.
- **`consolidate homeostasis`** — 결정론 메타가소성 틱 (LLM 0). mutable(read-path)
  유전자만, 활성화 기록의 낭비 신호에만 반응하고(분포 미학 금지 — 특정 축이 많이 발화하는
  것은 전문성이지 불균형이 아니다), 조정은 1스텝·bounds 안·wild-type 상한. 윈도는
  watermark 로 정확히 한 번 소비되고 증거는 min_sample 까지 누적되므로 호출 빈도는 숨은
  파라미터가 아니다. get 추적 도입 이전의 윈도는 증거에서 제외된다(눈먼 코호트 가드 —
  계측 없던 시절의 0 은 낭비의 증거가 아니라 관측의 부재다).

관찰 표면: `genome list`(카탈로그·현재값·source), `genome history`(변이 provenance),
`genome shadow`(보존창 내 search/related 로그를 현 corpus 에서 후보값으로 A/B 재실행 —
offline reranking 이지 반사실이 아니다), `query stats` 의 activation 섹션.

## Semantic enrichment (retrieval 의미층)

lexical(BM25)·그래프 위에 *의미층* 을 더한다. 두 갈래 — ① LLM 이 capture 때 심는
의미 데이터(alias·cue·`assoc` edge), ② 그래프에서 유도한 알고리즘 벡터
(`note_vectors`, PPMI+SVD). retrieval 은 계속 **LLM 0**.

**경계** — llmemory 가 슬롯·검증·retrieval 의 SSoT, 외부는 LLM artifact 를
*생성* 만 하는 교체 가능 client. 검증은 llmemory 안에 있어, 약한 모델이 노이즈를 줘도
인덱스를 오염시키지 않는다 (graceful degradation — 최악이 no-op).

**write 계약** (`operations describe <op>`):
- `add_retrieval_terms` — alias/cue 텍스트. round-trip + IDF 검증 후 `notes_fts` 의
  `enrich` 컬럼에 색인 (동의어·한글 조사 사각지대를 메움).
- `propose_link` — LLM 의미 연상 edge (`assoc`). 낮은 weight 로 들어가 decay/strengthen
  루프가 곧 validator.
- `purge_enrichment` — provenance 단위 회수.

**상태 관찰**: `query enrichment` — term active/pending/rejected, `assoc` edge,
벡터 커버리지, provenance 별 모델 노이즈율.

**알고리즘 벡터**: `index vector` — `note_links` 그래프를 PPMI+SVD 로 분해해
`note_vectors` 를 빌드 (`index build --rebuild` 이 끝에 자동 재생성). `query related` 가
`vector_linked` 로 키워드를 안 공유하는 의미상 가까운 노트를 확장. `consolidate integrate` 가
주기적으로 refactorize (호출 시 항상 재분해).

**스키마 버전 (마이그레이션)**: 스키마는 순서 있는 migration 으로 관리된다 — 적용 이력은
DB 안의 migration 원장에 남는다. brain 이 binary 보다 뒤처져 있으면(원장에 미적용 migration 존재)
모든 명령이 fast-fail 하며, `llmemory update` 가 앞으로 옮겨 심는다 (실행 전
`sqlite3 data/memory.db ".backup backup.db"` 백업 권장 — WAL-safe; 단순 파일 복사는
체크포인트 안 된 -wal 내용을 놓친다). 더 새로운 binary 가 만진 brain 은 이 binary 가
읽지 않는다 — binary 를 올려라.

> **주의 — DB 삭제는 "cortex 에서 재구성"이 아니라 "의미층 폐기"다.** markdown 이 SSoT 인 것은
> `notes`(+tags/entities/source) 뿐이고, **의미층과 이력은 DB 에만 있다** — assoc/cooccur 엣지,
> retrieval terms(alias·cue), `note_meta`, ripple flag, candidate dismissal, lifecycle 이벤트,
> hit 관측값. 지우면 전부 사라지고 재구성되지 않는다(enrich 가 시간을 들여 다시 쌓아야 한다).
> migration 이 있으므로 스키마 변경으로 DB 를 지울 일은 원칙적으로 없다 — 손상 등으로
> 재구성이 불가피하면 **먼저 `memory.db` 를 복사해두고**, init 후 그 사본에서 위 테이블을
> 옮겨 심는다.

각 op·명령의 계약·검증 규칙은 llmemory 자체 표면이 SSoT — `operations describe <op>`,
`index <cmd> --help`, `query enrichment`. (별도 설계 문서에 의존하지 않는다.)

## 데이터 위치

```
<state-root>/
  data/
    memory.db         — catalog, FTS5 index, events(30일) + 영속 활성화 흔적
                        (activity_windows/retrieval_hits) + genome(epigenome)
  cortex/
    <axis>/<id>.md    — flat 노트 (axis-agnostic)
    <axis>/YYYY/MM/<id>.md  — 시간순 thread (id 끝이 YYMMDD)
    .innate/          — 선천 지식 (axis: innate, locked). 배포본과 다르면(내용 변경·
                        파일 없음·외부 파일) update 가 경고만 하고 안 건드림 — `--override` 만이
                        배포본 그대로 되돌린다. 디렉터리째 지우면 손뗀 것(스킵). `--check` 로 확인.
    .trash/           — soft-deleted (사람 검토 대기)
```
