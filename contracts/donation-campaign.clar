(define-constant ERR-CAMPAIGN-NOT-STARTED (err u100))
(define-constant ERR-CAMPAIGN-ENDED (err u101))
(define-constant ERR-CAMPAIGN-CANCELED (err u102))
(define-constant ERR-CAMPAIGN-INVALID (err u103))
(define-constant ERR-NOT-CREATOR (err u104))
(define-constant ERR-NOT-SUPPORTER (err u105))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u106))
(define-constant ERR-VOTE-ALREADY-CAST (err u107))
(define-constant ERR-INVALID-GOAL (err u108))
(define-constant ERR-INVALID-DURATION (err u109))
(define-constant ERR-INVALID-ESCROW (err u110))
(define-constant ERR-INVALID-DIST (err u111))
(define-constant ERR-ZERO-AMOUNT (err u200))
(define-constant ERR-ZERO-WEIGHT (err u201))
(define-constant ERR-NOT-REVEALED (err u202))

(define-data-var creator principal tx-sender)
(define-data-var goal-amount uint u0)
(define-data-var start-time uint u0)
(define-data-var duration-fundraise uint u0)
(define-data-var duration-vote uint u0)
(define-data-var theme (string-utf8 100) "")
(define-data-var is-canceled bool false)

(define-map escrow-contract principal principal)
(define-map distributor-contract principal principal)

(define-map contributions principal uint)
(define-map total-raised { id: uint } uint)

(define-map proposals uint
  {
    hash: (buff 32),
    revealed: bool,
    description: (optional (string-utf8 280)),
    budget: uint,
    submitter: principal
  }
)

(define-data-var next-id uint u0)

(define-map proposal-votes uint uint)
(define-map voter-cast { proposal: uint, voter: principal } bool)

(define-trait ft-trait
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-balance (principal) (response uint uint))
    (get-decimals () (response uint uint))
    (get-symbol () (response (string-ascii 32) uint))
    (get-name () (response (string-ascii 32) uint))
  )
)

(define-private (only-creator)
  (asserts! (is-eq tx-sender (var-get creator)) ERR-NOT-CREATOR)
)

(define-private (campaign-active)
  (let ((st (var-get start-time)))
    (if (or (var-get is-canceled) (is-eq st u0)) ERR-CAMPAIGN-INVALID (ok true))
  )
)

(define-private (in-fundraise)
  (let ((st (var-get start-time)) (dur (var-get duration-fundraise)))
    (if (<= block-height (+ st dur)) (ok true) ERR-CAMPAIGN-ENDED)
  )
)

(define-private (in-vote)
  (let ((st (var-get start-time)) (fd (var-get duration-fundraise)) (vd (var-get duration-vote)))
    (if (and (> block-height (+ st fd)) (<= block-height (+ st fd vd))) (ok true) ERR-CAMPAIGN-NOT-STARTED)
  )
)

(define-read-only (get-creator) (ok (var-get creator)))
(define-read-only (get-goal) (ok (var-get goal-amount)))
(define-read-only (get-start) (ok (var-get start-time)))
(define-read-only (get-fundraise-duration) (ok (var-get duration-fundraise)))
(define-read-only (get-vote-duration) (ok (var-get duration-vote)))
(define-read-only (get-theme) (ok (var-get theme)))
(define-read-only (get-canceled) (ok (var-get is-canceled)))

(define-read-only (get-contribution (who principal))
  (ok (default-to u0 (map-get? contributions who)))
)

(define-read-only (get-proposal (id uint))
  (map-get? proposals id)
)

(define-read-only (get-votes (id uint))
  (ok (default-to u0 (map-get? proposal-votes id)))
)

(define-read-only (get-total-raised)
  (ok (default-to u0 (map-get? total-raised { id: u0 })))
)

(define-public (init-campaign (new-goal uint) (fundraise-dur uint) (vote-dur uint) (new-theme (string-utf8 100)) (escrow-pr principal) (dist-pr principal))
  (begin
    (only-creator)
    (asserts! (is-eq (var-get start-time) u0) ERR-CAMPAIGN-INVALID)
    (asserts! (> new-goal u0) ERR-INVALID-GOAL)
    (asserts! (> fundraise-dur u0) ERR-INVALID-DURATION)
    (asserts! (> vote-dur u0) ERR-INVALID-DURATION)
    (asserts! (is-principal? escrow-pr) ERR-INVALID-ESCROW)
    (asserts! (is-principal? dist-pr) ERR-INVALID-DIST)
    (var-set goal-amount new-goal)
    (var-set duration-fundraise fundraise-dur)
    (var-set duration-vote vote-dur)
    (var-set theme new-theme)
    (map-set escrow-contract (var-get creator) escrow-pr)
    (map-set distributor-contract (var-get creator) dist-pr)
    (var-set start-time block-height)
    (map-set total-raised { id: u0 } u0)
    (ok true)
  )
)

(define-public (contribute (amount uint))
  (begin
    (try! (campaign-active))
    (try! (in-fundraise))
    (asserts! (> amount u0) ERR-ZERO-AMOUNT)
    (let ((current (default-to u0 (map-get? contributions tx-sender)))
          (t (default-to u0 (map-get? total-raised { id: u0 }))))
      (map-set contributions tx-sender (+ current amount))
      (map-set total-raised { id: u0 } (+ t amount))
      (ok true)
    )
  )
)

(define-public (cancel)
  (begin
    (only-creator)
    (try! (campaign-active))
    (var-set is-canceled true)
    (ok true)
  )
)

(define-public (submit-proposal-hash (proposal-hash (buff 32)) (budget uint))
  (begin
    (try! (campaign-active))
    (let ((nid (var-get next-id)))
      (map-set proposals nid { hash: proposal-hash, revealed: false, description: none, budget: budget, submitter: tx-sender })
      (var-set next-id (+ nid u1))
      (ok nid)
    )
  )
)

(define-public (reveal-proposal (id uint) (desc (string-utf8 280)))
  (let ((p (map-get? proposals id)))
    (match p
      proposal (begin (map-set proposals id { hash: (get hash proposal), revealed: true, description: (some desc), budget: (get budget proposal), submitter: (get submitter proposal) }) (ok true))
      (err ERR-PROPOSAL-NOT-FOUND)
    )
  )
)

(define-public (cast-vote (proposal-id uint) (vote-weight uint))
  (begin
    (try! (campaign-active))
    (try! (in-vote))
    (asserts! (> vote-weight u0) ERR-ZERO-WEIGHT)
    (asserts! (is-eq (default-to false (map-get? voter-cast { proposal: proposal-id, voter: tx-sender })) false) ERR-VOTE-ALREADY-CAST)
    (let ((p (map-get? proposals proposal-id)))
      (match p
        proposal (begin
                   (asserts! (is-eq (get revealed proposal) true) ERR-NOT-REVEALED)
                   (let ((cur (default-to u0 (map-get? proposal-votes proposal-id))))
                     (map-set proposal-votes proposal-id (+ cur vote-weight))
                     (map-set voter-cast { proposal: proposal-id, voter: tx-sender } true)
                     (ok true)
                   )
                 )
        (err ERR-PROPOSAL-NOT-FOUND)
      )
    )
  )
)

(define-public (update-escrow (new-escrow principal))
  (begin
    (only-creator)
    (asserts! (is-principal? new-escrow) ERR-INVALID-ESCROW)
    (map-set escrow-contract (var-get creator) new-escrow)
    (ok true)
  )
)

(define-public (update-distributor (new-dist principal))
  (begin
    (only-creator)
    (asserts! (is-principal? new-dist) ERR-INVALID-DIST)
    (map-set distributor-contract (var-get creator) new-dist)
    (ok true)
  )
)


