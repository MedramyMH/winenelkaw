-- Production workflow helpers for Win Nalkaw. Apply after 001_initial_schema.sql.
-- Uses SECURITY DEFINER only for narrow, identity-checked operations.

create or replace function public.register_provider_role()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  insert into public.user_roles(user_id, role) values (auth.uid(), 'provider') on conflict do nothing;
end;
$$;
revoke all on function public.register_provider_role() from public;
grant execute on function public.register_provider_role() to authenticated;

-- Atomically validates and creates an appointment. The staff row is locked so
-- concurrent requests for the same professional cannot both pass the overlap check.
create or replace function public.create_booking(
  p_business_id bigint,
  p_service_id bigint,
  p_booking_date date,
  p_start_time time,
  p_customer_name text,
  p_customer_phone text,
  p_staff_id bigint default null,
  p_customer_note text default null
)
returns table(id bigint, booking_reference text, status public.booking_status, end_time time)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_service public.services%rowtype;
  v_staff_id bigint;
  v_staff_found boolean := false;
  v_end time;
  v_weekday integer;
  v_open time;
  v_close time;
  v_booking_id bigint;
  v_ref text;
  v_status public.booking_status;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if length(trim(coalesce(p_customer_name,''))) < 2 then raise exception 'A valid customer name is required'; end if;
  if length(regexp_replace(coalesce(p_customer_phone,''), '[^0-9]', '', 'g')) < 8 then raise exception 'A valid phone number is required'; end if;
  if p_booking_date < (now() at time zone 'Africa/Tunis')::date then raise exception 'Booking date must be today or later'; end if;

  select s.* into v_service from public.services s
   join public.businesses b on b.id=s.business_id
   where s.id=p_service_id and s.business_id=p_business_id and s.is_active
     and b.is_active and b.accepts_online_booking;
  if not found then raise exception 'Service or business is not available for online booking'; end if;
  v_end := (p_start_time + make_interval(mins => v_service.duration_minutes + v_service.buffer_minutes))::time;
  if v_end <= p_start_time then raise exception 'Appointments cannot cross midnight'; end if;
  v_weekday := extract(dow from p_booking_date)::integer;
  select h.opens_at,h.closes_at into v_open,v_close from public.business_hours h
   where h.business_id=p_business_id and h.weekday=v_weekday and not h.is_closed;
  if not found or p_start_time < v_open or v_end > v_close then raise exception 'Outside business opening hours'; end if;
  if exists(select 1 from public.business_closures c where c.business_id=p_business_id
      and (p_booking_date + p_start_time) < c.ends_at at time zone 'Africa/Tunis'
      and (p_booking_date + v_end) > c.starts_at at time zone 'Africa/Tunis') then
    raise exception 'Business is closed at this time';
  end if;

  if p_staff_id is not null then
    select sp.id into v_staff_id from public.staff_profiles sp
     where sp.id=p_staff_id and sp.business_id=p_business_id and sp.is_active for update;
    v_staff_found := found;
  else
    for v_staff_id in select sp.id from public.staff_profiles sp
      where sp.business_id=p_business_id and sp.is_active order by sp.id
    loop
      perform 1 from public.staff_profiles sp where sp.id=v_staff_id for update;
      if not exists(select 1 from public.bookings b where b.staff_id=v_staff_id
        and b.booking_date=p_booking_date and b.status in ('pending','confirmed')
        and p_start_time < b.end_time and v_end > b.start_time) then
        v_staff_found := true; exit;
      end if;
    end loop;
  end if;
  if not v_staff_found then raise exception 'No professional is available'; end if;

  if exists(select 1 from public.bookings b where b.staff_id=v_staff_id
    and b.booking_date=p_booking_date and b.status in ('pending','confirmed')
    and p_start_time < b.end_time and v_end > b.start_time) then
    raise exception 'This time slot has just been booked. Choose another slot.';
  end if;
  if exists(select 1 from public.staff_breaks sb where sb.staff_id=v_staff_id
    and (p_booking_date + p_start_time) < (sb.ends_at at time zone 'Africa/Tunis')::timestamp
    and (p_booking_date + v_end) > (sb.starts_at at time zone 'Africa/Tunis')::timestamp) then
    raise exception 'The professional has a break during this time';
  end if;
  if exists(select 1 from public.staff_availability sa where sa.staff_id=v_staff_id and sa.weekday=v_weekday)
    and not exists(select 1 from public.staff_availability sa where sa.staff_id=v_staff_id
      and sa.weekday=v_weekday and p_start_time >= sa.starts_at and v_end <= sa.ends_at) then
    raise exception 'The professional is not scheduled at this time';
  end if;

  insert into public.bookings(customer_id,business_id,staff_id,customer_name,customer_phone,booking_date,start_time,end_time,customer_note,status)
  values(v_user,p_business_id,v_staff_id,trim(p_customer_name),trim(p_customer_phone),p_booking_date,p_start_time,v_end, nullif(trim(coalesce(p_customer_note,'')),''),'pending')
  returning bookings.id,bookings.booking_reference,bookings.status into v_booking_id,v_ref,v_status;
  insert into public.booking_items(booking_id,service_id,service_name_snapshot,duration_minutes,unit_price,currency)
  values(v_booking_id,v_service.id,v_service.name_ar,v_service.duration_minutes,v_service.price,v_service.currency);
  insert into public.booking_status_history(booking_id,changed_by,new_status,note)
  values(v_booking_id,v_user,'pending','Booking submitted by customer');
  insert into public.notifications(user_id,title,body,kind,related_booking_id)
  select b.owner_id,'New booking request','A customer submitted a new appointment request.','booking',v_booking_id
  from public.businesses b where b.id=p_business_id;
  return query select v_booking_id,v_ref,v_status,v_end;
end;
$$;
revoke all on function public.create_booking(bigint,bigint,date,time,text,text,bigint,text) from public;
grant execute on function public.create_booking(bigint,bigint,date,time,text,text,bigint,text) to authenticated;

-- Keep booking status history append-only for customers; provider/admin changes are audited.
create or replace function public.change_booking_status(p_booking_id bigint,p_new_status public.booking_status,p_note text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_booking public.bookings%rowtype; v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;
  if not (v_booking.customer_id=v_user or public.is_business_member(v_booking.business_id) or public.is_admin()) then raise exception 'Not authorized'; end if;
  if v_booking.customer_id=v_user and p_new_status not in ('cancelled') then raise exception 'Customers can only cancel their own booking'; end if;
  if public.is_business_member(v_booking.business_id) and p_new_status not in ('confirmed','rejected','cancelled','completed','no_show') then raise exception 'Invalid provider status transition'; end if;
  if v_booking.status in ('cancelled','rejected','completed','no_show') then raise exception 'Booking is already closed'; end if;
  update public.bookings set status=p_new_status,cancellation_reason=case when p_new_status='cancelled' then nullif(trim(coalesce(p_note,'')),'') else cancellation_reason end where id=p_booking_id;
  insert into public.booking_status_history(booking_id,changed_by,old_status,new_status,note) values(p_booking_id,v_user,v_booking.status,p_new_status,p_note);
  insert into public.notifications(user_id,title,body,kind,related_booking_id)
  values(case when v_booking.customer_id=v_user then (select owner_id from public.businesses where id=v_booking.business_id) else v_booking.customer_id end,
    'Booking updated','Your booking status is now '||p_new_status::text||'.','booking',p_booking_id);
end; $$;
revoke all on function public.change_booking_status(bigint,public.booking_status,text) from public;
grant execute on function public.change_booking_status(bigint,public.booking_status,text) to authenticated;

-- Clients must use create_booking() rather than inserting appointments directly.
drop policy if exists "customer create booking" on public.bookings;
drop policy if exists "customer or provider update booking" on public.bookings;
create policy "booking participants read" on public.bookings for select to authenticated
  using (customer_id=auth.uid() or public.is_business_member(business_id) or public.is_admin());

-- Prevent a provider from self-publishing or self-verifying a business listing.
create or replace function public.guard_business_publication()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    if tg_op='INSERT' then
      new.is_active := false;
      new.verified := false;
    elsif new.is_active is distinct from old.is_active or new.verified is distinct from old.verified then
      raise exception 'Only an administrator can publish or verify a business';
    end if;
  end if;
  return new;
end; $$;
create trigger guard_business_publication_trigger before insert or update on public.businesses
  for each row execute function public.guard_business_publication();
