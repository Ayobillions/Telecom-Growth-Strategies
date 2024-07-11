CREATE TABLE "Nexa_Sat".nexa_sat(
	customer_id varchar(50),
	gender varchar(10),
	partner varchar(3),
	dependants varchar(3),
	senior_citizen int,
	call_duration float,
	data_usage float,
	plan_type varchar(20),
	plan_level varchar(20),
	monthly_bill_amount float,
	tenure_months int,
	multiple_lines varchar(3),
	tenure_support varchar(3),
	churn int);

--confirm current schema
select current_schema();

--set path for queries
SET search_path TO "Nexa_Sat";

--view data
SELECT *
FROM nexa_sat;

--Data Cleaning
--checking for duplicates
SELECT customer_id, gender, partner, dependants, senior_citizen, 
	call_duration, data_usage, plan_type, plan_level, monthly_bill_amount, 
	tenure_months, multiple_lines, tenure_support, churn
FROM nexa_sat 
GROUP BY customer_id, gender, partner, dependants, senior_citizen, 
	call_duration, data_usage, plan_type, plan_level, monthly_bill_amount, 
	tenure_months, multiple_lines, tenure_support, churn
HAVING COUNT(*) > 1; -- FILTERS OUT ROWS THAT ARE DUPLICATES

--checking for null values
SELECT * 
FROM nexa_sat
WHERE customer_id is null
OR gender is null
OR partner is null
OR dependants is null 
OR senior_citizen is null
OR call_duration is null
OR data_usage is null
OR plan_type is null 
OR plan_level is null 
OR monthly_bill_amount is null  
OR tenure_months is null
OR multiple_lines is null 	
OR tenure_support is null
OR churn is null;

--EDA
--total users who have not churned -4272
SELECT COUNT(customer_id) as current_users
FROM nexa_sat
WHERE churn = 0

--total number of users by plan level
SELECT 	plan_level, COUNT(customer_id) as totla_users
FROM nexa_sat
GROUP BY 1;

--total number of users by plan level who have churned 
SELECT 	plan_level, COUNT(customer_id) as totla_users
FROM nexa_sat
WHERE churn = 0
GROUP BY 1;

--total revenue
select round(sum(monthly_bill_amount::numeric),2) as revenue
FROM nexa_sat

--revenue by plan_level
select plan_level, round(sum(monthly_bill_amount::numeric),2) AS revenue
FROM  nexa_sat
GROUP BY 1
ORDER BY 2;


--churn count by plan type and plan level
SELECT plan_level, 
	plan_type, COUNT(*) AS total_customers, 
	SUM(churn) AS churn_count 
FROM nexa_sat
GROUP BY 1,2
ORDER BY 1


--avg tenure by plan level
SELECT plan_level, ROUND(AVG(tenure_months),2) AS avg_tenure
FROM nexa_sat
GROUP BY 1;


--MARKETING SEGMENTS
CREATE TABLE existing_user AS
SELECT * FROM nexa_sat
WHERE churn =0;

--view new table
select * from existing_user;


--calculate Average Revenue per user ARPU fro existing user
SELECT ROUND(AVG(monthly_bill_amount::int), 2) AS ARPU
FROM existing_user

--calculate CLV and add column
ALTER TABLE existing_user
ADD COLUMN clv float

UPDATE existing_user
SET clv = monthly_bill_amount * tenure_months;


--view new clv column
SELECT customer_id, clv
FROM existing_user;

--clv score
--monthly_bill = 40%, tenure = 30%, call_duration = 10%, data_usage = 10%, premium = 10%
ALTER TABLE existing_user
ADD COLUMN clv_score NUMERIC(10, 2);

UPDATE existing_user
SET clv_score =  
	(0.4* monthly_bill_amount) + 
	(0.3 * tenure_months) +
	(0.1 *  call_duration) + 
	(0.1 * data_usage) + 
	(0.1 * CASE WHEN plan_level = 'Premium' THEN 1 ELSE 0 END);


--view new clv_score column
SELECT customer_id, clv_score
FROM existing_user;


--group users into segments based on clv_ scores
ALTER TABLE existing_user
ADD COLUMN clv_segments VARCHAR;

UPDATE existing_user
SET clv_segments = 
			CASE WHEN clv_score > (SELECT percentile_cont(0.85)
								   	WITHIN GROUP (ORDER BY clv_score)
									FROM existing_user) THEN 'High Value'
				WHEN clv_score >= (SELECT percentile_cont(0.50)
									WITHIN GROUP (ORDER BY clv_score)
									FROM existing_user) THEN 'Moderate Value'
				WHEN clv_score >= (SELECT percentile_cont(0.25)
									WITHIN GROUP (ORDER BY clv_score)
									FROM existing_user) THEN 'Low Value'
				ELSE 'Churn Risk'
				END

--view segment
SELECT customer_id, clv, clv_score, clv_segments 
FROM existing_user;


--ANALYZING THE SEGMENTS
--average bill and tenure per segment
SELECT clv_segments, ROUND(AVG(monthly_bill_amount::INT),2) AS avg_monthly_charges, 
	ROUND(AVG(tenure_months::INT),2) AS avg_tenure
FROM existing_user
GROUP BY 1;


	
--tech support and multiple lines count
SELECT clv_segments,
		ROUND(AVG(CASE WHEN tenure_support = 'Yes' THEN 1 ELSE 0 END),2) AS tech_support_percent,
		ROUND(AVG(CASE WHEN multiple_lines= 'Yes' THEN 1 ELSE 0 END),2) AS multiple_lines_percent 
FROM existing_user
GROUP BY 1;


--revenue per segment
SELECT clv_segments, COUNT(customer_id), CAST(SUM(monthly_bill_amount * tenure_months) AS NUMERIC(10,2)) AS total_revenue
FROM existing_user
GROUP BY 1;


--CROSS-SELLING AND UP-SELLING
--cross selling : tech_support to senior citizens
SELECT customer_id
FROM existing_user
WHERE senior_citizen = 1 --senior citizen
AND dependants = 'No' --no children or tech savy helpers
AND tenure_support = 'No' --do not already have this service
AND (clv_segments = 'Churn Risk' OR  clv_segments = 'Low Value');
			

--cross selling : multiple lines for partners and dependants
SELECT customer_id
FROM existing_user
WHERE multiple_lines = 'No'
AND (dependants = 'Yes' OR partner = 'Yes')
AND plan_level = 'Basic';


--up-selling: premium discount for basIC users with churn risk
SELECT customer_id
FROM existing_user
WHERE clv_segments = 'Churn Risk'
AND plan_level = 'Basic';

--up-selling: basic to premium for longer lck in period and higher ARPU
SELECT plan_level, ROUND(AVG(monthly_bill_amount::INT),2) AS avg_bill, ROUND(AVG(tenure_months::INT),2) AS avg_tenure
FROM existing_user
WHERE clv_segments = 'High Value'
OR clv_segments = 'Moderate Value'
GROUP BY  1;


--select customers 
SELECT customer_id, monthly_bill_amount
FROM existing_user
WHERE plan_level = 'Basic'
AND (clv_segments = 'Hihg Value' OR clv_segments = 'Moderate Value')
AND monthly_bill_amount >150


--CREATE STORED PROCEDURES
 --senior citizen who will be offered support
CREATE FUNCTION tech_suppot_senior_citizen()
RETURNS TABLE (customer_id VARCHAR(50))
AS $$
BEGIN
	RETURN QUERY
	SELECT eu.customer_id
	FROM existing_user eu
	WHERE eu.senior_citizen = 1 --senior citizen
	AND eu.dependants = 'No' --no children or tech savy helper
	AND eu.tenure_support = 'No' --do not already have this service
	AND (eu.clv_segments = 'Churn Risk' OR eu.clv_segments = 'Low Value');
END;
$$ LANGUAGE plpgsql;


--at risk customers who will be offered premium discount
CREATE FUNCTION churn_risk_discount()
RETURNS TABLE (customer_id VARCHAR(50))
AS $$
BEGIN
	RETURN QUERY
	SELECT eu.customer_id 
	FROM existing_user eu
	WHERE eu.clv_segments = 'Churn Risk'
	AND eu.plan_level = 'Basic';
END;
$$ LANGUAGE plpgsql


--high usage customers who will be offered premium upgrade
CREATE FUNCTION high_usage_basic()
RETURNS TABLE (customer_id VARCHAR(50))
AS $$
BEGIN 
	RETURN QUERY
	SELECT eu.customer_id
	FROM existing_user eu
	WHERE eu.plan_level = 'Basic'
	AND (eu.clv_segments = 'Hihg Value' OR eu.clv_segments = 'Moderate Value')
	AND eu.monthly_bill_amount >150;
END;
$$ LANGUAGE plpgsql


--USE PROCEDURES
--churn risk discount
SELECT * 
FROM churn_risk_discount()


--high usage basic
SELECT * 
FROM high_usage_basic()


SELECT * 
FROM tech_suppot_senior_citizen()










	
	
























