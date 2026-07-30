-- Weekly feature adoption. `active_users` means users with any exported event in the week.
-- Existing entries/screens use their closed-enum parameters; feature_used is new instrumentation.
DECLARE start_date STRING DEFAULT '20260701';
DECLARE end_date STRING DEFAULT '20260731';

WITH raw_events AS (
  SELECT
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK(MONDAY)) AS week,
    COALESCE(NULLIF(user_id, ''), user_pseudo_id) AS analysis_user_id,
    event_name,
    NULLIF((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'entry_type'), '') AS entry_type,
    NULLIF((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'screen'), '') AS screen,
    NULLIF((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'feature'), '') AS feature
  FROM `YOUR_PROJECT.analytics_YOUR_PROPERTY.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
),
weekly_active AS (
  SELECT week, COUNT(DISTINCT analysis_user_id) AS active_users
  FROM raw_events
  WHERE analysis_user_id IS NOT NULL
  GROUP BY 1
),
feature_events AS (
  SELECT week, analysis_user_id, CONCAT('entry_saved:', COALESCE(entry_type, 'unknown')) AS feature
  FROM raw_events
  WHERE event_name = 'entry_saved'

  UNION ALL
  SELECT week, analysis_user_id, 'voice_entry_confirmed'
  FROM raw_events
  WHERE event_name = 'voice_entry_confirmed'

  UNION ALL
  SELECT week, analysis_user_id, 'receipt_entry_confirmed'
  FROM raw_events
  WHERE event_name = 'receipt_entry_confirmed'

  UNION ALL
  SELECT week, analysis_user_id, 'export_csv'
  FROM raw_events
  WHERE event_name = 'export_csv'

  UNION ALL
  SELECT week, analysis_user_id, 'export_pdf'
  FROM raw_events
  WHERE event_name = 'export_pdf'

  UNION ALL
  SELECT week, analysis_user_id, 'oil_analysis_succeeded'
  FROM raw_events
  WHERE event_name = 'oil_analysis_succeeded'

  UNION ALL
  SELECT week, analysis_user_id, 'reminder_created'
  FROM raw_events
  WHERE event_name = 'reminder_created'

  UNION ALL
  SELECT week, analysis_user_id, 'reminder_completed'
  FROM raw_events
  WHERE event_name = 'reminder_completed'

  UNION ALL
  SELECT week, analysis_user_id, 'recall_lookup_succeeded'
  FROM raw_events
  WHERE event_name = 'recall_lookup_succeeded'

  UNION ALL
  SELECT week, analysis_user_id, CONCAT('screen_viewed:', COALESCE(screen, 'unknown'))
  FROM raw_events
  WHERE event_name = 'screen_viewed'

  UNION ALL
  SELECT week, analysis_user_id, CONCAT('feature_used:', feature)
  FROM raw_events
  WHERE event_name = 'feature_used'
    AND feature IN ('gallery', 'warranty', 'wear', 'dossier', 'theming')
)
SELECT
  feature,
  week AS week_start,
  COUNT(DISTINCT feature_events.analysis_user_id) AS active_users,
  COUNT(*) AS events,
  SAFE_DIVIDE(COUNT(DISTINCT feature_events.analysis_user_id), weekly_active.active_users) AS share_of_active
FROM feature_events
JOIN weekly_active USING (week)
WHERE feature_events.analysis_user_id IS NOT NULL
GROUP BY 1, 2, weekly_active.active_users
ORDER BY week_start, feature;

