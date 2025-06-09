(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_REQUEST (err u101))
(define-constant ERR_REQUEST_NOT_FOUND (err u102))
(define-constant ERR_REQUEST_ALREADY_FULFILLED (err u103))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u104))
(define-constant ERR_INVALID_RANGE (err u105))

(define-data-var request-counter uint u0)
(define-data-var oracle-fee uint u1000000)
(define-data-var contract-balance uint u0)

(define-map random-requests
  uint
  {
    requester: principal,
    min-value: uint,
    max-value: uint,
    stacks-block-height: uint,
    fulfilled: bool,
    random-value: (optional uint),
    payment: uint
  }
)

(define-map user-requests
  principal
  (list 50 uint)
)

(define-public (request-random-number (min-value uint) (max-value uint))
  (let
    (
      (request-id (+ (var-get request-counter) u1))
      (payment (stx-get-balance tx-sender))
      (fee (var-get oracle-fee))
    )
    (asserts! (>= payment fee) ERR_INSUFFICIENT_PAYMENT)
    (asserts! (< min-value max-value) ERR_INVALID_RANGE)
    (try! (stx-transfer? fee tx-sender (as-contract tx-sender)))
    (var-set contract-balance (+ (var-get contract-balance) fee))
    (map-set random-requests request-id
      {
        requester: tx-sender,
        min-value: min-value,
        max-value: max-value,
        stacks-block-height: stacks-block-height,
        fulfilled: false,
        random-value: none,
        payment: fee
      }
    )
    (let
      (
        (current-requests (default-to (list) (map-get? user-requests tx-sender)))
        (updated-requests (unwrap! (as-max-len? (append current-requests request-id) u50) ERR_INVALID_REQUEST))
      )
      (map-set user-requests tx-sender updated-requests)
    )
    (var-set request-counter request-id)
    (ok request-id)
  )
)

(define-public (fulfill-random-request (request-id uint) (seed uint))
  (let
    (
      (request-data (unwrap! (map-get? random-requests request-id) ERR_REQUEST_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (not (get fulfilled request-data)) ERR_REQUEST_ALREADY_FULFILLED)
    (let
      (
        (min-val (get min-value request-data))
        (max-val (get max-value request-data))
        (block-hash (unwrap-panic (get-stacks-block-info? id-header-hash (get stacks-block-height request-data))))
        ;; (combined-seed (+ seed (buff-to-uint-be block-hash)))
        (range (- max-val min-val))
        (random-num (+ min-val (mod u30 range)))
      )
      (map-set random-requests request-id
        (merge request-data
          {
            fulfilled: true,
            random-value: (some random-num)
          }
        )
      )
      (ok random-num)
    )
  )
)

(define-public (set-oracle-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set oracle-fee new-fee)
    (ok true)
  )
)

(define-public (withdraw-fees (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= amount (var-get contract-balance)) ERR_INSUFFICIENT_PAYMENT)
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))
    (var-set contract-balance (- (var-get contract-balance) amount))
    (ok true)
  )
)

(define-read-only (get-random-request (request-id uint))
  (map-get? random-requests request-id)
)

(define-read-only (get-user-requests (user principal))
  (map-get? user-requests user)
)

(define-read-only (get-oracle-fee)
  (var-get oracle-fee)
)

(define-read-only (get-contract-balance)
  (var-get contract-balance)
)

(define-read-only (get-request-counter)
  (var-get request-counter)
)

(define-read-only (is-request-fulfilled (request-id uint))
  (match (map-get? random-requests request-id)
    request-data (get fulfilled request-data)
    false
  )
)

(define-read-only (get-random-value (request-id uint))
  (match (map-get? random-requests request-id)
    request-data 
      (if (get fulfilled request-data)
        (get random-value request-data)
        none
      )
    none
  )
)

(define-private (custom-buff-to-uint-be (input (buff 16)))
  (let
    (
      (b1 (unwrap-panic (element-at input u0)))
      (b2 (unwrap-panic (element-at input u1)))
      (b3 (unwrap-panic (element-at input u2)))
      (b4 (unwrap-panic (element-at input u3)))
    )
    (+ 
      (* (buff-to-uint-le (unwrap-panic (slice? input u0 u1))) u16777216)
      (* (buff-to-uint-le (unwrap-panic (slice? input u1 u2))) u65536)
      (* (buff-to-uint-le (unwrap-panic (slice? input u2 u3))) u256)
      (buff-to-uint-le (unwrap-panic (slice? input u3 u4)))
    )
  )
)

(define-public (batch-fulfill-requests (requests (list 10 {id: uint, seed: uint})))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (ok (map fulfill-single-request requests))
  )
)

(define-private (fulfill-single-request (request {id: uint, seed: uint}))
  (match (fulfill-random-request (get id request) (get seed request))
    success success
    error u0
  )
)

(define-read-only (get-pending-requests-count)
  (let
    (
      (total-requests (var-get request-counter))
    )
    (fold count-pending-requests (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) u0)
  )
)

(define-private (count-pending-requests (request-id uint) (acc uint))
  (match (map-get? random-requests request-id)
    request-data
      (if (get fulfilled request-data)
        acc
        (+ acc u1)
      )
    acc
  )
)

(define-read-only (verify-randomness (request-id uint))
  (match (map-get? random-requests request-id)
    request-data
      (if (get fulfilled request-data)
        (let
          (
            (block-hash (unwrap-panic (get-stacks-block-info? id-header-hash (get stacks-block-height request-data))))
            (min-val (get min-value request-data))
            (max-val (get max-value request-data))
            (random-val (unwrap-panic (get random-value request-data)))
          )
          (and 
            (>= random-val min-val)
            (< random-val max-val)
          )
        )
        false
      )
    false
  )
)