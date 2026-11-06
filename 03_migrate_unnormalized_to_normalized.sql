-- =====================================================================
--  HOTEL BOOKING SYSTEM  -  MIGRATION
--  hotel_unnormalized (NOT normalized)  -->  hotel_booking (3NF)
--
--  Requires: 01_unnormalized_schema.sql and 02_normalized_schema.sql
--            were run first. MySQL 8.0 (uses JSON_TABLE and window
--            functions).
--
--  The whole migration is ONE transaction: if any step fails, nothing
--  is copied.
-- =====================================================================

USE hotel_booking;

START TRANSACTION;

-- ---------------------------------------------------------------------
--  Step 1. room_type  <-  type_* columns of UNF_room_catalog
--  DISTINCT collapses the repeated type data to one row per type.
-- ---------------------------------------------------------------------
INSERT INTO room_type (type_name, capacity, price_per_night, description)
SELECT DISTINCT type_name, type_capacity, type_price_per_night, type_description
FROM   hotel_unnormalized.UNF_room_catalog
ORDER BY type_price_per_night;

-- ---------------------------------------------------------------------
--  Step 2. room  <-  room columns, with a foreign key to room_type
-- ---------------------------------------------------------------------
INSERT INTO room (room_number, floor, status, room_type_id)
SELECT  c.room_number, c.floor, c.room_status, rt.room_type_id
FROM    hotel_unnormalized.UNF_room_catalog c
JOIN    room_type rt ON rt.type_name = c.type_name
ORDER BY c.room_number;

-- ---------------------------------------------------------------------
--  Step 3. guest  <-  guest_* columns
--  * one row per email (the unique business key)
--  * guest_name is split into first_name and last_name (1NF)
--  * when the copies disagree (two phone numbers for one guest), the
--    value from the booking with the NEWEST booking_date wins
-- ---------------------------------------------------------------------
INSERT INTO guest (first_name, last_name, email, phone)
SELECT  SUBSTRING_INDEX(t.guest_name, ' ', 1),
        TRIM(SUBSTRING(t.guest_name, LOCATE(' ', t.guest_name) + 1)),
        LOWER(t.guest_email),
        t.guest_phone
FROM (
        SELECT  f.*,
                ROW_NUMBER() OVER (PARTITION BY LOWER(f.guest_email) ORDER BY f.booking_date DESC, f.booking_id DESC) AS rn,
                MIN(f.booking_id) OVER (PARTITION BY LOWER(f.guest_email))                       AS first_booking
        FROM    hotel_unnormalized.UNF_booking_flat f
     ) t
WHERE   t.rn = 1
ORDER BY t.first_booking;

-- ---------------------------------------------------------------------
--  Step 4. booking  <-  booking-level columns (guest data replaced by guest_id,
--  total_price dropped because it can be calculated)
-- ---------------------------------------------------------------------
INSERT INTO booking (booking_id, guest_id, booking_date, check_in, check_out, status)
SELECT  f.booking_id, g.guest_id, f.booking_date, f.check_in, f.check_out, f.booking_status
FROM    hotel_unnormalized.UNF_booking_flat f
JOIN    guest g ON g.email = LOWER(f.guest_email);

-- ---------------------------------------------------------------------
--  Step 5. booking_room  <-  the ';' lists
--  Each list is turned into rows with JSON_TABLE. The position (n) ties
--  the room number, the price and the guest count of the same room.
--  room_types is not copied: the type is already known from the room.
-- ---------------------------------------------------------------------
INSERT INTO booking_room (booking_id, room_id, guests_count, price_per_night)
SELECT  f.booking_id,
        r.room_id,
        CAST(g.val AS UNSIGNED),
        CAST(p.val AS DECIMAL(8,2))
FROM    hotel_unnormalized.UNF_booking_flat f
CROSS JOIN JSON_TABLE(CONCAT('["', REPLACE(f.room_numbers,    ';', '","'), '"]'),
                      '$[*]' COLUMNS (n FOR ORDINALITY, val VARCHAR(10) PATH '$')) rn
CROSS JOIN JSON_TABLE(CONCAT('["', REPLACE(f.guests_per_room, ';', '","'), '"]'),
                      '$[*]' COLUMNS (n FOR ORDINALITY, val VARCHAR(10) PATH '$')) g
CROSS JOIN JSON_TABLE(CONCAT('["', REPLACE(f.room_prices,     ';', '","'), '"]'),
                      '$[*]' COLUMNS (n FOR ORDINALITY, val VARCHAR(10) PATH '$')) p
JOIN    room r ON r.room_number = rn.val
WHERE   g.n = rn.n
  AND   p.n = rn.n
ORDER BY f.booking_id, rn.n;

-- ---------------------------------------------------------------------
--  Step 6. payment  <-  payment1_* and payment2_* columns
--  The repeating group of columns becomes one row per payment.
--  Empty payment slots (NULL) are skipped.
-- ---------------------------------------------------------------------
INSERT INTO payment (booking_id, amount, payment_method, payment_status, payment_date)
SELECT booking_id,
       payment1_amount AS amount,
       payment1_method AS payment_method,
       payment1_status AS payment_status,
       payment1_date   AS payment_date
FROM   hotel_unnormalized.UNF_booking_flat
WHERE  payment1_method IS NOT NULL
UNION ALL
SELECT booking_id, payment2_amount, payment2_method, payment2_status, payment2_date
FROM   hotel_unnormalized.UNF_booking_flat
WHERE  payment2_method IS NOT NULL
ORDER BY booking_id, payment_date;

COMMIT;


-- =====================================================================
--  CHECKS: run these after the migration
-- =====================================================================

-- 1. Row counts: expected  guest 3, room_type 3, room 6, booking 6,
--    booking_room 7, payment 7
SELECT 'guest' AS table_name, COUNT(*) AS rows_copied FROM guest
UNION ALL SELECT 'room_type',    COUNT(*) FROM room_type
UNION ALL SELECT 'room',         COUNT(*) FROM room
UNION ALL SELECT 'booking',      COUNT(*) FROM booking
UNION ALL SELECT 'booking_room', COUNT(*) FROM booking_room
UNION ALL SELECT 'payment',      COUNT(*) FROM payment;

-- 2. The stored total_price of the old table must equal the calculated
--    total of the new database. Expected: 0 rows (no differences).
SELECT f.booking_id, f.total_price AS old_total, v.total_price AS new_total
FROM   hotel_unnormalized.UNF_booking_flat f
JOIN   v_booking_total v ON v.booking_id = f.booking_id
WHERE  f.total_price <> v.total_price;

-- 3. Amina now has ONE phone number (from her newest booking, ending 2233)
SELECT first_name, last_name, email, phone FROM guest ORDER BY guest_id;

-- 4. The Task 9 availability query, 10 Dec to 13 Dec 2026.
--    Expected: Deluxe 0, Suite 1, Standard 2
SELECT rt.type_name,
       rt.price_per_night,
       COUNT(r.room_id) AS available_rooms
FROM   room_type rt
LEFT JOIN room r
       ON  r.room_type_id = rt.room_type_id
       AND r.status = 'Available'
       AND r.room_id NOT IN (
             SELECT br.room_id
             FROM   booking_room br
             JOIN   booking b ON b.booking_id = br.booking_id
             WHERE  b.status IN ('Confirmed', 'CheckedIn')
               AND  b.check_in  < '2026-12-13'
               AND  b.check_out > '2026-12-10'
           )
GROUP BY rt.room_type_id, rt.type_name, rt.price_per_night
ORDER BY available_rooms ASC;
