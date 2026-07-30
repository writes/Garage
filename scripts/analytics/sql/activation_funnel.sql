-- Activation by assigned design arm. Uses only existing Garage event names.
-- Replace the table identifier before execution. Dates are inclusive YYYYMMDD.
DECLARE start_date STRING DEFAULT '20260701';
DECLARE end_date STRING DEFAULT '20260731';
DECLARE observation_end_date STRING DEFAULT FORMAT_DATE(
  '%Y%m%d', DATE_ADD(PARSE_DATE('%Y%m%d', end_date), INTERVAL 7 DAY)
);

WITH raw_events AS (
  SELECT
    event_date,
    event_timestamp,
    COALESCE(NULLIF(user_id, ''), user_pseudo_id) AS analysis_user_id,
    event_name,
    NULLIF((
      SELECT value.string_value
      FROM UNNEST(user_properties)
      WHERE key = 'design_arm'
    ), '') AS design_arm,
    NULLIF(COALESCE(
      (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'experiment_epoch'),
      CAST((SELECT value.int_value FROM UNNEST(user_properties) WHERE key = 'experiment_epoch') AS STRING)
    ), '') AS experiment_epoch
  FROM `YOUR_PROJECT.analytics_YOUR_PROPERTY.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND observation_end_date
),
user_assignment AS (
  -- Assignment is read from the latest observed user property in the window.
  SELECT
    analysis_user_id,
    ARRAY_AGG(design_arm IGNORE NULLS ORDER BY event_timestamp DESC LIMIT 1)[SAFE_OFFSET(0)] AS design_arm,
    ARRAY_AGG(experiment_epoch IGNORE NULLS ORDER BY event_timestamp DESC LIMIT 1)[SAFE_OFFSET(0)] AS experiment_epoch
  FROM raw_events
  WHERE analysis_user_id IS NOT NULL
  GROUP BY analysis_user_id
),
cohort_first_opens AS (
  SELECT
    analysis_user_id,
    MIN(event_timestamp) AS first_open_timestamp
  FROM raw_events
  WHERE event_name = 'first_open'
    AND event_date BETWEEN start_date AND end_date
    AND analysis_user_id IS NOT NULL
  GROUP BY analysis_user_id
),
per_user AS (
  SELECT
    first_open.analysis_user_id,
    COALESCE(assignment.design_arm, 'unassigned') AS design_arm,
    COALESCE(assignment.experiment_epoch, 'unassigned') AS experiment_epoch,
    MAX(IF(
      event.event_name = 'first_vehicle_added'
      AND event.event_timestamp BETWEEN first_open.first_open_timestamp
        AND first_open.first_open_timestamp + 7 * 24 * 60 * 60 * 1000000,
      1,
      0
    )) = 1 AS added_vehicle,
    MAX(IF(
      event.event_name = 'first_entry_added'
      AND event.event_timestamp BETWEEN first_open.first_open_timestamp
        AND first_open.first_open_timestamp + 7 * 24 * 60 * 60 * 1000000,
      1,
      0
    )) = 1 AS added_entry,
    MAX(IF(
      event.event_name IN (
        'voice_capture_started', 'oil_analysis_requested', 'receipt_capture_started'
      )
      AND event.event_timestamp BETWEEN first_open.first_open_timestamp
        AND first_open.first_open_timestamp + 7 * 24 * 60 * 60 * 1000000,
      1,
      0
    )) = 1 AS started_ai_feature
  FROM cohort_first_opens AS first_open
  LEFT JOIN user_assignment AS assignment USING (analysis_user_id)
  LEFT JOIN raw_events AS event USING (analysis_user_id)
  GROUP BY 1, 2, 3
)
SELECT
  design_arm,
  experiment_epoch,
  COUNT(*) AS first_open_users,
  COUNTIF(added_vehicle) AS first_vehicle_added_users,
  SAFE_DIVIDE(COUNTIF(added_vehicle), COUNT(*)) AS first_vehicle_added_rate,
  COUNTIF(added_vehicle AND added_entry) AS first_entry_added_users,
  SAFE_DIVIDE(COUNTIF(added_vehicle AND added_entry), COUNT(*)) AS first_entry_added_rate,
  COUNTIF(added_vehicle AND added_entry AND started_ai_feature) AS first_ai_event_users,
  SAFE_DIVIDE(
    COUNTIF(added_vehicle AND added_entry AND started_ai_feature),
    COUNT(*)
  ) AS first_ai_event_rate,
  COUNTIF(added_vehicle AND added_entry AND started_ai_feature) AS activation_complete_users,
  SAFE_DIVIDE(
    COUNTIF(added_vehicle AND added_entry AND started_ai_feature),
    COUNT(*)
  ) AS activation_complete_rate
FROM per_user
GROUP BY 1, 2
ORDER BY 1, 2;

