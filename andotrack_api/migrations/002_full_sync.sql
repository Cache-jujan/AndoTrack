-- AndoTrack — Migration 002: Full DB sync
-- Adds all columns that exist in models but may be missing from the DB
-- Safe to run: uses IF NOT EXISTS logic via IGNORE / column checks
-- Run this on ANY database (local or Railway) to bring it up to date

USE andotrack;


-- ── users ─────────────────────────────────────────────────
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS date_of_birth DATE DEFAULT NULL;

-- ── race_runners ──────────────────────────────────────────
ALTER TABLE race_runners
    ADD COLUMN IF NOT EXISTS race_status VARCHAR(20) DEFAULT 'registered',
    ADD COLUMN IF NOT EXISTS bib_number INT DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS shirt_size VARCHAR(5) DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS claimed BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS claimed_at DATETIME DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS is_walkin BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS walkin_name VARCHAR(100) DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS walkin_contact VARCHAR(30) DEFAULT NULL;

-- ── race_results ──────────────────────────────────────────
ALTER TABLE race_results
    ADD COLUMN IF NOT EXISTS segment VARCHAR(20) DEFAULT NULL;

-- ── Verify ────────────────────────────────────────────────
SELECT 'users columns:' AS '';
SHOW COLUMNS FROM users;

SELECT 'race_runners columns:' AS '';
SHOW COLUMNS FROM race_runners;

SELECT 'race_results columns:' AS '';
SHOW COLUMNS FROM race_results;