	set search_path to bookings

select * from  airports a order by city
select * from aircrafts
select * from flights_v
select * from ticket_flights tf 
select * from boarding_passes
--1   
select    city, count(airport_code) as counter
  from airports a 
  	group by city
  	having count(airport_code)>1
-------------------------------------
--2-


select distinct s."range", s.flight_no, s.airport_name, s.model from  	
  ------Присоединяем рейсы и аэропорты, добавляем столбец Ранг, чтоб без лишнего напряжения
  ------разбить длину полета по группам с номерами	
 			(select "range", 
 			dense_rank () over(order by "range" desc) as rang,   
 			f.flight_no, a.airport_name,a.airport_code, ac,model 
 			
 			from 	 aircrafts ac
 			 	join flights f on f.aircraft_code = ac.aircraft_code 
 			 	join airports a on a.airport_code=f.departure_airport
 	 				
  			) s
  ---ну и отсеиваем по рангу			
  where rang =1	
----------------------------------------
 ---3---
 select * from 

 (select fv.flight_no,fv.scheduled_arrival ,
         fv.actual_arrival , 
         (fv.actual_arrival -fv.scheduled_arrival)::interval as losttime
    from flights_v fv 
  ) t
  where t.losttime>'00:00:00'  ---чтобы убрать нули
  order by t.losttime desc limit 10
-----------------------------------------------  
 ---4---
 
  --------Соединяю таблицы boarding_passes  и tickets, Left Outer Join выполняется 
  --------немного быстрее, чем full.
    explain analyze
   (
  				select * from	select * from tickets t
 					left outer join boarding_passes bp on bp.ticket_no = t.ticket_no 
 				 ) t1
  where t1.boarding_no is null
  
  
---5-----
   
 select *,
 sum(occuped_seats) over (partition by actual_departure, departure_airport 
 						 					order by actual_departure asc 
rows between unbounded preceding and current row)
 						 	---у меня сработало только с этой строкой...
from(
 -------Здесь считаю, сколько мест в каждом типе самолета.
--------Мне нравится использовать CTE, а не подзапрос.
 		with s  as 
  					(select distinct aircraft_code,
  						count	(aircraft_code) over (partition by seats.aircraft_code) as seats
  					from seats)
 ------------------------------
 --------Собираю в одну таблицу все расчеты
  select actual_departure,departure_airport, flight_no, seats,occuped_seats, 
  									(seats-occuped_seats) as free_seats, 
			((seats-occuped_seats)*100/seats)||'%' as Perc_of_free_seats
from (
-----------Здесь считаю, сколько мест занято, то есть на какие места выдан посадочный талон---------
 			select distinct bp.flight_id ,f.departure_airport,
 							date(f.actual_departure) as actual_departure,
							f.flight_no, f.aircraft_code, 
				count(bp.ticket_no) over (partition by  bp.flight_id ) as occuped_seats, 
							s.seats
				from boarding_passes bp
 							join flights f on f.flight_id =bp.flight_id 
 							join s on s.aircraft_code=f.aircraft_code 
							
      ) t
------Из условия я поняла, что считаем только вылетевшие рейсы. То есть те, у которых 
------проставлено время вылета. Вообще, сложно понять условие, если честно.      
 where actual_departure is not null ) newest

--------6--------------
 -----Исхожу из определения: "Перелет - результат полета, когда самолет уже приземлился 
 -----или должен приземлиться с высокой долей вероятности в точке назначения." 
 -----Поэтому беру строки из таблицы flights с известным временем вылета.
 select t.aircraft_code as "Тип самолета",
 		model as "Модель",  
 		t_flights as "Количество перелетов", 
       round(((t_flights*100)::numeric/sum_flights),2) as "% от общего количества перелетов"
from (
			select distinct aircraft_code , ---группирую перелеты по модели самолета,
											---заодно сразу вывожу общее количество полетов
						count(f.flight_id) over (partition by f.aircraft_code) as t_flights,
						count(f.flight_id) over() as sum_flights
			from flights f 
				where f.actual_departure is not null ----считаем, что все взлетевшие самолеты приземлятся 
													 ----с высокой долей вероятности
 ) t
join aircrafts a on a.aircraft_code =t.aircraft_code   ----с названием модели красивее таблица
 group by t.aircraft_code,a.model,t_flights, t.sum_flights 
 			order by "% от общего количества перелетов" desc   ----тоже для красоты
 ----Удивил результат. Но так может быть, потому что много маленьких перелетов. 
 ----С количествм перевезенных людей нет корреляции.
-------7-----------
 			
with cond1 as   ---------таблица со стоимостью перелета
(select distinct fv.flight_no , tf.amount ,tf.fare_conditions,
		fv.arrival_city
	from ticket_flights tf 			
 join flights_v fv  on fv.flight_id = tf.flight_id 
 where fv.actual_departure is not null and 
 		(tf.fare_conditions='Economy' or tf.fare_conditions='Business')
  ) 

  select * from (  ----ничего умнее не придумала, как соединить таблицу с собой же
  				   ---- и просто сравнить два столбца. Но это долго и наверняка не оптимально

select cond1.flight_no , cond1.amount ,cond1.fare_conditions,cond1.arrival_city,
		cond2.flight_no as flight_no2, cond2.amount as amount2, 
		cond2.fare_conditions as fare_conditions2,
		cond2.arrival_city arrival_city2 
from cond1
left join cond1 cond2 on cond1.flight_no=cond2.flight_no		
 
 ) t
 where flight_no=flight_no2 and fare_conditions='Economy'  and fare_conditions2='Business'
 and amount>amount2
------------Вроде как нет. ) Наверное, надо было представление использовать, но я про них
----вспомнила только в следующем задании.
------8-------
 	
create view	Dekart   ---Тут вроде нечего объяснять. Создаем представление,
					-----со списком всевозможных пар, кроме одинаковых.
					------Исключаем дубли.
as 
 select distinct  fv.departure_city, fv2.arrival_city from flights_v fv 
 cross join flights_v fv2  where fv.departure_city !=fv2.arrival_city
 ------берем представление Decart и выкидываем из него все строки, которые есть в списке перелетов.
 ------Взяла представление flights_v, потому что там уже есть названия городов.
 ------Можно было к flights приджойнить названия из Airports, но вроде нет смысла. Или есть?
 select * from Dekart
	except
  select distinct
		fv.departure_city, fv.arrival_city
	from flights_v fv 

drop view Dekart 
-----У меня этот запрос выполнялся 6 минут. Это ужас.
----8------
-------
	

select flight_no as "Номер рейса",
	   model as "Самолет",
	   "range" as "Дальность полета",
	   departure_airport_name as "Аэропорт отправления",
	   arrival_airport_name as "Аэропорт прибытия",
	   distance as "Расстояние",
   case when t."range" <= t.Distance-200 then 'Замена'  --это надо было? 
 ---Что значит сравнить, не поняла. Не могут же назначить на прямой рейс самолет
 ---с недостаточной дальностью полета.
   else 'OK' 
end  as "Допуск"

from (
	
select flight_no, aircraft_code, model,"range",departure_airport_name,arrival_airport_name,
	round(6371*(acos(sin(radians(a1.latitude_A))*sin(radians(a1.latitude_B)) 
	        + cos(radians( a1.latitude_A))*cos(radians( a1.latitude_B))*
	        cos(radians( a1.longtitude_B)-radians( a1.longtitude_A))) )) as Distance        
	        	            
	        from	
	(select distinct   
		fv.flight_no,fv.aircraft_code, a2.model, a2."range", 
		fv.departure_airport,fv.departure_airport_name ,  
		a.longitude as longtitude_A, a.latitude as latitude_A, 
		fv.arrival_airport, fv.arrival_airport_name,
		b.longitude as longtitude_B, b.latitude as latitude_B
		from flights_v fv
	join airports a  on a.airport_code = fv.departure_airport  --присоединяю аэропорты по отправлению
	join airports b on b.airport_code = fv.arrival_airport     --то же самое по прибытию
	join aircrafts a2 on a2.aircraft_code = fv.aircraft_code   --модели для полноты картины
	) a1
	) t
	
		



------------------

  	
  	
  	
