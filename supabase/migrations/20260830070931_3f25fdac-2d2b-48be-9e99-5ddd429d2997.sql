
create type public.app_role as enum ('admin','user');
create type public.memo_status as enum ('draft','submitted','pending_review','pending_approval','changes_requested','approved','rejected','cancelled');
create type public.memo_priority as enum ('normal','high','urgent');
create type public.step_action as enum ('pending','approved','rejected','changes_requested','reviewed');

create table public.organizations (id uuid primary key default gen_random_uuid(), name text not null, slug text not null unique, created_at timestamptz not null default now());
create table public.profiles (id uuid primary key references auth.users on delete cascade, org_id uuid not null references public.organizations on delete cascade, full_name text not null default '', email text not null default '', department_id uuid, active boolean not null default true, created_at timestamptz not null default now());
create table public.user_roles (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users on delete cascade, org_id uuid not null references public.organizations on delete cascade, role public.app_role not null, unique(user_id, role));
create table public.departments (id uuid primary key default gen_random_uuid(), org_id uuid not null references public.organizations on delete cascade, name text not null, active boolean not null default true, created_at timestamptz not null default now());
create table public.memo_categories (id uuid primary key default gen_random_uuid(), org_id uuid not null references public.organizations on delete cascade, name text not null, active boolean not null default true, created_at timestamptz not null default now());
create table public.memos (id uuid primary key default gen_random_uuid(), org_id uuid not null references public.organizations on delete cascade, ref_no text not null, subject text not null, body text not null default '', author_id uuid not null references auth.users on delete cascade, department_id uuid references public.departments on delete set null, category_id uuid references public.memo_categories on delete set null, priority public.memo_priority not null default 'normal', status public.memo_status not null default 'draft', current_step int not null default 0, submitted_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.memo_workflow_steps (id uuid primary key default gen_random_uuid(), memo_id uuid not null references public.memos on delete cascade, org_id uuid not null references public.organizations on delete cascade, step_order int not null, participant_id uuid not null references auth.users on delete cascade, action public.step_action not null default 'pending', comment text, acted_at timestamptz);
create table public.comments (id uuid primary key default gen_random_uuid(), memo_id uuid not null references public.memos on delete cascade, org_id uuid not null references public.organizations on delete cascade, author_id uuid not null references auth.users on delete cascade, body text not null, kind text not null default 'comment', created_at timestamptz not null default now());
create table public.notifications (id uuid primary key default gen_random_uuid(), org_id uuid not null references public.organizations on delete cascade, user_id uuid not null references auth.users on delete cascade, memo_id uuid references public.memos on delete cascade, message text not null, read boolean not null default false, created_at timestamptz not null default now());
create table public.audit_logs (id uuid primary key default gen_random_uuid(), org_id uuid not null references public.organizations on delete cascade, user_id uuid references auth.users on delete set null, action text not null, detail text, created_at timestamptz not null default now());

alter table public.profiles add constraint profiles_department_fk foreign key (department_id) references public.departments on delete set null;

grant select, insert, update, delete on public.organizations, public.profiles, public.user_roles, public.departments, public.memo_categories, public.memos, public.memo_workflow_steps, public.comments, public.notifications, public.audit_logs to authenticated;
grant all on public.organizations, public.profiles, public.user_roles, public.departments, public.memo_categories, public.memos, public.memo_workflow_steps, public.comments, public.notifications, public.audit_logs to service_role;
grant select on public.organizations to anon;

create or replace function public.has_role(_user_id uuid, _role public.app_role) returns boolean language sql stable security definer set search_path = public as $$ select exists(select 1 from public.user_roles where user_id=_user_id and role=_role) $$;
create or replace function public.current_org_id() returns uuid language sql stable security definer set search_path = public as $$ select org_id from public.profiles where id = auth.uid() $$;

alter table public.organizations enable row level security;
alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.departments enable row level security;
alter table public.memo_categories enable row level security;
alter table public.memos enable row level security;
alter table public.memo_workflow_steps enable row level security;
alter table public.comments enable row level security;
alter table public.notifications enable row level security;
alter table public.audit_logs enable row level security;

create policy "org read" on public.organizations for select to anon, authenticated using (true);
create policy "org admin update" on public.organizations for update to authenticated using (id = public.current_org_id() and public.has_role(auth.uid(),'admin'));

create policy "profiles same org" on public.profiles for select to authenticated using (org_id = public.current_org_id() or id = auth.uid());
create policy "profiles self update" on public.profiles for update to authenticated using (id = auth.uid() or (org_id = public.current_org_id() and public.has_role(auth.uid(),'admin')));

create policy "roles same org read" on public.user_roles for select to authenticated using (org_id = public.current_org_id() or user_id = auth.uid());
create policy "roles admin write" on public.user_roles for all to authenticated using (org_id = public.current_org_id() and public.has_role(auth.uid(),'admin')) with check (org_id = public.current_org_id() and public.has_role(auth.uid(),'admin'));

create policy "dept read" on public.departments for select to authenticated using (org_id = public.current_org_id());
create policy "dept admin write" on public.departments for all to authenticated using (org_id = public.current_org_id() and public.has_role(auth.uid(),'admin')) with check (org_id = public.current_org_id() and public.has_role(auth.uid(),'admin'));

create policy "cat read" on public.memo_categories for select to authenticated using (org_id = public.current_org_id());
create policy "cat admin write" on public.memo_categories for all to authenticated using (org_id = public.current_org_id() and public.has_role(auth.uid(),'admin')) with check (org_id = public.current_org_id() and public.has_role(auth.uid(),'admin'));

create policy "memo read org" on public.memos for select to authenticated using (org_id = public.current_org_id());
create policy "memo insert own" on public.memos for insert to authenticated with check (org_id = public.current_org_id() and author_id = auth.uid());
create policy "memo update author or participant" on public.memos for update to authenticated using (org_id = public.current_org_id() and (author_id = auth.uid() or public.has_role(auth.uid(),'admin') or exists(select 1 from public.memo_workflow_steps s where s.memo_id = memos.id and s.participant_id = auth.uid())));
create policy "memo delete author draft" on public.memos for delete to authenticated using (author_id = auth.uid() and status = 'draft');

create policy "steps read org" on public.memo_workflow_steps for select to authenticated using (org_id = public.current_org_id());
create policy "steps author write" on public.memo_workflow_steps for all to authenticated using (org_id = public.current_org_id() and (participant_id = auth.uid() or exists(select 1 from public.memos m where m.id = memo_id and m.author_id = auth.uid()))) with check (org_id = public.current_org_id());

create policy "comments read org" on public.comments for select to authenticated using (org_id = public.current_org_id());
create policy "comments insert" on public.comments for insert to authenticated with check (org_id = public.current_org_id() and author_id = auth.uid());

create policy "notif own" on public.notifications for select to authenticated using (user_id = auth.uid());
create policy "notif update own" on public.notifications for update to authenticated using (user_id = auth.uid());
create policy "notif insert org" on public.notifications for insert to authenticated with check (org_id = public.current_org_id());

create policy "audit admin read" on public.audit_logs for select to authenticated using (org_id = public.current_org_id() and public.has_role(auth.uid(),'admin'));
create policy "audit insert org" on public.audit_logs for insert to authenticated with check (org_id = public.current_org_id());

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
declare v_org uuid; v_slug text; v_role public.app_role;
begin
  v_slug := lower(coalesce(nullif(new.raw_user_meta_data->>'org_slug',''),'default-org'));
  select id into v_org from public.organizations where slug = v_slug;
  if v_org is null then
    insert into public.organizations(name, slug) values (coalesce(nullif(new.raw_user_meta_data->>'org_name',''), v_slug), v_slug) returning id into v_org;
    v_role := 'admin';
  else
    v_role := 'user';
  end if;
  insert into public.profiles(id, org_id, full_name, email) values (new.id, v_org, coalesce(new.raw_user_meta_data->>'full_name',''), new.email);
  insert into public.user_roles(user_id, org_id, role) values (new.id, v_org, v_role);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.next_ref_no(_org uuid) returns text language sql stable security definer set search_path = public as $$
  select 'MEMO-' || to_char(now(),'YYYY') || '-' || lpad((count(*)+1)::text, 4, '0') from public.memos where org_id = _org
$$;
