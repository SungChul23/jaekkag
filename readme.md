# role-3: 재고처리 정합성

### Kinesis Consumer

- boto3 `get_records()` 응답 형식의 `Data` 디코딩 구현
- 주문 이벤트 딕셔너리 복원 구현
- Inventory Worker 재고 처리 함수 연결
- mock 기반 단위 테스트 완료
- 실제 Kinesis 스트림 연결은 팀 공통 인프라 구축 후 진행 예정