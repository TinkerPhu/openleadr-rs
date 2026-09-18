-- GB-04: filter events by active/past status in SQL instead of fetching every row and
-- filtering in Rust after OFFSET/LIMIT already ran (which also made `?active=` plus
-- pagination silently wrong: LIMIT/OFFSET picked a page *before* the active filter was
-- applied, so a page could come back short or with rows from the wrong page).
--
-- ends_at is NULL for an open-ended or undeterminable end (the event is always active);
-- otherwise it is the instant the event stops being active. It is computed
-- application-side by openleadr_wire::event::EventRequest::ends_at() -- the single
-- authority for that question -- and kept in sync on every insert and update.
alter table event
    add column ends_at timestamptz;

create index event_ends_at_index
    on event (ends_at);

-- Backfill existing rows for the common case only: an event-level intervalPeriod with a
-- duration. Postgres accepts ISO 8601 duration text (e.g. "PT1H") as an `interval`
-- literal directly, so this covers it without re-implementing the app's duration parser
-- in SQL. Rows whose end depends on per-interval timing or on the 3.1 top-level duration
-- are left NULL -- the same "always active" fallback used for undeterminable cases -- and
-- get a real ends_at as soon as they are next created or updated.
update event
set ends_at = (interval_period ->> 'start')::timestamptz
    + (interval_period ->> 'duration')::interval
where interval_period is not null
  and interval_period ->> 'duration' is not null;
