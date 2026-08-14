//
//  Migration1.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB

// v1 baseline — the full schema as of packaging llmemory as an official package.
// The DDL keeps IF NOT EXISTS so migrating a pre-migrator brain (tables already
// present, no migration record) is a safe no-op that only records the migration.
public struct Migration1: GRDBMigration {
    // MARK: - Property
    public var id: Int { 1 }
    public var description: String? { "v1 baseline schema" }

    static let schema: String = #"""
-- ─────────────────────────────────────────────────────────
-- 어휘 (tag_vocab / tag_aliases)
-- ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tag_vocab (
  tag TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS tag_aliases (
  alias TEXT PRIMARY KEY,
  canonical TEXT NOT NULL REFERENCES tag_vocab(tag) ON DELETE CASCADE,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_tag_aliases_canonical ON tag_aliases(canonical);

-- ─────────────────────────────────────────────────────────
-- notes — *모든* 노트의 공통 정체성·위치·lifecycle 헤드.
-- 도메인 별 확장 메타는 frontmatter 가 SSoT.
--
-- 위치 컬럼은 없다. id 가 곧 주소이고(`a.b.c` ↔ `cortex/a/b/c.md`) 경로는 그
-- 순수 함수라, 저장하면 자기 자신과 어긋날 수 있는 값이 하나 생길 뿐이다.
-- 계층을 세는 표면(query tree)도 id 접두사를 세지 별도 테이블을 읽지 않는다.
--
-- 활성/비활성 라벨은 없다. 차가운 지식을 숨기는 층(archived)도 없다 — 차갑다는 것은
-- 인출 비용을 만들지 않으므로 감출 이유가 없고, 비대한 지식은 감추는 게 아니라 분화한다
-- (brain: knowledge-fragmentation). hit_count/last_retrieved_at 은 순수 관측값이다.
-- ─────────────────────────────────────────────────────────
-- notes = 마크다운(SSoT)의 *순수 투영* — `notes = f(cortex/*.md)`. 전 컬럼이 파일/
-- frontmatter/본문에서 결정적으로 재생성됨 (rebuild 가 개념적으로 순수해진다). 비투영
-- brain-state(사용/활성/소스drift)는 아래 별도 테이블로 — NoteArtifacts 가 균일 보존.
CREATE TABLE IF NOT EXISTS notes (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  summary TEXT,
  priority TEXT NOT NULL DEFAULT 'lazy' CHECK (priority IN ('eager','lazy')),
  edited_at INTEGER NOT NULL DEFAULT 0,
  -- 의미적 부정 신호 (invalidate op). frontmatter 파생.
  stale INTEGER NOT NULL DEFAULT 0 CHECK (stale IN (0,1)),
  -- 구조화 문서: 따르는 템플릿 노트 id (frontmatter 파생, nullable).
  -- locked 와 함께 망각 면제(consolidate 후보 제외)의 SSoT 신호. derive 라벨 없음.
  template TEXT,
  -- 사람 전용 편집 — operations mutation 차단, 파일 직접 수정만 (frontmatter 파생).
  locked INTEGER NOT NULL DEFAULT 0 CHECK (locked IN (0,1)),
  word_count INTEGER NOT NULL DEFAULT 0,
  section_count INTEGER NOT NULL DEFAULT 0,
  -- 투영 identity: 파일 원문 전체의 해시. 증분 skip 과 verify L2 가 이 하나로 판정한다
  -- (초 단위 mtime 은 같은 초 편집을 가렸다 — 08-03).
  content_hash TEXT NOT NULL DEFAULT ''
);
-- note_usage = engram 의 활성 동역학 (memory-trace). 매 회상마다 갱신, 마크다운 밖.
CREATE TABLE IF NOT EXISTS note_usage (
  note_id TEXT PRIMARY KEY REFERENCES notes(id) ON DELETE CASCADE,
  hit_count INTEGER NOT NULL DEFAULT 0,
  last_retrieved_at INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL DEFAULT 0
);
-- note_source = 외부 source 파일 binding 의 drift 상태. sparse (source: 있는 노트만).
-- 관측 row 는 "무엇을"(decl_hash: 정규화된 checkable 선언 집합의 해시) "어떤 상태로"
-- (source_hash: 내용 지문) 봤는지를 함께 든다 — 선언 변경(투영이 따라감)과 내용
-- 드리프트(관측 불가침)를 구분하는 근거. 메타데이터 관측(mtime)은 여기 없다: freshness 는
-- 내용의 문제이고, 바이트가 달라도 같아질 수 있는 proxy 는 그 물음을 판정할 수 없다.
CREATE TABLE IF NOT EXISTS note_source (
  note_id TEXT PRIMARY KEY REFERENCES notes(id) ON DELETE CASCADE,
  source_hash TEXT,
  source_stale INTEGER NOT NULL DEFAULT 0 CHECK (source_stale IN (0,1)),
  decl_hash TEXT
);
CREATE INDEX IF NOT EXISTS idx_notes_priority ON notes(priority);
CREATE INDEX IF NOT EXISTS idx_notes_stale ON notes(stale);
CREATE INDEX IF NOT EXISTS idx_notes_template ON notes(template);
CREATE INDEX IF NOT EXISTS idx_notes_locked ON notes(locked);
CREATE INDEX IF NOT EXISTS idx_note_usage_last_retrieved ON note_usage(last_retrieved_at);
CREATE INDEX IF NOT EXISTS idx_note_source_stale ON note_source(source_stale);

-- ─────────────────────────────────────────────────────────
-- note_lifecycle_events — append-only 이력.
-- archive/invalidate/restore/unarchive/promote/created/flagged/flag_resolved 등.
-- notes.stale 는 *최신 state cache* — 진짜 history 는 여기.
-- ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS note_lifecycle_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  -- vocabulary 자유 — 코드 (handlers) 가 정의. 일반: created/invalidated/
  -- restored/revalidated/promoted/flagged/flag_resolved.
  reason TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_lifecycle_events_note
  ON note_lifecycle_events(note_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_lifecycle_events_kind
  ON note_lifecycle_events(kind);

-- ─────────────────────────────────────────────────────────
-- note↔tag 매핑
-- ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tags (
  note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  tag TEXT NOT NULL REFERENCES tag_vocab(tag) ON DELETE RESTRICT,
  PRIMARY KEY (note_id, tag)
);
CREATE INDEX IF NOT EXISTS idx_tags_tag ON tags(tag);

-- ─────────────────────────────────────────────────────────
-- note_extra — frontmatter 의 비-일급 필드(FrontmatterDoc.extra) 투영.
-- 도메인이 필요로 하는 메타(예: journal 의 affect)를 코드에 필드로 박지 않고
-- 노트가 스스로 들고 다니게 하는 자리. **파일이 SSoT** — 여기는 질의 가능한 거울일
-- 뿐이라 타임스탬프도 두지 않는다 (파일이 재생산하지 못하는 값은 투영이 아니다).
-- 지식만 옮긴 뇌가 이 값을 잃지 않는 이유가 그것.
-- ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS note_extra (
  note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  PRIMARY KEY (note_id, key)
);
CREATE INDEX IF NOT EXISTS idx_note_extra_key ON note_extra(key, value);

-- ─────────────────────────────────────────────────────────
-- note↔note 그래프. kind 는 코드 (service/links.py 의 KIND_*) 와 동기.
-- 'promoted_to' 도 일반 link kind — domain 이 노트 간 승격 관계를 그래프로 표현.
-- ripple_flags 와 일관되게 vocabulary 는 자유 (CHECK 없음). 검증은 L3.
-- 신규 kind 'assoc' = LLM 이 capture 때 심은 의미 연상 edge (propose_link).
-- provenance — LLM-proposed edge 의 생산자 id (algorithmic edge 는 NULL).
-- 노이즈 모델 batch 단위 회수(purge_enrichment)를 위해 보관.
-- ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS note_links (
  src TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  dst TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  weight REAL NOT NULL DEFAULT 1.0,
  created_at INTEGER NOT NULL,
  last_activated_at INTEGER NOT NULL,
  provenance TEXT,
  PRIMARY KEY (src, dst, kind),
  CHECK (src != dst)
);
CREATE INDEX IF NOT EXISTS idx_note_links_src ON note_links(src);
CREATE INDEX IF NOT EXISTS idx_note_links_dst ON note_links(dst);
CREATE INDEX IF NOT EXISTS idx_note_links_kw ON note_links(kind, weight DESC);

-- ─────────────────────────────────────────────────────────
-- note_retrieval_terms — LLM 이 capture 때 emit 하는 retrieval 보조 텍스트.
-- 설계가 표면에서 읽히도록 first-class 테이블로 둔다.
--   alias — 동의어·약어·한↔영 짝·조사 뗀 어근. BM25 synonymy 사각지대를 메움.
--   cue   — "이 노트를 찾을 법한 질문". retrieval 을 query↔query 매칭으로(write-time HyDE).
-- status pending→active/rejected 전이는 외부 op 가 아니라 llmemory 내부 검증
-- pass (Validation) 가 직접 쓴다. rejected term 도 행을 남겨 재검증(corpus 변하면
-- 통과할 수도) 을 가능하게 한다 — add_retrieval_terms 재제안이 rejected 를 pending 으로
-- 재개하며, 그때 provenance/created_at 은 새 제안이 승계한다(행은 항상 최신 제안을 기술;
-- 재검증 윈도 리셋에 created_at 갱신이 필요).
-- ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS note_retrieval_terms (
  note_id    TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  kind       TEXT NOT NULL,            -- 'alias' | 'cue'
  term       TEXT NOT NULL,            -- alias 구(句) 또는 cue 질문
  status     TEXT NOT NULL DEFAULT 'pending'
             CHECK (status IN ('pending','active','rejected')),
  provenance TEXT,                     -- 예: "forge:capture:claude-sonnet-4-6"
  reject_reason TEXT,                  -- rejected 일 때 사유 (roundtrip_fail / idf_common / ...)
  created_at   INTEGER NOT NULL,
  validated_at INTEGER,
  PRIMARY KEY (note_id, kind, term)
);
CREATE INDEX IF NOT EXISTS idx_nrt_status ON note_retrieval_terms(status);
CREATE INDEX IF NOT EXISTS idx_nrt_status_created ON note_retrieval_terms(status, created_at);
CREATE INDEX IF NOT EXISTS idx_nrt_provenance ON note_retrieval_terms(provenance);

-- ─────────────────────────────────────────────────────────
-- note_vectors — note_links + 태그에서 유도한 dense 벡터. PPMI + truncated SVD.
-- 외부 임베딩 모델 0 — word2vec/GloVe 가 하는 co-occurrence 행렬 분해와 동일.
-- 빌드 메타는 meta KV 에: vectors.built_at / vectors.dim.
-- ─────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────
-- note_ref_markers — 본문의 인용 마커(`id`/[[id]]) 를 *해석 성공 무관하게* 영속화.
-- reference 엣지는 이 인덱스 ⋈ notes 의 물질화다: 마커를 쓴 시점에 대상이 없어도
-- 행은 남고, 대상 노트가 나중에 생기면 그 노트의 업서트가 inbound 엣지를 완성한다
-- (스캔/생성 순서 의존 소거 — 07-29). 대상 없는 행 = 미해결 인용(관측 가능).
-- 쓰기는 Notes.refreshReferenceLinks 단일 경로. 본문 파생이라 reconstructable.
-- ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS note_ref_markers (
  src TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  marker TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (src, marker)
);
CREATE INDEX IF NOT EXISTS idx_note_ref_markers_marker ON note_ref_markers(marker);

CREATE TABLE IF NOT EXISTS note_vectors (
  note_id  TEXT PRIMARY KEY REFERENCES notes(id) ON DELETE CASCADE,
  dim      INTEGER NOT NULL,
  vec      BLOB NOT NULL,              -- dim × Float32, little-endian
  built_at INTEGER NOT NULL
);

-- ─────────────────────────────────────────────────────────
-- FTS5 (contented — body 보유. application-side sync via notes.upsert/delete)
-- 노트당 1+N rows — *섹션 단위* 인덱싱:
--   head row (section=''): title/summary/enrich + 본문 *전체* — v1 의 노트-통짜
--   문서 row. cross-section·title+body 다중 토큰 증거 누적의 floor.
--   섹션 rows: section = full path ("## A > ### B"), body = 그 섹션의 *직속*
--   내용만 (자식 섹션 제외) — 국소 매치가 head 의 길이 패널티를 이기고 올라오는
--   passage 오버레이이자 매치 위치 귀속.
-- 노트 단위 결과는 소비자가 GROUP BY id + best-rank(MIN) 로 집계 —
-- 사실상 max(문서 점수, 최고 passage 점수). head 가 이기면 귀속 없음(null) =
-- "한 섹션에 국한되지 않는 매치" 의 명시 표현.
-- enrich 셀 = note_retrieval_terms 중 status='active' 인 alias/cue 를 개행으로
-- 이어붙인 텍스트 — head row 에만 산다.
-- 쓰기는 Notes.reindexFTS 단일 경로 — raw INSERT 금지.
-- ─────────────────────────────────────────────────────────
CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
  id UNINDEXED, section UNINDEXED, title, summary, body, enrich,
  tokenize = 'unicode61 remove_diacritics 2'
);

-- ─────────────────────────────────────────────────────────
-- events (mutation/hygiene/retrieval trace). vocabulary 자유 (CHECK 없음) —
-- caller (Events.swift) 가 정의. 압축은 raw 삭제 — 단 retrieval 이벤트는 삭제 전에
-- activity_windows/retrieval_hits 로 승계된다 (Activation.deriveWindows, integrate 가
-- 순서 강제. 승계 후 폐기 — 뇌가 발화 로그 대신 흔적을 남기는 것과 같다).
-- ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts INTEGER NOT NULL,
  kind TEXT NOT NULL,
  session_id TEXT,
  payload TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts);
CREATE INDEX IF NOT EXISTS idx_events_kind ON events(kind);
CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id);

-- KV
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);

-- ─────────────────────────────────────────────────────────
-- ripple_flags — drift 큐. consolidator 가 처리할 신호.
-- flag vocabulary 는 코드에서 자유.
-- flag_count + last_flagged_at: 재발 신호 보존 (ON CONFLICT 시 increment).
-- ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ripple_flags (
  note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  flag TEXT NOT NULL,
  reason TEXT,
  created_at INTEGER NOT NULL,
  last_flagged_at INTEGER NOT NULL,
  flag_count INTEGER NOT NULL DEFAULT 1,
  resolved_at INTEGER,
  PRIMARY KEY (note_id, flag)
);
CREATE INDEX IF NOT EXISTS idx_ripple_flags_unresolved ON ripple_flags(flag, resolved_at);

-- ─────────────────────────────────────────────────────────
-- entity_index — entity → note 역인덱스 (cue-driven recall).
-- ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS entity_index (
  entity TEXT NOT NULL,
  note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  last_seen_at INTEGER NOT NULL,
  hit_count INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (entity, note_id)
);
CREATE INDEX IF NOT EXISTS idx_entity_index_entity ON entity_index(entity);
CREATE INDEX IF NOT EXISTS idx_entity_index_note ON entity_index(note_id);
CREATE INDEX IF NOT EXISTS idx_entity_index_last_seen ON entity_index(last_seen_at);

-- ─────────────────────────────────────────────────────────
-- candidate_dismissals — 정리 후보(standing query)를 "통짜로 둔다"고 판단한 결정.
-- 뇌의 습관화(habituation): 변화 없이 반복되는 후보 자극에 대한 반응을 죽인다.
-- 행을 남겨 같은 후보의 재부상을 막고, *노트가 변하면* 재부상(탈습관화)시킨다.
--   word_count/section_count — 기각 시점 shape 스냅샷 (예측오차의 baseline).
--   dismiss_count — 누적 기각 횟수. 재부상 역치가 이 값에 따라 깊어진다(ratchet).
--   generation — 기각 시점의 전역 candidate_generation. 전역 격변(sensitization)이
--                이 값을 bump 하면 더 낮은 generation 의 기각은 한 번 재개방된다.
-- 비투영 brain-state — NoteArtifacts.identityTables 로 rebuild/migrate/merge 생존.
-- 판단(split/keep)은 LLM, 게이트 산술(언제 재부상)은 코드. 채널-특이적 — retrieval
-- 엔 영향 0, 후보 쿼리만 게이트한다.
-- ─────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────
-- activity_windows / retrieval_hits — 활성화 기록 (기질 2층).
-- 윈도는 세션의 *추정*이다 (Type-Reality): label 은 호출자 correlation id
-- (--session-id) 가 있을 때만 사실이고, NULL-label 윈도는 시간 근접(gap)
-- 클러스터링의 휴리스틱이다. 추정임을 타입 이름에 남긴다 — retrieval_session 아님.
-- raw events 는 retention 후 폐기되지만 이 두 테이블은 영속 — 승계 후 폐기.
-- 파생은 Activation.deriveWindows 단일 경로, watermark 로 정확히 한 번.
-- ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS activity_windows (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at INTEGER NOT NULL,
  ended_at INTEGER NOT NULL,
  label TEXT,
  query_count INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_activity_windows_span ON activity_windows(started_at, ended_at);
CREATE INDEX IF NOT EXISTS idx_activity_windows_label ON activity_windows(label);

-- note_id 에 FK 없음: 노트가 나중에 삭제돼도 관측은 사실로 남는다.
-- used_signal 은 약한 타입 — 인과적 사용 증명이 아니다:
--   reported        호출자 신고 (mark_used, evidence 없음)
--   content_overlap 응답 텍스트와의 겹침 휴리스틱 통과 (mark_used + response)
CREATE TABLE IF NOT EXISTS retrieval_hits (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  window_id INTEGER NOT NULL REFERENCES activity_windows(id) ON DELETE CASCADE,
  note_id TEXT NOT NULL,
  surfaced_at INTEGER NOT NULL,
  cmd TEXT NOT NULL,
  surface_kind TEXT NOT NULL CHECK (surface_kind IN ('hit','expand')),
  used_signal TEXT CHECK (used_signal IN ('reported','content_overlap')),
  used_at INTEGER
);
CREATE INDEX IF NOT EXISTS idx_retrieval_hits_window ON retrieval_hits(window_id);
CREATE INDEX IF NOT EXISTS idx_retrieval_hits_note ON retrieval_hits(note_id, surfaced_at);

-- ─────────────────────────────────────────────────────────
-- genome / genome_events — 가소성 파라미터의 브레인별 현재값 (기질 3층의 데이터 절반).
-- *선언*(카탈로그: bounds·wild-type·mutable)은 코드(Service/Genes.swift)가 SSoT 다 —
-- 규칙은 종-수준이고 검증 가능해야 하므로 데이터가 아니다. 여기 저장되는 것은
-- 브레인별 *현재값*(epigenome)과 그 변경 이력뿐. 행이 없는 유전자는 wild-type 로 동작.
-- 쓰기는 두 경로만: set_gene op(사람 escape hatch — 전 유전자) 와
-- consolidate homeostasis(결정론 규칙 — mutable 유전자만).
-- ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS genome (
  gene_id TEXT PRIMARY KEY,
  value REAL NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS genome_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  gene_id TEXT NOT NULL,
  old_value REAL,
  new_value REAL NOT NULL,
  cause TEXT NOT NULL,
  detail TEXT,
  ts INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_genome_events_gene ON genome_events(gene_id, ts);

CREATE TABLE IF NOT EXISTS candidate_dismissals (
  note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  dismiss_count INTEGER NOT NULL DEFAULT 1,
  word_count INTEGER NOT NULL DEFAULT 0,
  section_count INTEGER NOT NULL DEFAULT 0,
  generation INTEGER NOT NULL DEFAULT 0,
  reason TEXT,
  last_dismissed_at INTEGER NOT NULL,
  PRIMARY KEY (note_id, kind)
);
CREATE INDEX IF NOT EXISTS idx_candidate_dismissals_kind ON candidate_dismissals(kind);

-- ─────────────────────────────────────────────────────────
-- corpus_dismissals — 노트가 아닌 *코퍼스* 사실에 대한 기각 결정.
-- candidate_dismissals 와 같은 습관화 루프지만 대상 타입이 다르다: 위는
-- notes(id) FK 를 타는 노트 스코프고, 여기는 어떤 노트도 소유하지 않는 사실
-- (예: 태그 쌍 '금리'·'금융' 이 edit-distance 1) 이라 걸 FK 가 없다. FK 로
-- 억지로 밀어넣으면 note_id="" 가 되어 어떤 행도 제약을 만족하지 못하고,
-- 카탈로그는 dismissible 이라 광고하는데 문은 닫혀 있는 상태가 된다.
--   target_key — 스코프 안정 식별자. 사실 자체가 identity 다 (개수·순서 아님).
--   재개방 게이트는 generation(sensitization) 뿐 — 노트 shape 는 코퍼스 사실의
--   증거가 아니므로 탈습관화 축이 없다 (Dismissals.corpusGate).
-- notes 에 FK 가 없으므로 rebuild 의 DELETE FROM notes cascade 를 그대로 생존한다.
-- ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS corpus_dismissals (
  target_key TEXT NOT NULL,
  kind TEXT NOT NULL,
  dismiss_count INTEGER NOT NULL DEFAULT 1,
  generation INTEGER NOT NULL DEFAULT 0,
  reason TEXT,
  last_dismissed_at INTEGER NOT NULL,
  PRIMARY KEY (target_key, kind)
);
CREATE INDEX IF NOT EXISTS idx_corpus_dismissals_kind ON corpus_dismissals(kind);
"""#

    // MARK: - Initializer
    public init() { }

    // MARK: - Lifecycle
    public func migrate(_ db: Database) throws {
        try db.execute(sql: Self.schema)
    }
}
