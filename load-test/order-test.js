// 부하 테스트 단계
// 0 → 10 VUs
// 10 → 50 VUs
// 50 → 100 VUs
// 마지막에는 0 VUs로 감소

// 각 가상 사용자는 다음 형식의 주문 요청을 반복 전송
// {
//   "product_id": 101~104, 201~204, 301~304 중 하나,
//   "quantity": 1~3
// }

import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
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
  101, 102, 103, 104,
  201, 202, 203, 204,
  301, 302, 303, 304,
];

export default function () {
  const productId =
    productIds[Math.floor(Math.random() * productIds.length)];

  const quantity = Math.floor(Math.random() * 3) + 1;

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

    "status is RECEIVED": (res) => {
      try {
        return res.json("status") === "RECEIVED";
      } catch {
        return false;
      }
    },
  });

  sleep(0.1);
}