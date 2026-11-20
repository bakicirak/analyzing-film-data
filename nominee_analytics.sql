-- ============================================================================
-- Film nominee analytics (BigQuery Standard SQL)
-- Tables
--   nominee_information.core_table : one row per nominee (name, top_genre, birthday, id)
--   nominee_filmography.core_table : one row per credit (name, amg_movie_id, movie_title,
--                                    role_type, rating, year, id)
--
-- IMPORTANT: filmography.id is a running row number, NOT the nominee id.
-- The two tables are joined on `name`. (An earlier version joined on id,
-- which matched credits to the wrong people.)
-- `rating` is missing for ~22 % of credits. AVG/STDDEV ignore NULLs, and
-- minimum sample sizes are applied where averages are ranked.
-- ============================================================================


-- 0. Data quality checks
SELECT
  (SELECT COUNT(*) FROM `main-data-hub.nominee_filmography.core_table`)                        AS credits,
  (SELECT COUNTIF(rating IS NULL) FROM `main-data-hub.nominee_filmography.core_table`)         AS credits_without_rating,
  (SELECT COUNT(*) FROM `main-data-hub.nominee_information.core_table`)                        AS nominees,
  (SELECT COUNT(*) - COUNT(DISTINCT amg_person_id)
   FROM `main-data-hub.nominee_information.core_table`)                                        AS duplicate_person_ids;
-- -> 2 people are stored twice under different spellings (e.g. "Daniel Day Lewis" / "Daniel Day-Lewis")


-- 1. Number of credits per person and role type
SELECT
  f.name,
  i.top_genre,
  f.role_type,
  COUNT(*) AS credits
FROM `main-data-hub.nominee_filmography.core_table` AS f
JOIN `main-data-hub.nominee_information.core_table` AS i
  ON f.name = i.name
GROUP BY f.name, i.top_genre, f.role_type
ORDER BY credits DESC;


-- 2. Highest average rating per nominee (min. 10 rated films)
SELECT
  name,
  ROUND(AVG(rating), 2) AS avg_rating,
  COUNT(rating)         AS rated_films
FROM `main-data-hub.nominee_filmography.core_table`
GROUP BY name
HAVING COUNT(rating) >= 10
ORDER BY avg_rating DESC
LIMIT 10;


-- 3. Films per decade
SELECT
  CAST(FLOOR(year / 10) * 10 AS INT64) AS decade,
  COUNT(DISTINCT amg_movie_id)         AS films
FROM `main-data-hub.nominee_filmography.core_table`
WHERE year IS NOT NULL
GROUP BY decade
ORDER BY decade;


-- 4. Nominees per top genre, with average film rating
SELECT
  i.top_genre,
  COUNT(DISTINCT i.name)  AS nominees,
  ROUND(AVG(f.rating), 2) AS avg_film_rating
FROM `main-data-hub.nominee_information.core_table` AS i
LEFT JOIN `main-data-hub.nominee_filmography.core_table` AS f
  ON f.name = i.name
GROUP BY i.top_genre
ORDER BY nominees DESC;


-- 5. Age at debut (first credited film) distribution
WITH debut AS (
  SELECT
    i.name,
    CAST(MIN(f.year) AS INT64) - EXTRACT(YEAR FROM DATE(i.birthday)) AS age_at_debut
  FROM `main-data-hub.nominee_filmography.core_table` AS f
  JOIN `main-data-hub.nominee_information.core_table` AS i
    ON f.name = i.name
  WHERE i.birthday IS NOT NULL AND f.year IS NOT NULL
  GROUP BY i.name, i.birthday
)
SELECT
  CASE
    WHEN age_at_debut < 20 THEN '1) under 20'
    WHEN age_at_debut < 25 THEN '2) 20-24'
    WHEN age_at_debut < 30 THEN '3) 25-29'
    WHEN age_at_debut < 40 THEN '4) 30-39'
    ELSE                        '5) 40+'
  END      AS age_band,
  COUNT(*) AS nominees
FROM debut
GROUP BY age_band
ORDER BY age_band;


-- 6. Top-rated film per genre (genre = nominee's top genre)
WITH ranked AS (
  SELECT
    i.top_genre,
    f.movie_title,
    f.name,
    f.rating,
    ROW_NUMBER() OVER (PARTITION BY i.top_genre ORDER BY f.rating DESC, f.movie_title) AS rn
  FROM `main-data-hub.nominee_filmography.core_table` AS f
  JOIN `main-data-hub.nominee_information.core_table` AS i
    ON f.name = i.name
  WHERE f.rating IS NOT NULL
)
SELECT top_genre, movie_title, name, rating
FROM ranked
WHERE rn = 1
ORDER BY top_genre;


-- 7. Year-over-year change in average rating per nominee
WITH yearly AS (
  SELECT name, CAST(year AS INT64) AS year, AVG(rating) AS avg_rating
  FROM `main-data-hub.nominee_filmography.core_table`
  WHERE rating IS NOT NULL AND year IS NOT NULL
  GROUP BY name, year
)
SELECT
  name,
  year,
  ROUND(avg_rating, 2) AS avg_rating,
  ROUND(100 * SAFE_DIVIDE(avg_rating - LAG(avg_rating) OVER w, LAG(avg_rating) OVER w), 1) AS pct_change_vs_prev_active_year
FROM yearly
WINDOW w AS (PARTITION BY name ORDER BY year)
ORDER BY name, year;


-- 8. Most connected nominees (distinct fellow nominees they shared a film with)
WITH credits AS (
  SELECT DISTINCT name, amg_movie_id
  FROM `main-data-hub.nominee_filmography.core_table`
)
SELECT
  a.name,
  COUNT(DISTINCT b.name) AS distinct_collaborators
FROM credits AS a
JOIN credits AS b
  ON a.amg_movie_id = b.amg_movie_id
 AND a.name <> b.name
GROUP BY a.name
ORDER BY distinct_collaborators DESC
LIMIT 10;


-- 9. Rating volatility: most inconsistent careers (min. 10 rated films)
SELECT
  name,
  ROUND(STDDEV_POP(rating), 2) AS rating_stddev,
  ROUND(AVG(rating), 2)        AS avg_rating,
  COUNT(rating)                AS rated_films
FROM `main-data-hub.nominee_filmography.core_table`
GROUP BY name
HAVING COUNT(rating) >= 10
ORDER BY rating_stddev DESC
LIMIT 10;


-- 10. Does age at debut predict average rating? (Pearson correlation)
WITH per_person AS (
  SELECT
    i.name,
    CAST(MIN(f.year) AS INT64) - EXTRACT(YEAR FROM DATE(i.birthday)) AS age_at_debut,
    AVG(f.rating)                                                    AS avg_rating,
    COUNT(f.rating)                                                  AS rated_films
  FROM `main-data-hub.nominee_filmography.core_table` AS f
  JOIN `main-data-hub.nominee_information.core_table` AS i
    ON f.name = i.name
  WHERE i.birthday IS NOT NULL
  GROUP BY i.name, i.birthday
)
SELECT
  ROUND(CORR(age_at_debut, avg_rating), 2) AS corr_debut_age_vs_rating,
  COUNT(*)                                 AS nominees
FROM per_person
WHERE rated_films >= 5;


-- 11. Do ratings decline over a career? (avg rating by film number)
WITH numbered AS (
  SELECT
    name,
    rating,
    ROW_NUMBER() OVER (PARTITION BY name ORDER BY year, amg_movie_id) AS film_no
  FROM `main-data-hub.nominee_filmography.core_table`
  WHERE rating IS NOT NULL AND year IS NOT NULL
)
SELECT
  CASE
    WHEN film_no <= 10 THEN '1) films 1-10'
    WHEN film_no <= 30 THEN '2) films 11-30'
    WHEN film_no <= 60 THEN '3) films 31-60'
    ELSE                    '4) film 61+'
  END                   AS career_stage,
  ROUND(AVG(rating), 2) AS avg_rating,
  COUNT(*)              AS films
FROM numbered
GROUP BY career_stage
ORDER BY career_stage;
