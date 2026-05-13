-- ============================================================
-- AndoTrack — Migration: Race & Registration expansion
-- Run this ONCE against your existing andotrack database.
-- Safe to run: all statements use IF NOT EXISTS / IGNORE.
-- ============================================================

USE andotrack;

-- ── races table — new columns ─────────────────────────────

ALTER TABLE races
    ADD COLUMN category VARCHAR(20) DEFAULT NULL,
    ADD COLUMN description TEXT DEFAULT NULL,
    ADD COLUMN location VARCHAR(255) DEFAULT NULL,
    ADD COLUMN sponsors TEXT DEFAULT NULL,
    ADD COLUMN max_participants INT DEFAULT NULL,
    ADD COLUMN scheduled_start DATETIME DEFAULT NULL,
    ADD COLUMN registration_fee FLOAT DEFAULT 0.0,
    ADD COLUMN banner_url VARCHAR(500) DEFAULT NULL,
    ADD COLUMN created_at DATETIME DEFAULT CURRENT_TIMESTAMP;

-- Expand status ENUM to include new lifecycle values
-- (MySQL requires redefining the full ENUM)
ALTER TABLE races
    MODIFY COLUMN status VARCHAR(20) DEFAULT 'upcoming';

-- ── race_runners table — new columns ─────────────────────

ALTER TABLE race_runners
    ADD COLUMN city VARCHAR(100) DEFAULT NULL,
    ADD COLUMN contact_number VARCHAR(30) DEFAULT NULL,
    ADD COLUMN is_first_marathon BOOLEAN DEFAULT FALSE,
    ADD COLUMN emergency_contact VARCHAR(100) DEFAULT NULL,
    ADD COLUMN sex ENUM('male','female','prefer_not_to_say')
        DEFAULT 'prefer_not_to_say',
    ADD COLUMN qr_token VARCHAR(100) DEFAULT NULL,
    ADD COLUMN is_present BOOLEAN DEFAULT FALSE,
    ADD COLUMN checked_in_at DATETIME DEFAULT NULL;

ALTER TABLE race_runners
    ADD CONSTRAINT uq_qr_token UNIQUE (qr_token);

-- ── Verify ───────────────────────────────────────────────

SELECT 'races columns:' AS '';
SHOW COLUMNS FROM races;

SELECT 'race_runners columns:' AS '';
SHOW COLUMNS FROM race_runners;