-- Notification task funnel by category and notif_holdout user property.
-- This is user/category chronological attribution: no notification instance ID is in scope.
DECLARE start_date STRING DEFAULT '20260701';
DECLARE end_date STRING DEFAULT '20260731';

WITH raw_events AS (
  SELECT
    event_timestamp,
    COALESCE(NULLIF(user_id, ''), user_pseudo_id) AS analysis_user_id,
    event_name,
    NULLIF((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'category'), '') AS category,
    NULLIF(COALESCE(
      (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'notif_holdout'),
      CAST((SELECT value.int_value FROM UNNEST(user_properties) WHERE key = 'notif_holdout') AS STRING)
    ), '') AS notif_holdout
  FROM `YOUR_PROJECT.analytics_YOUR_PROPERTY.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
),
scheduled AS (
  SELECT * EXCEPT (schedule_rank)
  FROM (
    SELECT
      analysis_user_id,
      category,
      COALESCE(notif_holdout, 'unassigned') AS notif_holdout,
      event_timestamp AS scheduled_timestamp,
      ROW_NUMBER() OVER (
        PARTITION BY analysis_user_id, category, COALESCE(notif_holdout, 'unassigned')
        ORDER BY event_timestamp
      ) AS schedule_rank
    FROM raw_events
    WHERE event_name = 'notif_scheduled'
      AND analysis_user_id IS NOT NULL
      AND category IS NOT NULL
  )
  WHERE schedule_rank = 1
),
opened AS (
  SELECT
    scheduled.*,
    MIN(event.event_timestamp) AS opened_timestamp
  FROM scheduled
  LEFT JOIN raw_events AS event
    ON event.analysis_user_id = scheduled.analysis_user_id
    AND event.category = scheduled.category
    AND event.event_name = 'notif_opened'
    AND event.event_timestamp >= scheduled.scheduled_timestamp
  GROUP BY 1, 2, 3, 4
),
per_user AS (
  SELECT
    opened.*,
    MIN(event.event_timestamp) AS task_completed_timestamp
  FROM opened
  LEFT JOIN raw_events AS event
    ON event.analysis_user_id = opened.analysis_user_id
    AND event.category = opened.category
    AND event.event_name = 'notif_task_completed'
    AND event.event_timestamp >= opened.opened_timestamp
  GROUP BY 1, 2, 3, 4, 5
)
SELECT
  category,
  notif_holdout,
  COUNT(*) AS notif_scheduled_users,
  COUNTIF(opened_timestamp IS NOT NULL) AS notif_opened_users,
  SAFE_DIVIDE(COUNTIF(opened_timestamp IS NOT NULL), COUNT(*)) AS scheduled_to_open_rate,
  COUNTIF(task_completed_timestamp IS NOT NULL) AS notif_task_completed_users,
  SAFE_DIVIDE(
    COUNTIF(task_completed_timestamp IS NOT NULL),
    COUNTIF(opened_timestamp IS NOT NULL)
  ) AS open_to_completion_rate,
  SAFE_DIVIDE(COUNTIF(task_completed_timestamp IS NOT NULL), COUNT(*)) AS scheduled_to_completion_rate
FROM per_user
GROUP BY 1, 2
ORDER BY 1, 2;

