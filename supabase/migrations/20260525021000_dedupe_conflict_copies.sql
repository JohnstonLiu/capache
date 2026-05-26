with ranked_conflicts as (
  select
    id,
    row_number() over (
      partition by user_id, conflict_parent_id, content_hash
      order by updated_at desc, id asc
    ) as duplicate_rank
  from public.notes
  where is_conflict = true
    and conflict_parent_id is not null
    and content_hash <> ''
)
delete from public.notes
using ranked_conflicts
where notes.id = ranked_conflicts.id
  and ranked_conflicts.duplicate_rank > 1;
