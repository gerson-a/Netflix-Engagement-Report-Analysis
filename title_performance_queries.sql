#identify the type of each title using 'kind' from the IMDb data scrape
#identify Netflix originals

	  SELECT DISTINCT(h.Title), 
	    h.imdb_title as imdb_title, 
	    t.kind, 
	    --identify the type of each title using 'kind' from the IMDb data scrape
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
	      --identify the type of each title using 'kind' from the IMDb data scrape
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
	    --rank each film according to total views
	    CASE
	      WHEN type = 'Film' THEN  DENSE_RANK() OVER (ORDER BY views DESC) 
	      ELSE NULL
	    END AS film_rank,
	    --rank all titles according to total views
	    DENSE_RANK() OVER (ORDER BY views DESC) AS overall_rank
	    FROM all_views
	   ORDER BY views DESC

#Identify top genre for each title
#Exclude 'Drama' and include 'Dramedy' if top 2 genres are 'Drama' & 'Comedy'

	WITH numbered_genres AS (
	    SELECT Title, 
	    	index,
	       	CASE 
	            -- Combine "Drama" and "Comedy" into "Dramedy"
	            WHEN 'Drama' IN (SELECT TRIM(individual_genre) FROM UNNEST(SPLIT(genres, ',')) AS individual_genre)
	                 AND 'Comedy' IN (SELECT TRIM(individual_genre) FROM UNNEST(SPLIT(genres, ',')) AS individual_genre) THEN 'Dramedy'
	            -- Remove "Drama" if it's accompanied by another genre that isn't "Comedy"
	            WHEN 'Drama' IN (SELECT TRIM(individual_genre) FROM UNNEST(SPLIT(genres, ',')) AS individual_genre)
	                 AND NOT 'Comedy' IN (SELECT TRIM(individual_genre) FROM UNNEST(SPLIT(genres, ',')) AS individual_genre) THEN REPLACE(genres, 'Drama,', '')
	            ELSE genres
	       	END AS modified_genres
	    FROM netflix-what-we-watched.top_500.imdb_data_full
	)
	
	SELECT index, 
		Title, 
	   	TRIM(individual_genre) AS genre,
	   	ROW_NUMBER() OVER (PARTITION BY Title ORDER BY index) AS genre_row_number
	  FROM numbered_genres,
	  	UNNEST(SPLIT(modified_genres, ',')) AS individual_genre
	QUALIFY ROW_NUMBER() OVER (PARTITION BY Title ORDER BY index) <= 1
	ORDER BY 1 ASC, 4 ASC

#Identify countries/regions of top 2 producers for each title
	
	WITH numbered_country_codes AS (
	    SELECT Title, 
	    	index,
	       	--remove spaces
	      	TRIM(individual_country) AS country_code,
	       	--count each country in each title
	       	ROW_NUMBER() OVER (PARTITION BY Title) AS country_row_number
	      FROM netflix-what-we-watched.top_500.imdb_data_full AS i,
	      	--retrieve each country associated with a title
	      	UNNEST(SPLIT(country_codes, ',')) AS individual_country
	)
	
	SELECT index, 
		Title, 
		Full_Country_Name AS country, 
		Region
	  FROM numbered_country_codes
	  JOIN netflix-what-we-watched.top_500.region_lookup
	    ON UPPER(country_code) = Country_ISO
	 WHERE country_row_number in (1, 2)
	 ORDER BY index ASC, country_row_number ASC

#Identify top 2 languages spoken in each title

	WITH numbered_language_codes AS (
	    SELECT index, 
	    	Title,
	       --remove spaces
	       TRIM(individual_language) AS language_code,
	       ROW_NUMBER() OVER (PARTITION BY Title) AS language_row_number
	      FROM netflix-what-we-watched.top_500.imdb_data_full,
	        -- retrieve each language associated with a title
	        UNNEST(SPLIT(language_codes, ',')) AS individual_language
	    ORDER BY index ASC
	)
	
	--join language_lookup to get full language names
	SELECT index, 
		Title, 
		Ref_Name AS language
	  FROM numbered_language_codes
	  JOIN netflix-what-we-watched.top_500.language_lookup
	    ON CASE
	            WHEN LENGTH(language_code) = 2 THEN language_code = Part_1
	            WHEN LENGTH(language_code) = 3 THEN language_code = ID
	   END
	 WHERE language_row_number IN (1, 2)
	 ORDER BY index ASC, language_row_number ASC
