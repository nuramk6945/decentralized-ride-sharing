;; Ride Coordinator Smart Contract
;; Match riders with drivers and handle payments without platform intermediaries

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-RIDE-NOT-FOUND (err u101))
(define-constant ERR-INVALID-STATUS (err u102))

;; Ride Status
(define-constant STATUS-REQUESTED u1)
(define-constant STATUS-ACCEPTED u2)
(define-constant STATUS-IN-PROGRESS u3)
(define-constant STATUS-COMPLETED u4)
(define-constant STATUS-CANCELLED u5)

;; Data Variables
(define-data-var ride-counter uint u0)

;; Rides Map
(define-map rides
    uint ;; ride-id
    {
        rider: principal,
        driver: (optional principal),
        pickup-lat: int,
        pickup-lng: int,
        destination-lat: int,
        destination-lng: int,
        price: uint,
        status: uint,
        created-at: uint,
        completed-at: (optional uint)
    }
)

;; User Profiles
(define-map user-profiles
    principal
    {
        name: (string-ascii 64),
        rating: uint,
        total-rides: uint,
        is-driver: bool,
        is-active: bool
    }
)

;; Public Functions

;; Request a ride
(define-public (request-ride
    (pickup-lat int)
    (pickup-lng int)
    (destination-lat int)
    (destination-lng int)
    (price uint)
    )
    (let
        ((ride-id (+ (var-get ride-counter) u1)))
        
        ;; Create ride request
        (map-set rides ride-id {
            rider: tx-sender,
            driver: none,
            pickup-lat: pickup-lat,
            pickup-lng: pickup-lng,
            destination-lat: destination-lat,
            destination-lng: destination-lng,
            price: price,
            status: STATUS-REQUESTED,
            created-at: stacks-block-height,
            completed-at: none
        })
        
        ;; Transfer payment to escrow
        (try! (stx-transfer? price tx-sender (as-contract tx-sender)))
        
        ;; Update counter
        (var-set ride-counter ride-id)
        
        (ok ride-id)
    )
)

;; Accept a ride (driver)
(define-public (accept-ride (ride-id uint))
    (let
        ((ride (unwrap! (map-get? rides ride-id) ERR-RIDE-NOT-FOUND)))
        
        ;; Validate ride can be accepted
        (asserts! (is-eq (get status ride) STATUS-REQUESTED) ERR-INVALID-STATUS)
        
        ;; Update ride with driver
        (map-set rides ride-id
            (merge ride {
                driver: (some tx-sender),
                status: STATUS-ACCEPTED
            })
        )
        
        (ok true)
    )
)

;; Complete ride and release payment
(define-public (complete-ride (ride-id uint))
    (let
        ((ride (unwrap! (map-get? rides ride-id) ERR-RIDE-NOT-FOUND)))
        
        ;; Only driver can complete
        (asserts! (is-eq (some tx-sender) (get driver ride)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status ride) STATUS-IN-PROGRESS) ERR-INVALID-STATUS)
        
        ;; Release payment to driver
        (try! (as-contract (stx-transfer? (get price ride) tx-sender tx-sender)))
        
        ;; Update ride status
        (map-set rides ride-id
            (merge ride {
                status: STATUS-COMPLETED,
                completed-at: (some stacks-block-height)
            })
        )
        
        (ok true)
    )
)

;; Read-Only Functions

;; Get ride details
(define-read-only (get-ride (ride-id uint))
    (map-get? rides ride-id)
)

;; Get user profile
(define-read-only (get-user-profile (user principal))
    (map-get? user-profiles user)
)

;; Get platform stats
(define-read-only (get-platform-stats)
    {
        total-rides: (var-get ride-counter)
    }
)
