-- Make report.event_id cascade on event deletion.
-- Without this, DELETE /events/{id} fails with a FK violation whenever
-- a VEN has submitted a report referencing that event.
ALTER TABLE report DROP CONSTRAINT IF EXISTS report_event_id_fkey;
ALTER TABLE report
    ADD CONSTRAINT report_event_id_fkey
    FOREIGN KEY (event_id) REFERENCES event(id) ON DELETE CASCADE;
