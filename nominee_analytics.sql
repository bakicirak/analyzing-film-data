-- 1. Count of Roles per Person (by Role Type)

SELECT
  f.name,
  i.top_genre,
  f.role_type,
  COUNT(1) AS role_count
FROM `main-data-hub.nominee_filmography.core_table`  AS f
JOIN `main-data-hub.nominee_information.core_table` AS i
  ON f.id = i.id
GROUP BY f.name, i.top_genre, f.role_type
ORDER BY role_count DESC;



-- 2. Average Movie Rating per Nominee

SELECT
  f.name,
  ROUND(AVG(f.rating), 2) AS avg_rating,
  COUNT(1) AS films_count
FROM `main-data-hub.nominee_filmography.core_table` AS f
GROUP BY f.name
HAVING films_count > 2 
ORDER BY avg_rating DESC
LIMIT 10;


-- 3. Films per Year Trend

SELECT
  SAFE_CAST(f.year AS INT64) AS year,
  COUNT(DISTINCT f.amg_movie_id) AS films_count
FROM `main-data-hub.nominee_filmography.core_table` AS f
GROUP BY year
ORDER BY year;



-- 4. Top Genres by Number of Nominees

SELECT
  i.top_genre,
  COUNT(DISTINCT i.id) AS nominee_count
FROM `main-data-hub.nominee_information.core_table` AS i
GROUP BY i.top_genre
ORDER BY nominee_count DESC;


-- 5. Nominee Age Distribution

SELECT
  name,
  DATE_DIFF("1925-01-01", DATE(birthday), YEAR) AS current_age
FROM `main-data-hub.nominee_information.core_table`
WHERE birthday IS NOT NULL
ORDER BY current_age DESC;

-- 6. Top-Rated Movie per Genre

WITH best_per_nominee AS (
  SELECT
    f.id,
    f.name,
    i.top_genre,
    f.movie_title,
    f.rating,
    ROW_NUMBER() OVER (PARTITION BY f.id ORDER BY f.rating DESC) AS rn
  FROM `main-data-hub.nominee_filmography.core_table`  AS f
  JOIN `main-data-hub.nominee_information.core_table` AS i
    ON f.id = i.id
)
SELECT
  top_genre,
  name,
  movie_title,
  rating
FROM best_per_nominee
WHERE rn = 1
ORDER BY top_genre, rating DESC;


-- 7. Year‑Over‑Year Rating Growth per Nominee

WITH yearly_avg AS (
  SELECT
    f.name,
    CAST(f.year AS INT64) AS year,
    AVG(f.rating) AS avg_rating
  FROM `main-data-hub.nominee_filmography.core_table` AS f
  GROUP BY f.name, year
),
growth AS (
  SELECT
    name,
    year,
    avg_rating,
    LAG(avg_rating) OVER (PARTITION BY name ORDER BY year) AS prev_avg
  FROM yearly_avg
)
SELECT
  name,
  year,
  ROUND((avg_rating - prev_avg) * 100 / NULLIF(prev_avg,0), 2) AS pct_change
FROM growth
WHERE prev_avg IS NOT NULL
ORDER BY name, year;


-- 8. Who are the most “central” collaborators?

WITH credits AS (
  SELECT
    id,
    amg_movie_id,
    id AS nominee_id
  FROM `main-data-hub.nominee_filmography.core_table`
),
pairs AS (
  SELECT 
    a.nominee_id AS n1,
    b.nominee_id AS n2
  FROM credits AS a
  JOIN credits AS b
    ON a.amg_movie_id = b.amg_movie_id
   AND a.id <> b.id
),
distinct_counts AS (
  SELECT 
    n1 AS nominee_id,
    COUNT(DISTINCT n2) AS distinct_collabs
  FROM pairs
  GROUP BY n1
)
SELECT 
  i.name,
  dc.distinct_collabs
FROM distinct_counts AS dc
JOIN `main-data-hub.nominee_information.core_table` AS i
  ON dc.nominee_id = i.id
ORDER BY dc.distinct_collabs DESC
LIMIT 10;


-- 9. Rating Volatility: Who has the most inconsistent film scores?

SELECT
  f.name,
  ROUND(STDDEV_POP(f.rating), 2) AS rating_stddev,
  COUNT(1) AS films_count
FROM `main-data-hub.nominee_filmography.core_table` AS f
GROUP BY f.name
HAVING films_count > 3 
ORDER BY rating_stddev DESC
LIMIT 10;

-- 10. Predictive Signal: Does Debut Age Predict Average Rating?


WITH debut_info AS (
  SELECT
    f.id,
    i.birthday,
    MIN(f.year) AS debut_year
  FROM `main-data-hub.nominee_filmography.core_table` AS f
  JOIN `main-data-hub.nominee_information.core_table` AS i
    ON f.id = i.id
  WHERE i.birthday IS NOT NULL
  GROUP BY f.id, i.birthday
),
avg_rating AS (
  SELECT
    id,
    AVG(rating) AS avg_rating
  FROM `main-data-hub.nominee_filmography.core_table`
  GROUP BY id
),
joined AS (
  SELECT
    d.id,
    DATE_DIFF(DATE(CONCAT(d.debut_year,'-01-01')), DATE(d.birthday), YEAR)
      AS age_at_debut,
    ar.avg_rating
  FROM debut_info AS d
  JOIN avg_rating AS ar
    ON d.id = ar.id
)
SELECT
  ROUND(CORR(age_at_debut, avg_rating),2) AS corr_age_vs_rating,
  COUNT(1) AS sample_size
FROM joined;