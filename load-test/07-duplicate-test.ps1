# [7] DUPLICATE 감지 - 같은 event_id 두 번 발행
#
# Order API를 거치면 매번 새 event_id가 생겨서 중복이 재현되지 않으므로,
# Kinesis에 직접 같은 payload를 두 번 발행한다.

$eventId = [guid]::NewGuid().ToString()
$eventJson = @{
    event_id = $eventId
    event_type = "ORDER_CREATED"
    order_id = 999999
    product_id = "101"
    quantity = 1
    created_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
} | ConvertTo-Json -Compress

Write-Host "event_id: $eventId"

# 같은 이벤트 2번 발행
aws kinesis put-record --stream-name ecommerce-order-events --partition-key "999999" --data $eventJson
Start-Sleep -Seconds 2
aws kinesis put-record --stream-name ecommerce-order-events --partition-key "999999" --data $eventJson

<#
실행:
  .\load-test\07-duplicate-test.ps1

확인 (SQL):
  SELECT * FROM processed_events WHERE order_id = 999999;
  -- 1건만 (SUCCESS), 두 번째는 DUPLICATE로 스킵됐는지 확인

  SELECT stock FROM master_inventory WHERE product_id = '101';
  -- 재고가 한 번만 차감됐는지 (두 번 안 깎였는지) 이전 값과 비교

확인 (kubectl):
  kubectl logs -n ecommerce <worker파드이름> --tail=30 | Select-String "999999"

참고: Worker 로그 포맷이 실제로 event_id를 그대로 찍는지는 3번(차현지) 코드 기준 확인 필요.
#>