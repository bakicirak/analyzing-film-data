# Film Nominee Analytics (BigQuery SQL)

**Question:** What do the careers of ~850 acting-award nominees look like in terms of output, ratings, collaboration networks and longevity?

**Stack:** BigQuery Standard SQL · window functions · self-joins for network analysis · `CORR`, `STDDEV_POP`
**Data:** 847 nominees and 61,696 film credits, 1910–2018 ([`nominee_information.csv`](nominee_information.csv), [`nominee_filmography.csv`](nominee_filmography.csv))

---

## Key findings

| Finding | Evidence |
|---|---|
| **Debut age does not predict quality** | Correlation between age at first film and average rating: **r = −0.01** (n = 832) |
| **Ratings drop slowly over long careers** | Average rating for films 1–10: **4.74** → films 61+: **4.38** |
| **Network hubs are character actors, not only stars** | Most connected: Shelley Winters (220 fellow nominees), Charlton Heston (212), Henry Fonda (206) |
| **Most consistent quality** | Highest average with 10+ rated films: Daniel Day-Lewis (6.48), Carey Mulligan (6.33), Jennifer Lawrence (6.17) |
| **Most volatile careers** | Peggy Wood, Ronee Blakley, Gene Wilder (rating SD ≈ 2.4–2.5) |
| **Output peaked in the 1990s** | 6,137 distinct films in the 1990s vs. 1,882 in 2010–2018 (the last decade is incomplete) |

## Data quality notes

Checking the data before analysing it changed the results:

- **Wrong join key fixed.** `filmography.id` is a running row number, not a person id. Joining on it matched credits to the wrong people. All joins now use `name`.
- **Duplicate people.** Two nominees are stored twice under different spellings (e.g. *Daniel Day Lewis* and *Daniel Day-Lewis*). That is why they appear twice in the rankings. In production this would be fixed with a person-id mapping table.
- **Missing ratings.** 22 % of credits have no rating. Rankings use a minimum number of rated films to avoid small-sample noise.

## Queries

[`nominee_analytics.sql`](nominee_analytics.sql) contains data-quality checks plus 11 analyses: credits by role, top-rated nominees, films per decade, genre mix, debut-age distribution, top film per genre, year-over-year rating change, collaboration network, rating volatility, debut age vs. rating, and rating by career stage.

**How to run:** load the two CSVs into BigQuery as `nominee_information.core_table` and `nominee_filmography.core_table`, then run the queries one by one.
