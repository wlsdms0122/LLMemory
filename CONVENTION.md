# 코드 규약

이 문서는 이 패키지의 **설계 규칙**이다. 규칙이지 동작이 아니므로 테스트가 아니라 여기에 산다
— 유닛 테스트는 프로덕션 코드의 *행위* 를 검증하는 자리이고, "파일 이름이 무엇으로 끝나는가",
"이 타입을 어디서 이름 부르는가" 는 행위가 아니라 우리가 합의한 형태다.

리뷰가 이 문서의 집행자다.

## 1. 계층 — Feature → Service → Module

방향은 한쪽이다. 아래 계층은 위 계층의 타입을 **이름조차 부르지 않는다** — 잘못된 타입의
필드는 조용히 컴파일되고, 나중에 누가 쓰라고 놓아둔 것처럼 읽힌다.

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

## 3. 조립은 합성 루트에서

- `GRDBStorage` 생성은 `Session` 만, `Session` 생성은 `Brain` 만, `Container` 조립은 `Brain` 만.
- 서비스 인스턴스(`XxxService(`, `OperationsEngine(`)는 `Container` 에서 한 번 만들어 주입한다.
  스스로 협력자를 조립하는 객체는 없다.
- 전역 상태를 두지 않는다. `enum X { static func … }` 로 행위를 담지 말고, 소유자가
  `private let x = X()` 로 쥔다. 닫힌 어휘(링크 종류, 예약 필드, 정규식)만 타입 멤버로 남는다.

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
  쿼리마다 손으로 적으면 하나씩 어긋난다.
- **필수 필드**는 `OperationSchema` 에만 선언한다. 핸들러가 다시 검사하면 규칙의 사본이 생기고,
  사본은 표류한다(`missingRequiredField(` 는 스키마/엔진의 것).
- `notes_fts` 쓰기는 `ReindexNoteFTSTransaction` 한 곳. 두 번째 writer 는 인덱스 행이
  무엇인가에 대한 두 번째 정의다.
- 소스 재기준선(`RebaseNoteSourceTransaction` / `InheritSourceObservationTransaction`)은 ops
  핸들러와 Source 트랜잭션들만. 읽기 경로는 관측만 하고 판단하지 않는다.

## 6. 오퍼레이션 계층

- 거부는 문자열이 아니라 케이스로 한다 — `OperationError`, `NSError(domain:)` 금지.
  케이스는 주어만 싣고 문장은 `description` 이 쓴다.
- `OperationsEngine.apply` 는 내부 호출자를 갖지 않는다. 자동 경로가 상태를 삼키면 안 되므로,
  모든 진입은 표면 → `OperationsService`(디코드 문 하나)를 지난다.

## 7. SQL

- `LIMIT` 로 자르는 쿼리는 유니크 컬럼으로 전순서를 만든다. 아니면 살아남는 행은 SQLite 가
  먼저 닿은 것이 된다.

---

이 규칙들은 한때 소스 텍스트를 스캔하는 테스트로 강제됐다. 그 방식은 규칙을 검증한 게 아니라
*철자* 를 검증했고(접미사·경로·주석 마커), 리팩터링 한 번에 눈이 멀거나 헛발질했다.
규칙은 규칙으로 두고, 테스트는 행위에만 쓴다.
