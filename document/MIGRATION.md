# MIGRATION — legacy v1 brain 을 현재 v1 로 옮기기

2026-08-11 안정화에서 v1 스키마가 슬림해졌다. 버전 번호는 그대로 v1 이다 — 개발 중의
재정의이므로 migration 카탈로그에 v2 를 쌓지 않고 baseline 자체를 고쳤다. 그 대신
이전 모양의 DB 를 쓰던 brain 은 **별도 스크립트 한 번**으로 현재 모양에 올라탄다.

## 무엇이 달라졌나

| 대상 | 처분 | 이유 |
|------|------|------|
| `ruleset` / `rule` 테이블 | 삭제 (기능 제거) | 정책 게이트인데 쓰기 경로가 없어 손 SQL 없이는 동작 자체가 불가능한 미완 기관 |
| `note_meta` 테이블 | 삭제 (`note_extra` 로 대체) | DB 에만 사는 지식이었다 — 같은 역할을 frontmatter 커스텀 필드가 하고, `note_extra` 가 그걸 투영한다 |
| `axes` 테이블, `notes.axis` | 삭제 (개념째 제거) | id 가 주소가 됐다 — 점으로 이은 라벨이 곧 위치라 축이 할 일이 남지 않는다 |
| `notes.path` 컬럼 | 삭제 | 경로는 id 의 순수 함수다. 저장하면 자기 자신과 어긋날 수 있는 값이 하나 생길 뿐 |
| `notes.file_mtime`, `notes.indexed_at` | 컬럼 삭제 | 쓰기만 있고 읽기 없음 — 증분/verify 판정은 `content_hash` 가 한다 |
| `note_source.source_checked_at` | 컬럼 삭제 | 소비자 없는 관측 타임스탬프 |
| meta 키 `note_count`, `last_build_at`, `last_consolidation_at`, `last_consolidation_note_count`, `vectors.model` | 행 삭제 | write-only 스탬프 — 아무도 읽지 않는다 |

CLI 표면에서는 `ruleset` 그룹, `operations apply/dry-run` 의 `--ruleset`,
env `LLMEMORY_RULESET(_LOCKED)`, `query meta`, op `set_note_meta`/`delete_note_meta`,
op `set_axis_description`, `create_note` 의 `axis_description`,
split routing 의 `type:"meta"` 가 함께 사라졌다.

## id 가 주소가 됐다

id 는 이제 라벨을 `.` 으로 이은 것이고, 파일 경로는 그 순수 함수다 — `a.b.c` 는
`cortex/a/b/c.md`. 위치를 담던 것(축·`notes.path`)이 전부 여기로 접혔다.

- **`axis` 소멸** — `notes.axis`·`axes` 테이블·frontmatter `axis:` 필드·op `rename_axis`
  ·`create_note`/`split_note` 의 `axis` 필드가 전부 없어졌다. `migrate_note` 의 `new_axis`
  도 없다 — 옮기는 것이 곧 개명이라 `new_id` 하나면 된다.
- **`query axes` → `query tree`** — 축 테이블을 세던 자리를 id 접두사를 세는 것으로 갈아끼웠다.
  `--prefix` 로 한 단계씩 내려간다. `query stats --axis` 와 `query structure --axis` 는
  `--prefix` 가 됐다(그 접두사 *아래 전부*의 집계).
- **인용 재작성** — `migrate_note` 가 옛 id 를 인용하던 모든 노트의 본문을 새 id 로 다시 쓴다
  (`` `id` ``·`[[id]]` 둘 다). **alias 테이블은 두지 않는다** — 부채를 쌓는 대신 인용을
  정본화한다. brain *밖*(슬랙·PR)의 옛 id 는 끊긴다.
- **`path-mismatch`** — verify L2 의 `axis-mismatch` 자리를 대신한다. frontmatter 의 `id` 와
  파일 위치가 어긋나면 무결성 위반이다. lint `invalid-id` 도 점 표기를 허용하도록 넓어졌다.
- **`cortex/.innate/` → `cortex/innate/`** — 씨드 id 는 `innate.knowledge-fragmentation`.
  배포본이냐는 *어디 있냐*가 아니라 *어디서 왔냐*의 문제라 점 디렉터리 예외를 없앴다.
- **예약 파일명 없음** — `README.md`·`INDEX.md`·`GUIDE.md`·`_` 접두를 스캔에서 건너뛰던
  분기가 사라졌다. cortex 아래는 전부 지식이다. **대신 아무 메모나 떨어뜨려 두면 안 된다** —
  frontmatter 없는 파일은 인덱싱 에러가 되고, `index build --rebuild` 는 에러가 하나라도
  있으면 전체를 중단한다(부분 재구축을 남기지 않는 기존 방침). 일반 인덱싱은 그 파일만
  에러로 싣고 계속 간다. 초안은 cortex 밖에 둔다.

`query search`/`query list` 의 `--axis`(및 `--exclude-axes`)는 `--tag`/`--exclude-tags` 로
바뀌었다 — 분류는 태그가 한다. L3 lint 의
`axis-tag-missing`/`axis-unregistered` 도 없어졌다 (강제할 규약 자체가 사라짐).
`tag-only-axis` 는 `tag-underclassified` 로 바뀌었다 — 판정(태그 1개)은 같고 이유가
"축 태그뿐"에서 "들어오는 길이 하나뿐"으로 정정됐다. **코드가 바뀌었으니 이 코드로 걸어둔
기존 dismissal 은 끊기고 경고가 한 번 되살아난다.** `tag-near-duplicate` 는 축 이름인 태그를
건너뛰던 예외가 사라졌다 — 이제 그냥 태그다. `unknown-field` 는 `field-typo` 로 좁아졌다:
모르는 필드는 이제 기능이라 결함이 아니고, 일급 필드와 edit-distance 1 인 것(`summry`)만 짚는다.

## 왜 스크립트인가

`llmemory update` 의 migration 게이트는 L0 schema-shape 검증(코드 스키마와 라이브 DB 의
DDL/테이블/컬럼 비교)에 걸리면 하드 실패한다. 이전 모양의 DB 는 잉여 테이블·컬럼 때문에
이 게이트를 통과하지 못하므로, ALTER 로 깎는 대신 **정본 DDL 로 새 DB 를 만들고
비투영 상태를 이식**한다 — sqlite_master 의 DDL 텍스트까지 정본과 일치해야 하기 때문.

## 사전 검사 — 무엇도 옮기기 전에

무엇을 옮기기 전에, 스크립트는 **아무것도 건드리지 않은 상태에서** 두 가지를 먼저 본다.
3단계의 이식은 `sqlite3 -bail` 한 트랜잭션이라, 없는 컬럼 하나가 **이식 도중에** 늦게 터지고
그때는 이미 구 DB 가 옆으로 치워진 뒤다. 이름 대조는 싸니까 먼저 전부 한다.

1. **shape 대조** — 이식이 이름으로 읽는 테이블의 전 컬럼을 `PRAGMA table_info` 로
   대조하고, 없는 것을 **한 번에 모두** 찍고 중단한다. `notes.axis`/`notes.path` 도 목록에
   있는데, 그게 곧 구 모양이라 **두 번째 실행이 여기서 걸린다** — 이미 옮긴 brain 을 다시
   돌려 코퍼스를 두 번 재주소화하는 사고를 막는 자리다.
2. **`note_meta` 잔존 확인** — 행이 남아 있으면 그대로 사라지므로, **어느 파일에 어떤 줄을
   넣어야 하는지** 를 파일 경로와 함께 찍고 중단한다. `set_frontmatter` op 를 안내하지 않는
   이유는 이 시점에 그 op 를 돌릴 수 있는 바이너리가 없기 때문이다 — 구 바이너리는 커스텀 키를
   거부하고, 신 바이너리는 파일을 쓴 뒤 아직 없는 `note_extra` 에 투영하다 죽는다. 반면
   markdown 한 줄은 편집기로 넣을 수 있고 3단계 재투영이 그대로 집어간다.
   `(note, namespace, key)` 중 namespace 만 다른 동명 key, frontmatter 키 규칙
   (`[A-Za-z_]\w*`)을 못 맞추는 key, 여러 줄 값은 한 줄로 접을 수 없으므로 **따로 열거만 하고
   자동으로 뭉개지 않는다.** 값을 의도적으로 버릴 거면 `ALLOW_NOTE_META_LOSS=1`.

`note_meta` 의 값은 frontmatter 커스텀 필드로 옮기면 `note_extra` 에 투영돼
`query list --field <key>=<value>` 로 계속 질의된다 — 이번엔 파일이 SSoT 다.

## 실행

```
tool/migrate-legacy.sh <state-root> [path-to-llmemory]
```

스크립트가 하는 일 (순서대로 — 0단계는 위의 사전 검사):

1. **백업** — `data/backup-pre-migrate-<ts>.db` (WAL-safe `.backup`), 구 DB 는
   `data/memory.legacy-<ts>.db` 로 보존.
2. **재주소화** — 모든 노트에 새 id 를 주고 파일을 그 자리로 옮긴다. 규칙은 기존 정보에서
   결정적으로 유도된다:

   ```
   날짜 꼬리 없음:  <axis>.<id>                 tech + di-container        → tech.di-container
   날짜 꼬리 있음:  <axis>.<YYYY>.<MM>.<stem>   journal + bkios-545-260508 → journal.2026.05.bkios-545
   ```

   frontmatter 의 `id` 가 함께 고쳐지고 `axis:` 줄은 지워진다. 그리고 **코퍼스 전체의 인용이
   새 id 로 다시 쓰인다** — alias 가 없으므로 여기서 안 고친 참조는 그냥 끊긴다.
   꼬리를 떼면 같은 달의 두 노트가 같은 주소로 겹치는 경우가 있는데, 그런 노트만 꼬리를
   유지하고 그 사실을 찍는다(카운터를 붙여 갈라놓지 않는다 — 둘을 구별하던 건 꼬리다).
   매핑은 구 DB 에 `id_map` 으로 남아 3단계가 조인한다.

3. **재투영** — `llmemory init` 이 정본 스키마의 새 DB 를 만들고 cortex markdown 에서
   notes/tags/entities/FTS/ref markers 를 재구성한다.
4. **의미층 이식** — markdown 에 없는 상태를 구 DB 에서 옮긴다. **note_id 는 `id_map` 을
   조인해 새 id 로 바뀐다** — 이력이 자기 노트를 따라가야 하기 때문이다: `note_usage`,
   `note_source`(drift 관측), `note_lifecycle_events`, `note_links`(가중치·활성 이력),
   `note_retrieval_terms`, `entity_index`(hit 카운트), `ripple_flags`, dismissal 2종,
   `events`, `activity_windows`+`retrieval_hits`(id 보존 — FK), `genome`(+events),
   tag vocab/aliases, meta KV(폐기 스탬프 제외).
   `note_extra` 는 옮기지 않는다 — frontmatter 파생이라 재투영이 만든다.
   `retrieval_hits` 만 예외로 전 행을 남긴다 — 사라진 노트에 대한 hit 도 hit 이다.
5. **재파생** — `llmemory index vector` 로 벡터 재빌드(accepted-loss), `llmemory update` 로
   씨드 재적용 + shape 게이트 통과 확인. **`update` 는 여기서 항상 innate 불일치를 경고한다** —
   재주소화가 씨드 파일도 고쳤기 때문이다. 스크립트는 그걸 중단 사유로 보지 않고 마지막에
   `update --override` 명령을 찍어준다(그 디렉터리에 저작 노트가 있으면 지워지므로 먼저 확인).

## 확인

끝나면 이 정도를 훑으면 된다:

```
llmemory index verify integrity --level 3 --home <root>   # OK 여야 정상
llmemory query lint --home <root> | grep '^error'          # 비어야 정상 (특히 dangling-note-ref)
llmemory query tree --home <root>                          # 옛 축이 그대로 최상위 접두사인가
llmemory query stats --home <root>                         # 노트/링크/텀 수가 이전과 같은가
sqlite3 <root>/data/memory.db "SELECT name FROM sqlite_master WHERE name IN ('ruleset','rule','note_meta','axes')"   # 비어야 정상
```

문제가 있으면 `data/memory.legacy-<ts>.db` 를 `memory.db` 로 되돌리고 이전 binary 로
복귀하면 된다 — 원본은 스크립트가 절대 지우지 않는다.
