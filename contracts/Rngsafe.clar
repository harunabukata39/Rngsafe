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

(define-constant ERR_SUBSCRIPTION_NOT_FOUND (err u106))
(define-constant ERR_SUBSCRIPTION_EXPIRED (err u107))
(define-constant ERR_QUOTA_EXCEEDED (err u108))
(define-constant ERR_INVALID_SUBSCRIPTION_TIER (err u109))

(define-data-var basic-subscription-price uint u10000000)
(define-data-var premium-subscription-price uint u25000000)
(define-data-var enterprise-subscription-price uint u50000000)
(define-data-var subscription-duration uint u144)

(define-map subscriptions
  principal
  {
    tier: uint,
    start-block: uint,
    end-block: uint,
    requests-used: uint,
    total-quota: uint,
    auto-renew: bool,
    payment-amount: uint
  }
)

(define-map subscription-tiers
  uint
  {
    name: (string-ascii 20),
    quota: uint,
    price: uint,
    priority-fulfillment: bool
  }
)

(define-public (initialize-subscription-tiers)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set subscription-tiers u1
      {
        name: "Basic",
        quota: u100,
        price: (var-get basic-subscription-price),
        priority-fulfillment: false
      }
    )
    (map-set subscription-tiers u2
      {
        name: "Premium",
        quota: u500,
        price: (var-get premium-subscription-price),
        priority-fulfillment: true
      }
    )
    (map-set subscription-tiers u3
      {
        name: "Enterprise",
        quota: u2000,
        price: (var-get enterprise-subscription-price),
        priority-fulfillment: true
      }
    )
    (ok true)
  )
)

(define-public (subscribe (tier uint) (auto-renew bool))
  (let
    (
      (tier-info (unwrap! (map-get? subscription-tiers tier) ERR_INVALID_SUBSCRIPTION_TIER))
      (current-block stacks-block-height)
      (end-block (+ current-block (var-get subscription-duration)))
      (subscription-price (get price tier-info))
      (user-balance (stx-get-balance tx-sender))
    )
    (asserts! (>= user-balance subscription-price) ERR_INSUFFICIENT_PAYMENT)
    (try! (stx-transfer? subscription-price tx-sender (as-contract tx-sender)))
    (var-set contract-balance (+ (var-get contract-balance) subscription-price))
    (map-set subscriptions tx-sender
      {
        tier: tier,
        start-block: current-block,
        end-block: end-block,
        requests-used: u0,
        total-quota: (get quota tier-info),
        auto-renew: auto-renew,
        payment-amount: subscription-price
      }
    )
    (ok true)
  )
)

(define-public (renew-subscription (user principal))
  (let
    (
      (subscription-data (unwrap! (map-get? subscriptions user) ERR_SUBSCRIPTION_NOT_FOUND))
      (tier-info (unwrap! (map-get? subscription-tiers (get tier subscription-data)) ERR_INVALID_SUBSCRIPTION_TIER))
      (current-block stacks-block-height)
      (is-expired (>= current-block (get end-block subscription-data)))
      (new-end-block (+ current-block (var-get subscription-duration)))
      (renewal-price (get price tier-info))
      (user-balance (stx-get-balance user))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! is-expired ERR_INVALID_REQUEST)
    (asserts! (get auto-renew subscription-data) ERR_INVALID_REQUEST)
    (asserts! (>= user-balance renewal-price) ERR_INSUFFICIENT_PAYMENT)
    (try! (stx-transfer? renewal-price user (as-contract tx-sender)))
    (var-set contract-balance (+ (var-get contract-balance) renewal-price))
    (map-set subscriptions user
      (merge subscription-data
        {
          start-block: current-block,
          end-block: new-end-block,
          requests-used: u0,
          payment-amount: renewal-price
        }
      )
    )
    (ok true)
  )
)

(define-public (upgrade-subscription (new-tier uint))
  (let
    (
      (current-subscription (unwrap! (map-get? subscriptions tx-sender) ERR_SUBSCRIPTION_NOT_FOUND))
      (current-tier (get tier current-subscription))
      (new-tier-info (unwrap! (map-get? subscription-tiers new-tier) ERR_INVALID_SUBSCRIPTION_TIER))
      (current-tier-info (unwrap! (map-get? subscription-tiers current-tier) ERR_INVALID_SUBSCRIPTION_TIER))
      (price-difference (- (get price new-tier-info) (get price current-tier-info)))
      (prorated-amount (/ (* price-difference (- (get end-block current-subscription) stacks-block-height)) (var-get subscription-duration)))
      (user-balance (stx-get-balance tx-sender))
    )
    (asserts! (> new-tier current-tier) ERR_INVALID_REQUEST)
    (asserts! (>= user-balance prorated-amount) ERR_INSUFFICIENT_PAYMENT)
    (try! (stx-transfer? prorated-amount tx-sender (as-contract tx-sender)))
    (var-set contract-balance (+ (var-get contract-balance) prorated-amount))
    (map-set subscriptions tx-sender
      (merge current-subscription
        {
          tier: new-tier,
          total-quota: (get quota new-tier-info),
          payment-amount: (+ (get payment-amount current-subscription) prorated-amount)
        }
      )
    )
    (ok true)
  )
)

(define-public (request-random-number-subscription (min-value uint) (max-value uint))
  (let
    (
      (subscription-data (unwrap! (map-get? subscriptions tx-sender) ERR_SUBSCRIPTION_NOT_FOUND))
      (current-block stacks-block-height)
      (is-active (<= current-block (get end-block subscription-data)))
      (quota-remaining (- (get total-quota subscription-data) (get requests-used subscription-data)))
      (request-id (+ (var-get request-counter) u1))
    )
    (asserts! is-active ERR_SUBSCRIPTION_EXPIRED)
    (asserts! (> quota-remaining u0) ERR_QUOTA_EXCEEDED)
    (asserts! (< min-value max-value) ERR_INVALID_RANGE)
    (map-set random-requests request-id
      {
        requester: tx-sender,
        min-value: min-value,
        max-value: max-value,
        stacks-block-height: stacks-block-height,
        fulfilled: false,
        random-value: none,
        payment: u0
      }
    )
    (let
      (
        (current-requests (default-to (list) (map-get? user-requests tx-sender)))
        (updated-requests (unwrap! (as-max-len? (append current-requests request-id) u50) ERR_INVALID_REQUEST))
      )
      (map-set user-requests tx-sender updated-requests)
    )
    (map-set subscriptions tx-sender
      (merge subscription-data
        {
          requests-used: (+ (get requests-used subscription-data) u1)
        }
      )
    )
    (var-set request-counter request-id)
    (ok request-id)
  )
)

(define-public (cancel-subscription)
  (let
    (
      (subscription-data (unwrap! (map-get? subscriptions tx-sender) ERR_SUBSCRIPTION_NOT_FOUND))
      (current-block stacks-block-height)
      (remaining-blocks (- (get end-block subscription-data) current-block))
      (total-blocks (var-get subscription-duration))
      (refund-amount (/ (* (get payment-amount subscription-data) remaining-blocks) total-blocks))
    )
    (asserts! (> remaining-blocks u0) ERR_SUBSCRIPTION_EXPIRED)
    (try! (as-contract (stx-transfer? refund-amount tx-sender tx-sender)))
    (var-set contract-balance (- (var-get contract-balance) refund-amount))
    (map-delete subscriptions tx-sender)
    (ok refund-amount)
  )
)

(define-public (set-subscription-prices (basic uint) (premium uint) (enterprise uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set basic-subscription-price basic)
    (var-set premium-subscription-price premium)
    (var-set enterprise-subscription-price enterprise)
    (ok true)
  )
)

(define-public (set-subscription-duration (new-duration uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set subscription-duration new-duration)
    (ok true)
  )
)

(define-read-only (get-subscription-info (user principal))
  (map-get? subscriptions user)
)

(define-read-only (get-subscription-tier-info (tier uint))
  (map-get? subscription-tiers tier)
)

(define-read-only (is-subscription-active (user principal))
  (match (map-get? subscriptions user)
    subscription-data
      (<= stacks-block-height (get end-block subscription-data))
    false
  )
)

(define-read-only (get-remaining-quota (user principal))
  (match (map-get? subscriptions user)
    subscription-data
      (- (get total-quota subscription-data) (get requests-used subscription-data))
    u0
  )
)

(define-read-only (get-subscription-expiry (user principal))
  (match (map-get? subscriptions user)
    subscription-data
      (some (get end-block subscription-data))
    none
  )
)

(define-read-only (get-subscription-prices)
  {
    basic: (var-get basic-subscription-price),
    premium: (var-get premium-subscription-price),
    enterprise: (var-get enterprise-subscription-price)
  }
)

(define-read-only (calculate-upgrade-cost (user principal) (new-tier uint))
  (match (map-get? subscriptions user)
    subscription-data
      (let
        (
          (current-tier (get tier subscription-data))
          (new-tier-info (unwrap! (map-get? subscription-tiers new-tier) (err u0)))
          (current-tier-info (unwrap! (map-get? subscription-tiers current-tier) (err u0)))
          (price-difference (- (get price new-tier-info) (get price current-tier-info)))
          (remaining-blocks (- (get end-block subscription-data) stacks-block-height))
          (total-blocks (var-get subscription-duration))
        )
        (ok (/ (* price-difference remaining-blocks) total-blocks))
      )
    (err u0)
  )
)