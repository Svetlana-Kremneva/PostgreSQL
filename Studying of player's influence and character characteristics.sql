/* Project goal: to study the influence of players and character characteristics on the purchase of the in-game currency
 * "Paradise Petals," and to evaluate player activity when making in-game purchases.
 */

 -- PART 1. Exploratory Data Analysis
 --Task 1. Investigating of the share of paying playersв

 -- 1.1. Share of paying users for all data
SELECT COUNT (*) AS total_players,
	SUM (
	CASE WHEN payer = 1 THEN 1 ELSE 0 END) AS paying_players,
	ROUND(100.0 * AVG(payer), 2) AS paying_percentage
FROM fantasy.users

-- 1.2. Share of paying users by character race:
SELECT COUNT (f.id) AS total_players,
	SUM (
	CASE WHEN f.payer = 1 THEN 1 ELSE 0 END) AS paying_players,
	ROUND(100.0 * AVG(f.payer), 2) AS paying_percentage,
	r.race
FROM fantasy.users AS f
JOIN fantasy.race AS r ON f.race_id=r.race_id
GROUP BY race
ORDER BY paying_percentage



-- Task 2. Research into in-game purchases

-- 2.1. Statistical indicators for the AMOUNT field:
SELECT COUNT (transaction_id) AS total_purchases, -- Total number of purchases
	SUM(amount) AS total_amount, -- Total cost of all purchases
	MIN(amount) AS min_amount, -- Minimum purchase price
	MAX(amount) AS max_amount, -- Maximum purchase price
	AVG(amount) AS avg_amount, -- Average purchase price
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount) AS median_amount,-- Median purchase price
	STDDEV(amount) AS stddev_amount -- Standard deviation of purchase price
FROM fantasy.events

-- 2.2: Abnormal zero purchases:
WITH total_purchases AS (
SELECT COUNT(*) AS total_count
FROM fantasy.events 
),
zero_purchases AS (
SELECT COUNT(*) AS zero_count
FROM fantasy.events 
WHERE amount = 0
)
SELECT zero_count AS zero_amount_purchases,
ROUND(100.0 * zero_count / total_count, 2) AS zero_amount_percentage
FROM  zero_purchases, total_purchases

-- 2.3: Popular Epic Items:
WITH filtered_purchases AS (
    SELECT *
    FROM fantasy.events
    WHERE amount > 0
),
total_sales_count AS (
    SELECT COUNT(*) AS total_sales
    FROM filtered_purchases
),
total_buyers_count AS (
    SELECT COUNT(id) AS total_buyers
    FROM filtered_purchases
)
SELECT
    i.game_items,
    COUNT(*) AS item_sales_count,
    ROUND(100.0 * COUNT(*) / (SELECT total_sales FROM total_sales_count), 2) AS item_sales_percentage,
    COUNT(DISTINCT fp.id) AS buyers_count,
    ROUND(100.0 * COUNT(DISTINCT fp.id) / (SELECT total_buyers FROM total_buyers_count), 2) AS buyers_percentage
FROM filtered_purchases fp
LEFT JOIN fantasy.items i ON fp.item_code = i.item_code
GROUP BY i.game_items
ORDER BY buyers_percentage DESC, item_sales_count DESC



-- PART 2. Ad hoc task
-- Task: Dependence of player activity on the character's race:

WITH 
registered_players AS (
	SELECT race_id,
		COUNT(id) AS total_players
	FROM fantasy.users
	GROUP BY race_id
),
paying_players AS (
	SELECT race_id, 
	       COUNT(id) AS paying_players
	FROM fantasy.users
	WHERE payer = 1
	GROUP BY race_id
),
paying_st AS (
	SELECT rp.race_id,
		COALESCE(pp.paying_players, 0) AS paying_players,
		COALESCE(pp.paying_players, 0)::decimal / rp.total_players AS paying_share
	FROM registered_players rp
	LEFT JOIN paying_players pp ON rp.race_id = pp.race_id
),
purchase_act AS (
	SELECT u.race_id,
		COUNT(*) AS total_purchases,
     	SUM(e.amount) AS total_amount,
    	AVG(e.amount) AS avg_amount_per_purchase,
    	COUNT(DISTINCT u.id) AS num_paying_players
    FROM fantasy.events e
    JOIN fantasy.users u ON e.id = u.id
    WHERE u.payer = 1 AND e.amount > 0
    GROUP BY u.race_id
),
activity_per_payer AS (
	SELECT race_id, avg_amount_per_purchase,
		ROUND(total_purchases::decimal / NULLIF(num_paying_players, 0), 2) AS avg_purchases_per_player,
		ROUND(total_amount::decimal / NULLIF(num_paying_players, 0), 2) AS avg_total_amount_per_player
	FROM purchase_act
)
SELECT rp.race_id, rp.total_players, ps.paying_players,
	ROUND(ps.paying_share, 2) AS paying_players_percentage,
	COALESCE(ap.avg_purchases_per_player, 0) AS avg_purchases_per_paying_player,
	COALESCE(ap.avg_amount_per_purchase, 0) AS avg_purchase_amount_per_paying_player,
	COALESCE(ap.avg_total_amount_per_player, 0) AS avg_total_amount_per_paying_player
FROM registered_players rp
LEFT JOIN paying_st ps ON rp.race_id = ps.race_id
LEFT JOIN activity_per_payer ap ON rp.race_id = ap.race_id
ORDER BY rp.race_id
 