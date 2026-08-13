# MIGRATION — legacy v1 brain 을 현재 v1 로 옮기기

2026-08-11 안정화에서 v1 스키마가 슬림해졌다. 버전 번호는 그대로 v1 이다 — 개발 중의
재정의이므로 migration 카탈로그에 v2 를 쌓지 않고 baseline 자체를 고쳤다. 그 대신
이전 모양의 DB 를 쓰던 brain 은 **별도 스크립트 한 번**으로 현재 모양에 올라탄다.

## 무엇이 달라졌나

| 대상 | 처분 | 이유 |
|------|------|------|
| `ruleset` / `rule` 테이블 | 삭제 (기능 제거) | 정책 게이트인데 쓰기 경로가 없어 손 SQL 없이는 동작 자체가 불가능한 미완 기관 |
| `note_meta` 테이블 | 삭제 (`note_extra` 로 대체) | DB 에만 사는 지식이었다 — 같은 역할을 frontmatter 커스텀 필드가 하고, `note_extra` 가 그걸 투영한다 |
| `axes.description` 컬럼 | 삭제 (기능 제거) | 파일에 대응물이 없는 DB-only 지식. 축은 이제 디렉터리 이름일 뿐 |
| `notes.file_mtime`, `notes.indexed_at` | 컬럼 삭제 | 쓰기만 있고 읽기 없음 — 증분/verify 판정은 `content_hash` 가 한다 |
| `note_source.source_checked_at` | 컬럼 삭제 | 소비자 없는 관측 타임스탬프 |
| meta 키 `note_count`, `last_build_at`, `last_consolidation_at`, `last_consolidation_note_count`, `vectors.model` | 행 삭제 | write-only 스탬프 — 아무도 읽지 않는다 |

CLI 표면에서는 `ruleset` 그룹, `operations apply/dry-run` 의 `--ruleset`,
env `LLMEMORY_RULESET(_LOCKED)`, `query meta`, op `set_note_meta`/`delete_note_meta`,
op `set_axis_description`, `create_note` 의 `axis_description`,
split routing 의 `type:"meta"` 가 함께 사라졌다.

`query search`/`query list` 의 `--axis`(및 `--exclude-axes`)는 `--tag`/`--exclude-tags` 로
바뀌었다 — 분류는 태그가 하고 axis 는 파일 주소만 남는다. `query stats --axis` 와
`query structure --axis` 는 디렉터리 관측 표면이라 그대로다. L3 lint 의
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

1. **shape 대조** — 이식이 이름으로 읽는 18개 테이블의 전 컬럼을 `PRAGMA table_info` 로
   대조하고, 없는 것을 **한 번에 모두** 찍고 중단한다.
2. **`note_meta` 잔존 확인** — 행이 남아 있으면 그대로 사라지므로, 각 행을 그대로 실행할 수 있는
   `set_frontmatter` op 로 찍어주고 중단한다. frontmatter 로 옮긴 뒤 다시 돌리면 된다
   (값을 의도적으로 버릴 거면 `ALLOW_NOTE_META_LOSS=1`).

`note_meta` 의 값은 frontmatter 커스텀 필드로 옮기면 `note_extra` 에 투영돼
`query list --field <key>=<value>` 로 계속 질의된다 — 이번엔 파일이 SSoT 다.

## 실행

```
tool/migrate-legacy.sh <state-root> [path-to-llmemory]
```

스크립트가 하는 일 (순서대로 — 0단계는 위의 사전 검사):

1. **백업** — `data/backup-pre-migrate-<ts>.db` (WAL-safe `.backup`), 구 DB 는
   `data/memory.legacy-<ts>.db` 로 보존.
2. **재투영** — `llmemory init` 이 정본 스키마의 새 DB 를 만들고 cortex markdown 에서
   notes/tags/entities/FTS/ref markers 를 재구성한다.
3. **의미층 이식** — markdown 에 없는 상태를 구 DB 에서 그대로 옮긴다: `note_usage`,
   `note_source`(drift 관측), `note_lifecycle_events`, `note_links`(가중치·활성 이력),
   `note_retrieval_terms`, `entity_index`(hit 카운트), `ripple_flags`, dismissal 2종,
   `events`, `activity_windows`+`retrieval_hits`(id 보존 — FK), `genome`(+events),
   tag vocab/aliases, axes(빈 축·created_at), meta KV(폐기 스탬프 제외).
   `note_extra` 는 옮기지 않는다 — frontmatter 파생이라 2단계 재투영이 만든다.
4. **재파생** — `llmemory index vector` 로 벡터 재빌드(accepted-loss), `llmemory update` 로
   씨드 재적용 + shape 게이트 통과 확인.

## 확인

끝나면 이 정도를 훑으면 된다:

```
llmemory query stats --home <root>          # 노트/링크/텀 수가 이전과 같은가
llmemory query search <아무거나> --home <root>
sqlite3 <root>/data/memory.db "SELECT name FROM sqlite_master WHERE name IN ('ruleset','rule','note_meta')"   # 비어야 정상
```

문제가 있으면 `data/memory.legacy-<ts>.db` 를 `memory.db` 로 되돌리고 이전 binary 로
복귀하면 된다 — 원본은 스크립트가 절대 지우지 않는다.
