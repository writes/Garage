-- Source-level conversion diagnostics by assigned design arm.
-- paywall_dismissed is an exit branch after a view; purchase attempts occur after a view,
-- not after dismissal. Existing purchase events do not carry source, so attribution is
-- observational when a user sees more than one source.
DECLARE start_date STRING DEFAULT '20260701';
DECLARE end_date STRING DEFAULT '20260731';

WITH raw_events AS (
  SELECT
    event_timestamp,
    COALESCE(NULLIF(user_id, ''), user_pseudo_id) AS analysis_user_id,
    event_name,
    NULLIF((
      SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source'
    ), '') AS source,
    NULLIF((
      SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'design_arm'
    ), '') AS design_arm,
    NULLIF(COALESCE(
      (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'experiment_epoch'),
      CAST((SELECT value.int_value FROM UNNEST(user_properties) WHERE key = 'experiment_epoch') AS STRING)
    ), '') AS experiment_epoch
  FROM `YOUR_PROJECT.analytics_YOUR_PROPERTY.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
),
source_exposures AS (
  SELECT * EXCEPT (exposure_rank)
  FROM (
    SELECT
      analysis_user_id,
      COALESCE(design_arm, 'unassigned') AS design_arm,
      COALESCE(experiment_epoch, 'unassigned') AS experiment_epoch,
      source,
      event_timestamp AS exposure_timestamp,
      ROW_NUMBER() OVER (
        PARTITION BY analysis_user_id, COALESCE(design_arm, 'unassigned'), source
        ORDER BY event_timestamp
      ) AS exposure_rank
    FROM raw_events
    WHERE event_name = 'upsell_exposure'
      AND analysis_user_id IS NOT NULL
      AND source IS NOT NULL
  )
  WHERE exposure_rank = 1
),
first_views AS (
  SELECT
    exposure.*,
    MIN(event.event_timestamp) AS paywall_viewed_timestamp
  FROM source_exposures AS exposure
  LEFT JOIN raw_events AS event
    ON event.analysis_user_id = exposure.analysis_user_id
    AND event.event_name = 'paywall_viewed'
    AND event.source = exposure.source
    AND event.event_timestamp >= exposure.exposure_timestamp
  GROUP BY 1, 2, 3, 4, 5
),
per_user AS (
  SELECT
    view.*,
    MIN(IF(
      event.event_name = 'paywall_dismissed'
      AND event.source = view.source
      AND event.event_timestamp >= view.paywall_viewed_timestamp,
      event.event_timestamp,
      NULL
    )) AS paywall_dismissed_timestamp,
    MIN(IF(
      event.event_name = 'purchase_attempted'
      AND event.event_timestamp >= view.paywall_viewed_timestamp,
      event.event_timestamp,
      NULL
    )) AS purchase_attempted_timestamp,
    MIN(IF(
      event.event_name = 'purchase_completed'
      AND event.event_timestamp >= view.paywall_viewed_timestamp,
      event.event_timestamp,
      NULL
    )) AS purchase_completed_timestamp,
    MIN(IF(
      event.event_name = 'trial_started'
      AND event.event_timestamp >= view.paywall_viewed_timestamp,
      event.event_timestamp,
      NULL
    )) AS trial_started_timestamp
  FROM first_views AS view
  LEFT JOIN raw_events AS event
    ON event.analysis_user_id = view.analysis_user_id
  GROUP BY 1, 2, 3, 4, 5, 6
)
SELECT
  source,
  design_arm,
  experiment_epoch,
  COUNT(*) AS upsell_exposure_users,
  COUNTIF(paywall_viewed_timestamp IS NOT NULL) AS paywall_viewed_users,
  SAFE_DIVIDE(COUNTIF(paywall_viewed_timestamp IS NOT NULL), COUNT(*)) AS upsell_to_paywall_view_rate,
  COUNTIF(paywall_dismissed_timestamp IS NOT NULL) AS paywall_dismissed_users,
  SAFE_DIVIDE(
    COUNTIF(paywall_dismissed_timestamp IS NOT NULL),
    COUNTIF(paywall_viewed_timestamp IS NOT NULL)
  ) AS paywall_dismiss_rate,
  COUNTIF(purchase_attempted_timestamp IS NOT NULL) AS purchase_attempted_users,
  SAFE_DIVIDE(
    COUNTIF(purchase_attempted_timestamp IS NOT NULL),
    COUNTIF(paywall_viewed_timestamp IS NOT NULL)
  ) AS paywall_to_purchase_attempt_rate,
  COUNTIF(purchase_completed_timestamp IS NOT NULL) AS purchase_completed_users,
  SAFE_DIVIDE(
    COUNTIF(purchase_completed_timestamp IS NOT NULL),
    COUNTIF(purchase_attempted_timestamp IS NOT NULL)
  ) AS purchase_completed_rate,
  COUNTIF(trial_started_timestamp IS NOT NULL) AS trial_started_users,
  SAFE_DIVIDE(
    COUNTIF(trial_started_timestamp IS NOT NULL),
    COUNTIF(purchase_attempted_timestamp IS NOT NULL)
  ) AS trial_started_rate,
  COUNTIF(
    purchase_completed_timestamp IS NOT NULL OR trial_started_timestamp IS NOT NULL
  ) AS converted_users,
  SAFE_DIVIDE(
    COUNTIF(purchase_completed_timestamp IS NOT NULL OR trial_started_timestamp IS NOT NULL),
    COUNT(*)
  ) AS exposure_to_conversion_rate
FROM per_user
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;

