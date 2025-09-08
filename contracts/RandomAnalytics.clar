;; Random History Analytics Contract
;; Provides statistical analysis and historical tracking for random number requests

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_INVALID_PERIOD (err u201))
(define-constant ERR_STATS_NOT_FOUND (err u202))
(define-constant ERR_INVALID_RANGE (err u203))
(define-constant ERR_NO_DATA_AVAILABLE (err u204))

;; Data variables for configuration
(define-data-var analytics-enabled bool true)
(define-data-var max-history-entries uint u1000)
(define-data-var stats-update-frequency uint u10)

;; User statistics tracking
(define-map user-analytics
  principal
  {
    total-requests: uint,
    fulfilled-requests: uint,
    total-spent: uint,
    avg-range-size: uint,
    favorite-min: uint,
    favorite-max: uint,
    last-request-height: uint,
    streak-count: uint,
    success-rate: uint
  }
)

;; Historical request patterns
(define-map request-history
  {user: principal, entry-id: uint}
  {
    request-id: uint,
    min-value: uint,
    max-value: uint,
    random-result: (optional uint),
    block-height: uint,
    fee-paid: uint,
    fulfillment-time: uint,
    request-type: (string-ascii 20)
  }
)

;; User history counters
(define-map user-history-counters
  principal
  uint
)

;; Range frequency analysis
(define-map range-frequencies
  {user: principal, min-val: uint, max-val: uint}
  {
    usage-count: uint,
    last-used: uint,
    avg-result: uint,
    total-results: uint
  }
)

;; Daily usage patterns
(define-map daily-usage-stats
  {user: principal, day-block: uint}
  {
    request-count: uint,
    total-fees: uint,
    fulfilled-count: uint,
    avg-fulfillment-time: uint
  }
)

;; Global analytics for system insights
(define-map global-stats
  (string-ascii 20)
  uint
)

;; Record a new random request for analytics
(define-public (record-request 
  (user principal)
  (request-id uint)
  (min-value uint)
  (max-value uint)
  (fee-paid uint)
  (request-type (string-ascii 20)))
  (let
    (
      (current-stats (get-or-create-user-stats user))
      (entry-id (+ (default-to u0 (map-get? user-history-counters user)) u1))
      (day-block (/ stacks-block-height u144))
    )
    (asserts! (var-get analytics-enabled) (ok true))
    
    ;; Update user statistics
    (map-set user-analytics user
      (merge current-stats
        {
          total-requests: (+ (get total-requests current-stats) u1),
          total-spent: (+ (get total-spent current-stats) fee-paid),
          avg-range-size: (calculate-avg-range-size user (- max-value min-value)),
          last-request-height: stacks-block-height,
          streak-count: (calculate-streak user)
        }
      )
    )
    
    ;; Record in history
    (map-set request-history
      {user: user, entry-id: entry-id}
      {
        request-id: request-id,
        min-value: min-value,
        max-value: max-value,
        random-result: none,
        block-height: stacks-block-height,
        fee-paid: fee-paid,
        fulfillment-time: u0,
        request-type: request-type
      }
    )
    
    ;; Update history counter
    (map-set user-history-counters user entry-id)
    
    ;; Update range frequency
    (update-range-frequency user min-value max-value)
    
    ;; Update daily stats
    (update-daily-stats user day-block fee-paid)
    
    ;; Update global stats
    (update-global-counter "total-requests")
    
    (ok true)
  )
)

;; Record fulfillment of a random request
(define-public (record-fulfillment
  (user principal)
  (request-id uint)
  (random-result uint))
  (let
    (
      (current-stats (get-or-create-user-stats user))
      (entry-id (default-to u0 (map-get? user-history-counters user)))
      (current-history (map-get? request-history {user: user, entry-id: entry-id}))
      (fulfillment-time (if (is-some current-history)
                          (- stacks-block-height (get block-height (unwrap-panic current-history)))
                          u0))
      (day-block (/ stacks-block-height u144))
    )
    (asserts! (var-get analytics-enabled) (ok true))
    
    ;; Update user statistics
    (map-set user-analytics user
      (merge current-stats
        {
          fulfilled-requests: (+ (get fulfilled-requests current-stats) u1),
          success-rate: (calculate-success-rate 
                          (+ (get fulfilled-requests current-stats) u1)
                          (get total-requests current-stats))
        }
      )
    )
    
    ;; Update history entry if exists
    (match current-history
      history-data
        (map-set request-history
          {user: user, entry-id: entry-id}
          (merge history-data
            {
              random-result: (some random-result),
              fulfillment-time: fulfillment-time
            }
          )
        )
      false
    )
    
    ;; Update range frequency with result
    (match current-history
      history-data
        (update-range-result user 
                           (get min-value history-data) 
                           (get max-value history-data) 
                           random-result)
      false
    )
    
    ;; Update daily fulfillment stats
    (update-daily-fulfillment user day-block fulfillment-time)
    
    ;; Update global stats
    (update-global-counter "total-fulfilled")
    
    (ok true)
  )
)

;; Helper function to get or create user stats
(define-private (get-or-create-user-stats (user principal))
  (default-to
    {
      total-requests: u0,
      fulfilled-requests: u0,
      total-spent: u0,
      avg-range-size: u0,
      favorite-min: u1,
      favorite-max: u100,
      last-request-height: u0,
      streak-count: u0,
      success-rate: u0
    }
    (map-get? user-analytics user)
  )
)

;; Calculate average range size
(define-private (calculate-avg-range-size (user principal) (new-range uint))
  (let
    (
      (current-stats (get-or-create-user-stats user))
      (total-requests (get total-requests current-stats))
      (current-avg (get avg-range-size current-stats))
    )
    (if (is-eq total-requests u0)
      new-range
      (/ (+ (* current-avg total-requests) new-range) (+ total-requests u1))
    )
  )
)

;; Calculate user request streak
(define-private (calculate-streak (user principal))
  (let
    (
      (current-stats (get-or-create-user-stats user))
      (last-height (get last-request-height current-stats))
      (current-streak (get streak-count current-stats))
    )
    (if (< (- stacks-block-height last-height) u144) ;; Within 1 day
      (+ current-streak u1)
      u1
    )
  )
)

;; Calculate success rate percentage
(define-private (calculate-success-rate (fulfilled uint) (total uint))
  (if (is-eq total u0)
    u0
    (/ (* fulfilled u100) total)
  )
)

;; Update range frequency statistics
(define-private (update-range-frequency (user principal) (min-val uint) (max-val uint))
  (let
    (
      (current-freq (default-to
                      {usage-count: u0, last-used: u0, avg-result: u0, total-results: u0}
                      (map-get? range-frequencies {user: user, min-val: min-val, max-val: max-val})))
    )
    (map-set range-frequencies
      {user: user, min-val: min-val, max-val: max-val}
      (merge current-freq
        {
          usage-count: (+ (get usage-count current-freq) u1),
          last-used: stacks-block-height
        }
      )
    )
    true
  )
)

;; Update range frequency with actual result
(define-private (update-range-result (user principal) (min-val uint) (max-val uint) (result uint))
  (let
    (
      (current-freq (default-to
                      {usage-count: u0, last-used: u0, avg-result: u0, total-results: u0}
                      (map-get? range-frequencies {user: user, min-val: min-val, max-val: max-val})))
      (total-results (get total-results current-freq))
      (current-avg (get avg-result current-freq))
    )
    (map-set range-frequencies
      {user: user, min-val: min-val, max-val: max-val}
      (merge current-freq
        {
          avg-result: (if (is-eq total-results u0)
                        result
                        (/ (+ (* current-avg total-results) result) (+ total-results u1))),
          total-results: (+ total-results u1)
        }
      )
    )
    true
  )
)

;; Update daily usage statistics
(define-private (update-daily-stats (user principal) (day-block uint) (fee-paid uint))
  (let
    (
      (current-daily (default-to
                       {request-count: u0, total-fees: u0, fulfilled-count: u0, avg-fulfillment-time: u0}
                       (map-get? daily-usage-stats {user: user, day-block: day-block})))
    )
    (map-set daily-usage-stats
      {user: user, day-block: day-block}
      (merge current-daily
        {
          request-count: (+ (get request-count current-daily) u1),
          total-fees: (+ (get total-fees current-daily) fee-paid)
        }
      )
    )
    true
  )
)

;; Update daily fulfillment statistics
(define-private (update-daily-fulfillment (user principal) (day-block uint) (fulfillment-time uint))
  (let
    (
      (current-daily (default-to
                       {request-count: u0, total-fees: u0, fulfilled-count: u0, avg-fulfillment-time: u0}
                       (map-get? daily-usage-stats {user: user, day-block: day-block})))
      (fulfilled-count (get fulfilled-count current-daily))
      (current-avg-time (get avg-fulfillment-time current-daily))
    )
    (map-set daily-usage-stats
      {user: user, day-block: day-block}
      (merge current-daily
        {
          fulfilled-count: (+ fulfilled-count u1),
          avg-fulfillment-time: (if (is-eq fulfilled-count u0)
                                  fulfillment-time
                                  (/ (+ (* current-avg-time fulfilled-count) fulfillment-time) 
                                     (+ fulfilled-count u1)))
        }
      )
    )
    true
  )
)

;; Update global counters
(define-private (update-global-counter (key (string-ascii 20)))
  (let
    (
      (current-value (default-to u0 (map-get? global-stats key)))
    )
    (map-set global-stats key (+ current-value u1))
    true
  )
)

;; Administrative functions
(define-public (toggle-analytics)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set analytics-enabled (not (var-get analytics-enabled)))
    (ok (var-get analytics-enabled))
  )
)

(define-public (set-max-history-entries (new-max uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set max-history-entries new-max)
    (ok true)
  )
)

;; Read-only functions for user insights
(define-read-only (get-user-analytics (user principal))
  (map-get? user-analytics user)
)

(define-read-only (get-user-history (user principal) (entry-id uint))
  (map-get? request-history {user: user, entry-id: entry-id})
)

(define-read-only (get-range-frequency (user principal) (min-val uint) (max-val uint))
  (map-get? range-frequencies {user: user, min-val: min-val, max-val: max-val})
)

(define-read-only (get-daily-stats (user principal) (day-block uint))
  (map-get? daily-usage-stats {user: user, day-block: day-block})
)

(define-read-only (get-user-history-count (user principal))
  (default-to u0 (map-get? user-history-counters user))
)

(define-read-only (get-global-stat (key (string-ascii 20)))
  (default-to u0 (map-get? global-stats key))
)

(define-read-only (is-analytics-enabled)
  (var-get analytics-enabled)
)

(define-read-only (get-analytics-config)
  {
    enabled: (var-get analytics-enabled),
    max-history: (var-get max-history-entries),
    update-frequency: (var-get stats-update-frequency)
  }
)
