# delete-user

Deletes the signed-in user's synced Capache rows and Supabase Auth user.

Deploy with the Supabase CLI:

```sh
supabase functions deploy delete-user
```

Do not manually set secrets whose names start with `SUPABASE_`. Supabase reserves that prefix and provides `SUPABASE_URL` and secret keys to hosted Edge Functions automatically.

The app invokes this function with the user's existing Supabase session bearer token. The function verifies the token, deletes rows for that auth user, and then deletes the auth user through the admin API.
