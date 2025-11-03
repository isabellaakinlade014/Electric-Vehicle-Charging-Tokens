(define-constant ERR_UNAUTHORIZED u100)
(define-constant ERR_NOT_FOUND u404)
(define-constant ERR_BAD_STATUS u409)
(define-constant ERR_INVALID u400)

(define-data-var owner principal tx-sender)
(define-data-var next-id uint u1)
(define-data-var default-rate uint u1)

(define-map sessions uint
  { driver: principal, provider: principal, kwh: uint, rate: uint, created-at: uint, status: uint })

(define-read-only (get-owner) (var-get owner))
(define-read-only (get-default-rate) (var-get default-rate))
(define-read-only (get-next-id) (var-get next-id))
(define-read-only (get-session (id uint)) (map-get? sessions id))

(define-read-only (quote (kwh uint) (rate uint))
  (* kwh (if (> rate u0) rate (var-get default-rate))))

(define-public (set-default-rate (rate uint))
  (if (is-eq tx-sender (var-get owner))
      (begin (var-set default-rate rate) (ok rate))
      (err ERR_UNAUTHORIZED)))

(define-public (create-session (provider principal) (kwh uint) (rate uint))
  (if (> kwh u0)
      (let ((id (var-get next-id)) (final-rate (if (> rate u0) rate (var-get default-rate))))
        (begin
          (map-set sessions id {driver: tx-sender, provider: provider, kwh: kwh, rate: final-rate, created-at: stacks-block-height, status: u0})
          (var-set next-id (+ id u1))
          (ok id)))
      (err ERR_INVALID)))

(define-public (finalize-session (id uint))
  (let ((data (unwrap! (map-get? sessions id) (err ERR_NOT_FOUND))))
    (if (and (is-eq (get provider data) tx-sender) (is-eq (get status data) u0))
        (begin
          (map-set sessions id {driver: (get driver data), provider: (get provider data), kwh: (get kwh data), rate: (get rate data), created-at: (get created-at data), status: u1})
          (ok true))
        (err ERR_UNAUTHORIZED))))

(define-public (cancel-session (id uint))
  (let ((data (unwrap! (map-get? sessions id) (err ERR_NOT_FOUND))))
    (if (and (is-eq (get driver data) tx-sender) (is-eq (get status data) u0))
        (begin
          (map-set sessions id {driver: (get driver data), provider: (get provider data), kwh: (get kwh data), rate: (get rate data), created-at: (get created-at data), status: u2})
          (ok true))
        (err ERR_UNAUTHORIZED))))

(define-public (mark-paid (id uint))
  (let ((data (unwrap! (map-get? sessions id) (err ERR_NOT_FOUND))))
    (if (and (is-eq (get provider data) tx-sender) (is-eq (get status data) u1))
        (begin
          (map-set sessions id {driver: (get driver data), provider: (get provider data), kwh: (get kwh data), rate: (get rate data), created-at: (get created-at data), status: u3})
          (ok true))
        (err ERR_BAD_STATUS))))
