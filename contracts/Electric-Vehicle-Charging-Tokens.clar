(define-fungible-token charging-token)

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-balance (err u101))
(define-constant err-station-not-found (err u102))
(define-constant err-station-inactive (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-session-not-found (err u105))
(define-constant err-session-already-ended (err u106))
(define-constant err-unauthorized (err u107))
(define-constant err-insufficient-points (err u108))
(define-constant err-invalid-tier (err u109))
(define-constant err-pricing-disabled (err u110))

(define-data-var total-supply uint u0)
(define-data-var token-price uint u1000000)
(define-data-var points-to-token-ratio uint u100)

(define-map station-registry
    { station-id: uint }
    {
        owner: principal,
        location: (string-ascii 50),
        price-per-kwh: uint,
        is-active: bool,
        total-sessions: uint,
        base-price: uint,
        dynamic-pricing-enabled: bool,
        peak-multiplier: uint,
        sessions-last-24h: uint,
        last-demand-update: uint,
    }
)

(define-map charging-sessions
    { session-id: uint }
    {
        station-id: uint,
        user: principal,
        start-block: uint,
        end-block: (optional uint),
        kwh-consumed: uint,
        tokens-paid: uint,
        is-completed: bool,
    }
)

(define-map user-balances
    { user: principal }
    { balance: uint }
)

(define-map user-loyalty
    { user: principal }
    {
        points: uint,
        total-sessions: uint,
        tier: uint,
    }
)

(define-data-var next-station-id uint u1)
(define-data-var next-session-id uint u1)

(define-read-only (get-balance (user principal))
    (default-to u0 (get balance (map-get? user-balances { user: user })))
)

(define-read-only (get-total-supply)
    (var-get total-supply)
)

(define-read-only (get-token-price)
    (var-get token-price)
)

(define-read-only (get-station-info (station-id uint))
    (map-get? station-registry { station-id: station-id })
)

(define-read-only (get-session-info (session-id uint))
    (map-get? charging-sessions { session-id: session-id })
)

(define-read-only (get-user-loyalty (user principal))
    (default-to {
        points: u0,
        total-sessions: u0,
        tier: u1,
    }
        (map-get? user-loyalty { user: user })
    )
)

(define-read-only (get-loyalty-tier-multiplier (tier uint))
    (if (is-eq tier u1)
        u1
        (if (is-eq tier u2)
            u2
            (if (is-eq tier u3)
                u3
                u1
            )
        )
    )
)

(define-read-only (get-active-stations)
    (var-get next-station-id)
)

(define-public (mint-tokens
        (amount uint)
        (recipient principal)
    )
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> amount u0) err-invalid-amount)
        (try! (ft-mint? charging-token amount recipient))
        (var-set total-supply (+ (var-get total-supply) amount))
        (map-set user-balances { user: recipient } { balance: (+ (get-balance recipient) amount) })
        (ok amount)
    )
)

(define-public (transfer-tokens
        (amount uint)
        (sender principal)
        (recipient principal)
    )
    (begin
        (asserts! (or (is-eq tx-sender sender) (is-eq tx-sender contract-owner))
            err-unauthorized
        )
        (asserts! (>= (get-balance sender) amount) err-insufficient-balance)
        (asserts! (> amount u0) err-invalid-amount)
        (try! (ft-transfer? charging-token amount sender recipient))
        (map-set user-balances { user: sender } { balance: (- (get-balance sender) amount) })
        (map-set user-balances { user: recipient } { balance: (+ (get-balance recipient) amount) })
        (ok amount)
    )
)

(define-public (purchase-tokens (stx-amount uint))
    (let ((token-amount (/ stx-amount (var-get token-price))))
        (asserts! (> stx-amount u0) err-invalid-amount)
        (asserts! (> token-amount u0) err-invalid-amount)
        (try! (stx-transfer? stx-amount tx-sender contract-owner))
        (try! (mint-tokens token-amount tx-sender))
        (ok token-amount)
    )
)

(define-public (register-charging-station
        (location (string-ascii 50))
        (price-per-kwh uint)
    )
    (let ((station-id (var-get next-station-id)))
        (asserts! (> price-per-kwh u0) err-invalid-amount)
        (map-set station-registry { station-id: station-id } {
            owner: tx-sender,
            location: location,
            price-per-kwh: price-per-kwh,
            is-active: true,
            total-sessions: u0,
            base-price: price-per-kwh,
            dynamic-pricing-enabled: false,
            peak-multiplier: u150,
            sessions-last-24h: u0,
            last-demand-update: stacks-block-height,
        })
        (var-set next-station-id (+ station-id u1))
        (ok station-id)
    )
)

(define-public (update-station-status
        (station-id uint)
        (is-active bool)
    )
    (let ((station (unwrap! (map-get? station-registry { station-id: station-id })
            err-station-not-found
        )))
        (asserts! (is-eq tx-sender (get owner station)) err-unauthorized)
        (map-set station-registry { station-id: station-id }
            (merge station { is-active: is-active })
        )
        (ok true)
    )
)

(define-public (update-station-price
        (station-id uint)
        (new-price uint)
    )
    (let ((station (unwrap! (map-get? station-registry { station-id: station-id })
            err-station-not-found
        )))
        (asserts! (is-eq tx-sender (get owner station)) err-unauthorized)
        (asserts! (> new-price u0) err-invalid-amount)
        (map-set station-registry { station-id: station-id }
            (merge station { price-per-kwh: new-price })
        )
        (ok true)
    )
)

(define-public (start-charging-session (station-id uint))
    (let (
            (station (unwrap! (map-get? station-registry { station-id: station-id })
                err-station-not-found
            ))
            (session-id (var-get next-session-id))
        )
        (asserts! (get is-active station) err-station-inactive)
        (map-set charging-sessions { session-id: session-id } {
            station-id: station-id,
            user: tx-sender,
            start-block: stacks-block-height,
            end-block: none,
            kwh-consumed: u0,
            tokens-paid: u0,
            is-completed: false,
        })
        (var-set next-session-id (+ session-id u1))
        (ok session-id)
    )
)

(define-public (end-charging-session
        (session-id uint)
        (kwh-consumed uint)
    )
    (let (
            (session (unwrap! (map-get? charging-sessions { session-id: session-id })
                err-session-not-found
            ))
            (station (unwrap!
                (map-get? station-registry { station-id: (get station-id session) })
                err-station-not-found
            ))
            (total-cost (* kwh-consumed (get price-per-kwh station)))
        )
        (asserts! (is-eq tx-sender (get user session)) err-unauthorized)
        (asserts! (not (get is-completed session)) err-session-already-ended)
        (asserts! (>= (get-balance tx-sender) total-cost)
            err-insufficient-balance
        )
        (asserts! (> kwh-consumed u0) err-invalid-amount)

        (try! (transfer-tokens total-cost tx-sender (get owner station)))

        (map-set charging-sessions { session-id: session-id }
            (merge session {
                end-block: (some stacks-block-height),
                kwh-consumed: kwh-consumed,
                tokens-paid: total-cost,
                is-completed: true,
            })
        )

        (let ((updated-station (merge station { total-sessions: (+ (get total-sessions station) u1) })))
            (map-set station-registry { station-id: (get station-id session) }
                (if (get dynamic-pricing-enabled updated-station)
                    (merge updated-station {
                        sessions-last-24h: (+ (get sessions-last-24h updated-station) u1),
                        last-demand-update: stacks-block-height,
                    })
                    updated-station
                ))
        )

        (let ((loyalty-data (get-user-loyalty tx-sender)))
            (let (
                    (base-points (* kwh-consumed u10))
                    (tier-multiplier (get-loyalty-tier-multiplier (get tier loyalty-data)))
                    (points-earned (* base-points tier-multiplier))
                    (new-total-sessions (+ (get total-sessions loyalty-data) u1))
                    (new-tier (if (<= new-total-sessions u10)
                        u1
                        (if (<= new-total-sessions u25)
                            u2
                            u3
                        )
                    ))
                )
                (map-set user-loyalty { user: tx-sender } {
                    points: (+ (get points loyalty-data) points-earned),
                    total-sessions: new-total-sessions,
                    tier: new-tier,
                })
            )
        )

        (ok total-cost)
    )
)

(define-public (refund-session (session-id uint))
    (let (
            (session (unwrap! (map-get? charging-sessions { session-id: session-id })
                err-session-not-found
            ))
            (station (unwrap!
                (map-get? station-registry { station-id: (get station-id session) })
                err-station-not-found
            ))
        )
        (asserts!
            (or (is-eq tx-sender (get user session)) (is-eq tx-sender (get owner station)))
            err-unauthorized
        )
        (asserts! (get is-completed session) err-session-not-found)
        (asserts! (> (get tokens-paid session) u0) err-invalid-amount)

        (try! (transfer-tokens (get tokens-paid session) (get owner station)
            (get user session)
        ))

        (map-set charging-sessions { session-id: session-id }
            (merge session { tokens-paid: u0 })
        )

        (ok (get tokens-paid session))
    )
)

(define-public (bulk-mint-tokens (recipients (list 20 {
    user: principal,
    amount: uint,
})))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map mint-tokens-helper recipients))
    )
)

(define-private (mint-tokens-helper (recipient {
    user: principal,
    amount: uint,
}))
    (begin
        (unwrap-panic (ft-mint? charging-token (get amount recipient) (get user recipient)))
        (var-set total-supply (+ (var-get total-supply) (get amount recipient)))
        (map-set user-balances { user: (get user recipient) } { balance: (+ (get-balance (get user recipient)) (get amount recipient)) })
        (get amount recipient)
    )
)

(define-public (burn-tokens (amount uint))
    (begin
        (asserts! (>= (get-balance tx-sender) amount) err-insufficient-balance)
        (asserts! (> amount u0) err-invalid-amount)
        (try! (ft-burn? charging-token amount tx-sender))
        (var-set total-supply (- (var-get total-supply) amount))
        (map-set user-balances { user: tx-sender } { balance: (- (get-balance tx-sender) amount) })
        (ok amount)
    )
)

(define-public (set-token-price (new-price uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> new-price u0) err-invalid-amount)
        (var-set token-price new-price)
        (ok new-price)
    )
)

(define-public (emergency-pause-station (station-id uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (let ((station (unwrap! (map-get? station-registry { station-id: station-id })
                err-station-not-found
            )))
            (map-set station-registry { station-id: station-id }
                (merge station { is-active: false })
            )
            (ok true)
        )
    )
)

(define-read-only (get-session-cost
        (station-id uint)
        (kwh-amount uint)
    )
    (let ((station (unwrap! (map-get? station-registry { station-id: station-id })
            err-station-not-found
        )))
        (ok (* kwh-amount (get price-per-kwh station)))
    )
)

(define-read-only (get-user-sessions (user principal))
    (ok (var-get next-session-id))
)

(define-read-only (can-afford-charging
        (user principal)
        (station-id uint)
        (kwh-amount uint)
    )
    (let (
            (station (unwrap! (map-get? station-registry { station-id: station-id })
                err-station-not-found
            ))
            (cost (* kwh-amount (get price-per-kwh station)))
        )
        (ok (>= (get-balance user) cost))
    )
)

(define-public (batch-transfer (transfers (list 10 {
    recipient: principal,
    amount: uint,
})))
    (begin
        (ok (map transfer-helper transfers))
    )
)

(define-private (transfer-helper (transfer {
    recipient: principal,
    amount: uint,
}))
    (begin
        (unwrap-panic (transfer-tokens (get amount transfer) tx-sender (get recipient transfer)))
        (get amount transfer)
    )
)

(define-read-only (get-contract-stats)
    (ok {
        total-supply: (var-get total-supply),
        token-price: (var-get token-price),
        total-stations: (- (var-get next-station-id) u1),
        total-sessions: (- (var-get next-session-id) u1),
    })
)

(define-public (withdraw-station-earnings
        (station-id uint)
        (amount uint)
    )
    (let ((station (unwrap! (map-get? station-registry { station-id: station-id })
            err-station-not-found
        )))
        (asserts! (is-eq tx-sender (get owner station)) err-unauthorized)
        (asserts! (>= (get-balance (get owner station)) amount)
            err-insufficient-balance
        )
        (try! (transfer-tokens amount (get owner station) tx-sender))
        (ok amount)
    )
)

(define-read-only (get-station-earnings (station-id uint))
    (let ((station (unwrap! (map-get? station-registry { station-id: station-id })
            err-station-not-found
        )))
        (ok (get-balance (get owner station)))
    )
)

(define-public (redeem-loyalty-points (points-to-redeem uint))
    (let (
            (loyalty-data (get-user-loyalty tx-sender))
            (available-points (get points loyalty-data))
            (tokens-to-mint (/ points-to-redeem (var-get points-to-token-ratio)))
        )
        (asserts! (>= available-points points-to-redeem) err-insufficient-points)
        (asserts! (> tokens-to-mint u0) err-invalid-amount)
        (asserts! (> points-to-redeem u0) err-invalid-amount)

        (map-set user-loyalty { user: tx-sender }
            (merge loyalty-data { points: (- available-points points-to-redeem) })
        )

        (try! (mint-tokens tokens-to-mint tx-sender))
        (ok tokens-to-mint)
    )
)

(define-public (set-points-ratio (new-ratio uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> new-ratio u0) err-invalid-amount)
        (var-set points-to-token-ratio new-ratio)
        (ok new-ratio)
    )
)

(define-read-only (calculate-points-for-kwh
        (kwh-amount uint)
        (user principal)
    )
    (let (
            (loyalty-data (get-user-loyalty user))
            (tier-multiplier (get-loyalty-tier-multiplier (get tier loyalty-data)))
            (base-points (* kwh-amount u10))
        )
        (ok (* base-points tier-multiplier))
    )
)

(define-public (enable-dynamic-pricing
        (station-id uint)
        (peak-multiplier uint)
    )
    (let ((station (unwrap! (map-get? station-registry { station-id: station-id })
            err-station-not-found
        )))
        (asserts! (is-eq tx-sender (get owner station)) err-unauthorized)
        (asserts! (and (>= peak-multiplier u100) (<= peak-multiplier u300))
            err-invalid-amount
        )
        (map-set station-registry { station-id: station-id }
            (merge station {
                dynamic-pricing-enabled: true,
                peak-multiplier: peak-multiplier,
                sessions-last-24h: u0,
                last-demand-update: stacks-block-height,
            })
        )
        (ok true)
    )
)

(define-public (disable-dynamic-pricing (station-id uint))
    (let ((station (unwrap! (map-get? station-registry { station-id: station-id })
            err-station-not-found
        )))
        (asserts! (is-eq tx-sender (get owner station)) err-unauthorized)
        (map-set station-registry { station-id: station-id }
            (merge station {
                dynamic-pricing-enabled: false,
                price-per-kwh: (get base-price station),
            })
        )
        (ok true)
    )
)

(define-public (update-dynamic-pricing (station-id uint))
    (let (
            (station (unwrap! (map-get? station-registry { station-id: station-id })
                err-station-not-found
            ))
            (current-block stacks-block-height)
            (blocks-since-update (- current-block (get last-demand-update station)))
        )
        (asserts! (get dynamic-pricing-enabled station) err-pricing-disabled)
        (asserts! (> blocks-since-update u144) err-invalid-amount)

        (let (
                (demand-factor (if (> (get sessions-last-24h station) u10)
                    u2
                    u1
                ))
                (peak-hour (is-peak-hour current-block))
                (base-price (get base-price station))
                (multiplier (if peak-hour
                    (get peak-multiplier station)
                    u100
                ))
                (new-price (/ (* base-price multiplier demand-factor) u100))
            )
            (map-set station-registry { station-id: station-id }
                (merge station {
                    price-per-kwh: new-price,
                    sessions-last-24h: u0,
                    last-demand-update: current-block,
                })
            )
            (ok new-price)
        )
    )
)

(define-read-only (is-peak-hour (current-block uint))
    (let ((hour-of-day (mod current-block u144)))
        (or
            (and (>= hour-of-day u72) (<= hour-of-day u108))
            (and (>= hour-of-day u126) (<= hour-of-day u144))
        )
    )
)

(define-read-only (get-current-price
        (station-id uint)
        (kwh-amount uint)
    )
    (let (
            (station (unwrap! (map-get? station-registry { station-id: station-id })
                err-station-not-found
            ))
            (current-block stacks-block-height)
        )
        (if (get dynamic-pricing-enabled station)
            (let (
                    (demand-factor (if (> (get sessions-last-24h station) u10)
                        u2
                        u1
                    ))
                    (peak-hour (is-peak-hour current-block))
                    (base-price (get base-price station))
                    (multiplier (if peak-hour
                        (get peak-multiplier station)
                        u100
                    ))
                    (adjusted-price (/ (* base-price multiplier demand-factor) u100))
                )
                (ok (* kwh-amount adjusted-price))
            )
            (ok (* kwh-amount (get price-per-kwh station)))
        )
    )
)

(define-read-only (get-pricing-info (station-id uint))
    (let ((station (unwrap! (map-get? station-registry { station-id: station-id })
            err-station-not-found
        )))
        (ok {
            base-price: (get base-price station),
            current-price: (get price-per-kwh station),
            dynamic-enabled: (get dynamic-pricing-enabled station),
            peak-multiplier: (get peak-multiplier station),
            demand-sessions: (get sessions-last-24h station),
            is-peak-now: (is-peak-hour stacks-block-height),
        })
    )
)

;; ===== SUBSCRIPTION MANAGEMENT SYSTEM =====
;; Independent feature for managing charging subscriptions

(define-constant err-subscription-not-found (err u111))
(define-constant err-subscription-expired (err u112))
(define-constant err-subscription-already-active (err u113))
(define-constant err-invalid-plan (err u114))
(define-constant err-insufficient-usage (err u115))

;; Subscription data maps
(define-map user-subscriptions
    { user: principal }
    {
        plan-type: uint, ;; 1=monthly, 2=yearly, 3=premium-yearly
        start-block: uint,
        end-block: uint,
        kwh-allowance: uint,
        kwh-used: uint,
        discount-rate: uint, ;; percentage discount (10=10%)
        auto-renew: bool,
        is-active: bool,
    }
)

(define-map subscription-plans
    { plan-id: uint }
    {
        name: (string-ascii 50),
        duration-blocks: uint, ;; blocks duration
        kwh-allowance: uint, ;; kWh included
        token-cost: uint, ;; cost in tokens
        discount-rate: uint, ;; discount percentage
        is-available: bool,
    }
)

(define-data-var next-plan-id uint u1)
(define-data-var subscription-revenue uint u0)

;; Initialize default subscription plans
(map-set subscription-plans { plan-id: u1 } {
    name: "Monthly Basic",
    duration-blocks: u4320, ;; ~30 days
    kwh-allowance: u100,
    token-cost: u1000,
    discount-rate: u15, ;; 15% discount
    is-available: true,
})

(map-set subscription-plans { plan-id: u2 } {
    name: "Yearly Standard",
    duration-blocks: u52560, ;; ~365 days
    kwh-allowance: u1500,
    token-cost: u10000,
    discount-rate: u25, ;; 25% discount
    is-available: true,
})

(map-set subscription-plans { plan-id: u3 } {
    name: "Premium Yearly",
    duration-blocks: u52560, ;; ~365 days
    kwh-allowance: u3000,
    token-cost: u18000,
    discount-rate: u35, ;; 35% discount
    is-available: true,
})

(var-set next-plan-id u4)

;; Read-only functions for subscriptions
(define-read-only (get-user-subscription (user principal))
    (map-get? user-subscriptions { user: user })
)

(define-read-only (get-subscription-plan (plan-id uint))
    (map-get? subscription-plans { plan-id: plan-id })
)

(define-read-only (is-subscription-active (user principal))
    (match (map-get? user-subscriptions { user: user })
        subscription (and
            (get is-active subscription)
            (> (get end-block subscription) stacks-block-height)
        )
        false
    )
)

(define-read-only (get-subscription-discount (user principal))
    (match (map-get? user-subscriptions { user: user })
        subscription (if (and
                (get is-active subscription)
                (> (get end-block subscription) stacks-block-height)
                (< (get kwh-used subscription) (get kwh-allowance subscription))
            )
            (get discount-rate subscription)
            u0
        )
        u0
    )
)

(define-read-only (get-remaining-kwh (user principal))
    (match (map-get? user-subscriptions { user: user })
        subscription (if (and
                (get is-active subscription)
                (> (get end-block subscription) stacks-block-height)
            )
            (- (get kwh-allowance subscription) (get kwh-used subscription))
            u0
        )
        u0
    )
)

(define-read-only (get-all-available-plans)
    (ok {
        monthly-basic: (get-subscription-plan u1),
        yearly-standard: (get-subscription-plan u2),
        premium-yearly: (get-subscription-plan u3),
    })
)

;; Public functions for subscription management
(define-public (purchase-subscription (plan-id uint))
    (let (
            (plan (unwrap! (map-get? subscription-plans { plan-id: plan-id })
                err-invalid-plan
            ))
            (existing-sub (map-get? user-subscriptions { user: tx-sender }))
        )
        (asserts! (get is-available plan) err-invalid-plan)
        (asserts! (>= (get-balance tx-sender) (get token-cost plan))
            err-insufficient-balance
        )

        ;; Check if user already has active subscription
        (match existing-sub
            current-sub
            (asserts!
                (or
                    (not (get is-active current-sub))
                    (<= (get end-block current-sub) stacks-block-height)
                )
                err-subscription-already-active
            )
            true ;; No existing subscription, proceed
        )

        ;; Burn tokens for subscription cost
        (try! (burn-tokens (get token-cost plan)))

        ;; Create or update subscription
        (map-set user-subscriptions { user: tx-sender } {
            plan-type: plan-id,
            start-block: stacks-block-height,
            end-block: (+ stacks-block-height (get duration-blocks plan)),
            kwh-allowance: (get kwh-allowance plan),
            kwh-used: u0,
            discount-rate: (get discount-rate plan),
            auto-renew: false,
            is-active: true,
        })

        ;; Update revenue tracking
        (var-set subscription-revenue
            (+ (var-get subscription-revenue) (get token-cost plan))
        )

        (ok plan-id)
    )
)

(define-public (cancel-subscription)
    (let ((subscription (unwrap! (map-get? user-subscriptions { user: tx-sender })
            err-subscription-not-found
        )))
        (asserts! (get is-active subscription) err-subscription-not-found)

        ;; Deactivate subscription
        (map-set user-subscriptions { user: tx-sender }
            (merge subscription { is-active: false })
        )

        (ok true)
    )
)

(define-public (toggle-auto-renew)
    (let ((subscription (unwrap! (map-get? user-subscriptions { user: tx-sender })
            err-subscription-not-found
        )))
        (asserts! (get is-active subscription) err-subscription-not-found)

        ;; Toggle auto-renew setting
        (map-set user-subscriptions { user: tx-sender }
            (merge subscription { auto-renew: (not (get auto-renew subscription)) })
        )

        (ok (not (get auto-renew subscription)))
    )
)

(define-public (use-subscription-kwh (kwh-amount uint))
    (let ((subscription (unwrap! (map-get? user-subscriptions { user: tx-sender })
            err-subscription-not-found
        )))
        (asserts! (get is-active subscription) err-subscription-expired)
        (asserts! (> (get end-block subscription) stacks-block-height)
            err-subscription-expired
        )
        (asserts!
            (>= (- (get kwh-allowance subscription) (get kwh-used subscription))
                kwh-amount
            )
            err-insufficient-usage
        )

        ;; Update kWh usage
        (map-set user-subscriptions { user: tx-sender }
            (merge subscription { kwh-used: (+ (get kwh-used subscription) kwh-amount) })
        )

        (ok (- (get kwh-allowance subscription) (get kwh-used subscription)
            kwh-amount
        ))
    )
)

(define-public (create-custom-plan
        (name (string-ascii 50))
        (duration-blocks uint)
        (kwh-allowance uint)
        (token-cost uint)
        (discount-rate uint)
    )
    (let ((plan-id (var-get next-plan-id)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts!
            (and
                (> duration-blocks u0)
                (> kwh-allowance u0)
                (> token-cost u0)
            )
            err-invalid-amount
        )
        (asserts! (and (>= discount-rate u0) (<= discount-rate u50))
            err-invalid-amount
        )

        (map-set subscription-plans { plan-id: plan-id } {
            name: name,
            duration-blocks: duration-blocks,
            kwh-allowance: kwh-allowance,
            token-cost: token-cost,
            discount-rate: discount-rate,
            is-available: true,
        })

        (var-set next-plan-id (+ plan-id u1))
        (ok plan-id)
    )
)

(define-public (toggle-plan-availability (plan-id uint))
    (let ((plan (unwrap! (map-get? subscription-plans { plan-id: plan-id })
            err-invalid-plan
        )))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)

        (map-set subscription-plans { plan-id: plan-id }
            (merge plan { is-available: (not (get is-available plan)) })
        )

        (ok (not (get is-available plan)))
    )
)

(define-read-only (get-subscription-stats)
    (ok {
        total-revenue: (var-get subscription-revenue),
        total-plans: (- (var-get next-plan-id) u1),
    })
)

(define-read-only (calculate-discounted-price
        (base-price uint)
        (user principal)
    )
    (let ((discount (get-subscription-discount user)))
        (if (> discount u0)
            (ok (- base-price (/ (* base-price discount) u100)))
            (ok base-price)
        )
    )
)

(define-read-only (get-subscription-status (user principal))
    (match (map-get? user-subscriptions { user: user })
        subscription (ok {
            is-active: (and
                (get is-active subscription)
                (> (get end-block subscription) stacks-block-height)
            ),
            plan-type: (get plan-type subscription),
            blocks-remaining: (if (> (get end-block subscription) stacks-block-height)
                (- (get end-block subscription) stacks-block-height)
                u0
            ),
            kwh-remaining: (- (get kwh-allowance subscription) (get kwh-used subscription)),
            discount-rate: (get discount-rate subscription),
            auto-renew: (get auto-renew subscription),
        })
        (err err-subscription-not-found)
    )
)
