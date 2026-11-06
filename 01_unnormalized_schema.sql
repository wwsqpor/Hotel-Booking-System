-- =====================================================================
--  HOTEL BOOKING SYSTEM  -  DATABASE 1 OF 2
--
--  !!!  NOT NORMALIZED  !!!
--
--  Database name : hotel_unnormalized
--  Table prefix  : UNF_   (every table in this file starts with UNF_)
--  DBMS          : MySQL 8.0 or newer
--
--  Why this file exists: it is the "before" picture. It stores the
--  same business facts as the final database, but in the way a beginner
--  would first put them into tables. Every problem is marked in two
--  places: in a "-- PROBLEM" comment here, and in the COMMENT text of the
--  table or column (visible with SHOW CREATE TABLE or in any DB tool).
--
--  Run order:
--     01_unnormalized_schema.sql              (this file)
--     02_normalized_schema.sql
--     03_migrate_unnormalized_to_normalized.sql
-- =====================================================================

DROP DATABASE IF EXISTS hotel_unnormalized;
CREATE DATABASE hotel_unnormalized
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE hotel_unnormalized;

-- ---------------------------------------------------------------------
--  UNF_booking_flat  -  NOT NORMALIZED
--
--  One giant table that mixes guests, bookings, rooms, room prices and
--  payments. One row = one booking.
--
--  Problems (normal form that is broken in brackets):
--   1. guest_name holds first AND last name in one cell        (1NF)
--   2. room_numbers, room_types, room_prices, guests_per_room
--      hold LISTS of values separated by ';'                   (1NF)
--   3. payment1_* / payment2_* are a repeating group of columns.
--      A third payment attempt needs a new column              (1NF)
--   4. guest_name / guest_email / guest_phone are copied into
--      every booking of the same guest                         (3NF)
--   5. room_types depends on room_numbers, not on the booking  (2NF/3NF)
--   6. total_price is calculated data stored as a fact         (3NF)
--   7. no foreign keys and no CHECK rules: any text is accepted
-- ---------------------------------------------------------------------
CREATE TABLE UNF_booking_flat (
    booking_id        INT          NOT NULL AUTO_INCREMENT,
    booking_date      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    guest_name        VARCHAR(100) NOT NULL COMMENT 'UNF: first+last name in one cell (1NF); repeated for each booking of the guest (3NF)',
    guest_email       VARCHAR(100) NOT NULL COMMENT 'UNF: repeated for each booking of the guest (3NF)',
    guest_phone       VARCHAR(20)  NOT NULL COMMENT 'UNF: repeated for each booking, copies can disagree (update anomaly)',

    room_numbers      VARCHAR(100) NOT NULL COMMENT 'UNF 1NF violation: list separated by ; for example 102;103',
    room_types        VARCHAR(255) NOT NULL COMMENT 'UNF 1NF violation: list; also depends on room number, not on booking (2NF/3NF)',
    room_prices       VARCHAR(100) NOT NULL COMMENT 'UNF 1NF violation: list of prices at booking time',
    guests_per_room   VARCHAR(50)  NOT NULL COMMENT 'UNF 1NF violation: list of guest counts',

    check_in          DATE         NOT NULL,
    check_out         DATE         NOT NULL,
    booking_status    VARCHAR(15)  NOT NULL COMMENT 'UNF: free text, no CHECK rule',

    total_price       DECIMAL(10,2) NOT NULL COMMENT 'UNF: calculated from nights x room prices, can become wrong (3NF)',

    payment1_method   VARCHAR(15)  NULL COMMENT 'UNF 1NF violation: repeating group of columns',
    payment1_status   VARCHAR(10)  NULL COMMENT 'UNF 1NF violation: repeating group of columns',
    payment1_amount   DECIMAL(10,2) NULL COMMENT 'UNF 1NF violation: repeating group of columns',
    payment1_date     DATETIME     NULL COMMENT 'UNF 1NF violation: repeating group of columns',
    payment2_method   VARCHAR(15)  NULL COMMENT 'UNF 1NF violation: repeating group of columns (mostly NULL)',
    payment2_status   VARCHAR(10)  NULL COMMENT 'UNF 1NF violation: repeating group of columns (mostly NULL)',
    payment2_amount   DECIMAL(10,2) NULL COMMENT 'UNF 1NF violation: repeating group of columns (mostly NULL)',
    payment2_date     DATETIME     NULL COMMENT 'UNF 1NF violation: repeating group of columns (mostly NULL)',

    PRIMARY KEY (booking_id)
) ENGINE=InnoDB
  COMMENT='NOT NORMALIZED (violates 1NF, 2NF and 3NF). Replaced by guest, booking, booking_room and payment.';


-- ---------------------------------------------------------------------
--  UNF_room_catalog  -  NOT NORMALIZED
--
--  One row = one room. The room type details are copied into every
--  room of that type.
--
--  Problems:
--   1. type_capacity, type_price_per_night and type_description depend
--      on type_name, and type_name depends on room_number.
--      This is a transitive dependency                          (3NF)
--   2. the price of "Standard" is stored once per Standard room, so a
--      price change must be made in many rows (update anomaly)
--   3. a new room type cannot be saved until a room of that type exists
--      (insertion anomaly)
--   4. deleting the last room of a type deletes the type and its price
--      (deletion anomaly)
-- ---------------------------------------------------------------------
CREATE TABLE UNF_room_catalog (
    room_number          VARCHAR(10)   NOT NULL,
    floor                INT           NOT NULL,
    room_status          VARCHAR(15)   NOT NULL COMMENT 'UNF: free text, no CHECK rule',

    -- PROBLEM 1: these four columns describe the room TYPE, not the room
    type_name            VARCHAR(50)   NOT NULL COMMENT 'UNF 3NF violation: describes the type, repeated for every room of the type',
    type_capacity        INT           NOT NULL COMMENT 'UNF 3NF violation: depends on type_name, not on room_number',
    type_price_per_night DECIMAL(8,2)  NOT NULL COMMENT 'UNF 3NF violation: depends on type_name, not on room_number',
    type_description     VARCHAR(255)  NOT NULL COMMENT 'UNF 3NF violation: depends on type_name, not on room_number',

    PRIMARY KEY (room_number)
) ENGINE=InnoDB
  COMMENT='NOT NORMALIZED (violates 3NF: transitive dependency room -> type -> price). Replaced by room_type and room.';


-- ---------------------------------------------------------------------
--  Sample data
-- ---------------------------------------------------------------------
INSERT INTO UNF_room_catalog
    (room_number, floor, room_status, type_name, type_capacity, type_price_per_night, type_description)
VALUES
    ('101', 1, 'Available', 'Standard', 2,  60.00, 'Queen bed, quiet courtyard view, 24 m2.'),
    ('102', 1, 'Available', 'Standard', 2,  60.00, 'Queen bed, quiet courtyard view, 24 m2.'),
    ('103', 1, 'Available', 'Standard', 2,  60.00, 'Queen bed, quiet courtyard view, 24 m2.'),
    ('201', 2, 'Available', 'Deluxe',   3,  90.00, 'King bed, city view, work desk and rain shower, 32 m2.'),
    ('202', 2, 'Available', 'Deluxe',   3,  90.00, 'King bed, city view, work desk and rain shower, 32 m2.'),
    ('301', 3, 'Available', 'Suite',    4, 150.00, 'Bedroom and separate lounge with corner windows, 55 m2.');

INSERT INTO UNF_booking_flat
    (booking_id, booking_date, guest_name, guest_email, guest_phone,
     room_numbers, room_types, room_prices, guests_per_room,
     check_in, check_out, booking_status, total_price,
     payment1_method, payment1_status, payment1_amount, payment1_date,
     payment2_method, payment2_status, payment2_amount, payment2_date)
VALUES
    -- Amina books for the first time (phone ends with 2233)
    (1, '2026-10-02 09:15:00', 'Amina Sadykova', 'amina@example.com', '+7 700 111 2233',
        '101', 'Standard', '60', '2',
        '2026-12-09', '2026-12-12', 'Confirmed', 180.00,
        'Card', 'Paid', 180.00, '2026-10-02 09:16:00',
        NULL, NULL, NULL, NULL),

    (2, '2026-10-05 14:40:00', 'Daniel Brooks', 'daniel@example.com', '+44 20 7946 0101',
        '201', 'Deluxe', '90', '2',
        '2026-12-11', '2026-12-14', 'Confirmed', 270.00,
        'Card', 'Paid', 270.00, '2026-10-05 14:41:00',
        NULL, NULL, NULL, NULL),

    -- PROBLEM (update anomaly): the same guest, but an OLD phone number
    -- (ends with 2200). Her phone was changed in booking 1 only.
    (3, '2026-09-10 11:05:00', 'Amina Sadykova', 'amina@example.com', '+7 700 111 2200',
        '102', 'Standard', '60', '1',
        '2026-12-01', '2026-12-05', 'Completed', 240.00,
        'Cash', 'Paid', 240.00, '2026-09-10 11:06:00',
        NULL, NULL, NULL, NULL),

    (4, '2026-10-07 18:22:00', 'Mei Tanaka', 'mei@example.com', '+81 3 5550 0123',
        '103', 'Standard', '60', '2',
        '2026-12-10', '2026-12-13', 'Cancelled', 180.00,
        'Card', 'Refunded', 180.00, '2026-10-07 18:23:00',
        NULL, NULL, NULL, NULL),

    (5, '2026-10-08 10:00:00', 'Daniel Brooks', 'daniel@example.com', '+44 20 7946 0101',
        '202', 'Deluxe', '90', '3',
        '2026-12-10', '2026-12-13', 'Confirmed', 270.00,
        'Transfer', 'Paid', 270.00, '2026-10-08 10:02:00',
        NULL, NULL, NULL, NULL),

    -- PROBLEM (1NF): two rooms in one cell and two payment attempts
    -- (the first card payment failed, the second one worked)
    (6, '2026-10-20 16:30:00', 'Mei Tanaka', 'mei@example.com', '+81 3 5550 0123',
        '102;103', 'Standard;Standard', '60;60', '2;2',
        '2027-01-05', '2027-01-07', 'Confirmed', 240.00,
        'Card', 'Failed', 240.00, '2026-10-20 16:31:00',
        'Card', 'Paid',   240.00, '2026-10-20 16:33:00');


-- ---------------------------------------------------------------------
--  Examples of the anomalies (read-only queries, safe to run)
-- ---------------------------------------------------------------------

-- A. Two different phone numbers for one guest (update anomaly)
SELECT guest_email, COUNT(DISTINCT guest_phone) AS different_phones
FROM UNF_booking_flat
GROUP BY guest_email
HAVING COUNT(DISTINCT guest_phone) > 1;

-- B. Which bookings use room 103? A LIST cannot be searched with a normal
--    join or index; the whole table must be scanned and the text split.
SELECT booking_id, room_numbers
FROM UNF_booking_flat
WHERE FIND_IN_SET('103', REPLACE(room_numbers, ';', ',')) > 0;

-- C. To raise the Standard price, every Standard room row must change.
--    SELECT COUNT(*) FROM UNF_room_catalog WHERE type_name = 'Standard';  -- 3 rows
