// 부하 테스트 단계
// 0 → 10 VUs
// 10 → 50 VUs
// 50 → 100 VUs
// 마지막에는 0 VUs로 감소

// path 찾을 수 없어서 명령어 실행
// & "C:\Program Files\k6\k6.exe" version

import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
//   // Test 
//   stages: [
//   { duration: "10s", target: 10 },
//   { duration: "10s", target: 0 },
// ],
    
  stages: [
    { duration: "30s", target: 10 },
    { duration: "1m", target: 50 },
    { duration: "1m", target: 100 },
    { duration: "30s", target: 0 },
  ],

  thresholds: {
    http_req_failed: ["rate<0.05"],
    http_req_duration: ["p(95)<1000"],
  },
};

// 3개 기종 × 4개 색상 = 총 12개 상품
// 101~104: Fold
// 201~204: Flip
// 301~304: Ultra
const productIds = [
  "101", "102", "103", "104",
  "201", "202", "203", "204",
  "301", "302", "303", "304",
];

export default function () {
  const productId =
    productIds[Math.floor(Math.random() * productIds.length)];

  // 한정 판매 정책에 따라 주문 수량은 1대로 고정
  const quantity = 1;
  const payload = JSON.stringify({
    product_id: productId,
    quantity: quantity,
  });

  const response = http.post(
    `${__ENV.BASE_URL}/orders`,
    payload,
    {
      headers: {
        "Content-Type": "application/json",
      },
      tags: {
        api: "create-order",
      },
    }
  );

  check(response, {
    "status is 201": (res) => res.status === 201,

    "response has order_id": (res) => {
      try {
        return res.json("order_id") !== undefined;
      } catch {
        return false;
      }
    },

    "status is CREATED": (res) => {
      try {
        return res.json("status") === "CREATED";
      } catch {
        return false;
      }
    },
  });

  sleep(0.1);
}