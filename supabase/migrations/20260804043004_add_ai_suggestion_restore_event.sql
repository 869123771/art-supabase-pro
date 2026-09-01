alter table public.ai_suggestion_event
  drop constraint if exists ai_suggestion_event_event_type_check;

alter table public.ai_suggestion_event
  add constraint ai_suggestion_event_event_type_check
  check (
    event_type = any (
      array[
        'shown'::text,
        'expanded'::text,
        'copied'::text,
        'liked'::text,
        'disliked'::text,
        'accepted'::text,
        'completed'::text,
        'dismissed'::text,
        'restored'::text
      ]
    )
  );;
