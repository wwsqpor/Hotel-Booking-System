-- =====================================================================
--  HOTEL BOOKING SYSTEM  -  DATABASE 2 OF 2
--
--  NORMALIZED (3rd Normal Form)  -  this is the database the website uses
--
--  Database name : hotel_booking
--  DBMS          : MySQL 8.0.16 or newer (CHECK constraints are enforced)
--
--  Tables (same as the Task 9 database plan and ERD):
--     guest, room_type, room, booking, booking_room, payment
--
--  Where each table comes from:
--     guest         <- guest_* columns of UNF_booking_flat
--     booking       <- booking-level columns of UNF_booking_flat
--     booking_room  <- the ';' lists of UNF_booking_flat (one row per room)
--     payment       <- the payment1_* / payment2_* columns (one row per payment)
--     room_type     <- type_* columns of UNF_room_catalog
--     room          <- room columns of UNF_room_catalog
--
--  Run 01_unnormalized_schema.sql before this file only if you also want
--  to run the migration script (03_...) afterwards.
-- =====================================================================

DROP DATABASE IF EXISTS hotel_booking;
CREATE DATABASE hotel_booking
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE hotel_booking;


-- ---------------------------------------------------------------------
--  guest : one row per person. Name, email and phone live ONLY here.
-- ---------------------------------------------------------------------
CREATE TABLE guest (
    guest_id    INT          NOT NULL AUTO_INCREMENT,
    first_name  VARCHAR(50)  NOT NULL,
    last_name   VARCHAR(50)  NOT NULL,
    email       VARCHAR(100) NOT NULL,
    phone       VARCHAR(20)  NOT NULL,

    PRIMARY KEY (guest_id),
    CONSTRAINT uq_guest_email   UNIQUE (email),
    CONSTRAINT chk_guest_email  CHECK (email LIKE '%_@_%._%'),
    CONSTRAINT chk_guest_names  CHECK (CHAR_LENGTH(TRIM(first_name)) > 0 AND CHAR_LENGTH(TRIM(last_name)) > 0)
) ENGINE=InnoDB COMMENT='Normalized (3NF). One row per guest.';


-- ---------------------------------------------------------------------
--  room_type : price, capacity and description of each category, once.
-- ---------------------------------------------------------------------
CREATE TABLE room_type (
    room_type_id    INT           NOT NULL AUTO_INCREMENT,
    type_name       VARCHAR(50)   NOT NULL,
    capacity        INT           NOT NULL,
    price_per_night DECIMAL(8,2)  NOT NULL,
    description     VARCHAR(255)  NULL,

    PRIMARY KEY (room_type_id),
    CONSTRAINT uq_room_type_name     UNIQUE (type_name),
    CONSTRAINT chk_room_type_cap     CHECK (capacity BETWEEN 1 AND 10),
    CONSTRAINT chk_room_type_price   CHECK (price_per_night > 0)
) ENGINE=InnoDB COMMENT='Normalized (3NF). One row per room category.';


-- ---------------------------------------------------------------------
--  room : one row per physical room. Points to its type.
-- ---------------------------------------------------------------------
CREATE TABLE room (
    room_id       INT          NOT NULL AUTO_INCREMENT,
    room_number   VARCHAR(10)  NOT NULL,
    floor         INT          NOT NULL,
    status        VARCHAR(15)  NOT NULL DEFAULT 'Available',
    room_type_id  INT          NOT NULL,

    PRIMARY KEY (room_id),
    CONSTRAINT uq_room_number    UNIQUE (room_number),
    CONSTRAINT chk_room_floor    CHECK (floor BETWEEN 0 AND 50),
    CONSTRAINT chk_room_status   CHECK (status IN ('Available', 'Maintenance')),
    CONSTRAINT fk_room_type      FOREIGN KEY (room_type_id) REFERENCES room_type (room_type_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB COMMENT='Normalized (3NF). One row per physical room.';


-- ---------------------------------------------------------------------
--  booking : one reservation by one guest for one period.
--  The total price is NOT stored here (see view v_booking_total).
-- ---------------------------------------------------------------------
CREATE TABLE booking (
    booking_id    INT          NOT NULL AUTO_INCREMENT,
    guest_id      INT          NOT NULL,
    booking_date  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    check_in      DATE         NOT NULL,
    check_out     DATE         NOT NULL,
    status        VARCHAR(15)  NOT NULL DEFAULT 'Confirmed',

    PRIMARY KEY (booking_id),
    CONSTRAINT chk_booking_dates   CHECK (check_out > check_in),
    CONSTRAINT chk_booking_status  CHECK (status IN ('Confirmed', 'CheckedIn', 'Completed', 'Cancelled')),
    CONSTRAINT fk_booking_guest    FOREIGN KEY (guest_id) REFERENCES guest (guest_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    -- Speeds up the availability search (date overlap + status)
    INDEX idx_booking_dates (check_in, check_out, status)
) ENGINE=InnoDB COMMENT='Normalized (3NF). One row per reservation.';


-- ---------------------------------------------------------------------
--  booking_room : BRIDGE TABLE for the many-to-many link
--  booking <-> room. One row = one room inside one booking.
--  price_per_night is the price on the booking day (history), a
--  different fact from the current price in room_type.
-- ---------------------------------------------------------------------
CREATE TABLE booking_room (
    booking_room_id  INT           NOT NULL AUTO_INCREMENT,
    booking_id       INT           NOT NULL,
    room_id          INT           NOT NULL,
    guests_count     INT           NOT NULL,
    price_per_night  DECIMAL(8,2)  NOT NULL,

    PRIMARY KEY (booking_room_id),
    CONSTRAINT uq_booking_room      UNIQUE (booking_id, room_id),
    CONSTRAINT chk_br_guests        CHECK (guests_count BETWEEN 1 AND 10),
    CONSTRAINT chk_br_price         CHECK (price_per_night > 0),
    CONSTRAINT fk_br_booking        FOREIGN KEY (booking_id) REFERENCES booking (booking_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_br_room           FOREIGN KEY (room_id) REFERENCES room (room_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB COMMENT='Normalized (3NF). Bridge table: one row per room in a booking.';


-- ---------------------------------------------------------------------
--  payment : one row per payment attempt. A booking can have many.
-- ---------------------------------------------------------------------
CREATE TABLE payment (
    payment_id      INT            NOT NULL AUTO_INCREMENT,
    booking_id      INT            NOT NULL,
    amount          DECIMAL(10,2)  NOT NULL,
    payment_method  VARCHAR(15)    NOT NULL,
    payment_status  VARCHAR(10)    NOT NULL,
    payment_date    DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (payment_id),
    CONSTRAINT chk_payment_amount  CHECK (amount > 0),
    CONSTRAINT chk_payment_method  CHECK (payment_method IN ('Card', 'Cash', 'Transfer')),
    CONSTRAINT chk_payment_status  CHECK (payment_status IN ('Paid', 'Failed', 'Refunded')),
    CONSTRAINT fk_payment_booking  FOREIGN KEY (booking_id) REFERENCES booking (booking_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB COMMENT='Normalized (3NF). One row per payment attempt.';


-- ---------------------------------------------------------------------
--  View: the total price is calculated when it is needed, so it can
--  never disagree with the room lines.
-- ---------------------------------------------------------------------
CREATE VIEW v_booking_total AS
SELECT  b.booking_id,
        b.guest_id,
        b.check_in,
        b.check_out,
        b.status,
        DATEDIFF(b.check_out, b.check_in)                          AS nights,
        SUM(br.price_per_night) * DATEDIFF(b.check_out, b.check_in) AS total_price
FROM    booking b
JOIN    booking_room br ON br.booking_id = b.booking_id
GROUP BY b.booking_id, b.guest_id, b.check_in, b.check_out, b.status;
