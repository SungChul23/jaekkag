# [7] DUPLICATE 감지 - 같은 event_id 두 번 발행
#
# Order API를 거치면 매번 새 event_id가 생겨서 중복이 재현되지 않으므로,
# Kinesis에 직접 같은 payload를 두 번 발행한다.

$eventId = [guid]::NewGuid().ToString()
$eventJson = @{
    event_id   = $eventId
    event_type = "ORDER_CREATED"
    order_id   = 999999
    product_id = "101"
    quantity   = 1
    created_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
} | ConvertTo-Json -Compress

Write-Host "event_id: $eventId"

# BOM 없는 UTF-8로 저장 (Python json.loads가 BOM을 못 읽음)
$tmpFile = New-TemporaryFile
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($tmpFile.FullName, $eventJson, $utf8NoBom)

Write-Host "발행할 payload: $eventJson"

aws kinesis put-record --stream-name ecommerce-order-events --partition-key "999999" --data "fileb://$($tmpFile.FullName)"

Start-Sleep -Seconds 2

aws kinesis put-record --stream-name ecommerce-order-events --partition-key "999999" --data "fileb://$($tmpFile.FullName)"

Remove-Item $tmpFile.FullName