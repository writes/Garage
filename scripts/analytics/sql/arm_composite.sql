-- Experiment decision input: one row per assigned design arm.
-- The seven-day horizon prevents immature cohorts from inflating an arm's outcome rate.
-- Replace the table identifier and edit experiment_name/experiment_epoch before execution.
DECLARE start_date STRING DEFAULT '20260701';
DECLARE end_date STRING DEFAULT '20260731';
DECLARE experiment_name STRING DEFAULT 'design_megatest';
DECLARE experiment_epoch STRING DEFAULT '1';
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
      SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'design_arm'
    ), '') AS design_arm_property,
    NULLIF(COALESCE(
      (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'experiment_epoch'),
      CAST((SELECT value.int_value FROM UNNEST(user_properties) WHERE key = 'experiment_epoch') AS STRING)
    ), '') AS experiment_epoch_property,
    NULLIF((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source'), '') AS source,
    NULLIF((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'experiment'), '') AS experiment_param,
    NULLIF((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'arm'), '') AS arm_param,
    NULLIF(COALESCE(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'epoch'),
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'epoch') AS STRING)
    ), '') AS epoch_param
  FROM `YOUR_PROJECT.analytics_YOUR_PROPERTY.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND observation_end_date
),
cohorts AS (
  SELECT * EXCEPT (exposure_rank)
  FROM (
    SELECT
      analysis_user_id,
      event_timestamp AS exposure_timestamp,
      PARSE_DATE('%Y%m%d', event_date) AS exposure_date,
      -- The property is the reporting arm. Param fallback retains an exposure if Firebase
      -- has not echoed the just-set property on the same event yet.
      COALESCE(design_arm_property, arm_param, 'unassigned') AS design_arm,
      COALESCE(experiment_epoch_property, epoch_param, experiment_epoch) AS assignment_epoch,
      arm_param AS exposure_arm,
      epoch_param AS exposure_epoch,
      ROW_NUMBER() OVER (PARTITION BY analysis_user_id ORDER BY event_timestamp) AS exposure_rank
    FROM raw_events
    WHERE event_name = 'experiment_exposure'
      AND event_date BETWEEN start_date AND end_date
      AND experiment_param = experiment_name
      AND epoch_param = experiment_epoch
      AND analysis_user_id IS NOT NULL
  )
  WHERE exposure_rank = 1
),
first_opens AS (
  SELECT
    cohort.analysis_user_id,
    cohort.exposure_timestamp,
    MIN(event.event_timestamp) AS first_open_timestamp
  FROM cohorts AS cohort
  LEFT JOIN raw_events AS event
    ON event.analysis_user_id = cohort.analysis_user_id
    AND event.event_name = 'first_open'
    AND event.event_timestamp <= cohort.exposure_timestamp
  GROUP BY 1, 2
),
per_user AS (
  SELECT
    cohort.*,
    first_open.first_open_timestamp,
    cohort.exposure_date <= DATE_SUB(PARSE_DATE('%Y%m%d', end_date), INTERVAL 7 DAY) AS is_mature,
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
    )) = 1 AS started_ai_feature,
    MAX(IF(
      event.event_name = 'session_start'
      AND PARSE_DATE('%Y%m%d', event.event_date) = DATE_ADD(cohort.exposure_date, INTERVAL 7 DAY),
      1,
      0
    )) = 1 AS returned_d7,
    COUNTIF(
      event.event_name IN ('entry_saved', 'receipt_entry_confirmed', 'voice_entry_confirmed')
      AND PARSE_DATE('%Y%m%d', event.event_date) BETWEEN cohort.exposure_date
        AND DATE_ADD(cohort.exposure_date, INTERVAL 6 DAY)
    ) AS core_actions,
    COUNT(DISTINCT IF(
      event.event_name = 'session_start'
      AND PARSE_DATE('%Y%m%d', event.event_date) BETWEEN cohort.exposure_date
        AND DATE_ADD(cohort.exposure_date, INTERVAL 6 DAY),
      event.event_date,
      NULL
    )) AS active_user_days,
    MAX(IF(
      event.event_name = 'upsell_exposure'
      AND event.event_timestamp BETWEEN cohort.exposure_timestamp
        AND cohort.exposure_timestamp + 7 * 24 * 60 * 60 * 1000000,
      1,
      0
    )) = 1 AS had_upsell_exposure,
    MAX(IF(
      event.event_name = 'paywall_viewed'
      AND event.event_timestamp BETWEEN cohort.exposure_timestamp
        AND cohort.exposure_timestamp + 7 * 24 * 60 * 60 * 1000000,
      1,
      0
    )) = 1 AS viewed_paywall,
    MAX(IF(
      event.event_name IN ('purchase_completed', 'trial_started')
      AND event.event_timestamp BETWEEN cohort.exposure_timestamp
        AND cohort.exposure_timestamp + 7 * 24 * 60 * 60 * 1000000,
      1,
      0
    )) = 1 AS converted
  FROM cohorts AS cohort
  LEFT JOIN first_opens AS first_open
    ON first_open.analysis_user_id = cohort.analysis_user_id
    AND first_open.exposure_timestamp = cohort.exposure_timestamp
  LEFT JOIN raw_events AS event
    ON event.analysis_user_id = cohort.analysis_user_id
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
)
SELECT
  experiment_name AS experiment,
  experiment_epoch AS experiment_epoch,
  design_arm,
  COUNT(*) AS n_exposed,
  COUNTIF(is_mature AND added_vehicle AND added_entry AND started_ai_feature) AS activation_numerator,
  COUNTIF(is_mature) AS activation_denominator,
  SAFE_DIVIDE(
    COUNTIF(is_mature AND added_vehicle AND added_entry AND started_ai_feature),
    COUNTIF(is_mature)
  ) AS activation_rate,
  COUNTIF(is_mature AND returned_d7) AS d7_return_numerator,
  COUNTIF(is_mature) AS d7_return_denominator,
  SAFE_DIVIDE(COUNTIF(is_mature AND returned_d7), COUNTIF(is_mature)) AS d7_return_rate,
  SUM(IF(is_mature, core_actions, 0)) AS core_actions_numerator,
  SUM(IF(is_mature, active_user_days, 0)) AS core_actions_denominator,
  SAFE_DIVIDE(
    SUM(IF(is_mature, core_actions, 0)),
    SUM(IF(is_mature, active_user_days, 0))
  ) AS core_actions_per_active_day,
  COUNTIF(is_mature AND had_upsell_exposure AND viewed_paywall) AS paywall_ctr_numerator,
  COUNTIF(is_mature AND had_upsell_exposure) AS paywall_ctr_denominator,
  SAFE_DIVIDE(
    COUNTIF(is_mature AND had_upsell_exposure AND viewed_paywall),
    COUNTIF(is_mature AND had_upsell_exposure)
  ) AS paywall_ctr,
  COUNTIF(is_mature AND converted) AS purchase_numerator,
  COUNTIF(is_mature) AS purchase_denominator,
  SAFE_DIVIDE(COUNTIF(is_mature AND converted), COUNTIF(is_mature)) AS purchase_rate
FROM per_user
GROUP BY 1, 2, 3
ORDER BY design_arm;

