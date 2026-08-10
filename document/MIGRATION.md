# MIGRATION — legacy v1 brain 을 현재 v1 로 옮기기

2026-08-11 안정화에서 v1 스키마가 슬림해졌다. 버전 번호는 그대로 v1 이다 — 개발 중의
재정의이므로 migration 카탈로그에 v2 를 쌓지 않고 baseline 자체를 고쳤다. 그 대신
이전 모양의 DB 를 쓰던 brain 은 **별도 스크립트 한 번**으로 현재 모양에 올라탄다.

## 무엇이 달라졌나

| 대상 | 처분 | 이유 |
|------|------|------|
| `ruleset` / `rule` 테이블 | 삭제 (기능 제거) | 정책 게이트인데 쓰기 경로가 없어 손 SQL 없이는 동작 자체가 불가능한 미완 기관 |
| `note_meta` 테이블 | 삭제 (기능 제거) | core 가 해석하지 않는 plugin kv — 도메인 메타의 SSoT 는 frontmatter 라 역할 중복 |
| `notes.file_mtime`, `notes.indexed_at` | 컬럼 삭제 | 쓰기만 있고 읽기 없음 — 증분/verify 판정은 `content_hash` 가 한다 |
| `note_source.source_checked_at` | 컬럼 삭제 | 소비자 없는 관측 타임스탬프 |
| meta 키 `note_count`, `last_build_at`, `last_consolidation_at`, `last_consolidation_note_count`, `vectors.model` | 행 삭제 | write-only 스탬프 — 아무도 읽지 않는다 |

CLI 표면에서는 `ruleset` 그룹, `operations apply/dry-run` 의 `--ruleset`,
env `LLMEMORY_RULESET(_LOCKED)`, `query meta`, op `set_note_meta`/`delete_note_meta`,
split routing 의 `type:"meta"` 가 함께 사라졌다.

## 왜 스크립트인가

`llmemory update` 의 migration 게이트는 L0 schema-shape 검증(코드 스키마와 라이브 DB 의
DDL/테이블/컬럼 비교)에 걸리면 하드 실패한다. 이전 모양의 DB 는 잉여 테이블·컬럼 때문에
이 게이트를 통과하지 못하므로, ALTER 로 깎는 대신 **정본 DDL 로 새 DB 를 만들고
비투영 상태를 이식**한다 — sqlite_master 의 DDL 텍스트까지 정본과 일치해야 하기 때문.

## 실행

```
tool/migrate-legacy.sh <state-root> [path-to-llmemory]
```

스크립트가 하는 일 (순서대로):

1. **백업** — `data/backup-pre-migrate-<ts>.db` (WAL-safe `.backup`), 구 DB 는
   `data/memory.legacy-<ts>.db` 로 보존.
2. **재투영** — `llmemory init` 이 정본 스키마의 새 DB 를 만들고 cortex markdown 에서
   notes/tags/entities/FTS/ref markers 를 재구성한다.
3. **의미층 이식** — markdown 에 없는 상태를 구 DB 에서 그대로 옮긴다: `note_usage`,
   `note_source`(drift 관측), `note_lifecycle_events`, `note_links`(가중치·활성 이력),
   `note_retrieval_terms`, `entity_index`(hit 카운트), `ripple_flags`, dismissal 2종,
   `events`, `activity_windows`+`retrieval_hits`(id 보존 — FK), `genome`(+events),
   tag vocab/aliases, axis description, meta KV(폐기 스탬프 제외).
4. **재파생** — `llmemory index vector` 로 벡터 재빌드(accepted-loss), `llmemory update` 로
   씨드 재적용 + shape 게이트 통과 확인.

`note_meta` 에 있던 행은 옮기지 않는다 — 테이블 자체가 퇴역했다. 필요한 값이 있었다면
마이그레이션 전에 노트 frontmatter 로 옮겨 적어라.

## 확인

끝나면 이 정도를 훑으면 된다:

```
llmemory query stats --home <root>          # 노트/링크/텀 수가 이전과 같은가
llmemory query search <아무거나> --home <root>
sqlite3 <root>/data/memory.db "SELECT name FROM sqlite_master WHERE name IN ('ruleset','rule','note_meta')"   # 비어야 정상
```

문제가 있으면 `data/memory.legacy-<ts>.db` 를 `memory.db` 로 되돌리고 이전 binary 로
복귀하면 된다 — 원본은 스크립트가 절대 지우지 않는다.
