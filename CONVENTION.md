# 코드 규약

이 문서는 이 패키지의 **설계 규칙**이다. 규칙이지 동작이 아니므로 테스트가 아니라 여기에 산다
— 유닛 테스트는 프로덕션 코드의 *행위* 를 검증하는 자리이고, "파일 이름이 무엇으로 끝나는가",
"이 타입을 어디서 이름 부르는가" 는 행위가 아니라 우리가 합의한 형태다.

리뷰가 이 문서의 집행자다.

## 1. 계층 — Feature → Service → Module

방향은 한쪽이다. 아래 계층은 위 계층의 타입을 **이름조차 부르지 않는다** — 잘못된 타입의
필드는 조용히 컴파일되고, 나중에 누가 쓰라고 놓아둔 것처럼 읽힌다.

Module 안쪽의 방향은 규정하지 않는다 — `Module/Lint` 가 `Module/DB` 트랜잭션을 부르는 것은
정상이고, 반대(DB 가 Lint 를 부르는 것)는 없다. 필요해지는 날 그때 규칙을 만든다.

- `import GRDB` 는 `Module/` 안에서만.
- 문자열 SQL(`sql:`, `db.execute(`, `StatementArguments(`)은 `Module/DB/` 안에서만.
- `storage.run` / `storage.read` — 스코프를 여는 것은 Service 계층뿐. 표면(CLI/Feature)은
  서비스의 도메인 메서드를 부른다.
- `transaction.perform(...)` 직접 호출은 `Module/DB/` 안에서만 (트랜잭션끼리의 합성).
  나머지는 `scope.run`.
- `GRDBScope(` / `GRDBReadScope(` 생성은 `GRDBStorage` / `GRDBScope` 만.
  스코프는 롤백 경계를 소유한 `storage.run/read` 안에서만 존재한다.
- `storage.connect()` / `writeLock` 은 `GRDBStorage`, `Session`(부트스트랩), `Config`(워밍)만.
- CLI 는 SQL 을 갖지 않고 GRDB 를 import 하지 않는다.

## 2. 서비스는 계약으로 참조한다 (POP)

- 모든 서비스는 `XServiceable` 프로토콜을 먼저 갖고, 구현체가 그것을 선언한다.
- 모든 참조는 `any XServiceable`. **concrete 타입을 이름 부르는 곳은 조립하는 자리 하나뿐**
  (`Feature/Container.swift`).
- 이유는 의례가 아니다 — 구현 타입을 이름 부르는 호출부는 계약 너머로 손을 뻗을 수 있고,
  그 손길 하나하나가 아무도 선언하지 않은 의존성이다.
- 계약의 폭은 **협력자가 실제로 부르는 것**까지다. 테스트가 통과하게 하려고 넓히면 계약은
  구현의 사본이 되고 존재 이유가 사라진다. 동기 코어가 필요한 테스트는 fixture 에서
  concrete 타입을 직접 조립한다.
- 프로토콜 요구사항은 기본 인자를 실을 수 없다 — 기본값은 파사드(`Query`/`Operations`/`Index`)에만.
- 계약은 협력자 *객체* 를 반환하지 않는다(`var engine: OperationsEngine`). 행위를 준다.
- **스코프는 서비스 경계를 건너지 않는다.** 서비스 *계약* 은 기능만 말하고 트랜잭션은 안에서
  알아서 연다. 협력자가 *자기 스코프 안에서* 시켜야 하는 일이면 그건 그 서비스의 기능이 아니라
  **트랜잭션**이다 — `Module/DB/Transaction/` 으로 내리고 호출부가 `scope.run` 한다.
  계약에 실린 스코프 인자는 "이 일은 사실 한 층 아래 것"이라는 영수증이다.
  한 서비스가 자기 async 문 안에서 쓰는 internal sync core 는 스코프를 받아도 된다
  (`RetrievalService.related(_ scope:)`) — 밖으로 건네지 않는 한 그건 그 서비스의 내부다.

## 3. 조립은 합성 루트에서

- `GRDBStorage` 생성은 `Session` 만, `Session` 생성은 `Brain` 만, `Container` 조립은 `Brain` 만.
- 서비스 인스턴스(`XxxService(`, `OperationsEngine(`)는 `Container` 에서 한 번 만들어 주입한다.
  스스로 협력자를 조립하는 객체는 없다.
- 전역 *상태* 를 두지 않는다. **선은 static 이냐가 아니라 무엇을 쥐고 있느냐다**:
  - **상태나 협력자를 가지면 인스턴스** — 소유자가 `private let x = X()` 로 쥐고, 주입이
    필요하면 계약으로 받는다. `enum X { static func … }` 안에 행위를 담지 않는다.
  - **순수 계산·상수면 static** — 같은 입력에 같은 출력이고, 쥘 것도 갈아끼울 것도 없다.
    인스턴스로 감싸도 획득하는 게 없다 (`Policy.fresh("n")`, 닫힌 어휘, 정규식).
- 명명된 예외 하나: **`Genes`/`Config` 의 프로세스 캐시**. brain 하나에 바인딩된 프로세스
  전역 상태이고, 그게 무엇인지 `Session` 이 문서로 안고 있다. 새로 만들지 않는다 — 이건
  "이미 그렇게 산다"는 기록이지 허가가 아니다.

## 4. 한 파일에 한 타입

- 최상위 타입 하나, 파일 이름이 곧 그 타입 이름.
- `Foo+Bar.swift` 같은 확장 파일은 이름이 가리키는 타입에 **더하기만** 한다 — 타입을 선언하지 않는다.
- 딸린 타입(값 어휘, 에러, IO 레코드)은 그 영역의 `Model/` 로, 역할 묶음은 `Rule/` `Handler/`
  `Support/` 로 내려간다.
- MARK 4구획: Property → Initializer → Public → Private. 독립 프로토콜 파일엔 MARK 없음,
  빈 MARK 는 붙여 쓴다.

## 5. 중복 선언을 만들지 않는다

- **게이트 술어**(`archived = 0`, `template IS NULL`, `priority = 'eager'`,
  `NOT EXISTS (SELECT 1 FROM candidate_dismissals …` 등)는 `Policy` 에만 쓰고 나머지는 조합한다.
  쿼리마다 손으로 적으면 하나씩 어긋난다. SQL 조각을 만드는 것들(`Policy`,
  `Search.staleClause`, `Links.rankWeightSQL`, `Framing.ftsQuery`)은 전부 `Module/DB` 안에
  산다 — DB 의 표현력은 DB 모듈 안에 있고, 위로 나가는 것은 매핑된 결과 타입뿐이다.
- **필수 필드**는 `OperationSchema` 에만 선언한다. 핸들러가 다시 검사하면 규칙의 사본이 생기고,
  사본은 표류한다(`missingRequiredField(` 는 스키마/엔진의 것).
- **인덱스 행의 *정의*(`INSERT INTO notes_fts`)는 `ReindexNoteFTSTransaction` 한 곳.**
  두 번째 INSERT 는 "행이 무엇인가"에 대한 두 번째 정의다. 삭제는 소유 트랜잭션이 하고
  (`DeleteNoteRowTransaction`, `ClearNoteFTSTransaction`, `PruneFtsOrphansTransaction`,
  rebuild), `enrich` 갱신은 `SyncNoteEnrichTransaction` 이 정본이다 —
  `ValidatePendingTermsTransaction` 의 `UPDATE … SET enrich` 두 개는 IDF 측정용 임시
  probe/restore 쌍이라 정의가 아니다.
- 소스 재기준선(`RebaseNoteSourceTransaction` / `InheritSourceObservationTransaction`)은 ops
  핸들러와 Source 트랜잭션들만. 읽기 경로는 관측만 하고 판단하지 않는다.

## 6. 오퍼레이션 계층

- 거부는 문자열이 아니라 케이스로 한다 — `OperationError`, `NSError(domain:)` 금지.
  케이스는 주어만 싣고 문장은 `description` 이 쓴다.
- `OperationsEngine.apply` 는 내부 호출자를 갖지 않는다. 자동 경로가 상태를 삼키면 안 되므로,
  모든 진입은 표면 → `OperationsService`(디코드 문 하나)를 지난다.

## 7. SQL — 이 둘만 기계가 본다

```
tool/lint-sql.py
```

- `LIMIT` 로 자르는 쿼리는 유니크 컬럼으로 전순서를 만든다. 아니면 살아남는 행은 SQLite 가
  먼저 닿은 것이 된다.
- 게이트 술어는 `Policy` 밖에 손으로 쓰지 않는다 (§5).
- `INSERT INTO notes_fts` 는 `ReindexNoteFTSTransaction` 밖에 없다 (§5).

**왜 얘들만 도구인가**: 검사 대상이 코드의 *모양* 이 아니라 SQLite 에 실제로 가는 **문자열**
이다. 그리고 행위 테스트로는 원리상 안 잡힌다 — 틀린 WHERE 절은 예외를 던지지 않고 그냥
다른 행을 돌려준다. 빨간불이 뜰 자리가 없다. 유닛 테스트의 집이 아닐 뿐 검사 자체는 살아야
해서, 테스트 타깃 밖의 lint 로 산다.

---

나머지 규칙들은 한때 소스 텍스트를 스캔하는 테스트로 강제됐다. 그 방식은 규칙을 검증한 게
아니라 *철자* 를 검증했고(접미사·경로·주석 마커), 리팩터링 한 번에 눈이 멀거나 헛발질했다.
규칙은 규칙으로 두고, 테스트는 행위에만 쓴다.
