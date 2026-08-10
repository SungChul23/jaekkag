# [4] Kinesis 이벤트 급증 - Worker lag 관측 (관찰)

k6 스파이크(`02-spike-test.js`)가 도는 동안 별도 터미널에서 실행.
Grafana 대시보드가 켜져 있으면 그걸로 대체 가능 (`outbox_pending_events` 패널도 함께 확인).

## Iterator Age (Worker가 못 따라가고 지연되는지)

```powershell
aws cloudwatch get-metric-statistics `
  --namespace AWS/Kinesis `
  --metric-name GetRecords.IteratorAgeMilliseconds `
  --dimensions Name=StreamName,Value=ecommerce-order-events `
  --start-time (Get-Date).AddMinutes(-5).ToString("yyyy-MM-ddTHH:mm:ssZ") `
  --end-time (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ") `
  --period 60 --statistics Maximum
```

## 임계 확인 (부하 종료 후) - 샤드 3개가 감당했는지

```powershell
aws cloudwatch get-metric-statistics `
  --namespace AWS/Kinesis `
  --metric-name WriteProvisionedThroughputExceeded `
  --dimensions Name=StreamName,Value=ecommerce-order-events `
  --start-time (Get-Date).AddMinutes(-5).ToString("yyyy-MM-ddTHH:mm:ssZ") `
  --end-time (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ") `
  --period 60 --statistics Sum
```

0이면 여유 있음 -> 다음 리허설엔 02-spike-test.js의 target을 600~800으로 올려도 됨.