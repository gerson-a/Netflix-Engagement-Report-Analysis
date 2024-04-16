#identify the type of each title using 'kind' from the IMDb data scrape
#identify Netflix originals

  SELECT DISTINCT(h.Title), 
    h.imdb_title as imdb_title, 
    t.kind, 
    CASE
      WHEN t.kind IN ('tv series', 'tv mini series') THEN 'TV'
      ELSE 'Film'
    END AS type, 
    h.release_date, 
    h.eff_release_date, 
    h.avail_globally,
    CASE 
      WHEN h.release_date IS NOT NULL THEN 'Yes' 
      ELSE 'No'
    END AS nflx_original
    FROM netflix-what-we-watched.top_500.hours_viewed AS h
    JOIN netflix-what-we-watched.top_500.title_kinds AS t
      ON h.movieID = t.movieID

#Calculate total views, and rank title performance by total views
  
  WITH types AS (
    SELECT DISTINCT(h.Title), 
      t.kind, 
      CASE
        WHEN t.kind IN ('tv series', 'tv mini series') THEN 'TV'
        ELSE 'Film'
      END AS type, 
      h.hours_viewed, 
      h.imdb_title as imdb_title,
      --calculate days on Netflix in the provided window
      DATE_DIFF('2023-06-30', h.eff_release_date, day) AS days_avail,
      FROM netflix-what-we-watched.top_500.hours_viewed AS h
      JOIN netflix-what-we-watched.top_500.title_kinds AS t
        ON h.movieID = t.movieID
  ),

  all_views AS (
    SELECT t.Title, 
      t.kind, 
      t.type, 
      t.imdb_title, 
      t.days_avail, 
      t.hours_viewed, 
      i.eps_in_season,
      --calculate total runtime only if runtime per episode is provided, otherwise assume runtime is already calculated for entire season
      CASE 
        WHEN (i.runtimes < 99 AND t.type = 'TV')  THEN CAST(ROUND(((t.hours_viewed*60)/(i.runtimes*i.eps_in_season))) AS INT)
        ELSE CAST(ROUND(((t.hours_viewed*60)/(i.runtimes))) AS INT)
      END AS views
      FROM types as t
      JOIN netflix-what-we-watched.top_500.imdb_data_full AS i
        ON t.Title = i.Title
     ORDER BY views DESC
  )
  
  SELECT Title, 
    days_avail, 
    hours_viewed, 
    views,
    --calculate segmented viewing metrics
    CAST(ROUND((views/days_avail)) AS INT) AS daily_views,
    CASE 
      WHEN type = 'TV' THEN  CAST(ROUND((views/eps_in_season)) AS INT) 
      ELSE NULL
    END AS views_per_ep,
    CASE 
      WHEN type = 'TV' THEN CAST(ROUND((views/eps_in_season)/days_avail) AS INT) 
      ELSE NULL
    END AS daily_views_per_ep,
    --calculate watch rate
    ROUND((views/240000000)*100, 2) AS perc_subs_viewed,
    --rank each TV show according to total views
    CASE
      WHEN type = 'TV' THEN  DENSE_RANK() OVER (ORDER BY views DESC) 
      ELSE NULL
    END AS tv_rank,
    CASE
      WHEN type = 'Film' THEN  DENSE_RANK() OVER (ORDER BY views DESC) 
      ELSE NULL
    END AS film_rank,
    DENSE_RANK() OVER (ORDER BY views DESC) AS overall_rank
    FROM all_views
   ORDER BY views DESC
