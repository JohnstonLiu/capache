create or replace function public.prevent_folder_parent_cycle()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ancestor_id uuid;
begin
  if new.parent_id is null then
    return new;
  end if;

  if new.parent_id = new.id then
    raise exception 'folder cannot be its own parent';
  end if;

  select parent.parent_id
    into ancestor_id
  from public.folders parent
  where parent.id = new.parent_id
    and parent.user_id = new.user_id;

  if not found then
    raise exception 'parent folder not found';
  end if;

  while ancestor_id is not null loop
    if ancestor_id = new.id then
      raise exception 'folder parent cycle detected';
    end if;

    select parent.parent_id
      into ancestor_id
    from public.folders parent
    where parent.id = ancestor_id
      and parent.user_id = new.user_id;
  end loop;

  return new;
end;
$$;

drop trigger if exists prevent_folder_parent_cycle on public.folders;
create trigger prevent_folder_parent_cycle
  before insert or update of parent_id, user_id on public.folders
  for each row
  execute function public.prevent_folder_parent_cycle();
