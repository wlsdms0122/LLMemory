# llmemory

자기성장형 에이전트의 메모리 CLI 패키지. markdown 노트(`cortex/`)를 SQLite+FTS5
(`data/memory.db`)와 동기화해 검색·연상 탐색·재구조화를 제공한다.

**사용법(에이전트 가이드)은 [`document/GUIDE.md`](document/GUIDE.md)** —
이 README 는 패키지(레포지토리) 설명만 담는다. GUIDE.md 는 바이너리에 임베드되어
`llmemory init` 시 `<state-root>/README.md` 로 복사된다 — 모든 brain 이 자기 매뉴얼을
갖고 다닌다.

## 셋업

클론 직후 한 번 (tuist `generate` 처럼):

```
tool/set-up.sh
```

`document/` 의 markdown 을 `Sources/LLMemory/Resource/{Guide,Innate}.swift` 로
임베드한다. `Resource/` 는 gitignore 된 로컬 산출물(`.build` 와 같은 성격)이라
**setup 없이는 컴파일되지 않는다.** `document/` 를 수정했으면 다시 실행한다 —
markdown 과 임베드 사본의 drift 는 byte-equality 테스트가 fail-loud 로 잡는다.

## 구조

```
Sources/
  LLMemory/           — 코어 라이브러리 (Feature: Query/Ops/Index/Consolidate/…, Service, Module)
    Resource/         — set-up.sh 생성물 (gitignored): Guide.swift, Innate.swift
  LLMemoryCLI/        — CLI (swift-argument-parser), 실행 파일 llmemory
Tests/
  LLMemoryTests/      — 유닛 + 실바이너리 CLI 통합 테스트
document/
  GUIDE.md         — 에이전트용 사용 가이드 (SSoT)
  innate/*.md         — 선천 지식 (SSoT) — init/update 시 cortex/.innate/ 에 심긴다
tool/
  set-up.sh            — document/ → Sources/LLMemory/Resource/ 임베드 생성
  deploy.sh           — setup → release 빌드 → build/llmemory
```

## 빌드 / 테스트

```
tool/set-up.sh   # 최초 1회 (또는 document/ 수정 후)
swift build
swift test
```

의존성: GRDB(SQLite), swift-argument-parser, Yams. `note_vectors`(PPMI+SVD)는
Accelerate(LAPACK) 링크.

## 배포

```
tool/deploy.sh   # → build/llmemory
```

setup 을 먼저 돌려 임베드를 최신으로 만든 뒤 release 빌드한다. 바이너리는 단일
파일로 배포된다(사이드카 리소스 없음 — 가이드가 임베드인 이유). `build/llmemory`
를 어디로 가져가느냐는 소비자의 일이다.

## 설계 원칙 (요약)

- **Anchor-free**: 상태 위치는 `--home` 으로만. 바이너리 위치·외부 경로 가정 없음.
- **SSoT**: cortex/ markdown 이 진실, DB 는 파생 — `data/memory.db` 를 지우고
  `init` 하면 재구성된다.
- **탈 하드코딩**: llmemory 는 자기 자신에 대한 것만 갖는다. 갓 init 한 brain 은
  축·태그 0개에서 시작해 ops 로 자란다. 선천적인 것은 `innate` 축 하나와
  `cortex/.innate/` 의 선천 지식뿐.
- **LLM 0**: 모든 query/consolidate 는 알고리즘. LLM artifact(enrichment)는
  외부 client 가 생성하고 llmemory 가 검증한다.

상세 계약은 각 명령의 `--help` 와 `ops describe <op>` 가 SSoT.
