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

(define-data-var total-supply uint u0)
(define-data-var token-price uint u1000000)

(define-map station-registry
    { station-id: uint }
    {
        owner: principal,
        location: (string-ascii 50),
        price-per-kwh: uint,
        is-active: bool,
        total-sessions: uint,
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

        (map-set station-registry { station-id: (get station-id session) }
            (merge station { total-sessions: (+ (get total-sessions station) u1) })
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
