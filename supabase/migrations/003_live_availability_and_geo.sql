-- Live availability and geographic search for Win Nalkaw.
-- Apply after migrations 001 and 002 in a fresh/staging Supabase project.

create or replace function public.get_available_slots(
  p_business_id bigint,
  p_service_id bigint,
  p_booking_date date,
  p_interval_minutes integer default 15
)
returns table(slot_start time, slot_end time, staff_id bigint)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_service public.services%rowtype;
  v_weekday integer;
  v_open time;
  v_close time;
  v_start time;
  v_end time;
  v_staff record;
  v_has_availability boolean;
  v_found boolean;
  v_step integer := greatest(5, least(coalesce(p_interval_minutes,15),60));
begin
  if p_booking_date < (now() at time zone 'Africa/Tunis')::date then
    return;
  end if;
  select s.* into v_service
    from public.services s join public.businesses b on b.id=s.business_id
   where s.id=p_service_id and s.business_id=p_business_id
     and s.is_active and b.is_active and b.accepts_online_booking;
  if not found then return; end if;

  v_weekday := extract(dow from p_booking_date)::integer;
  select h.opens_at,h.closes_at into v_open,v_close
    from public.business_hours h
   where h.business_id=p_business_id and h.weekday=v_weekday and not h.is_closed;
  if not found then return; end if;

  v_start := v_open;
  while v_start + make_interval(mins => v_service.duration_minutes + v_service.buffer_minutes) <= v_close loop
    v_end := (v_start + make_interval(mins => v_service.duration_minutes + v_service.buffer_minutes))::time;
    if not exists (
      select 1 from public.business_closures c
       where c.business_id=p_business_id
         and (p_booking_date + v_start) < (c.ends_at at time zone 'Africa/Tunis')
         and (p_booking_date + v_end) > (c.starts_at at time zone 'Africa/Tunis')
    ) then
      for v_staff in
        select sp.id from public.staff_profiles sp
         where sp.business_id=p_business_id and sp.is_active
           and (not exists(select 1 from public.service_staff ss where ss.service_id=p_service_id)
                or exists(select 1 from public.service_staff ss where ss.service_id=p_service_id and ss.staff_id=sp.id))
         order by sp.id
      loop
        select exists(select 1 from public.staff_availability sa where sa.staff_id=v_staff.id and sa.weekday=v_weekday)
          into v_has_availability;
        if (not v_has_availability or exists(
             select 1 from public.staff_availability sa where sa.staff_id=v_staff.id and sa.weekday=v_weekday
               and v_start >= sa.starts_at and v_end <= sa.ends_at
           ))
           and not exists(select 1 from public.bookings b where b.staff_id=v_staff.id
             and b.booking_date=p_booking_date and b.status in ('pending','confirmed')
             and v_start < b.end_time and v_end > b.start_time)
           and not exists(select 1 from public.staff_breaks sb where sb.staff_id=v_staff.id
             and (p_booking_date + v_start) < (sb.ends_at at time zone 'Africa/Tunis')
             and (p_booking_date + v_end) > (sb.starts_at at time zone 'Africa/Tunis')) then
          slot_start := v_start;
          slot_end := v_end;
          staff_id := v_staff.id;
          return next;
          exit;
        end if;
      end loop;
    end if;
    v_start := (v_start + make_interval(mins => v_step))::time;
  end loop;
end;
$$;
revoke all on function public.get_available_slots(bigint,bigint,date,integer) from public;
grant execute on function public.get_available_slots(bigint,bigint,date,integer) to anon, authenticated;

-- Search returns only public, active businesses. Distances are calculated only
-- when both the user's coordinates and the business geography are available.
create or replace function public.search_nearby_businesses(
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_radius_km double precision default 10,
  p_category_key text default null,
  p_search_text text default null
)
returns table(
  business_id bigint,
  name_ar text,
  name_fr text,
  category_key text,
  address_ar text,
  address_fr text,
  city text,
  phone text,
  verified boolean,
  distance_km double precision,
  services jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select b.id,b.name_ar,b.name_fr,b.category_key,b.address_ar,b.address_fr,b.city,b.phone,b.verified,
    case when p_latitude is not null and p_longitude is not null and b.location is not null
      then st_distance(b.location, st_setsrid(st_makepoint(p_longitude,p_latitude),4326)::geography)/1000.0
      else null end as distance_km,
    coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name_ar',s.name_ar,'name_fr',s.name_fr,
       'duration_minutes',s.duration_minutes,'price',s.price,'currency',s.currency) order by s.name_ar)
       from public.services s where s.business_id=b.id and s.is_active),'[]'::jsonb) as services
  from public.businesses b
  where b.is_active=true and b.accepts_online_booking=true
    and (p_category_key is null or p_category_key='' or b.category_key=p_category_key)
    and (p_search_text is null or p_search_text='' or
      concat_ws(' ',b.name_ar,b.name_fr,b.category_key,b.address_ar,b.address_fr,b.city) ilike '%'||p_search_text||'%'
      or exists(select 1 from public.services s where s.business_id=b.id and s.is_active
        and concat_ws(' ',s.name_ar,s.name_fr) ilike '%'||p_search_text||'%'))
    and (p_latitude is null or p_longitude is null or
      (b.location is not null and st_dwithin(b.location,st_setsrid(st_makepoint(p_longitude,p_latitude),4326)::geography,
        greatest(1,least(coalesce(p_radius_km,10),200))*1000)))
  order by case when p_latitude is not null and p_longitude is not null and b.location is not null
    then st_distance(b.location,st_setsrid(st_makepoint(p_longitude,p_latitude),4326)::geography) else null end asc nulls last,
    b.verified desc,b.name_ar asc;
$$;
revoke all on function public.search_nearby_businesses(double precision,double precision,double precision,text,text) from public;
grant execute on function public.search_nearby_businesses(double precision,double precision,double precision,text,text) to anon, authenticated;

-- Set or update the business point without exposing arbitrary business IDs.
create or replace function public.set_my_business_location(p_business_id bigint,p_latitude double precision,p_longitude double precision)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_latitude is null or p_longitude is null or p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    raise exception 'Invalid coordinates';
  end if;
  update public.businesses set location=st_setsrid(st_makepoint(p_longitude,p_latitude),4326)::geography
   where id=p_business_id and (owner_id=auth.uid() or public.is_business_member(id) or public.is_admin());
  if not found then raise exception 'Business not found or access denied'; end if;
end; $$;
revoke all on function public.set_my_business_location(bigint,double precision,double precision) from public;
grant execute on function public.set_my_business_location(bigint,double precision,double precision) to authenticated;
