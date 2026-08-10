# [8] 부하 종료 - 최종 정합성 확인

모든 케이스(01~07)가 끝난 뒤 한 번에 확인.

## Outbox 적체 없는지 (PENDING/FAILED가 0에 수렴해야 함)

```sql
SELECT publish_status, COUNT(*) FROM outbox_events GROUP BY publish_status;
```

## 처리 결과 분포

```sql
SELECT status, COUNT(*) FROM processed_events GROUP BY status;
```

## 재고 음수 절대 없어야 함

```sql
SELECT * FROM master_inventory WHERE stock < 0;
```

## Pod 다시 정상 개수로 줄어드는지

```powershell
kubectl get hpa -n ecommerce
kubectl get pods -n ecommerce
```