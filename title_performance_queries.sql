#Calculate total views, and rank title performance by total views

--identify TV shows
WITH tv_shows AS (
  SELECT DISTINCT(h.Title), 
    t.kind, 
    'TV' as type, 
    h.hours_viewed, 
    h.imdb_title as imdb_title,
    --calculate days on Netflix in the provided window
    DATE_DIFF('2023-06-30', h.eff_release_date, day) AS days_avail,
    FROM netflix-what-we-watched.top_500.hours_viewed AS h
    JOIN netflix-what-we-watched.top_500.title_kinds AS t
      ON h.movieID = t.movieID
   WHERE t.kind IN ('tv series', 'tv mini series') 
),

--calculate views for tv shows
tv_views AS (
  SELECT tv.Title, 
    tv.kind, 
    tv.type, 
    tv.imdb_title, 
    tv.days_avail, 
    tv.hours_viewed, 
    i.eps_in_season,
    --calculate total runtime only if runtime per episode is provided, otherwise assume runtime is already calculated for entire season
    CASE 
      WHEN runtimes < 99 THEN CAST(ROUND(((tv.hours_viewed*60)/(i.runtimes*i.eps_in_season))) AS INT)
      ELSE CAST(ROUND(((tv.hours_viewed*60)/(i.runtimes))) AS INT)
    END AS views
    FROM tv_shows AS tv
    JOIN netflix-what-we-watched.top_500.imdb_data_full AS i
      ON tv.Title = i.Title
   ORDER BY views DESC
),

--identify films
films AS (
  SELECT DISTINCT(h.Title), 
    t.kind, 
    'Film' as type, 
    h.hours_viewed, 
    h.imdb_title as imdb_title,
    --calculate days on Netflix in the provided window
    DATE_DIFF('2023-06-30', h.eff_release_date, day) AS days_avail,
    FROM netflix-what-we-watched.top_500.hours_viewed AS h
    JOIN netflix-what-we-watched.top_500.title_kinds AS t
      ON h.movieID = t.movieID
   WHERE t.kind NOT IN ('tv series', 'tv mini series') 
),

--calculate views for films
film_views AS (
  SELECT f.Title, 
    f.kind, 
    f.type, 
    f.imdb_title, 
    f.days_avail, 
    f.hours_viewed,
    --calculate views and cast as integer
    CAST(ROUND(((f.hours_viewed*60)/i.runtimes)) AS INT) AS views
    FROM films AS f
    JOIN netflix-what-we-watched.top_500.imdb_data_full AS i
      ON f.Title = i.Title
   ORDER BY views DESC
),

--combine tv and film views into one table
all_views AS (
  SELECT Title, 
    kind, 
    type, 
    imdb_title, 
    days_avail, 
    hours_viewed, 
    views,
    --calculate segmented viewing metrics
    CAST(ROUND((views/days_avail)) AS INT) AS daily_views,
    CAST(ROUND((views/eps_in_season)) AS INT) AS views_per_ep,
    CAST(ROUND((views/eps_in_season)/days_avail) AS INT) AS daily_views_per_ep,
    --calculate watch rate
    ROUND((views/240000000)*100, 2) AS perc_subs_viewed,
    --rank each TV show according to total views
    DENSE_RANK() OVER (ORDER BY views DESC) AS tv_rank,
    NULL as film_rank
  FROM tv_views

UNION ALL

SELECT Title, 
  kind, 
  type, 
  imdb_title, 
  days_avail, 
  hours_viewed, 
  views,
  --calculate segmented viewing metrics
  CAST(ROUND((views/days_avail)) AS INT) AS daily_views,
  NULL AS views_per_ep,
  NULL AS daily_views_per_ep,
  --calculate watch rate
  ROUND((views/240000000)*100, 2) AS perc_subs_viewed,
  NULL AS tv_rank,
  --rank each film according to total views
  DENSE_RANK() OVER (ORDER BY views DESC) AS film_rank
  FROM film_views
)

SELECT Title, 
  days_avail, 
  hours_viewed, 
  views, 
  daily_views, 
  views_per_ep, 
  daily_views_per_ep, 
  perc_subs_viewed, 
  tv_rank, 
  film_rank,
  --rank all titles according to total views
  DENSE_RANK() OVER (ORDER BY views DESC) AS overall_rank
  FROM all_views
 ORDER BY views DESC
