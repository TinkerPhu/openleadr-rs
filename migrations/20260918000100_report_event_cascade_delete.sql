-- Make report.event_id cascade on event deletion.
--
-- Without this, DELETE /events/{id} fails with a foreign-key violation whenever a VEN
-- has submitted a report referencing that event. 3.1 makes this more pressing, not less:
-- eventID is now a report's only object link (programID and venID were dropped), so every
-- report is FK-bound to an event.
--
-- Dated after the last upstream migration so it applies in order on a fresh database.
ALTER TABLE report DROP CONSTRAINT IF EXISTS report_event_id_fkey;
ALTER TABLE report
    ADD CONSTRAINT report_event_id_fkey
    FOREIGN KEY (event_id) REFERENCES event (id) ON DELETE CASCADE;
