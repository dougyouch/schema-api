# Auth example

A small auth service built with SchemaApi: users, organizations (tenants), affiliations with organization-level details, login sessions, and application tokens for server-to-server calls. Models come from `db/schema.rb` through [dynamic-active-model-rails](https://github.com/dougyouch/dynamic-active-model); there are no model files, only extensions in `app/models/auth_db/`.

## Running it

```bash
bundle install
bin/rails db:prepare
bin/rails auth:create_application[billing]   # prints an app_... token, shown once
bin/rails server
bundle exec rspec
```

## Callers

| Header | Who | Can |
|---|---|---|
| `X-Application-Token: app_...` | another service | everything: create users and organizations, manage affiliations, imports |
| `Authorization: Bearer <token>` | a logged-in user | read people and organizations they share, update themselves, manage their sessions |

## Endpoints

```bash
# log in: a token good for an hour
curl -X POST localhost:3000/sessions -H 'Content-Type: application/json' \
  -d '{"session": {"email": "ada@example.com", "password": "secret-password"}}'

# an organization, only with an application token
curl -X POST localhost:3000/organizations -H "X-Application-Token: $APP" -H 'Content-Type: application/json' \
  -d '{"organization": {"name": "Acme", "slug": "acme"}}'

# a user with an affiliation and its organization-level details, in one request
curl -X POST localhost:3000/users -H "X-Application-Token: $APP" -H 'Content-Type: application/json' -d '{
  "user": {"name": "Ada", "email": "ada@example.com", "password": "secret-password",
           "affiliations": [{"organization_id": 1, "affiliation_attributes": {"department": "Eng", "title": "Lead"}}]}}'

# the same affiliations from the organization's side; a manager's reports
curl "localhost:3000/organizations/1/members?affiliation_attributes.manager_user_id=7" -H "X-Application-Token: $APP"

# GraphQL: people and organizations in one request, scoped to the caller as over REST
curl -X POST localhost:3000/graphql -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"query":
  "{ users(sort: \"name\") { nodes { name affiliations { organization { name } } } } organizations { nodes { name member_count } } }"}'
```

## What it shows

- **GraphQL** (`GraphqlController`): `POST /graphql` serves users, organizations and sessions as queries and mutations. Each field runs its controller's `before_action`s, `resource_scope` and write hooks, so a token can read and write only what it could over REST. `password` is on `UserInput` but never on `User`. Organization members are nested under a route, so they aren't exposed yet. [auth_graphql](../auth_graphql) is this service with only the GraphQL endpoint.

- **Nested writes** (`UsersController`): `affiliations` are matched by `organization_id`, a `belongs_to` key. Each one's `affiliation_attributes` row (one per affiliation) is updated in place, and `manager_user_id` is a `belongs_to` checked against a scope.
- **The same tables from two sides**: `OrganizationMembersController` exposes affiliations under an organization. Its manager scope only allows managers who are members of that organization.
- **Write-only and computed fields**:
  - `password` is write-only, so it's written when sent and kept when a PUT leaves it out.
  - The session `token` is a computed field that's only filled in on the create response.
- **Hooks**:
  - `before_save` authenticates the login and issues the token inside the create transaction, so a wrong password writes nothing and returns `401`.
  - `after_commit` ends a user's other sessions when their password changes.
  - `after_save` rejects affiliation changes from users based on what actually changed, so a user can still PUT back their own GET response.
- **Custom errors**: `Unauthorized` is a `SchemaApi::Error` subclass, so `401`s come back in the standard format.
- **Soft deletes**: `soft_delete` hides deleted rows and makes destroy set `deleted_at`. Users extend `destroy_resource!` to also end their sessions.
- **Server-set references**: organizations record the creating application with `belongs_to :application, set: :current_application_id, on: :create`.
- **Nested resources**: `parent :organization, scope: :organizations` scopes members to the organization in the route and adds an `organization` reader.
- **Lean controllers**: `include SchemaApi` is in `ApplicationController`, and the schemas use `model_attributes` and `timestamps`.
- **Scopes as authorization**: a user's `resource_scope` only contains people in their organizations, so anything else is a `404`.
- **Imports and locking**:
  - `upsert_key :email` with `bulk_upsert` for user imports; `upsert_key :slug` for organizations.
  - `lock: true` on `updated_at`.
