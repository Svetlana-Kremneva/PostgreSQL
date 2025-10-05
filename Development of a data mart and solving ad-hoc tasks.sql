/*Project goal: Development of a data mart and solving ad-hoc tasks
 */

-- PART 1. Development of a data mart

-- To add a new table to the database, you first need to write:
-- "CREATE TABLE product_user_features AS"   and then perform the following steps:
-- 1) Filtering orders by the parameters "Delivered," "Cancelled," and "Top 3 regions"
WITH filtered_orders AS (
    SELECT *
    FROM ds_ecom.orders
    WHERE order_status IN ('Доставлено', 'Отменено')
),
top_regions AS (
    SELECT u.region
    FROM filtered_orders AS fo
    JOIN ds_ecom.users AS u ON fo.buyer_id = u.buyer_id
    GROUP BY u.region
    ORDER BY COUNT(*) DESC
    LIMIT 3
),
-- Selection of customers and orders based on criteria, including conditions related to payment characteristics
orders_with_users AS (
    SELECT fo.order_id, u.user_id, u.region, fo.buyer_id, fo.order_status, fo.order_purchase_ts
    FROM filtered_orders AS fo
    JOIN ds_ecom.users AS u ON fo.buyer_id = u.buyer_id
    WHERE u.region IN (SELECT region FROM top_regions)
),
payment_features AS (
    SELECT op.order_id,
        MIN(CASE WHEN payment_sequential = 1 THEN payment_type END) AS first_payment_type,
        MAX(CASE WHEN payment_installments > 1 THEN 1 ELSE 0 END) AS is_installment,
        MAX(CASE WHEN payment_type = 'промокод' THEN 1 ELSE 0 END) AS is_promo
    FROM ds_ecom.order_payments AS op
    GROUP BY op.order_id
),
-- Information about order costs
order_costs AS (
    SELECT oi.order_id,
        SUM(oi.price + oi.delivery_cost) AS total_cost
    FROM ds_ecom.order_items AS oi
    JOIN filtered_orders AS fo ON oi.order_id = fo.order_id
    WHERE fo.order_status = 'Доставлено'
    GROUP BY oi.order_id
),
-- Information about the rating and its adjustment
order_reviews_cleaned AS (
    SELECT order_id,
        CASE 
            WHEN review_score BETWEEN 10 AND 50 THEN review_score / 10
            ELSE review_score
        END AS normalized_score
    FROM ds_ecom.order_reviews
),
-- Data aggregation by client-region
main_data AS (
    SELECT owu.user_id, owu.region, owu.order_id, owu.order_status, owu.order_purchase_ts,
    	pf.first_payment_type, pf.is_installment, pf.is_promo,
    	oc.total_cost, orc.normalized_score
    FROM orders_with_users AS owu
    LEFT JOIN payment_features AS pf ON owu.order_id = pf.order_id
    LEFT JOIN order_costs AS oc ON owu.order_id = oc.order_id
    LEFT JOIN order_reviews_cleaned AS orc ON owu.order_id = orc.order_id
),
--Final data aggregation and final calculation of metrics
aggregated_data AS (
    SELECT user_id, region,
        MIN(order_purchase_ts) AS first_order_ts,
        MAX(order_purchase_ts) AS last_order_ts,
        MAX(order_purchase_ts) - MIN(order_purchase_ts) AS lifetime,
        COUNT(*) AS total_orders,
        COUNT(normalized_score) AS num_orders_with_rating,
        ROUND(AVG(normalized_score), 2) AS avg_order_rating,
        COUNT(CASE WHEN order_status = 'Отменено' THEN 1 END) AS num_canceled_orders,
        ROUND(COUNT(CASE WHEN order_status = 'Отменено' THEN 1 END)::numeric / COUNT(*), 4) AS canceled_orders_ratio,
        SUM(total_cost) AS total_order_costs,
        ROUND(AVG(total_cost), 2) AS avg_order_cost,
        COUNT(CASE WHEN is_installment = 1 THEN 1 END) AS num_installment_orders,
        COUNT(CASE WHEN is_promo = 1 THEN 1 END) AS num_orders_with_promo,
        MAX(CASE WHEN first_payment_type = 'денежный перевод' THEN 1 ELSE 0 END) AS used_money_transfer,
        MAX(is_installment) AS used_installments,
        MAX(CASE WHEN order_status = 'Отменено' THEN 1 ELSE 0 END) AS used_cancel
    FROM main_data
    GROUP BY user_id, region
)
SELECT *
FROM aggregated_data


/* PART 2. Ad-hoc tasks
*/

/* Task 1. User Segmentation 
 * Divide users into groups based on the number of orders they have placed.
 * Calculate for each group the total number of users, the average number of orders, and the average order cost.

 * Define the following segments:
 * 1 order — segment "1 order"
 * from 2 to 5 orders — segment "2-5 orders"
 * from 6 to 10 orders — segment "6-10 orders"
 * 11 or more orders — segment "11 or more orders"
*/

 SELECT
    CASE
        WHEN total_orders = 1 THEN 'сегмент 1 заказ'
        WHEN total_orders BETWEEN 2 AND 5 THEN 'сегмент 2-5 заказов'
        WHEN total_orders BETWEEN 6 AND 10 THEN 'сегмент 6-10 заказов'
        WHEN total_orders >= 11 THEN 'сегмент 11 и более заказов'
    END AS segment,
    COUNT (user_id) AS users_count,
    ROUND(AVG(total_orders),2) AS avg_orders_per_user,
    ROUND(SUM(total_order_costs) / NULLIF(COUNT(total_orders), 0), 2) AS avg_order_cost_per_segment
FROM ds_ecom.product_user_features
GROUP BY segment 
ORDER BY users_count DESC

/* Results:
 * 
 * The segmentation of the customer base according to purchase frequency shows that during the analyzed 
 * period (2022-09-13 15:24:19.000 - 2024-10-17 17:30:18.000), the vast majority of customers made only 1 order,
 * about 2 thousand customers made between 2 and 5 orders (on average, these customers made 2 orders).
 * This order frequency on the platform may indicate a low level of customer loyalty.
 * The average check (order value) for customers who made between 1 and 5 orders on the site is approximately 4850 units.
 * During the period from 2023-06-18 22:56:48.000 to 2023-06-18 22:56:48.000, there was one customer who made 15 orders, 
 * and 5 customers who made between 6 and 10 orders.
 * The average check for these customers is higher than for those who made between 1 and 5 orders, averaging 19,000 units.
 * 
 For determining the time frame, the following script was used:
   "SELECT MIN(first_order_ts), MAX(last_order_ts)
    FROM public.product_user_features"
*/



/* Task 2. Users ranking 
 * Sort users who have made 3 or more orders by descending average purchase value.  
 * Display the top 15 users with the highest average purchase value within this group.
*/

WITH user_info AS (
    SELECT user_id, total_orders, avg_order_cost
    FROM ds_ecom.product_user_features
)
SELECT user_id, total_orders, avg_order_cost
FROM user_info
WHERE total_orders >= 3
ORDER BY avg_order_cost DESC
LIMIT 15

/* Results:
 * 
 * In the specified sample of 15 clients, the majority (about 86.6%) are clients who made 3 orders during the analyzed period.
 * One client made 4 orders, and one client made 5 orders in the same period.
 * The maximum average purchase value is 14,716.67 units, which is among the top 4 clients with an average check above 10,000 units.
 * The decrease in average purchase value from client to client is approximately 500-700 units.
 * The total number of clients who made more than 3 orders is 155 (see the script below), out of a total client base of 62,442.
 *  Based on the trend of decreasing average purchase value and the small share of such clients in the total volume, it can be 
 * said that the profit from these clients is insignificant for the platform.
 * 
 * "SELECT COUNT(user_id)
    FROM ds_ecom.product_user_features
    WHERE total_orders >= 3"
*/



/* Task 3. Regional Statistics. 
 * For each region, calculate:
 * - the total number of customers and orders;
 * - the average cost of one order;
 * - the proportion of orders purchased with installment payments;
 * - the proportion of orders purchased using promo codes;
 * - the proportion of users who canceled at least one order.
*/

WITH region_stats AS (
    SELECT
        region,
        COUNT(DISTINCT user_id) AS total_clients,
        SUM(total_orders) AS total_orders,
        SUM(total_order_costs) AS total_order_costs,
        SUM(num_installment_orders) AS total_installment_orders,
        SUM(num_orders_with_promo) AS total_promo_orders,
        COUNT(CASE WHEN used_cancel = 1 THEN 1 END) AS clients_with_cancel
    FROM ds_ecom.product_user_features
    GROUP BY region
)
SELECT
    region,
    total_clients,
    total_orders,
    ROUND(total_order_costs::numeric / NULLIF(total_orders,0), 2) AS avg_order_cost,
    ROUND(total_installment_orders::numeric / NULLIF(total_orders,0), 3) AS installment_orders_ratio,
    ROUND(total_promo_orders::numeric / NULLIF(total_orders,0), 3) AS promo_orders_ratio,
    ROUND(clients_with_cancel::numeric / NULLIF(total_clients,0), 3) AS clients_with_cancel_ratio
FROM region_stats
ORDER BY total_orders DESC

/* Results:
 * 
 * The largest number of clients within the "Top 3 regions" placing orders on the platform reside in Moscow (about 63.1%).
 * This group of clients uses installment plans and promo codes less frequently (compared to the other two regions), however, this region has the
 * lowest average order value and the highest order cancellation rate.
 * The number of clients from Saint Petersburg and Novosibirsk region is almost equal.
 * Second place is held by residents of Saint Petersburg, more than 50% of whom purchase goods via installment plans (the highest rate among the analyzed sample).
 * These clients have the highest average order value but also the highest usage of promo codes (which may indicate that the average
 * order value is reduced by the promo code amount and thus may not actually be as high).
 * Clients from the Novosibirsk region also have a high average order value compared to clients from Moscow,
 * but like Saint Petersburg clients, they show a high rate of purchasing goods via installment plans (about 54.1%).
 * The order cancellation rate in this region is the lowest among the three analyzed.
*/



/* Task 4. User activity by the month of their first order in 2023
 * Group users based on the month in 2023 when they made their first order.
 * For each group, calculate:
 * - the total number of clients, the number of orders, and the average cost per order;
 * - the average order rating;
 * - the proportion of users using money transfers as a payment method;
 * - the average duration of user activity.
*/

WITH users_2023_first_order AS (
    SELECT
        user_id,
        DATE_TRUNC('month', first_order_ts) AS first_order_month,
        total_orders,
        avg_order_cost,
        avg_order_rating,
        used_money_transfer,
        lifetime, total_order_costs
    FROM ds_ecom.product_user_features
    WHERE first_order_ts >= '2023-01-01' AND first_order_ts < '2024-01-01'
)
SELECT 
    TO_CHAR(first_order_month, 'YYYY-MM') AS month,
    COUNT(DISTINCT user_id) AS total_clients,
    SUM(total_orders) AS total_orders,
    ROUND(SUM(total_order_costs) / NULLIF(COUNT(total_orders), 0), 2) AS avg_order_cost,
    ROUND(AVG(avg_order_rating), 2) AS avg_order_rating,
    ROUND(AVG(CASE WHEN used_money_transfer = 1 THEN 1 ELSE 0 END), 3) AS share_using_money_transfer,
    ROUND(AVG(EXTRACT(epoch FROM lifetime) / 86400), 2) AS avg_lifetime_days
FROM users_2023_first_order
GROUP BY first_order_month
ORDER BY first_order_month

/* Results:
 * 
 * An increase in the customer base can be observed during pre-holiday and holiday months of the year.
 * The highest peak occurs in November, which may be related to "Black Friday" (if such a promotion is held on this platform) 
 * and consumers’ pre-New Year shopping. This is also reflected in the "Average user activity duration" metric — the lowest 
 * values throughout the year are in November and December.
 * On average, about 20% of platform users use money transfers as a payment method.
 * The average order rating remains stable, ranging from 4.15 to 4.25.
 * When analyzing the average order cost from January to August, a peak is noticeable in April, which may be linked to 
 * customers’ pre-holiday shopping in May.
 * From September to December, there is a steady increase in the average order cost compared to the January–August period.
 * This steady increase is connected to the growth of the customer base. 
 */

 
 
