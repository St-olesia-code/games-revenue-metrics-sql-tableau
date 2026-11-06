
/* CTE 1: monthly_revenue */

with monthly_revenue as (
    select
        date_trunc('month', payment_date)::date as payment_month,
        user_id,
        sum(revenue_amount_usd) as total_revenue
    from project.games_payments
    group by payment_month, user_id
),

/* CTE 2: payment_history */

payment_history as (
    select
        user_id,
        payment_month,
        total_revenue,
        (payment_month - interval '1 month')::date as previous_calendar_month,
        (payment_month + interval '1 month')::date as next_calendar_month,
        lag(payment_month)  over (partition by user_id order by payment_month) as previous_paid_month,
        lag(total_revenue)  over (partition by user_id order by payment_month) as previous_paid_month_revenue,
        lead(payment_month) over (partition by user_id order by payment_month) as next_paid_month,
        max(payment_month)  over () as last_data_month
    from monthly_revenue
),

/* CTE 3: user_month_metrics */

user_month_metrics as (
    select
        user_id,
        payment_month,
        total_revenue,

        case when previous_paid_month is null then 1 else 0 end as new_paid_users,
        case when previous_paid_month is null then total_revenue else 0 end as new_mrr,

        case when next_calendar_month <= last_data_month
              and (next_paid_month is null or next_paid_month <> next_calendar_month)
             	then 1 else 0 end as churned_users,
        case when next_calendar_month <= last_data_month
              and (next_paid_month is null or next_paid_month <> next_calendar_month)
             	then total_revenue else 0 end as churned_revenue,

        case when previous_paid_month = previous_calendar_month
              and total_revenue > previous_paid_month_revenue
            	 then total_revenue - previous_paid_month_revenue else 0 end as expansion_mrr,
        case when previous_paid_month = previous_calendar_month
              and total_revenue < previous_paid_month_revenue
             	then total_revenue - previous_paid_month_revenue else 0 end as contraction_mrr,

        case when previous_paid_month is not null
              and previous_paid_month <> previous_calendar_month
             	then total_revenue else 0 end as returned_mrr
    from payment_history
),

/* CTE 4: users */

users as (
    -- один рядок на user_id, щоб JOIN не множив рядки
    select distinct on (user_id)
        user_id,
        game_name,
        language,
        has_older_device_model,
        age
    from project.games_paid_users
    order by user_id, game_name
)

/* фінальний селект */

select
    m.payment_month,
    m.user_id,
    m.total_revenue,
    m.new_paid_users,
    m.new_mrr,
    m.churned_users,
    m.churned_revenue,
    m.expansion_mrr,
    m.contraction_mrr,
    m.returned_mrr,
    coalesce(u.language, 'unknown') as language,
    u.age,
    u.has_older_device_model,
    coalesce(u.game_name, 'unknown') as game_name
from user_month_metrics m
left join users u
    on u.user_id = m.user_id
order by m.payment_month, m.user_id;