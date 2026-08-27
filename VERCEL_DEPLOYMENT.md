# Deploying HPT Component Hub on Vercel

This project builds a server-rendered TanStack Start application and emits
Vercel-compatible output. The component inventory and employee records live in
the hosted backend, not in browser storage, so saved records are shared across
Chrome, Edge, Firefox, Safari, mobile browsers, and different devices.

## Required Vercel environment variables

In the Vercel project, open **Settings → Environment Variables** and add these
variables to **Production**, **Preview**, and **Development** as appropriate:

| Variable | Purpose |
| --- | --- |
| `SUPABASE_URL` | Hosted backend URL used by server functions |
| `SUPABASE_PUBLISHABLE_KEY` | Public backend key used by the application |
| `SUPABASE_SERVICE_ROLE_KEY` | Private server-only key used for custom employee authentication and protected inventory operations |
| `VITE_SUPABASE_URL` | Browser-side backend URL |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | Browser-side public backend key |
| `HPT_SESSION_SECRET` | Stable random secret of at least 32 characters used to encrypt login cookies |

Do not prefix the service-role key or session secret with `VITE_`; that would
expose private credentials to browsers. Never commit their values to GitHub.

The private service-role credential managed by Lovable Cloud is not available
for export. Therefore, a Vercel deployment can only use this custom
authentication implementation when it is connected to a backend whose owner
can securely provide that server credential. Otherwise, publish through
Lovable, where the backend credentials are wired automatically.

## Vercel project settings

1. Import the connected GitHub repository into Vercel.
2. Keep **Framework Preset** set to `Other` or allow automatic detection.
3. Use `bun run build` as the build command.
4. Do not set a custom output directory; Nitro creates `.vercel/output`.
5. Add all required environment variables before deploying.
6. Redeploy after changing any environment variable; an existing deployment
   does not receive newly added values automatically.

## Browser behavior

- Inventory and employee changes are saved centrally and appear in every
  browser after sign-in and refresh.
- Login cookies are secure, HTTP-only, and scoped to the deployed domain.
- A login on one browser does not sign in another browser. This is expected
  security behavior; use the same employee credentials to sign in there.
- Preview and production Vercel domains have separate cookies, although they
  can point to the same hosted data.

## Verification checklist

After deployment:

1. Open the production URL in a private/incognito window and sign in.
2. Add a temporary component and confirm it appears in search.
3. Open the production URL in another browser, sign in, and confirm the same
   component appears.
4. Delete the temporary component from the admin panel.

If login reports missing environment variables, confirm their exact names,
their Production scope, and that the deployment was rebuilt after adding them.